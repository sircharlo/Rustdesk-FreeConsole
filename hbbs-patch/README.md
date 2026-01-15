# HBBS Patches Documentation

This directory contains the modified RustDesk HBBS server files that enable:
1. **Real-time device status monitoring** through HTTP API
2. **Device banning system** - native ban check during registration

## Features

### 🔒 Device Banning System (NEW!)
Native integration with BetterDesk Console ban functionality. When a device is banned:
- Registration attempts are **rejected at source** by HBBS
- No "race conditions" - 100% effective blocking
- Minimal performance impact (single SQL query per registration)
- Fail-open policy - system continues if database unavailable

**How it works:**
```
Device connects → HBBS checks is_banned → Rejects if banned=1
```

See: [BAN_CHECK_PATCH.md](BAN_CHECK_PATCH.md) for technical details.

---

## Modified Files

### 1. `http_api.rs` (New File)
**Purpose**: HTTP REST API server for device status queries

**Key Features**:
- RESTful API endpoints using Axum framework
- Real-time device status detection (memory-based, not database)
- CORS support for web console integration
- JSON response format

**Endpoints**:
- `GET /api/health` - Health check endpoint
- `GET /api/peers` - List all registered peers with online status

**Technology Stack**:
- Axum web framework
- Tower-HTTP for CORS middleware
- Tokio async runtime

**Status Detection Algorithm**:
```rust
const REG_TIMEOUT: i32 = 30_000; // 30 seconds in milliseconds

// A peer is considered online if:
// 1. It exists in the PeerMap (in-memory storage)
// 2. Last registration time < 30 seconds ago

if let Some(peer) = peer_map.get_in_memory(&id).await {
    let elapsed = peer.read().await.last_reg_time.elapsed().as_millis() as i32;
    online = elapsed < REG_TIMEOUT;
}
```

This matches the **exact same mechanism** used by the RustDesk desktop client to determine online status.

---

### 2. `main.rs`
**Purpose**: Entry point for HBBS server

**Modifications**:
- Added `api_port` parameter (default: 21120)
- Passes API port to `RendezvousServer::start()`
- No changes to core HBBS functionality

**Changed Lines**:
```rust
// Added API port parameter
RendezvousServer::start(
    port, 
    serial, 
    &get_arg_or("key", "-".to_owned()), 
    rmem,
    21120  // API port
)?;
```

---

### 3. `rendezvous_server.rs`
**Purpose**: Main HBBS server managing peer connections

**Modifications**:

1. **Changed PeerMap to Arc for thread-safety**:
   ```rust
   // Before:
   pm: PeerMap
   
   // After:
   pm: Arc<PeerMap>
   ```

2. **Added API server spawn**:
   ```rust
   pub async fn start(..., api_port: u16) -> ResultType<()> {
       let pm = Arc::new(PeerMap::new().await?);
       let pm_clone = pm.clone();
       
       // Spawn HTTP API server with shared PeerMap
       tokio::spawn(async move {
           crate::http_api::start_api_server(db_path, api_port, pm_clone).await
       });
       
       // ... rest of the server logic
   }
   ```

3. **Shared State Architecture**:
   - `PeerMap` is wrapped in `Arc<RwLock<...>>` for safe concurrent access
   - Both the main HBBS server and HTTP API access the same `PeerMap`
   - Real-time synchronization without database polling

**Why This Approach**:
- **Zero latency**: No database queries needed for status
- **Authentic**: Uses the same logic as RustDesk client
- **Scalable**: In-memory lookups are extremely fast
- **Consistent**: Single source of truth (PeerMap)

---

### 4. `peer.rs`
**Purpose**: PeerMap management (in-memory peer storage)

**Modifications**:

1. **Changed `update_pk()` signature for Arc compatibility**:
   ```rust
   // Before:
   pub(crate) async fn update_pk(&mut self, ...)
   
   // After:
   pub(crate) async fn update_pk(&self, ...)
   ```
   
   Reason: `Arc<PeerMap>` doesn't allow mutable references. Changed to use interior mutability (`RwLock`) instead.

