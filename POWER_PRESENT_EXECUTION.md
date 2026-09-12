# Power Present — Execution Plan

## 1. Project Identity

Project name:

Power Present

Parent project:

Orbit X

Purpose:

Power Present is a low-bandwidth remote presentation system built on top of Orbit X P2P.

One Android device owns an authoritative WebView. The WebView loads and executes the actual web content. Its rendered output is encoded using AV1 and transmitted through Orbit X P2P to one or more presentation devices.

Presentation devices decode the AV1 stream and display it.

Input events from presentation devices are sent back through Orbit X P2P to the authoritative device and injected into the authoritative WebView.

The system must NOT depend on WebRTC.

The system must NOT use Android full-screen MediaProjection for the primary implementation.

The system must NOT synchronize DOM/JavaScript between devices.

The authoritative WebView is the single source of truth.


## 2. Core Architecture

```text
                         ORBIT X P2P
                  ┌──────────────────────┐
                  │                      │
                  │  Power Present      │
                  │  Session Protocol    │
                  │                      │
                  └──────────┬───────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             ▼
       PRESENTATION HOST              PRESENTATION CLIENT
       Android Device                 Android Device
       ┌───────────────┐              ┌───────────────┐
       │ Flutter UI    │              │ Flutter UI    │
       ├───────────────┤              ├───────────────┤
       │ Kotlin        │              │ AV1 decoder   │
       │ WebView       │              │ Video render   │
       │ WebView       │              │ Input capture  │
       │ capture      │              │               │
       │ AV1 encoder   │              │               │
       └───────┬───────┘              └───────┬───────┘
               │                              │
               │ AV1 frames                   │ input
               └──────────────┬───────────────┘
                              │
                         Orbit X P2P
```

## 3. Fundamental Rules

1. Orbit X P2P is the transport.
2. WebRTC must not be introduced.
3. AV1 is the preferred video codec.
4. The host WebView is authoritative.
5. Clients must not independently load the presented website.
6. Clients must not execute a second copy of the website as the source of truth.
7. Do not synchronize DOM trees.
8. Do not synchronize JavaScript execution.
9. Do not use MediaProjection to capture the complete Android display.
10. Capture only the Power Present WebView output.
11. Input must flow from clients to the authoritative WebView.
12. Video must flow from host to clients.
13. Keep the transport independent from Flutter UI.
14. Keep codec implementation behind an abstraction.
15. Implement one host + one client first.
16. Add multiple clients only after the single-client path is stable.


# 4. Technology Responsibilities

## Flutter

Flutter is responsible for:

- Power Present UI
- session creation/join UI
- presentation WebView container
- connection state
- client video renderer UI
- touch/mouse interaction capture
- keyboard interaction where possible
- presentation controls
- session status
- codec capability display
- errors

Flutter must not contain the core AV1 encoder implementation.

Flutter must not implement Orbit X transport directly if an existing Orbit X transport API exists.


## Kotlin / Android

Kotlin is responsible for Android-specific functionality:

- Android WebView
- WebView lifecycle
- WebView rendering/capture integration
- input event injection into WebView
- MediaCodec integration
- AV1 encoder
- AV1 decoder where Android hardware/software support is available
- Surface/Texture handling
- Android-specific capability detection

Do not use MediaProjection for the WebView capture path.


## Go / Orbit X

Go is responsible for:

- Power Present session protocol
- Orbit X P2P transport integration
- packet framing
- session identification
- peer identification
- ordering
- reliability where required
- backpressure
- video packet transport
- input packet transport
- control messages
- statistics

Reuse existing Orbit X networking primitives wherever possible.

Do not create another P2P implementation.


# 5. Initial Scope

The first implementation must support:

### Host

- Open a WebView
- Navigate to a URL
- Render the website
- Capture WebView output
- Encode output as AV1
- Send AV1 packets through Orbit X P2P
- Receive input events
- Inject input into WebView

### Client

- Connect to Power Present session
- Receive AV1 stream
- Decode AV1
- Render video
- Capture touch events
- Send input events
- Display connection state

### Supported input MVP

- touch down
- touch move
- touch up
- scroll
- mouse move
- mouse button down
- mouse button up
- keyboard key down
- keyboard key up
- text input

Implement touch first.

Mouse and keyboard can follow after touch is stable.


# 6. Do NOT Implement Initially

Do not implement:

- WebRTC
- WebRTC DataChannels
- WebRTC signaling
- DOM replication
- DOM mutation synchronization
- JavaScript state synchronization
- browser-engine modification
- Chromium modification
- full Android screen capture
- arbitrary desktop screen capture
- video transcoding pipelines unrelated to WebView
- multi-host sessions
- collaborative editing
- cloud relay servers
- FRP
- Firebase as the video transport
- HTTP streaming
- HLS
- DASH
- RTMP

