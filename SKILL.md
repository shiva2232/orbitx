# SKILL.md — Home-Automation Split-Tunnel P2P VPN
### (Kotlin `VpnService` + Go `c-shared` engine + Flutter `dart:ffi` control, Firebase pairing-hash signaling)

**Status:** frozen scope. Every function below is the *only* function that layer needs. Do not add
new cross-layer entry points later — extend behavior inside the functions listed, not by adding new ones.

---

## 1. What this builds

Two Android devices (`master` and `slave`) are matched by a shared **pairing hash**. Each device:

1. Runs an Android `VpnService` (Kotlin) whose TUN interface only captures traffic destined for the
   **home-automation subnet** (e.g. `192.168.50.0/24`). Every other IP continues to use the phone's
   normal default route (mobile data / Wi-Fi) — this is split tunneling, not full-tunnel VPN.
2. Hands the TUN file descriptor to a Go engine compiled as `libvpnengine.so`
   (`go build -buildmode=c-shared`), loaded once per process.
3. The Go engine publishes/reads `ip:port` under the pairing hash in Firebase Realtime Database,
   performs UDP hole punching directly between the two devices' public endpoints, and pumps packets
   between the TUN fd and the UDP tunnel — encrypted.
4. Flutter shows a single toggle switch. Flipping it calls into Go **directly via `dart:ffi`** (not
   through Kotlin) for start/stop/status, because Flutter and the native Android host share the same
   OS process on Android, so the same `.so` Kotlin loaded via JNI is already mapped in and callable
   from Dart.
5. If either side's IP/port changes (network switch while traveling, Wi-Fi↔LTE handoff, or the
   UDP session simply goes quiet), that side detects it and overwrites its own Firebase node
   **immediately** — the peer's live Firebase listener fires, and hole punching is redone against the
   new endpoint, with no manual re-pairing.

---

## 2. Process/address-space layout (why the FFI split works)

```
┌─────────────────────────── Android process (single) ───────────────────────────┐
│                                                                                  │
│   Flutter/Dart isolate                     Kotlin (Android framework side)      │
│   ─────────────────────                    ─────────────────────────────       │
│   dart:ffi DynamicLibrary.process()  ──┐    VpnService subclass                 │
│   calls StartEngine/StopEngine/        │    external fun (JNI) declarations     │
│   GetStatusJSON directly               │    calls SubmitTunFd / NotifyNetworkChanged
│                                         │                                       │
│                                         ▼                                       │
│                         libvpnengine.so (Go, c-shared, loaded ONCE              │
│                         via System.loadLibrary in Kotlin's companion init;      │
│                         already resident, so dart:ffi opens the *same* image    │
│                         with DynamicLibrary.process(), no second load)          │
│                                                                                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

**Rule:** Kotlin is the only layer allowed to create the TUN fd (OS requires the VPN permission
grant + `VpnService.Builder`). Go is the only layer allowed to touch sockets, encryption, and
Firebase. Flutter is the only layer allowed to initiate start/stop from user intent. No layer
reaches into another layer's responsibility.

---

## 3. Firebase Realtime Database schema

```
/pairings/{pairingHash}/
    master/
        ip          : string   ("203.0.113.4")
        port         : number
        updatedAt    : number   (epoch ms, server timestamp)
        online       : bool
    slave/
        ip           : string
        port         : number
        updatedAt    : number
        online       : bool
