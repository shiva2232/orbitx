# SKILL.md — Home-Automation Split-Tunnel P2P VPN
### (Kotlin `VpnService` + Go `c-shared` engine + Flutter `dart:ffi` control, Firebase pairing-hash signaling)

**Status:** partial implementation. The repo currently implements the VPN permission flow, TUN creation, and native bridge wiring, but several higher-level Go engine features are still only stubbed or not yet wired from Flutter.

---

## 1. What this builds

Two Android devices (`master` and `slave`) are matched by a shared **pairing hash**. Each device:

1. Runs an Android `VpnService` (Kotlin) whose TUN interface only captures traffic destined for the
   **home-automation subnet** (e.g. `192.168.50.0/24`). Every other IP continues to use the phone's
   normal default route (mobile data / Wi-Fi) — this is split tunneling, not full-tunnel VPN.
2. Hands the TUN file descriptor to a Go engine compiled as `libvpnengine.so`
   (`go build -buildmode=c-shared`), loaded once per process.
3. The Go engine publishes/reads signaling under the pairing hash in Firebase Realtime Database, establishes a WebRTC data-channel tunnel between the two devices, and pumps packets between the TUN fd and the WebRTC stream — encrypted.
4. Flutter shows a single toggle switch. The repo includes Dart `dart:ffi` bindings for `StartEngine`, `StopEngine`, and `GetStatusJSON`, but the current UI only invokes VPN permission and starts the Kotlin `HomeVpnService`. The actual Go engine start/stop wiring from Flutter remains unconnected in this implementation.
5. If either side's IP/port changes, the intended design is for the Go engine to refresh signaling via Firebase and keep the WebRTC channel alive. The current Go source contains a partial engine stub, but Firebase signaling and the WebRTC data-channel tunnel are not implemented in the checked-in code.

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
| `StartEngine` | `int StartEngine(char* pairingHash, char* role, char* presharedSecret)` | Flutter (`dart:ffi`) | Intended entry point for the toggle switch ON action. Requires `SubmitTunFd` to have already succeeded (returns error code if fd missing). In the target design, this initializes Firebase WebRTC signaling and opens a WebRTC data channel for raw IP packet transport. The current Go source starts a simple simulated `engineLoop` for state transitions, but the Flutter UI does not yet invoke it. |
| `StopEngine` | `int StopEngine()` | Flutter (`dart:ffi`) | Entry point the toggle switch calls on OFF. Cancels the context (stops all four loops), closes the UDP socket, closes the wrapped TUN file (does **not** close the underlying fd — Kotlin's `ParcelFileDescriptor.close()` owns that), clears in-memory peer state. Idempotent. |
| `NotifyNetworkChanged` | `int NotifyNetworkChanged()` | Kotlin (`ConnectivityManager.NetworkCallback`) | Fired the instant Android reports the active network changed (Wi-Fi→LTE, LTE→Wi-Fi, or a new Wi-Fi AP). Triggers an out-of-band `refreshLocalEndpoint()` + `writeEndpointToFirebase()` immediately, instead of waiting for the heartbeat to notice packet loss. This is what makes "IP changed while traveling" non-disruptive. |
| `GetStatusJSON` | `char* GetStatusJSON()` | Flutter (`dart:ffi`, polled or called after each status-relevant event) | Returns a heap-allocated JSON string: `{"state":"CONNECTED","peerIp":"...","peerPort":...,"lastHandshakeMs":...}`. Caller **must** pass the pointer to `FreeCString`. |
| `FreeCString` | `void FreeCString(char* ptr)` | Flutter (`dart:ffi`) | Frees a string previously returned by `GetStatusJSON`. Required because Go's cgo allocations aren't Dart's GC's responsibility. |

### 4.2 Internal functions (unexported, live inside the `.so`, never cross FFI — listed so naming stays consistent if you're reading the Go source)

| Function | Action |
|---|---|
| `refreshLocalEndpoint(ctx) (ip string, port int, err error)` | Learns this device's current public `ip:port` by refreshing Firebase signaling and optionally probing the peer's public relay/candidate address. Called at startup, on `NotifyNetworkChanged`, and on `handleConnectionFailure`. |
| `writeEndpointToFirebase(hash, role, ip, port)` | REST `PUT` to `/pairings/{hash}/{role}.json` with `{ip, port, updatedAt: now(), online: true}`. Also arms `onDisconnect` semantics via a companion `PATCH` if using the REST+websocket combo, or the SDK's `OnDisconnect` if using the Firebase Go Admin/Client SDK. This record is used as the WebRTC signaling target and keepalive endpoint for the peer. |
| `listenPeerEndpoint(hash, peerRole, onUpdate func(ip string, port int))` | Opens a persistent Firebase listener to `/pairings/{hash}/{peerRole}.json`. Every peer update invokes `onUpdate`, which refreshes WebRTC signaling and keeps the data-channel path valid when the peer's public endpoint changes. |
| `bridgeWebRTC(peerIP string, peerPort int) error` | Uses Firebase signaling to establish or refresh a WebRTC peer connection to the target device. The WebRTC data channel carries raw IP packets from the TUN. A lightweight keepalive is also sent to the peer's Firebase-published address to maintain NAT bindings. |
| `tunReadLoop(ctx)` | Reads raw IP packets off the wrapped TUN file (packets Kotlin's routing already guaranteed are home-subnet-bound), calls `encryptPacket`, and sends them over the WebRTC data channel to the peer. |
| `webrtcReadLoop(ctx)` | Reads packets off the WebRTC data channel, calls `decryptPacket`, writes the plaintext IP packet into the TUN file so the OS delivers it to whichever local app/process expects it. |
| `heartbeatLoop(ctx)` | Every 5s sends a keepalive over the WebRTC data channel or via Firebase pairer IP keepalive. After 3 consecutive missed heartbeats (~15s), calls `handleConnectionFailure()`. This is the fallback path for failures Firebase/network-callback didn't already catch (e.g. silent NAT rebinding). |
| `handleConnectionFailure()` | Calls `refreshLocalEndpoint` → `writeEndpointToFirebase` → refreshes the WebRTC peer connection using the most recently cached peer endpoint from `listenPeerEndpoint`. Sets status to `RECONNECTING` (surfaced via `GetStatusJSON`). |
| `encryptPacket(data []byte) []byte` / `decryptPacket(data []byte) []byte` | ChaCha20-Poly1305 AEAD using a session key derived via HKDF from `presharedSecret` (passed into `StartEngine` — **not** the pairing hash itself, which is only an identifier and should be treated as semi-public). |
| `EndpointRecord{IP string; Port int; UpdatedAt int64}` | Shared struct mirroring the Firebase node shape; used for the local peer-endpoint cache that `listenPeerEndpoint` updates and `handleConnectionFailure` reads. |

---

## 9. Verification requirements (user-requested) — mapping to function names and actions

The following four runtime requirements must be verifiable and are implemented by the functions named below. Each entry lists the requirement, the functions responsible, and the concrete actions they perform.

1) Dynamic public IP & port updates (mobile/navigation scenarios)
- Functions: `NotifyNetworkChanged()`, `getPublicIP()`, `refreshAndPublishEndpoint()`, `writeEndpointToFirebase()`
- Actions: on Android network change `NetworkChangeReceiver` calls `VpnBridge.notifyNetworkChanged()` → Go `NotifyNetworkChanged()` immediately calls `refreshAndPublishEndpoint()` which runs `getPublicIP()` and, when the public `ip:port` differs from the last published values, calls `writeEndpointToFirebase(pairingHash, role, ip, port)`. This ensures the peer's `listenPeerEndpoint()` stream observes the change and can re-negotiate the tunnel automatically.

2) Tunnel payload conversion and subnet reachability (STUN IP:port access)
- Functions: `tunReadLoop()`, `encodeTunnelPayload()`, `decodeTunnelPayload()`, `tunWriteLoop()`, `bridgeWebRTC()`
- Actions: packets read from the TUN by `tunReadLoop()` are framed by `encodeTunnelPayload()` and sent over the data transport created by `bridgeWebRTC()`; the remote side uses `decodeTunnelPayload()` and `tunWriteLoop()` to re-inject packets into its TUN. Framing preserves full IP packets so requests/responses (including those destined to devices in a target local subnet such as STUN targets) are tunneled end-to-end and re-inserted into the peer's subnet stack.