Power Present must remain an Orbit X P2P feature.


# 7. Session Model

Power Present has two roles:

```text
HOST
CLIENT
```

The host owns the authoritative WebView.

A client is a presentation/display/input peer.

Example:

```text
Host: device-A

Clients:
device-B
device-C
device-D
```

The host sends video to all clients.

Clients send input to the host.

```text
             HOST
              │
       ┌──────┼──────┐
       ↓      ↓      ↓
      B       C      D

      B/C/D → input → HOST
```


# 8. Power Present Session Lifecycle

## Create

```text
USER
 ↓
Power Present
 ↓
Create Session
 ↓
Generate session ID
 ↓
Advertise session through existing Orbit X mechanism
 ↓
Wait for peers
```

## Join

```text
CLIENT
 ↓
Discover Power Present session
 ↓
Join through Orbit X
 ↓
Capability exchange
 ↓
Video configuration
 ↓
Receive keyframe
 ↓
Start rendering
```

## Stop

```text
HOST
 ↓
Stop presentation
 ↓
Send SESSION_END
 ↓
Stop encoder
 ↓
Close streams
 ↓
Destroy session
```

Client:

```text
SESSION_END
 ↓
stop decoder
 ↓
release rendering resources
 ↓
return to Power Present screen
```


# 9. Protocol

Every Power Present message must have a common envelope.

Example:

```json
{
  "version": 1,
  "sessionId": "session-id",
  "peerId": "peer-id",
  "sequence": 100,
  "type": "INPUT",
  "payload": {}
}
```

For high-frequency video packets, avoid JSON.

Use compact binary framing.

Control messages may initially use a simple structured format.

Video packets must use binary framing.


# 10. Message Types

Control:

```text
POWER_PRESENT_HELLO
POWER_PRESENT_JOIN
POWER_PRESENT_ACCEPT
POWER_PRESENT_REJECT
POWER_PRESENT_CAPABILITIES
POWER_PRESENT_CONFIG
POWER_PRESENT_START
POWER_PRESENT_STOP
POWER_PRESENT_PING
POWER_PRESENT_PONG
POWER_PRESENT_KEYFRAME_REQUEST
POWER_PRESENT_STATS
POWER_PRESENT_ERROR
```

Input:

```text
INPUT_TOUCH_DOWN
INPUT_TOUCH_MOVE
INPUT_TOUCH_UP
INPUT_SCROLL
INPUT_MOUSE_MOVE
INPUT_MOUSE_DOWN
INPUT_MOUSE_UP
INPUT_KEY_DOWN
INPUT_KEY_UP
INPUT_TEXT
```

Video:

```text
VIDEO_CONFIG
VIDEO_KEYFRAME
VIDEO_FRAME
VIDEO_END
```


# 11. Input Packet

MVP touch packet:

```text
type
peerId
pointerId
action
x
y
timestamp
```

Coordinates must be normalized.

Do not assume the host and client have identical screen dimensions.

Preferred representation:

```text
x = 0.0 ... 1.0
y = 0.0 ... 1.0
```

Example:

```text
x = 0.52
y = 0.73
```

The host converts normalized coordinates into WebView coordinates.

This makes different resolutions easier to support.


# 12. Input Injection

Client:

```text
Touch
 ↓
Flutter/native input layer
 ↓
Power Present input message
 ↓
Orbit X P2P
 ↓
Host Go layer
 ↓
Kotlin bridge
 ↓
Android WebView
```

Do not use DOM selectors.

Do not identify buttons using IDs/classes.

Input is coordinate-based.

This allows Power Present to work with:

- normal HTML
- canvas
- SVG
- WebGL
- games
- maps
- custom controls


# 13. WebView Capture

The capture implementation must capture only the Power Present WebView.

Do NOT capture the entire Android display.

Required pipeline:

```text
Android WebView
      ↓
WebView rendering output
      ↓
video frame surface/buffer
      ↓
AV1 encoder
```

Investigate the available Android WebView rendering APIs and determine the lowest-copy path.

Avoid:

```text
WebView
 ↓
Bitmap
 ↓
JPEG
 ↓
AV1
```

unless used only as a temporary proof-of-concept.

Avoid unnecessary CPU copies.


# 14. AV1 Encoder

Create an abstraction.

Kotlin interface concept:

