# HBBS Patches Documentation

This directory contains the modified RustDesk HBBS server files that enable real-time device status monitoring through an HTTP API.

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
- Added `api_port` parameter (default: 21114)
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
    21114  // API port
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
        │   (Port 21114)              │
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
curl http://localhost:21114/api/health
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
curl http://localhost:21114/api/peers
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

1. **API Binding**: By default, API listens on `0.0.0.0:21114`
   - Consider using a firewall to restrict access
   - Or modify `http_api.rs` to bind to `127.0.0.1` only

2. **No Authentication**: Current implementation has no API authentication
   - Suitable for internal networks
   - For public exposure, add authentication middleware

3. **CORS**: Enabled for all origins (`*`)
   - Modify `http_api.rs` CORS settings if needed

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