3) Two-device mesh (Firebase used only as signaling)
- Functions: `StartEngine()`, `writeEndpointToFirebase()`, `listenPeerEndpoint()`, `bridgeWebRTC()`
- Actions: each client only writes its own `/pairings/{hash}/{role}` node with `writeEndpointToFirebase()` and only listens to the peer node with `listenPeerEndpoint()`. `StartEngine()` begins the lifecycle and `bridgeWebRTC()` performs peer-to-peer signaling via Firebase. No central relay stores traffic — data travels over the P2P data-channel (mesh of exactly two nodes per `pairingHash`).

4) Local-LAN preference and keep-alive to prevent NAT/firewall expiry
- Functions: `getLocalPrivateIP()`, `listenPeerEndpoint()`, `bridgeWebRTC()`, `heartbeatLoop()`
- Actions: `listenPeerEndpoint()` captures both the peer's public `ip:port` and optional `privateIp` field. When `StartEngine()` / peer-update logic detects both devices share the same public IP (determined by `getPublicIP()`/published records), the engine prefers the peer's `privateIp` (local LAN candidate) and routes the tunnel over LAN (`bridgeWebRTC()` accepts a private candidate and prefers it). Independently `heartbeatLoop()` republishes or sends periodic keep-alives to the peer and Firebase so NAT bindings remain active; missed heartbeats trigger `handleConnectionFailure()` which forces `refreshAndPublishEndpoint()` and re-negotiation.