2. **Preserved all existing functionality**:
   - Peer registration
   - Public key updates
   - Database synchronization
   - Memory management

**No breaking changes** - all original HBBS functionality remains intact.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    RustDesk Client                          │
│              (sends heartbeat every ~45s)                    │
└─────────────────────┬───────────────────────────────────────┘
                      │ Register peer
                      ▼
        ┌─────────────────────────────┐
        │   RendezvousServer          │
        │   (HBBS Main Server)        │
        └─────────────┬───────────────┘
                      │
                      ▼
        ┌─────────────────────────────┐
        │   Arc<PeerMap>              │
        │   (Shared In-Memory Store)  │
        │   - peer_id → LockPeer      │
        │   - last_reg_time: Instant  │
        └─────────────┬───────────────┘
                      │
                      ▼
        ┌─────────────────────────────┐
        │   HTTP API Server           │
        │   (Port 21120)              │
        └─────────────┬───────────────┘
                      │ Query status
                      ▼
        ┌─────────────────────────────┐
        │   Web Console               │
        │   (Flask + JavaScript)      │
        └─────────────────────────────┘
```

---

## Implementation Details

### Why Memory-Based Instead of Database?

**Original RustDesk behavior**:
- HBBS stores peers in memory (`PeerMap`)
- Database (`db_v2.sqlite3`) is used for persistence only
- The `status` column in database is **NEVER updated** by HBBS
- Online detection happens in real-time using `last_reg_time.elapsed()`

**Our implementation**:
- ✅ Uses the same memory-based approach
- ✅ Shares `PeerMap` between main server and API
- ✅ Calculates status on-demand (no stale data)
- ✅ 30-second timeout matches RustDesk client behavior

### REG_TIMEOUT Constant

```rust
const REG_TIMEOUT: i32 = 30_000; // 30 seconds
```

This is the **official RustDesk timeout value** found in the original source code (`rendezvous_server.rs:781`).

A peer must re-register within 30 seconds to remain online. This is why RustDesk clients send heartbeats approximately every 30-45 seconds.

### Thread Safety

All modifications maintain thread safety:
- `Arc<PeerMap>` allows shared ownership across threads
- `RwLock<HashMap<...>>` provides concurrent read access
- Write operations (peer registration) are already synchronized
- No race conditions or data corruption possible

---

## Compilation Requirements

### Additional Dependencies (added automatically by install.sh):

```toml
[dependencies]
axum = { version = "0.7", features = ["http1", "json", "tokio"] }
tower-http = { version = "0.5", features = ["cors"] }
tokio = { version = "1", features = ["full"] }
```

### Build Command:

```bash
cargo build --release --bin hbbs
```

Binary output: `target/release/hbbs`

---

## Testing the API

### Health Check:
```bash
curl http://localhost:21120/api/health
```

Response:
```json
{
  "success": true,
  "data": "RustDesk API is running",
  "error": null
}
```

### List Peers:
```bash
curl http://localhost:21120/api/peers
```

Response:
```json
{
  "success": true,
  "data": [
    {
      "id": "1234567890",
      "note": "Server NYC",
      "online": true
    },
    {
      "id": "9876543210",
      "note": "Workstation",
      "online": false
    }
  ],
  "error": null
}
```

---

## Compatibility

- **RustDesk Version**: Tested with HBBS 1.1.9+
- **Rust Version**: 1.70+
- **Operating Systems**: Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+)
- **Architecture**: x86_64, ARM64

---

## Security Considerations

### API Authentication (v1.4.0+)

**X-API-Key Authentication**: The HBBS API now requires authentication for all requests:

1. **API Key Generation**: During installation, a 64-character random API key is generated:
   ```bash
   openssl rand -base64 48 | tr -d '/+=' | cut -c1-64
   ```

2. **Key Storage**: Stored securely in `/opt/rustdesk/.api_key` with 600 permissions

3. **Usage**: All API requests must include the `X-API-Key` header:
   ```bash
   curl -H "X-API-Key: YOUR_API_KEY" http://192.168.1.100:21120/api/health
   ```

4. **Verification**: Middleware checks the header against stored key:
   ```rust
   async fn verify_api_key(
       State(state): State<Arc<ApiState>>,
       headers: HeaderMap,
       request: Request,
       next: Next,
   ) -> Result<Response, StatusCode> {
       let api_key = headers
           .get("X-API-Key")
           .and_then(|v| v.to_str().ok())
           .ok_or(StatusCode::UNAUTHORIZED)?;
       
       if api_key != state.api_key {
           return Err(StatusCode::UNAUTHORIZED);
       }
       
       Ok(next.run(request).await)
   }
   ```

### Network Access

1. **API Binding**: API listens on `0.0.0.0:21120` (LAN accessible)
   - Protected by X-API-Key authentication
   - Web console automatically provides key
   - External tools need API key from `/opt/rustdesk/.api_key`

2. **Firewall Recommendations**:
   ```bash
   # Allow API on LAN only
   sudo ufw allow from 192.168.0.0/16 to any port 21120 proto tcp
   
   # Or allow web console only (API via localhost)
   sudo ufw allow 5000/tcp
   ```

3. **CORS**: Enabled for all origins with credentials support
   - Safe due to API key requirement
   - Modify `http_api.rs` if stricter CORS needed

---

## Building with Ban Check

### Quick Build (Automated)

```bash
# Make script executable
chmod +x build.sh

