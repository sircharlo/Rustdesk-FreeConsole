# RustDesk Desktop Client - Technical Architecture Report

> Comprehensive analysis of the RustDesk desktop client source code from  
> [github.com/rustdesk/rustdesk](https://github.com/rustdesk/rustdesk)  
> Purpose: Feasibility assessment for building a browser-based viewer/controller  
> integrated with the BetterDesk web panel.

---

## Table of Contents

1. [Repository Overview](#1-repository-overview)
2. [Key Modules & Source Structure](#2-key-modules--source-structure)
3. [Protobuf Message Definitions](#3-protobuf-message-definitions)
4. [Connection Protocol Flow](#4-connection-protocol-flow)
5. [Video & Audio Codecs](#5-video--audio-codecs)
6. [Keyboard & Mouse Input](#6-keyboard--mouse-input)
7. [WebSocket Support](#7-websocket-support)
8. [Existing Web Client Implementations](#8-existing-web-client-implementations)
9. [Browser-Based Viewer Feasibility](#9-browser-based-viewer-feasibility)
10. [BetterDesk Integration Roadmap](#10-betterdesk-integration-roadmap)

---

## 1. Repository Overview

| Property | Value |
|----------|-------|
| **URL** | `https://github.com/rustdesk/rustdesk` |
| **Version** | v1.4.5 (as of analysis) |
| **Stars** | 108k+ |
| **Languages** | Rust 65%, Dart 25.9%, other 9.1% |
| **License** | AGPL-3.0 |
| **UI Framework** | Flutter (desktop, mobile, web via WASM) |
| **Build System** | Cargo (Rust) + Flutter + vcpkg (native deps) |

### Top-Level Directory Structure

```
rustdesk/
├── src/                    # Core Rust source code
├── libs/                   # Core libraries (submodules + internal)
│   ├── hbb_common/         # (Submodule) Protobuf, networking, config
│   ├── scrap/              # Screen capture
│   ├── enigo/              # Keyboard/mouse simulation
│   ├── clipboard/          # File clipboard (Win/Linux/macOS)
│   ├── portable/           # Portable mode support
│   ├── remote_printer/     # Remote printing
│   ├── virtual_display/    # Virtual display driver
│   └── libxdo-sys-stub/    # X11 automation stub
├── flutter/                # Flutter UI (desktop + mobile)
│   ├── lib/                # Dart source code
│   ├── android/            # Android platform
│   ├── ios/                # iOS platform
│   ├── linux/              # Linux platform
│   ├── macos/              # macOS platform
│   ├── windows/            # Windows platform
│   └── pubspec.yaml        # Flutter dependencies
├── res/                    # Resources
├── examples/               # Example code
├── docs/                   # Documentation
├── .github/                # CI/CD workflows
├── Cargo.toml              # Rust dependencies
├── Cargo.lock              # Locked dependencies
├── build.rs                # Rust build script
├── build.py                # Python build orchestrator
└── Dockerfile              # Docker build
```

### hbb_common Submodule

The `hbb_common` library is a separate repository at **`https://github.com/rustdesk/hbb_common`** (referenced in `.gitmodules`). It contains:

- `protos/message.proto` — Peer-to-peer message definitions
- `protos/rendezvous.proto` — Rendezvous server message definitions
- `src/` — TCP/UDP wrappers, config management, WebSocket utilities, encryption helpers

---

## 2. Key Modules & Source Structure

### `src/` Directory

| File/Directory | Purpose |
|----------------|---------|
| `client.rs` | **Core client logic** — connection, video/audio handling, input sending |
| `rendezvous_mediator.rs` | **Communication with hbbs** — registration, hole-punching, relay |
| `server.rs` | Controlled-side services (audio, clipboard, input, video) |
| `flutter.rs` | Flutter bridge — Dart-to-Rust integration |
| `flutter_ffi.rs` | FFI bindings for Flutter |
| `ipc.rs` | Inter-process communication |
| `keyboard.rs` | Keyboard event handling |
| `kcp_stream.rs` | KCP stream implementation |
| `port_forward.rs` | Port forwarding |
| `common.rs` | Shared utilities |
| `core_main.rs` | Core entry points |
| `lib.rs` | Library root |
| `main.rs` | Binary entry point |
| `client/` | Client-side sub-modules |
| `server/` | Server-side sub-modules |
| `hbbs_http/` | HBBS HTTP service code |
| `lang/` | Internationalization strings |
| `platform/` | Platform-specific code |
| `plugin/` | Plugin system |
| `privacy_mode/` | Privacy mode implementation |
| `ui/` | UI-related code |
| `whiteboard/` | Whiteboard feature |

### Key Data Types (from `client.rs`)

```rust
// Media data passed between threads
enum MediaData {
    VideoQueue,
    VideoFrame(Box<VideoFrame>),
    AudioFrame(Box<AudioFrame>),
    AudioFormat(AudioFormat),
    Reset,
    RecordScreen(bool),
}

// Commands sent to the connection
enum Data {
    Close,
    Login { ... },
    Message(Message),
    SendFiles { ... },
    RemoveDirAll { ... },
    // ... more variants
}
```

### Key Structs

| Struct | Purpose |
|--------|---------|
| `Client` | Main client — `start()`, `connect()`, `request_relay()`, `create_relay()`, `secure_connection()` |
| `LoginConfigHandler` | Login config, options, peer config, session management |
| `VideoHandler` | Video frame decoding — `Decoder`, `ImageRgb`, `ImageTexture`, format detection |
| `AudioHandler` | Audio decoding — `magnum-opus::Decoder`, sample rate conversion, buffer management |
| `RendezvousMediator` | Manages hbbs connection — registration, hole-punching dispatch |

### The `Interface` Trait

All UI backends (Flutter, Sciter, etc.) implement this trait:

```rust
trait Interface {
    fn send(&self, data: Data);
    fn msgbox(&self, msgtype: &str, title: &str, text: &str, link: &str);
    fn handle_login_error(&self, err: &str) -> bool;
    fn handle_peer_info(&mut self, pi: PeerInfo);
    fn handle_hash(&mut self, hash: Hash, peer: &mut Stream);
    fn handle_login_from_ui(&self, os_username: String, os_password: String, ...);
    fn handle_test_delay(&mut self, t: TestDelay, peer: &mut Stream);
    // ... more methods
}
```

---

## 3. Protobuf Message Definitions

### Source Files

- **`protos/message.proto`** — Peer-to-peer protocol (video, audio, input, clipboard, files)
- **`protos/rendezvous.proto`** — Rendezvous server protocol (registration, hole-punching, relay)

Both use `syntax = "proto3"` with package `hbb`.

### 3.1 Rendezvous Protocol (`rendezvous.proto`)

#### Top-Level Envelope

```protobuf
message RendezvousMessage {
  oneof union {
    RegisterPeer register_peer = 6;
    RegisterPeerResponse register_peer_response = 7;
    PunchHoleRequest punch_hole_request = 8;
    PunchHole punch_hole = 9;
    PunchHoleSent punch_hole_sent = 10;
    PunchHoleResponse punch_hole_response = 11;
    FetchLocalAddr fetch_local_addr = 12;
    LocalAddr local_addr = 13;
    ConfigUpdate configure_update = 14;
    RegisterPk register_pk = 15;
    RegisterPkResponse register_pk_response = 16;
    SoftwareUpdate software_update = 17;
    RequestRelay request_relay = 18;
    RelayResponse relay_response = 19;
    TestNatRequest test_nat_request = 20;
    TestNatResponse test_nat_response = 21;
    PeerDiscovery peer_discovery = 22;
    OnlineRequest online_request = 23;
    OnlineResponse online_response = 24;
    KeyExchange key_exchange = 25;
    HealthCheck hc = 26;
  }
}
```

#### Key Rendezvous Messages

```protobuf
message RegisterPeer {
  string id = 1;
  int32 serial = 2;
}

message RegisterPk {
  string id = 1;
  bytes uuid = 2;
  bytes pk = 3;
  string old_id = 4;
  bool no_register_device = 5;
}

message PunchHoleRequest {
  string id = 1;
  NatType nat_type = 2;
  string licence_key = 3;
  ConnType conn_type = 4;
  string token = 5;
  string version = 6;
  int32 udp_port = 7;
  bool force_relay = 8;
  int32 upnp_port = 9;
  bytes socket_addr_v6 = 10;
}

message PunchHoleResponse {
  bytes socket_addr = 1;
  bytes pk = 2;
  enum Failure {
    ID_NOT_EXIST = 0;
    OFFLINE = 2;
    LICENSE_MISMATCH = 3;
    LICENSE_OVERUSE = 4;
  }
  Failure failure = 3;
  string relay_server = 4;
  oneof union {
    NatType nat_type = 5;
    bool is_local = 6;
  }
  string other_failure = 7;
}

message RequestRelay {
  string id = 1;
  string uuid = 2;
  bytes socket_addr = 3;
  string relay_server = 4;
  bool secure = 5;
  string licence_key = 6;
  ConnType conn_type = 7;
  string token = 8;
  ControlPermissions control_permissions = 9;
}

message RelayResponse {
  bytes socket_addr = 1;
  string uuid = 2;
  string relay_server = 3;
  oneof union {
    string id = 4;
    bytes pk = 5;
  }
  string refuse_reason = 6;
  string version = 7;
}

enum NatType {
  UNKNOWN_NAT = 0;
  ASYMMETRIC = 1;
  SYMMETRIC = 2;
}

enum ConnType {
  DEFAULT_CONN = 0;
  FILE_TRANSFER = 1;
  PORT_FORWARD = 2;
  RDP = 3;
  VIEW_CAMERA = 4;
  TERMINAL = 5;
}
```

### 3.2 Peer-to-Peer Protocol (`message.proto`)

#### Top-Level Envelope

```protobuf
message Message {
  oneof union {
    SignedId signed_id = 3;
    PublicKey public_key = 4;
    TestDelay test_delay = 5;
    VideoFrame video_frame = 6;
    LoginRequest login_request = 7;
    LoginResponse login_response = 8;
    Hash hash = 9;
    MouseEvent mouse_event = 10;
    AudioFrame audio_frame = 11;
    CursorData cursor_data = 12;
    CursorPosition cursor_position = 13;
    uint64 cursor_id = 14;
    KeyEvent key_event = 15;
    Clipboard clipboard = 16;
    FileAction file_action = 17;
    FileResponse file_response = 18;
    Misc misc = 19;
    Cliprdr cliprdr = 20;
    MessageBox message_box = 21;
    SwitchSidesResponse switch_sides_response = 22;
    VoiceCallRequest voice_call_request = 23;
    VoiceCallResponse voice_call_response = 24;
    PeerInfo peer_info = 25;
    PointerDeviceEvent pointer_device_event = 26;
    Auth2FA auth_2fa = 27;
    MultiClipboards multi_clipboards = 28;
    ScreenshotRequest screenshot_request = 29;
    ScreenshotResponse screenshot_response = 30;
    TerminalAction terminal_action = 31;
    TerminalResponse terminal_response = 32;
  }
}
```

#### Video Messages

```protobuf
message EncodedVideoFrame {
  bytes data = 1;
  bool key = 2;
  int64 pts = 3;
}

message EncodedVideoFrames {
  repeated EncodedVideoFrame frames = 1;
}

message VideoFrame {
  oneof union {
    EncodedVideoFrames vp9s = 6;
    RGB rgb = 7;
    YUV yuv = 8;
    EncodedVideoFrames h264s = 10;
    EncodedVideoFrames h265s = 11;
    EncodedVideoFrames vp8s = 12;
    EncodedVideoFrames av1s = 13;
  }
  int32 display = 14;
}
```

#### Login Messages

```protobuf
message LoginRequest {
  string username = 1;
  bytes password = 2;
  string my_id = 4;
  string my_name = 5;
  OptionMessage option = 6;
  oneof union {
    FileTransfer file_transfer = 7;
    PortForward port_forward = 8;
    ViewCamera view_camera = 15;
    Terminal terminal = 16;
  }
  bool video_ack_required = 9;
  uint64 session_id = 10;
  string version = 11;
  OSLogin os_login = 12;
  string my_platform = 13;
  bytes hwid = 14;
}

message LoginResponse {
  oneof union {
    string error = 1;
    PeerInfo peer_info = 2;
  }
  bool enable_trusted_devices = 3;
}

message Hash {
  string salt = 1;
  string challenge = 2;
}
```

#### Input Messages

```protobuf
message MouseEvent {
  int32 mask = 1;      // buttons << 3 | type (1=down, 2=up, 3=wheel, 4=trackpad)
  sint32 x = 2;
  sint32 y = 3;
  repeated ControlKey modifiers = 4;
}

message KeyEvent {
  bool down = 1;
  bool press = 2;
  oneof union {
    ControlKey control_key = 3;
    uint32 chr = 4;
    uint32 unicode = 5;
    string seq = 6;
    uint32 win2win_hotkey = 7;
  }
  repeated ControlKey modifiers = 8;
  KeyboardMode mode = 9;
}

enum KeyboardMode {
  Legacy = 0;
  Map = 1;
  Translate = 2;
  Auto = 3;
}

message PointerDeviceEvent {
  oneof union {
    TouchEvent touch_event = 1;
  }
  repeated ControlKey modifiers = 2;
}
```

#### Audio Messages

```protobuf
message AudioFormat {
  uint32 sample_rate = 1;
  uint32 channels = 2;
}

message AudioFrame {
  bytes data = 1;
}
```

#### Codec Capability Negotiation

```protobuf
message SupportedDecoding {
  enum PreferCodec {
    Auto = 0; VP9 = 1; H264 = 2; H265 = 3; VP8 = 4; AV1 = 5;
  }
  int32 ability_vp9 = 1;
  int32 ability_h264 = 2;
  int32 ability_h265 = 3;
  PreferCodec prefer = 4;
  int32 ability_vp8 = 5;
  int32 ability_av1 = 6;
  CodecAbility i444 = 7;
  Chroma prefer_chroma = 8;
}

message OptionMessage {
  ImageQuality image_quality = 1;
  // ... various BoolOption fields ...
  SupportedDecoding supported_decoding = 10;
  int32 custom_fps = 11;
  // ... more options ...
}
```

#### Display & Cursor

```protobuf
message DisplayInfo {
  sint32 x = 1;
  sint32 y = 2;
  int32 width = 3;
  int32 height = 4;
  string name = 5;
  bool online = 6;
  bool cursor_embedded = 7;
  Resolution original_resolution = 8;
  double scale = 9;
}

message PeerInfo {
  string username = 1;
  string hostname = 2;
  string platform = 3;
  repeated DisplayInfo displays = 4;
  int32 current_display = 5;
  bool sas_enabled = 6;
  string version = 7;
  Features features = 9;
  SupportedEncoding encoding = 10;
  // ...
}

message CursorData {
  uint64 id = 1;
  sint32 hotx = 2;
  sint32 hoty = 3;
  int32 width = 4;
  int32 height = 5;
  bytes colors = 6;
}

message CursorPosition {
  sint32 x = 1;
  sint32 y = 2;
}
```

---

## 4. Connection Protocol Flow

### 4.1 Registration (Controlled Side → hbbs)

```
Controlled Device                     hbbs (Rendezvous Server)
      |                                        |
      |---- RegisterPk (id, uuid, pk) -------->|
      |<--- RegisterPkResponse (keep_alive) ---|
      |                                        |
      |---- RegisterPeer (id, serial) -------->|
      |<--- RegisterPeerResponse --------------|
      |                                        |
      | (repeat RegisterPeer every keep_alive) |
```

### 4.2 Connection Establishment (Controller → Controlled)

```
Controller          hbbs              hbbr (Relay)        Controlled
    |                 |                    |                    |
    |-- PunchHoleRequest(id,nat,token) -->|                    |
    |                 |-- PunchHole ------>|                    |
    |                 |                    |                    |
    |<-- PunchHoleResponse(addr/relay) ---|                    |
    |                 |                    |                    |

    === OPTION A: Direct Connection (UDP hole-punch) ===
    |<================== UDP hole punch ==================>|
    |                                                       |

    === OPTION B: Relay Connection (via hbbr) ===
    |-- RequestRelay(id, uuid, relay_server) -->|           |
    |                 |                    |<-- RequestRelay |
    |<-- RelayResponse(uuid, relay_server) ----|           |
    |============ TCP to hbbr ============>|<== TCP ======>|
```

### 4.3 Secure Handshake (after TCP/Relay established)

```
Controller                              Controlled
    |                                        |
    |<-------- SignedId (signed peer id) ----|
    |                                        |
    |-------- PublicKey (asym + sym) ------->|
    |                                        |
    | (connection is now encrypted)          |
    |                                        |
    |<-------- Hash (salt, challenge) -------|
    |                                        |
    |-------- LoginRequest (credentials) --->|
    |                                        |
    |<-------- LoginResponse (PeerInfo) -----|
    |                                        |
    | (session established, media flows)     |
```

### 4.4 Media Loop

```
Controller                              Controlled
    |                                        |
    |<--- VideoFrame (VP9/H264/H265/AV1) ---|  (continuous)
    |<--- AudioFrame (Opus-encoded) ---------|  (continuous)
    |<--- CursorData (shape, colors) --------|  (on change)
    |<--- CursorPosition (x, y) -------------|  (on move)
    |                                        |
    |--- MouseEvent (mask, x, y, mods) ---->|  (user input)
    |--- KeyEvent (key, mode, mods) -------->|  (user input)
    |--- Clipboard (text/image/rtf) -------->|  (on paste)
    |                                        |
    |<-> Misc (options, permissions, etc.) <>|  (bidirectional)
    |<-> TestDelay (latency measurement) --->|  (periodic)
```

### 4.5 Key Implementation Details

**From `client.rs` — `Client::start()`:**

1. Resolve rendezvous server address
2. Connect via TCP (or WebSocket if `use_ws()` returns true)
3. If server key/token present: secure the TCP stream with `secure_tcp()`
4. Send `PunchHoleRequest` with: peer ID, token, NAT type, connection type
5. Receive `PunchHoleResponse` (direct peer address) or `RelayResponse` (relay)
6. For relay: connect to hbbr, send `RequestRelay` with UUID
7. After connection: `secure_connection()` — exchange `SignedId` and `PublicKey`
8. Server sends `Hash(salt, challenge)` for password verification
9. Client sends `LoginRequest` with hashed credentials
10. Server responds with `LoginResponse(PeerInfo)` containing display info, encoding support

**From `rendezvous_mediator.rs` — `RendezvousMediator::start()`:**

- Uses TCP path if `use_ws()` || `Config::is_proxy()` || `is_udp_disabled()`
- Otherwise uses UDP with `FramedSocket`
- Handles `PunchHole` by decoding peer address, checking NAT types
- Forces relay for symmetric NAT or when `use_ws()` is true

---

## 5. Video & Audio Codecs

### 5.1 Video Codecs

| Codec | Library | Cargo Feature | Browser Decodable? |
|-------|---------|---------------|--------------------|
| **VP9** | libvpx (vcpkg) | default | Yes (WebCodecs / MSE) |
| **VP8** | libvpx (vcpkg) | default | Yes (WebCodecs / MSE) |
| **AV1** | aom (vcpkg) | default | Yes (WebCodecs / MSE) |
| **H.264** | hwcodec (FFmpeg) | `hwcodec` feature | Yes (WebCodecs / MSE) |
| **H.265** | hwcodec (FFmpeg) | `hwcodec` feature | Partial (Safari, some Chrome) |
| **VRAM** | GPU direct | `vram` feature | N/A |

**Encoding side** (controlled device): Uses `scrap` library for screen capture → encodes with VP9/AV1/H264 depending on negotiated codec.

**Decoding side** (controller): `VideoHandler` in `client.rs` uses `Decoder::handle_video_frame()` → detects format via `CodecFormat::from(&vf)` → decodes to RGB for display.

**Codec Negotiation:** During login, controller sends `SupportedDecoding` in `OptionMessage`. Controlled device selects the best matching codec. Format can switch mid-stream; the client detects format changes and reconfigures the decoder.

### 5.2 Audio Codec

| Codec | Library | Usage |
|-------|---------|-------|
| **Opus** | `magnum-opus` (rustdesk-org fork) | Encoding & decoding |
| **cpal** | Platform audio device | Playback (non-Linux) |
| **PulseAudio** | `psimple` crate | Playback (Linux) |

**Audio Flow:**
1. Controlled side captures audio → encodes with Opus → sends `AudioFrame`
2. Controller receives `AudioFormat` (sample_rate, channels) → configures decoder
3. `AudioHandler` decodes Opus frames → resamples if device rate differs → plays back
4. Channel resampling handles mono↔stereo conversion

### 5.3 Native Dependencies (vcpkg)

```
libvpx      — VP8/VP9 codec
libyuv      — YUV format conversion
opus         — Audio codec
aom          — AV1 codec
```

---

## 6. Keyboard & Mouse Input

### 6.1 Mouse Events

From `client.rs` — `send_mouse()`:

```rust
// mask format: buttons << 3 | event_type
// event_type: 1=down, 2=up, 3=wheel, 4=trackpad
// buttons: left=1, right=2, middle=4, back=8, forward=16

MouseEvent {
    mask: (button << 3) | event_type,
    x: position_x,  // sint32, relative to remote display
    y: position_y,
    modifiers: [Alt, Shift, Control, Meta],  // as needed
}
```

### 6.2 Keyboard Events

```protobuf
KeyEvent {
    down: bool,          // true = key down, false = key up
    press: bool,         // true = full click (down+up)
    union: {
        control_key: ControlKey,    // Special keys (F1-F12, arrows, etc.)
        chr: uint32,                // Position key code (scancode/keycode)
        unicode: uint32,            // Unicode character
        seq: string,                // Character sequence
        win2win_hotkey: uint32,     // Windows-to-Windows hotkey
    },
    modifiers: [ControlKey],        // Active modifiers
    mode: KeyboardMode,             // Legacy, Map, Translate, Auto
}
```

### 6.3 ControlKey Enum (subset)

```
Alt, Backspace, CapsLock, Control, Delete, DownArrow, End, Escape,
F1-F12, Home, LeftArrow, Meta, PageDown, PageUp, Return, RightArrow,
Shift, Space, Tab, UpArrow, Numpad0-9, Insert, NumLock, Scroll,
CtrlAltDel, LockScreen, ...
```

### 6.4 Touch/Pointer Events

```protobuf
message PointerDeviceEvent {
    TouchEvent touch_event = 1;  // Scale, pan start/update/end
    repeated ControlKey modifiers = 2;
}
```

---

## 7. WebSocket Support

### Current State in RustDesk

WebSocket support is **already built into the RustDesk protocol stack**:

1. **`use_ws()` function** — Checked throughout `client.rs` and `rendezvous_mediator.rs`
2. **`hbb_common::websocket::check_ws()`** — URL transformation for WebSocket connections
3. **`tokio-tungstenite`** — WebSocket library used in hbb_common
4. **hbbs already supports WebSocket** — The BetterDesk hbbs binary uses `tokio_tungstenite`

### WebSocket Behavior When Enabled

When `use_ws()` returns `true`:
- Rendezvous mediator uses TCP path (not UDP)
- `force_relay = true` — all connections go through hbbr relay
- TCP connections are wrapped in WebSocket frames
- Direct UDP hole-punching is **disabled**
- All traffic flows: `Controller ↔ [WS] ↔ hbbs ↔ hbbr ↔ Controlled`

### WebSocket Protocol Path

```
Browser                    hbbs (WS :21118)           hbbr (TCP :21117)        Controlled
   |                            |                          |                       |
   |== WebSocket connect =====>|                          |                       |
   |-- PunchHoleRequest ------>|                          |                       |
   |<-- RelayResponse ---------|                          |                       |
   |                            |                          |                       |
   |== WebSocket to hbbr ============================>|                       |
   |                            |                    |<== TCP ================>|
   |<===================== Relay traffic ===============================>|
```

### Port Configuration

| Port | Protocol | Purpose |
|------|----------|---------|
| 21116 | TCP/UDP | Rendezvous server (native) |
| 21117 | TCP | Relay server |
| **21118** | **WebSocket** | **Rendezvous server (WebSocket)** |
| **21119** | **WebSocket** | **Relay server (WebSocket)** |

> **Note:** Ports 21118 and 21119 are the WebSocket equivalents of 21116 and 21117.

---

## 8. Existing Web Client Implementations

### 8.1 RustDesk Official Flutter Web Client

RustDesk's Flutter codebase can be compiled to **WebAssembly (WASM)** for browser use. The web build was previously referenced in the repo at `flutter/web/` but is not always maintained as a first-class target. The web client uses:

- **Flutter WASM** — Full Flutter app compiled for browser
- **protobuf.js** — Protobuf serialization in the browser
- **WebSocket** — Communication with hbbs/hbbr
- **WebCodecs API** — Video decoding (VP9, H264, AV1)

The Docker image `keyurbhole/flutter_web_desk` was previously used to distribute this web client.

### 8.2 lejianwen/rustdesk-api (2.6k stars)

The most popular third-party project with a web client:

- **URL:** `https://github.com/lejianwen/rustdesk-api`
- **Tech:** Go backend + Flutter web client
- **Features:** Web admin panel, web client, OIDC login, address book sync
- **Web Client v2 was removed** due to DMCA takedown (commit message: "docs: Removed webclient2 because of DMCA")
- Uses custom WebSocket host configuration (`RUSTDESK_API_RUSTDESK_WS_HOST`)
- Has online status query via magic queryonline method

### 8.3 Other Projects

| Project | Approach | Stars |
|---------|----------|-------|
| `linuxserver/docker-rustdesk` | Full RustDesk desktop in Docker (noVNC) | 57 |
| `pmietlicki/docker-rustdesk-web-client` | Docker image with RustDesk web client | 24 |
| `GawdTech-Tools/RustDesk-Web` | RustDesk Web Client (JavaScript) | 0 |

### 8.4 nicennnnnnnlee

**Confirmed: This user has ZERO RustDesk repositories.** Their GitHub profile (100 repos) focuses on BilibiliDown, LiveRecorder, and other Chinese media tools. No RustDesk web client analysis blog posts were found.

---

## 9. Browser-Based Viewer Feasibility

### 9.1 Core Requirements

| Requirement | Browser API | Status |
|-------------|-------------|--------|
| WebSocket connection | `WebSocket` API | ✅ Fully supported |
| Protobuf serialization | `protobuf.js` / `protobufjs` | ✅ Mature library |
| VP9 video decoding | `WebCodecs` API | ✅ Chrome 94+, Firefox 130+ |
| H.264 video decoding | `WebCodecs` API | ✅ All modern browsers |
| AV1 video decoding | `WebCodecs` API | ✅ Chrome 94+, Firefox 130+ |
| H.265 video decoding | `WebCodecs` API | ⚠️ Safari only, partial Chrome |
| Opus audio decoding | `WebCodecs` / `AudioContext` | ✅ All modern browsers |
| Canvas rendering | `Canvas 2D` / `WebGL` | ✅ All browsers |
| Keyboard capture | `KeyboardEvent` API | ✅ All browsers |
| Mouse capture | `MouseEvent` / `PointerEvent` | ✅ All browsers |
| Pointer lock | `Pointer Lock` API | ✅ All modern browsers |
| Clipboard access | `Clipboard` API | ⚠️ Requires HTTPS + user gesture |
| File transfer | `File` API + `ReadableStream` | ✅ All modern browsers |
| Encryption (NaCl) | `SubtleCrypto` + `tweetnacl-js` | ✅ Available |

### 9.2 Architecture for Browser Client

```
┌──────────────────────────────────────────────────────┐
│                   Browser (Web Client)                │
│                                                      │
│  ┌──────────┐  ┌───────────┐  ┌──────────────────┐  │
│  │ UI Layer │  │ Input Mgr │  │  Media Pipeline   │  │
│  │ (Canvas) │  │ (KB+Mouse)│  │ (WebCodecs+Opus) │  │
│  └────┬─────┘  └─────┬─────┘  └────────┬─────────┘  │
│       │               │                 │            │
│  ┌────┴───────────────┴─────────────────┴─────────┐  │
│  │            Protocol Layer (protobuf.js)         │  │
│  │  Message ↔ binary serialization/deserialization │  │
│  └──────────────────────┬──────────────────────────┘  │
│                         │                            │
│  ┌──────────────────────┴──────────────────────────┐  │
│  │         Connection Layer (WebSocket)             │  │
│  │  Rendezvous (ws://hbbs:21118)                   │  │
│  │  Relay     (ws://hbbr:21119)                    │  │
│  │  Encryption (tweetnacl-js / SubtleCrypto)       │  │
│  └──────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
         │                              │
    WebSocket                      WebSocket
         │                              │
    ┌────┴────┐                   ┌─────┴─────┐
    │  hbbs   │                   │   hbbr    │
    │ :21118  │                   │  :21119   │
    └─────────┘                   └───────────┘
```

### 9.3 Implementation Complexity Estimate

| Component | Complexity | Effort (days) | Notes |
|-----------|------------|---------------|-------|
| Protobuf JS client | Medium | 3-5 | Generate from .proto files |
| WebSocket connection mgr | Medium | 3-5 | Handle reconnect, keepalive |
| Rendezvous handshake | High | 5-8 | PunchHole → Relay → SecureConnection |
| Encryption layer | High | 5-8 | NaCl box/secretbox, key exchange |
| Login flow | Medium | 2-3 | Hash challenge-response |
| Video decoder (WebCodecs) | High | 5-10 | VP9/H264/AV1, format switching |
| Audio decoder (Opus) | Medium | 3-5 | WebAudio API + Opus.js |
| Canvas renderer | Medium | 3-5 | Cursor overlay, multi-display |
| Keyboard input | Medium | 3-5 | KeyboardMode mapping |
| Mouse input | Low-Medium | 2-3 | Coordinate mapping, pointer lock |
| Clipboard | Medium | 2-3 | Requires HTTPS |
| File transfer | High | 5-8 | Bidirectional, resume support |
| **Total estimate** | | **~40-70 days** | Single developer |

### 9.4 Critical Challenges

1. **Encryption Compatibility** — RustDesk uses `sodiumoxide` (libsodium). Browser must use `tweetnacl-js` or equivalent with identical box/secretbox operations.

2. **Protobuf Wire Format** — Must exactly match Rust's `protobuf` crate output. Use the same `.proto` files with `protobufjs` for JavaScript.

3. **WebSocket Relay Requirement** — Browser clients **cannot** do UDP hole-punching. All connections must go through hbbr relay via WebSocket (port 21119). This adds latency.

4. **Video Frame Reassembly** — `EncodedVideoFrames` contains multiple frames per message. Each must be individually decoded.

5. **H.265 Browser Support** — Limited. Should negotiate VP9 or H.264 as preferred codec.

6. **Latency** — Relay adds ~10-50ms per hop. WebSocket framing adds minimal overhead.

7. **hbbr WebSocket Support** — The current hbbr relay server uses plain TCP. **WebSocket support on port 21119 may need to be added** to the BetterDesk hbbr binary, or a WebSocket-to-TCP proxy must be placed in front.

---

## 10. BetterDesk Integration Roadmap

### Phase 1: Minimal Viewer (View Only)

**Goal:** Display remote desktop in browser, no input.

1. Add protobuf.js generation from `message.proto` + `rendezvous.proto`
2. Implement WebSocket connection to hbbs (port 21118)
3. Implement relay connection to hbbr (port 21119 — may need WS proxy)
4. Implement encryption handshake (NaCl key exchange)
5. Implement login flow (Hash challenge → LoginRequest)
6. Decode video frames with WebCodecs (VP9 preferred)
7. Render to `<canvas>` element
8. Integrate viewer into BetterDesk web panel (Node.js or Flask)

### Phase 2: Full Controller

**Goal:** Add keyboard, mouse, audio.

1. Capture keyboard events → send `KeyEvent` protobuf
2. Capture mouse events → send `MouseEvent` protobuf
3. Implement cursor rendering (CursorData overlay)
4. Add Opus audio decoding + WebAudio playback
5. Add clipboard support (requires HTTPS)

### Phase 3: Advanced Features

1. File transfer UI
2. Multi-display support
3. Quality/FPS controls
4. Connection status & latency display
5. Address book integration

### Integration Points with BetterDesk

| BetterDesk Component | Integration |
|---------------------|-------------|
| Web Console (Node.js) | Host web client files, serve viewer page |
| HTTP API (hbbs) | Peer list, online status, device info |
| Authentication | Reuse BetterDesk admin auth for web client access |
| Database (SQLite) | Connection logs, session history |
| i18n System | Localize web client UI |

### hbbr WebSocket Proxy Requirement

Since the current BetterDesk hbbr binary uses plain TCP on port 21117, browser clients need a WebSocket gateway. Options:

1. **Modify hbbr source** — Add `tokio-tungstenite` WebSocket listener on port 21119 (recommended)
2. **External proxy** — Use nginx/caddy WebSocket-to-TCP proxy in front of hbbr
3. **Use existing WS support** — If hbbr already listens on 21119 for WebSocket (check binary)

### Recommended Tech Stack for Web Client

| Layer | Technology | Why |
|-------|-----------|-----|
| Protobuf | `protobufjs` | Battle-tested, generates from .proto files |
| WebSocket | Native `WebSocket` API | No library needed |
| Encryption | `tweetnacl-js` | Compatible with libsodium/NaCl |
| Video Decode | `WebCodecs` API | Hardware-accelerated, low latency |
| Audio Decode | `opus-decoder` (npm) / Emscripten Opus | Opus in browser |
| Rendering | `<canvas>` + `OffscreenCanvas` | Performance, Web Worker support |
| UI Framework | Vanilla JS or lightweight (Alpine.js) | Keep it minimal, embed in existing panel |
| Build Tool | Vite or esbuild | Fast bundling |

---

## Appendix A: Cargo.toml Key Dependencies

```toml
# Core
scrap = { path = "libs/scrap" }
hbb_common = { path = "libs/hbb_common" }
enigo = { path = "libs/enigo" }
clipboard = { path = "libs/clipboard" }

# Crypto
sodiumoxide = "0.2"
sha2 = "0.10"

# Networking
tokio = { version = "1", features = ["full"] }
tokio-tungstenite = "..."  # (in hbb_common)

# Audio
magnum-opus = { git = "https://github.com/nicennnnnnnlee-org/magnum-opus" }
cpal = "0.15"  # non-Linux audio
psimple = "..."  # Linux PulseAudio

# Serialization
protobuf = "..."
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# Video (via vcpkg)
# libvpx, libyuv, aom — installed as system libs

# Feature flags
# flutter — Flutter UI bridge
# hwcodec — H.264/H.265 hardware encoding
# vram — GPU memory direct access
# mediacodec — Android hardware codec
```

---

## Appendix B: Protocol Message Quick Reference

### Rendezvous Flow Messages

| Direction | Message | Fields |
|-----------|---------|--------|
| Client → hbbs | `RegisterPk` | id, uuid, pk |
| hbbs → Client | `RegisterPkResponse` | result, keep_alive |
| Client → hbbs | `RegisterPeer` | id, serial |
| hbbs → Client | `RegisterPeerResponse` | request_pk |
| Controller → hbbs | `PunchHoleRequest` | id, nat_type, token, conn_type, force_relay |
| hbbs → Controlled | `PunchHole` | socket_addr, relay_server, nat_type, force_relay |
| hbbs → Controller | `PunchHoleResponse` | socket_addr, pk, failure, relay_server |
| Client → hbbs | `RequestRelay` | id, uuid, relay_server, conn_type, token |
| hbbs → Client | `RelayResponse` | socket_addr, uuid, relay_server, id/pk |

### Peer-to-Peer Session Messages

| Direction | Message | Fields |
|-----------|---------|--------|
| Controlled → Controller | `SignedId` | id (signed bytes) |
| Controller → Controlled | `PublicKey` | asymmetric_value, symmetric_value |
| Controlled → Controller | `Hash` | salt, challenge |
| Controller → Controlled | `LoginRequest` | username, password, my_id, option, session_id |
| Controlled → Controller | `LoginResponse` | error or PeerInfo |
| Controlled → Controller | `VideoFrame` | vp9s/h264s/h265s/av1s + display |
| Controlled → Controller | `AudioFrame` | data (Opus bytes) |
| Controller → Controlled | `MouseEvent` | mask, x, y, modifiers |
| Controller → Controlled | `KeyEvent` | down/press, key union, modifiers, mode |
| Bidirectional | `Clipboard` | compress, content, format |
| Bidirectional | `Misc` | chat, switch_display, permissions, options |
| Bidirectional | `TestDelay` | time, from_client, last_delay |

---

*Generated: 2026-02-17 | Source: github.com/rustdesk/rustdesk @ v1.4.5*
*For BetterDesk Console project: github.com/UNITRONIX/Rustdesk-FreeConsole*