```

- Each device only ever **writes** its own role's node and only ever **listens** to the *other*
  role's node.
- `online` is set `true` on write, and should be attached to Firebase's `onDisconnect().setValue(false)`
  so an app kill / crash is visible to the peer too, not just an IP change.
- Security rule: writes to `/pairings/{hash}/{role}` require the client to have authenticated with a
  token that embeds `{hash, role}` (Firebase custom auth) — prevents a third party who guesses a hash
  from injecting a fake endpoint. (Auth setup is outside this file's scope — call it out as a
  prerequisite, don't change the schema above to work around it.)

---

## 4. Function reference — Go engine (`libvpnengine.so`)

### 4.1 Exported C ABI (the only functions crossing the FFI boundary — called by Kotlin JNI *and* Flutter dart:ffi)

| Function | Signature (C) | Called from | Action |
|---|---|---|---|
| `SubmitTunFd` | `int SubmitTunFd(int fd)` | Kotlin (JNI) | Stores the TUN file descriptor Kotlin just created via `VpnService.Builder.establish()`. Wraps it as `os.NewFile`. Does **not** start reading/writing yet — just makes it available. Returns `0` on success, negative error code otherwise. |
| `StartEngine` | `int StartEngine(char* pairingHash, char* role, char* presharedSecret)` | Flutter (`dart:ffi`) | Entry point the toggle switch calls on ON. Requires `SubmitTunFd` to have already succeeded (returns error code if fd missing). Derives the session key, spins up `signalingLoop`, `heartbeatLoop`, `tunReadLoop`, `udpReadLoop` goroutines under a fresh `context.Context`. Non-blocking — returns immediately once goroutines are launched. |
| `StopEngine` | `int StopEngine()` | Flutter (`dart:ffi`) | Entry point the toggle switch calls on OFF. Cancels the context (stops all four loops), closes the UDP socket, closes the wrapped TUN file (does **not** close the underlying fd — Kotlin's `ParcelFileDescriptor.close()` owns that), clears in-memory peer state. Idempotent. |
| `NotifyNetworkChanged` | `int NotifyNetworkChanged()` | Kotlin (`ConnectivityManager.NetworkCallback`) | Fired the instant Android reports the active network changed (Wi-Fi→LTE, LTE→Wi-Fi, or a new Wi-Fi AP). Triggers an out-of-band `refreshLocalEndpoint()` + `writeEndpointToFirebase()` immediately, instead of waiting for the heartbeat to notice packet loss. This is what makes "IP changed while traveling" non-disruptive. |
| `GetStatusJSON` | `char* GetStatusJSON()` | Flutter (`dart:ffi`, polled or called after each status-relevant event) | Returns a heap-allocated JSON string: `{"state":"CONNECTED","peerIp":"...","peerPort":...,"lastHandshakeMs":...}`. Caller **must** pass the pointer to `FreeCString`. |
| `FreeCString` | `void FreeCString(char* ptr)` | Flutter (`dart:ffi`) | Frees a string previously returned by `GetStatusJSON`. Required because Go's cgo allocations aren't Dart's GC's responsibility. |

### 4.2 Internal functions (unexported, live inside the `.so`, never cross FFI — listed so naming stays consistent if you're reading the Go source)

| Function | Action |
|---|---|
| `refreshLocalEndpoint(ctx) (ip string, port int, err error)` | Learns this device's current public `ip:port` for the UDP socket by sending a probe to a STUN server (e.g. `stun.l.google.com:19302`) and reading the mapped address back. Called at startup, on `NotifyNetworkChanged`, and on `handleConnectionFailure`. |
| `writeEndpointToFirebase(hash, role, ip, port)` | REST `PUT` to `/pairings/{hash}/{role}.json` with `{ip, port, updatedAt: now(), online: true}`. Also arms `onDisconnect` semantics via a companion `PATCH` if using the REST+websocket combo, or the SDK's `OnDisconnect` if using the Firebase Go Admin/Client SDK. |
| `listenPeerEndpoint(hash, peerRole, onUpdate func(ip string, port int))` | Opens a persistent Firebase REST streaming connection (`Accept: text/event-stream`) to `/pairings/{hash}/{peerRole}.json`. Every `put`/`patch` event invokes `onUpdate`, which immediately triggers `punchHole` against the new address — this is the mechanism that reacts to the *peer's* IP change, mirroring what `NotifyNetworkChanged` does for the local side. |
| `punchHole(peerIP string, peerPort int) (*net.UDPConn, error)` | Sends a burst of small UDP "punch" packets to `peerIP:peerPort` from the engine's bound local UDP socket, and simultaneously listens for the peer's punch packets, to open the NAT binding on both sides. Resolves once a punch-ack is received or times out (retries via `heartbeatLoop`). |
| `tunReadLoop(ctx)` | Reads raw IP packets off the wrapped TUN file (packets Kotlin's routing already guaranteed are home-subnet-bound), calls `encryptPacket`, writes to the active UDP conn toward the peer. |
| `udpReadLoop(ctx)` | Reads packets off the UDP conn, calls `decryptPacket`, writes the plaintext IP packet into the TUN file so the OS delivers it to whichever local app/process expects it. |
| `heartbeatLoop(ctx)` | Every 5s sends a keepalive over the UDP conn. After 3 consecutive missed acks (~15s), calls `handleConnectionFailure()`. This is the fallback path for failures Firebase/network-callback didn't already catch (e.g. silent NAT rebinding). |
| `handleConnectionFailure()` | Calls `refreshLocalEndpoint` → `writeEndpointToFirebase` → re-`punchHole` using the most recently cached peer endpoint from `listenPeerEndpoint`. Sets status to `RECONNECTING` (surfaced via `GetStatusJSON`). |
| `encryptPacket(data []byte) []byte` / `decryptPacket(data []byte) []byte` | ChaCha20-Poly1305 AEAD using a session key derived via HKDF from `presharedSecret` (passed into `StartEngine` — **not** the pairing hash itself, which is only an identifier and should be treated as semi-public). |
| `EndpointRecord{IP string; Port int; UpdatedAt int64}` | Shared struct mirroring the Firebase node shape; used for the local peer-endpoint cache that `listenPeerEndpoint` updates and `handleConnectionFailure` reads. |

---

## 5. Function reference — Kotlin (`HomeVpnService` + support classes)

| Function | Action |
|---|---|
| `HomeVpnService.onStartCommand(intent, flags, startId): Int` | Reads `pairingHash`, `role`, `presharedSecret` from the launch `Intent` extras (put there by the Flutter→platform call that requests VPN permission — see §7). Calls `establishTunnel()` then `startForegroundNotification()`. |
| `HomeVpnService.establishTunnel(): ParcelFileDescriptor` | Builds the TUN interface: `Builder().addAddress("10.99.0.1", 32).setMtu(1400).setSession("HomeVPN")`, then calls `configureSplitTunnel(builder, subnetCidr)`, then `.establish()`. |
| `HomeVpnService.configureSplitTunnel(builder: Builder, subnetCidr: String)` | Adds **only** `addRoute(subnetCidr's network, prefixLen)` (e.g. `addRoute("192.168.50.0", 24)`) to the builder. Deliberately never adds `0.0.0.0/0` — this single omission is what keeps all non-home-subnet traffic on the phone's normal default route. |
| `HomeVpnService.handoffTunFd(pfd: ParcelFileDescriptor)` | Extracts the raw int fd (`pfd.fd`) and calls the JNI native `submitTunFd(fd)`. Keeps the `ParcelFileDescriptor` object itself alive in a service-scoped field (closing it prematurely invalidates the fd Go is using). |
| `HomeVpnService.onRevoke()` | Android calls this if the user revokes VPN permission from system settings. Must call `stopEngineAndService()` — never leave Go holding a dead fd. |
| `HomeVpnService.stopEngineAndService()` | Calls JNI-exposed stop path (or lets Flutter's `StopEngine` call handle the Go side, if the OFF flow already ran) then `pfd.close()`, `stopForeground(true)`, `stopSelf()`. |
| `HomeVpnService.startForegroundNotification()` | Mandatory for any long-running `VpnService`; shows persistent "Home VPN connected" notification. |
| `VpnBridge` (Kotlin `object`, JNI declarations) — `external fun submitTunFd(fd: Int): Int` | Thin 1:1 wrapper calling into `SubmitTunFd` in the `.so`. Loaded via `System.loadLibrary("vpnengine")` in a `companion object { init { ... } }` block. |
| `VpnBridge.external fun notifyNetworkChanged(): Int` | Thin wrapper calling `NotifyNetworkChanged`. |
| `NetworkChangeReceiver : ConnectivityManager.NetworkCallback` — `onCapabilitiesChanged` / `onAvailable` | Registered once VPN is active. On any change to the *underlying* (non-VPN) network, calls `VpnBridge.notifyNetworkChanged()`. This is the proactive trigger for "IP changed while traveling." |
| `VpnPermissionActivity.requestPermission(pairingHash, role, presharedSecret): Boolean` | Wraps `VpnService.prepare(context)` → if non-null `Intent`, launches it via `startActivityForResult`; on `RESULT_OK`, starts `HomeVpnService` with the three extras. This is the only place Android's VPN consent dialog is triggered — call once per app, not per toggle. |

---

## 6. Function reference — Flutter (Dart)

| Function | Action |
|---|---|
| `VpnController.startVpn(String pairingHash, String role, String presharedSecret): Future<bool>` | (a) If VPN permission not yet granted, calls the platform channel `'com.home.vpn/permission'` → `VpnPermissionActivity.requestPermission` (one-time consent + starts `HomeVpnService`, which performs `SubmitTunFd`). (b) Once the fd-submitted callback (see `VpnController._onTunReady`) confirms readiness, calls the FFI-bound `StartEngine(pairingHash, role, presharedSecret)` directly. Returns `true` if `StartEngine` returned `0`. |
| `VpnController.stopVpn(): Future<bool>` | Calls FFI-bound `StopEngine()` directly, then platform channel `'com.home.vpn/control'` → tells `HomeVpnService` to `stopEngineAndService()` (fd cleanup only; Go side is already stopped). |
| `VpnController.getStatus(): Future<VpnStatus>` | Calls FFI-bound `GetStatusJSON()`, parses it, calls `FreeCString` on the returned pointer, maps to the `VpnStatus` enum. |
| `VpnController.vpnStatusStream: Stream<VpnStatus>` | Polls `getStatus()` on a short interval (e.g. every 2s) while the toggle is ON, or subscribes to an `EventChannel('com.home.vpn/status')` if Kotlin is also forwarding `NotifyNetworkChanged`-triggered state pushes — pick one mechanism and keep it, don't run both. |
| `VpnController._onTunReady: Future<void> Function()` | Internal callback awaited between permission grant and calling `StartEngine`, so Flutter never calls `StartEngine` before Kotlin's `SubmitTunFd` has actually completed (avoids the race where Go's `StartEngine` fails because no fd is stored yet). |
| `VpnToggleSwitch` (Widget) | Wraps a `Switch`; `onChanged` calls `VpnController.startVpn(...)` / `stopVpn()`; listens to `vpnStatusStream` to reflect `CONNECTING` / `CONNECTED` / `RECONNECTING` / `ERROR` states (e.g. switch thumb color or a small status caption) without changing its own on/off semantics. |
| `VpnStatus` (enum) | `DISCONNECTED, PERMISSION_PENDING, TUN_READY, WAITING_PEER, PUNCHING, CONNECTED, RECONNECTING, ERROR` — mirrors the states Go's `GetStatusJSON` reports plus the two Flutter/Kotlin-only pre-engine states. |

---

## 7. End-to-end sequence flows

### 7.1 Cold start (toggle flips ON, first time)
1. `VpnToggleSwitch.onChanged(true)` → `VpnController.startVpn(hash, role, secret)`
2. → platform channel → `VpnPermissionActivity.requestPermission` → system VPN consent dialog (first run only) → `HomeVpnService.onStartCommand`
3. `establishTunnel()` → `configureSplitTunnel()` (home subnet route only) → `.establish()`
4. `handoffTunFd(pfd)` → `VpnBridge.submitTunFd(fd)` → Go `SubmitTunFd`
5. Flutter's `_onTunReady` resolves → `StartEngine(hash, role, secret)` (Go)
6. Go: `refreshLocalEndpoint` → `writeEndpointToFirebase` → `listenPeerEndpoint` starts streaming
7. Status → `WAITING_PEER` until the peer device's node appears/updates in Firebase
8. On peer update → `punchHole` → on ack → `tunReadLoop`/`udpReadLoop` start → status → `CONNECTED`

### 7.2 Local IP change (this device roams to new Wi-Fi/LTE)
1. Android `ConnectivityManager` fires → `NetworkChangeReceiver` → `VpnBridge.notifyNetworkChanged()` → Go `NotifyNetworkChanged`
2. Go: `refreshLocalEndpoint` (new public ip:port) → `writeEndpointToFirebase` (overwrites this device's node) — no user action, no dropped session beyond the brief re-punch
3. Peer's `listenPeerEndpoint` stream fires on the updated node → peer re-`punchHole`s against the new address
4. Both sides resume `tunReadLoop`/`udpReadLoop`; status briefly `RECONNECTING` → `CONNECTED`

### 7.3 Silent failure (NAT rebind Firebase/network-callback didn't catch)
1. `heartbeatLoop` misses 3 acks → `handleConnectionFailure()`
2. Same recovery path as 7.2 steps 2–4, self-triggered instead of callback-triggered

### 7.4 Toggle OFF
1. `VpnController.stopVpn()` → `StopEngine()` (Go: cancel context, close UDP conn, stop loops) → platform channel → `HomeVpnService.stopEngineAndService()` (close `pfd`, stop foreground service)

---

## 8. Security notes (do not fold into the schema above — these are constraints on implementation, not new functions)

- `presharedSecret` must never be the pairing hash itself; the hash is a lookup key visible in
  Firebase paths, the secret is the encryption root and must be provisioned out-of-band (e.g. QR
  code exchanged once between the two devices).
- Firebase rules must scope write access to `/pairings/{hash}/{role}` per authenticated
  `{hash, role}` claim — otherwise anyone who learns/guesses a hash can inject a fake peer endpoint
  and hijack the tunnel.
- `GetStatusJSON`'s returned pointer is Go-owned heap memory — every call site in Dart must pair
  with `FreeCString`, no exceptions, or the engine leaks memory on every status poll.