# Run automated build
./build.sh
```

This will:
1. Clone RustDesk Server v1.1.14
2. Apply all patches (HTTP API + Ban Check)
3. Compile `hbbs`
4. Create installation package

### Manual Build

```bash
# Clone repository
git clone --branch 1.1.14 https://github.com/rustdesk/rustdesk-server.git
cd rustdesk-server

# Copy patched files
cp ../hbbs-patch/src/*.rs src/

# Or apply patches manually:
# 1. Add is_device_banned() to src/database.rs (see database_patch.rs)
# 2. Add ban check to update_pk() in src/peer.rs (see peer_patch.rs)

# Compile
cargo build --release --bin hbbs

# Result: target/release/hbbs
```

### Installation on Server

```bash
# 1. Stop HBBS
sudo systemctl stop hbbs

# 2. Backup current binary
sudo cp /opt/rustdesk/hbbs /opt/rustdesk/hbbs.backup

# 3. Install new binary
sudo cp target/release/hbbs /opt/rustdesk/
sudo chmod +x /opt/rustdesk/hbbs

# 4. Restart
sudo systemctl start hbbs

# 5. Verify
sudo journalctl -u hbbs -n 20 --no-pager
```

### Testing Ban Functionality

```bash
# 1. Ban a device in database
sqlite3 /opt/rustdesk/db_v2.sqlite3 "UPDATE peer SET is_banned=1 WHERE id='123456789'"

# 2. Try to connect from that device

# 3. Check logs - should see:
# "Registration REJECTED for device 123456789: DEVICE IS BANNED"

# 4. Unban
sqlite3 /opt/rustdesk/db_v2.sqlite3 "UPDATE peer SET is_banned=0 WHERE id='123456789'"
```

---

## Maintenance

### Updating to New RustDesk Versions

1. Clone the new RustDesk version
2. Apply patches from this directory
3. Test compilation
4. Check for API compatibility
5. Update if needed

### Reverting to Original HBBS

1. Stop the service: `sudo systemctl stop rustdesksignal`
2. Restore from backup: `sudo cp /opt/rustdesk-backup-*/hbbs /opt/rustdesk/`
3. Start the service: `sudo systemctl start rustdesksignal`

---

## Contributing

If you improve these patches or add features:
1. Test thoroughly with real RustDesk clients
2. Ensure backward compatibility
3. Update this documentation
4. Submit a pull request

---

## License

These modifications maintain the original RustDesk AGPL-3.0 license.

## Credits

- Original RustDesk Server: https://github.com/rustdesk/rustdesk-server
- Enhancement: BetterDesk Console project