```kotlin
interface VideoEncoder {
    fun configure(config: EncoderConfig)
    fun start()
    fun encode(frame: VideoFrame)
    fun requestKeyFrame()
    fun stop()
    fun release()
}
```

Implementation:

```text
Av1VideoEncoder
```

Use Android MediaCodec where AV1 encoding is available.

At startup query:

- AV1 encoder availability
- hardware acceleration
- supported resolutions
- supported frame rates
- supported bitrate ranges
- supported profiles
- supported color formats

Do not assume AV1 hardware encoding exists.


# 15. Codec Capability Negotiation

Host and client exchange capabilities.

Example:

```text
HOST:
AV1
1920x1080
30 FPS
hardware encoder

CLIENT:
AV1
1920x1080
60 FPS
hardware decoder
```

The host chooses a mutually supported configuration.

Example:

```text
codec = AV1
width = 1280
height = 720
fps = 30
bitrate = 2 Mbps
```

If the client cannot decode AV1:

```text
CLIENT → CAPABILITY_REJECT
```

Initial implementation may simply reject incompatible clients.

Codec fallback can be implemented later.


# 16. AV1 Stream

The stream must support:

```text
CONFIG
KEYFRAME
INTER_FRAME
```

A new client cannot start from an arbitrary inter-frame.

Therefore:

```text
CLIENT JOIN
 ↓
KEYFRAME_REQUEST
 ↓
HOST encoder
 ↓
AV1 keyframe
 ↓
CLIENT
 ↓
decode subsequent frames
```

When a client joins, immediately provide a keyframe.


# 17. Frame Metadata

Each video frame should have:

```text
streamId
frameId
timestamp
frameType
payloadLength
```

Example:

```text
streamId = 1
frameId = 1045
timestamp = ...
frameType = INTER
payloadLength = ...
```

Frame ordering must be detected.

If an inter-frame arrives without the required previous frame:

```text
request keyframe
```

Do not attempt to reconstruct a corrupted chain.


# 18. Bandwidth Strategy

Power Present is intended to minimize bandwidth.

Do not transmit frames unnecessarily.

Implement:

```text
static page
    ↓
low/no frame updates

user interaction
    ↓
temporarily increase frame rate

animation
    ↓
continuous frames

video
    ↓
continuous frames
```

Start with a simple fixed configuration.

Optimize after correctness.

Initial target:

```text
1280x720
30 FPS maximum
AV1
2 Mbps starting bitrate
```

Do not prematurely optimize encoder parameters.


# 19. Backpressure

The host must never create an unlimited frame queue.

Bad:

```text
encode
 ↓
queue
 ↓
queue
 ↓
queue
 ↓
memory explosion
```

Instead:

```text
latest frame
     ↓
encoder
     ↓
network
```

For interactive presentation, dropping stale frames is preferable to increasing latency.

Implement a bounded queue.

When the network is congested:

```text
drop stale video frames
keep newest useful frame
```

Input events must have higher priority than video frames.


# 20. Transport Priorities

Power Present should logically classify traffic:

### Priority 1

Input:

```text
TOUCH
MOUSE
KEYBOARD
SCROLL
```

### Priority 2

Control:

```text
SESSION
CONFIG
KEYFRAME_REQUEST
```

### Priority 3

Video:

```text
AV1 frames
```

Input latency is more important than preserving every video frame.


# 21. Orbit X Integration

Do not create a separate socket system if Orbit X already provides:

- peer discovery
- peer authentication
- encryption
- reliable transport
- connection management
- P2P routing

Create a Power Present service over Orbit X.

Conceptually:

```text
Orbit X
  │
  ├── Chat
  ├── File Transfer
  ├── Remote Control
  └── Power Present
```

Power Present should consume an Orbit X transport interface.

Example conceptual API:

```go
type PowerPresentTransport interface {
    SendControl(...)
    SendInput(...)
    SendVideo(...)
    Receive(...)
}
```

Adapt this to the existing Orbit X architecture rather than duplicating it.


# 22. Security

Power Present must inherit Orbit X peer authentication and encryption.

Do not introduce an independent encryption scheme for video unless there is a concrete requirement.

Do not expose the Power Present server directly to the public Internet.

All presentation traffic should flow through the authenticated Orbit X peer connection.


# 23. Flutter UI

Host screen:

```text
Power Present

[ Start Presentation ]

URL:
[ https://example.com             ]

Quality:
[ Auto ]

Resolution:
[ Auto ]

FPS:
[ Auto ]

Connected:
2 devices

Devices:
● Phone
● Laptop

[ Stop ]
```

Client screen:

```text
Power Present

Connected to:
Sivamani's Device

┌───────────────────────┐
│                       │
│     AV1 WebView       │
│      presentation     │
│                       │
└───────────────────────┘

Latency: 32 ms
Bitrate: 1.8 Mbps
FPS: 29
```

Do not expose complex technical settings in the MVP.


# 24. Implementation Phases

## Phase 0 — Repository investigation

AI agent must first inspect the existing Orbit X project.

Identify:

- Flutter architecture
- Android Kotlin architecture
- Go architecture
- existing P2P transport
- peer discovery
- encryption
- session/pairing
- native bridges
- existing file-transfer protocol
- existing message framing
- existing dependency versions

Do NOT rewrite existing networking.

Produce:

```text
POWER_PRESENT_ARCHITECTURE.md
```

before implementation.


## Phase 1 — WebView

Implement:

- Power Present screen
- Android WebView
- URL loading
- navigation
- lifecycle
- fullscreen presentation area

Acceptance:

```text
Open Power Present
 ↓
enter URL
 ↓
website appears in host WebView
```


## Phase 2 — WebView capture proof

Before networking, prove:

```text
WebView
 ↓
capture
 ↓
AV1 encoder
 ↓
AV1 packets
```

Display encoder statistics.

Acceptance:

- no full-screen MediaProjection
- WebView only
- AV1 encoder detected
- frames successfully encoded
- stable memory usage


## Phase 3 — AV1 decode proof

On a second Android device:

```text
AV1 packets
 ↓
decoder
 ↓
render surface
```

Initially use a local transport if necessary.

Acceptance:

- remote WebView is visible
- acceptable latency
- no severe frame corruption


## Phase 4 — Orbit X transport

Replace the temporary transport with Orbit X P2P.

Acceptance:

```text
Device A
WebView
 ↓
AV1
 ↓
Orbit X P2P
 ↓
Device B
decoder
 ↓
display
```


## Phase 5 — Touch

Implement:

```text
touch down
touch move
touch up
```

Acceptance:

```text
Device B touches link
 ↓
Orbit X
 ↓
Device A WebView
 ↓
link activates
```

This is the first complete end-to-end Power Present milestone.


## Phase 6 — Scroll

Implement normalized scroll events.

Acceptance:

- client scroll controls host WebView
- rendered result appears on client
- low input latency


## Phase 7 — Keyboard and mouse

Implement:

- key down
- key up
- text input
- mouse movement
- mouse button events

Test with:

- search boxes
- forms
- text editors
- menus
- drag/drop


## Phase 8 — Multi-client

Allow:

```text
Host
 ├── Client A
 ├── Client B
 └── Client C
```

Each client receives the same AV1 stream.

Each client may send input.

The host serializes input events.


## Phase 9 — Adaptive streaming

Implement:

- bitrate adaptation
- FPS adaptation
- resolution adaptation
- congestion detection
- frame dropping
- keyframe requests

Do this only after stable operation.


## Phase 10 — Orbit X integration hardening

Integrate with:

- existing pairing
- existing peer identity
- existing P2P connection
- existing encryption
- existing reconnection
- existing lifecycle

No duplicate infrastructure.


# 25. Testing Matrix

Test host:

- Android low-end
- Android mid-range
- Android high-end

Test clients:

- low resolution
- high resolution
- different aspect ratios
- portrait
- landscape

Test websites:

```text
static HTML
React
Next.js
animations
canvas
SVG
WebGL
video
maps
forms
file upload
drag/drop
keyboard input
```

Test network conditions:

```text
excellent
medium
high latency
packet loss
bandwidth constrained
disconnect/reconnect
```

Test input:

```text
tap
long press
drag
scroll
pinch if supported
keyboard
mouse
```

Do not consider Power Present complete until reconnect and keyframe recovery work.


# 26. Performance Metrics

Collect:

```text
capture FPS
encoded FPS
decoded FPS
display FPS
bitrate
encoder latency
decode latency
network latency
end-to-end latency
dropped frames
keyframe count
packet loss
input latency
CPU usage
GPU usage
memory usage
battery usage
```

Display a debug overlay in development builds.


# 27. Target Performance

Initial target:

```text
Resolution: 1280x720
FPS: 30
Codec: AV1
End-to-end latency: <150 ms on good network
Input latency: <100 ms on good network
Bounded memory
No continuous full-screen capture
```

Do not treat these as hard guarantees.

Optimize based on measurements.


# 28. Error Handling

Handle:

```text
NO_AV1_ENCODER
NO_AV1_DECODER
UNSUPPORTED_PROFILE
UNSUPPORTED_RESOLUTION
SESSION_NOT_FOUND
PEER_DISCONNECTED
VIDEO_TIMEOUT
KEYFRAME_TIMEOUT
DECODE_ERROR
ENCODE_ERROR
NETWORK_CONGESTION
INPUT_REJECTED
WEBVIEW_ERROR
```

When decoder loses synchronization:

```text
decoder error
 ↓
discard dependent frames
 ↓
KEYFRAME_REQUEST
 ↓
resume
```


# 29. Logging

Use structured logs.

Example:

```text
[PowerPresent][Host][WebView]
[PowerPresent][Encoder]
[PowerPresent][Decoder]
[PowerPresent][Transport]
[PowerPresent][Input]
[PowerPresent][Session]
```

Do not log:

- webpage passwords
- typed sensitive text
- authentication tokens
- cookies
- private page content

Debug video statistics are acceptable.


# 30. AI Agent Execution Rules

The AI agent must follow these rules:

1. Inspect existing Orbit X code before creating new infrastructure.
2. Reuse existing Orbit X P2P transport.
3. Reuse existing authentication and encryption.
4. Do not introduce WebRTC.
5. Do not use MediaProjection for Power Present.
6. Do not implement DOM synchronization.
7. Do not implement JavaScript synchronization.
8. Do not create a custom browser engine.
9. Do not duplicate Orbit X networking.
10. Implement one phase at a time.
11. Compile/test after each phase.
12. Do not proceed to the next phase if the current phase fails.
13. Keep Android-specific code in Kotlin.
14. Keep transport/session logic in Go where appropriate.
15. Keep application UI in Flutter.
16. Keep codec implementation behind an interface.
17. Do not assume AV1 hardware support.
18. Query codec capabilities at runtime.
19. Keep video queues bounded.
20. Prioritize input over video.
21. Prefer dropping stale video frames over increasing latency.
22. Do not make unrelated changes to Orbit X.
23. Do not rewrite working Orbit X components.
24. Document every new native dependency.
25. Document every new public interface.


# 31. Definition of Done

Power Present MVP is complete when:

```text
1. Host opens a WebView.
2. Host loads an arbitrary website.
3. Host captures only the WebView.
4. Host encodes the WebView output as AV1.
5. AV1 travels through Orbit X P2P.
6. Client decodes AV1.
7. Client displays the WebView in realtime.
8. Client touch events travel through Orbit X.
9. Host injects those events into its WebView.
10. Client sees the resulting WebView changes.
11. Scroll works.
12. Keyboard input works.
13. Disconnect/reconnect works.
14. A new client can request a keyframe.
15. No MediaProjection is required.
16. No WebRTC is required.
17. No DOM synchronization is required.
18. No independent website execution occurs on clients.
```

The final MVP flow must be:

```text
                 ┌──────────────────────────┐
                 │       HOST DEVICE        │
                 │                          │
                 │ Flutter                  │
                 │    ↓                     │
                 │ Kotlin WebView           │
                 │    ↓                     │
                 │ WebView rendering        │
                 │    ↓                     │
                 │ AV1 encoder              │
                 └──────────┬───────────────┘
                            │
                       Orbit X P2P
                            │
                     AV1 + CONTROL
                            │
                 ┌──────────┴───────────┐
                 ↓                      ↓
             CLIENT A                CLIENT B
             AV1 decode              AV1 decode
             render                  render
                 │                      │
              touch                  touch
              keyboard               keyboard
                 │                      │
                 └──────────┬───────────┘
                            ↓
                       Orbit X P2P
                            ↓
                       HOST WEBVIEW
```


# 32. Future Extensions

Only after MVP stability:

- adaptive AV1 bitrate
- AV1 hardware capability optimization
- multiple simultaneous viewers
- presenter permissions
- viewer permissions
- remote cursor
- pointer visualization
- audio streaming
- synchronized video playback
- file presentation
- PDF presentation
- image presentation
- local file WebView presentation
- low-bandwidth mode
- automatic quality selection
- presentation recording
- presentation pause/freeze
- frame caching
- partial update optimization
- AV1 scalable coding if supported
- desktop client
- non-Android presenter
- Orbit X remote-control integration


# 33. Final Product Principle

Power Present must follow this principle:

> Execute once, render once, encode once, distribute many times.

The authoritative WebView executes the website.

The authoritative WebView is captured.

The rendered output is encoded as AV1.

Orbit X distributes the encoded stream.

Remote devices send only lightweight input events back.

Do not replicate the browser.

Do not replicate the DOM.

Do not replicate JavaScript.

Do not replicate webpage resources.

Replicate the rendered result and user intent.