Verification notes:
- To verify #1: observe Firebase `/pairings/{hash}/{role}` updates on network change events and assert the timestamps (`updatedAt`) and `ip` change quickly while the device is moving.
- To verify #2: run a packet capture on each device's TUN interface (or log tunneled packet headers) and assert that a request to a local STUN IP:port on device A is received and responded to on device B's subnet.
- To verify #3: confirm that data payloads do not traverse any intermediate relay (look for direct data-channel establishment in logs) and only `/pairings/{hash}` nodes are written in Firebase.
- To verify #4: place both devices on the same NAT (same public IP) and observe the engine prefer `privateIp` and open the LAN path; also simulate NAT expiry and confirm `heartbeatLoop()` prevents connection tear-down.

These mappings are now authoritative guidance for the implementation and testing tasks in the repo. Implementations in `golang/vpnengine.go` should follow these function names and actions to satisfy the user's verification requirements.

---

## 5. Function reference — Kotlin (`HomeVpnService` + support classes)

| Function | Action |
|---|---|
| `HomeVpnService.onStartCommand(intent, flags, startId): Int` | Reads `pairingHash`, `role`, `presharedSecret` from the launch `Intent` extras (put there by the Flutter platform channel requestPermission flow). Calls `startForegroundNotification()`, `establishTunnel()`, and `handoffTunFd()` to pass the fd to the native library. It does not currently call the Go `StartEngine` entrypoint from Kotlin. |
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
| `VpnController.startVpn(String pairingHash, String role, String presharedSecret): Future<bool>` | Calls the platform channel `'com.home.vpn/permission'` to request VPN consent and start `HomeVpnService`, which performs `SubmitTunFd`. The current implementation does not wire a follow-up `StartEngine` call after the tun-ready callback. |
| `VpnController.stopVpn(): Future<bool>` | Calls the FFI-bound `StopEngine()` directly and then returns. The current implementation calls `stopEngine()` from `stopService()` but does not expose a structured `platform channel` stop-control path for `HomeVpnService` cleanup. |
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
8. On peer update → WebRTC signaling refreshes the peer connection and opens the data channel → `tunReadLoop`/`webrtcReadLoop` start → status → `CONNECTED`

### 7.2 Local IP change (this device roams to new Wi-Fi/LTE)
1. Android `ConnectivityManager` fires → `NetworkChangeReceiver` → `VpnBridge.notifyNetworkChanged()` → Go `NotifyNetworkChanged`
2. Go: `refreshLocalEndpoint` (new public ip:port) → `writeEndpointToFirebase` (overwrites this device's node) — no user action required beyond the brief reconnection
3. Peer's `listenPeerEndpoint` stream fires on the updated node → peer refreshes WebRTC signaling and reconnects the data channel
4. Both sides resume `tunReadLoop`/`webrtcReadLoop`; status briefly `RECONNECTING` → `CONNECTED`

### 7.3 Silent failure (NAT rebind Firebase/network-callback didn't catch)
1. `heartbeatLoop` misses 3 heartbeats → `handleConnectionFailure()`
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
