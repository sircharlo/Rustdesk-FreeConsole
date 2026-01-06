# HBBS Ban Enforcement - Architecture Documentation

## Overview

This document describes the comprehensive ban enforcement system implemented in RustDesk HBBS to prevent banned devices from connecting in **both directions**.

## Problem Statement

**Original Issue**: SQLx async database calls in HBBS caused Tokio runtime panic when called from async context.

**Discovery**: Ban enforcement was unidirectional:
- ✅ Connections **TO** banned devices were blocked
- ❌ Connections **FROM** banned devices were allowed

**Requirement**: Block banned devices from both receiving AND initiating connections.

## Architecture

### Components

1. **Database Layer** (`database.rs`)
   - `is_device_banned(id: &str) -> ResultType<bool>`
   - Uses `rusqlite` with `spawn_blocking` to avoid nested Tokio runtime
   - Read-only SQLite connection to prevent locks

2. **Peer Management** (`peer.rs`)
   - `update_pk()`: Registration point - rejects banned devices
   - `get()`: Load blocker - prevents loading banned devices from DB
   - `get_id_by_addr()`: **NEW** - Find device ID by socket address

3. **Connection Handlers** (`rendezvous_server.rs`)
   - `RequestRelay`: Relay connection requests
   - `PunchHoleRequest`: P2P hole punching requests

### Ban Check Points (5 locations)

#### 1. Registration (update_pk)
```rust
// peer.rs - update_pk()
match self.db.is_device_banned(&id).await {
    Ok(true) => {
        log::warn!("Registration REJECTED for device {}: DEVICE IS BANNED", id);
        self.map.write().await.remove(&id); // Remove from memory
        return register_pk_response::Result::UUID_MISMATCH;
    }
}
```

**Purpose**: Block banned devices at registration (heartbeat)  
**Effect**: Removes banned devices from active PeerMap memory

#### 2. Database Load (get)
```rust
// peer.rs - get()
if let Ok(true) = self.db.is_device_banned(id).await {
    log::warn!("Blocked loading banned device {} from database", id);
    return None;
}
```

**Purpose**: Prevent loading banned devices from persistent storage  
**Effect**: Ensures banned devices never enter memory

#### 3. Relay Initiator Check (RequestRelay)
```rust
// rendezvous_server.rs - RequestRelay
if let Some(initiator_id) = self.pm.get_id_by_addr(addr).await {
    if let Ok(true) = self.pm.db.is_device_banned(&initiator_id).await {
        log::warn!("Relay REJECTED - initiator {} is banned", initiator_id);
        return true;
    }
}
```

**Purpose**: Block relay requests FROM banned devices  
**Effect**: Banned device cannot relay through server to others

#### 4. Relay Target Check (RequestRelay)
```rust
// rendezvous_server.rs - RequestRelay
match self.pm.db.is_device_banned(&rf.id).await {
    Ok(true) => {
        log::warn!("Relay REJECTED - target {} is banned", rf.id);
        return true;
    }
}
```

**Purpose**: Block relay requests TO banned devices  
**Effect**: Other devices cannot relay to banned device

#### 5. P2P Initiator Check (PunchHoleRequest)
```rust
// rendezvous_server.rs - PunchHoleRequest
if let Some(initiator_id) = self.pm.get_id_by_addr(addr).await {
    match self.pm.db.is_device_banned(&initiator_id).await {
        Ok(true) => {
            log::warn!("Punch hole REJECTED - initiator {} is banned", initiator_id);
            return Err(PunchHoleResponse::OFFLINE);
        }
    }
}
```

**Purpose**: Block P2P connection attempts FROM banned devices  
**Effect**: Banned device cannot establish direct P2P connections

#### 6. P2P Target Check (PunchHoleRequest)
```rust
// rendezvous_server.rs - PunchHoleRequest  
match self.pm.db.is_device_banned(&id).await {
    Ok(true) => {
        log::warn!("Punch hole REJECTED - target {} is banned", id);
        return Err(PunchHoleResponse::OFFLINE);
    }
}
```

**Purpose**: Block P2P connection attempts TO banned devices  
**Effect**: Other devices cannot establish direct P2P to banned device

## Technical Details

### Why rusqlite instead of SQLx?

**Problem**: SQLx is async and integrates with Tokio's async runtime. When `is_device_banned()` is called from an async function that's already running in Tokio (like `update_pk()`), it creates a **nested runtime panic**.

**Solution**: Use synchronous `rusqlite` wrapped in `spawn_blocking`:
```rust
let result = hbb_common::tokio::task::spawn_blocking(move || -> ResultType<bool> {
    use rusqlite::{Connection, OptionalExtension};
    let conn = Connection::open_with_flags(
        db_path,
        rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY
    )?;
    // ... query logic
}).await??;
```

**Benefits**:
- No nested runtime issues
- Read-only connection prevents locks
- Compatible with existing SQLx (libsqlite3-sys 0.24)

### Why get_id_by_addr()?

**Problem**: In `RequestRelay` and `PunchHoleRequest`, we receive:
- `addr: SocketAddr` - IP address of initiator
- `rf.id` / `ph.id` - Device ID of target

We have target ID but not initiator ID.

**Solution**: Iterate through PeerMap to find device ID by socket address:
```rust
pub(crate) async fn get_id_by_addr(&self, addr: SocketAddr) -> Option<String> {
    let map = self.map.read().await;
    for (id, peer) in map.iter() {
        let peer_addr = peer.read().await.socket_addr;
        if peer_addr == addr {
            return Some(id.clone());
        }
    }
    None
}
```

**Performance**: O(n) where n = active devices (typically < 1000), runs in memory, very fast.

## Deployment

### Version History

- **v1**: Fixed Tokio panic with rusqlite
- **v2**: Added target-only ban checks (unidirectional)
- **v3**: Added initiator checks (bidirectional) ← **CURRENT**

### Quick Deployment

Use the pre-compiled binary with `deploy.ps1`:

```powershell
.\deploy.ps1 hbbs-v3-patched
```

This:
1. Uploads binary to server
2. Backs up current version with timestamp
3. Installs new version
4. Restarts service
5. Verifies deployment

**Time**: ~10 seconds vs 5-7 minutes compilation

### Manual Deployment

```bash
# Stop service
ssh -t YOUR_SSH_USER@YOUR_SERVER_IP "sudo systemctl stop rustdesksignal"

# Backup
ssh YOUR_SSH_USER@YOUR_SERVER_IP "sudo cp /opt/rustdesk/hbbs /opt/rustdesk/hbbs.backup.$(date +%s)"

# Upload and install
scp hbbs-v3-patched YOUR_SSH_USER@YOUR_SERVER_IP:/tmp/hbbs-new
ssh -t YOUR_SSH_USER@YOUR_SERVER_IP "sudo cp /tmp/hbbs-new /opt/rustdesk/hbbs && sudo chmod +x /opt/rustdesk/hbbs"

# Start and verify
ssh -t YOUR_SSH_USER@YOUR_SERVER_IP "sudo systemctl start rustdesksignal && sleep 2 && sudo systemctl status rustdesksignal"
```

## Testing

### Test Case 1: Initiator Ban (NEW)

1. Ban device `58457133` via console: http://YOUR_SERVER_IP:5000
2. Verify ban: `curl http://localhost:5000/api/devices | grep 58457133`
3. From device `58457133`, attempt to connect to device `1253021143`
4. **Expected**: Connection rejected

**Verify logs**:
```bash
ssh YOUR_SSH_USER@YOUR_SERVER_IP "grep '58457133' /var/log/rustdesk/signalserver.log | tail -20"
```

Look for:
- `"Relay REJECTED - initiator 58457133 is banned"` (relay)
- `"Punch hole REJECTED - initiator 58457133 is banned"` (P2P)

### Test Case 2: Target Ban (regression test)

1. Device `58457133` remains banned
2. From device `1253021143`, attempt to connect to `58457133`
3. **Expected**: Connection rejected

**Verify logs**:
```bash
ssh YOUR_SSH_USER@YOUR_SERVER_IP "grep '58457133' /var/log/rustdesk/signalserver.log | tail -20"
```

Look for:
- `"Relay REJECTED - target 58457133 is banned"` (relay)
- `"Punch hole REJECTED - target 58457133 is banned"` (P2P)

### Test Case 3: No False Positives

1. Unban device `58457133`
2. Verify unban: `curl http://localhost:5000/api/devices | grep 58457133`
3. Test connections both directions
4. **Expected**: Both succeed

## Troubleshooting

### Issue: "Cannot start a runtime from within a runtime"

**Symptom**: Panic in error logs, HBBS crashes
**Cause**: Using SQLx async in ban check
**Solution**: Ensure rusqlite with spawn_blocking is used

**Verify**:
```bash
ssh YOUR_SSH_USER@YOUR_SERVER_IP "grep 'spawn_blocking' /tmp/rustdesk-server/src/database.rs"
```

Should see `hbb_common::tokio::task::spawn_blocking`

### Issue: Banned device still connects

**Symptom**: Banned device can establish connections
**Cause**: Check if initiator or target check is missing

**Debug**:
```bash
# Check if device is actually banned
curl http://YOUR_SERVER_IP:5000/api/devices | python3 -m json.tool | grep -A5 "58457133"

# Check ban check logs
ssh YOUR_SSH_USER@YOUR_SERVER_IP "grep 'BAN CHECK\|REJECTED' /var/log/rustdesk/signalserver.log | tail -50"
```

**Verify patches applied**:
```bash
ssh YOUR_SSH_USER@YOUR_SERVER_IP "grep -c 'is_device_banned' /tmp/rustdesk-server/src/rendezvous_server.rs"
# Should show: 4 (2 initiator + 2 target)
```

### Issue: Device count mismatch (console vs client)

**Symptom**: Console shows 3 active, client shows 5
**Possible causes**:
1. PeerMap not cleaned properly (banned devices in memory)
2. Console query filtering differs from client
3. Client caching offline devices

**Debug**:
```bash
# Check console API count
curl -s http://localhost:5000/api/devices | python3 -c "import sys, json; print(len(json.load(sys.stdin)))"

# Check online devices only
curl -s http://localhost:5000/api/devices | python3 -c "import sys, json; print(len([d for d in json.load(sys.stdin) if d.get('is_online')]))"

# Check PeerMap size (requires HBBS mod)
ssh YOUR_SSH_USER@YOUR_SERVER_IP "grep 'PeerMap size' /var/log/rustdesk/signalserver.log | tail -1"
```

## Performance Impact

### Ban Check Overhead

- **Database query**: ~0.1-1ms (SQLite read-only)
- **spawn_blocking**: ~0.05-0.2ms (thread pool overhead)
- **get_id_by_addr**: ~0.01-0.1ms (in-memory O(n) iteration)

**Total per connection attempt**: ~0.2-1.3ms

**Impact**: Negligible for typical loads (<100 connections/sec)

### Memory Usage

- **rusqlite**: Minimal (read-only connection per query)
- **PeerMap iteration**: No additional allocations
- **Ban check results**: Not cached (always fresh from DB)

## Future Enhancements

### Potential Optimizations

1. **Cache ban status**: In-memory cache with TTL (30-60s)
   - Reduces DB queries
   - Trade-off: Slight delay in ban enforcement

2. **Reverse IP map**: `HashMap<SocketAddr, String>` for O(1) ID lookup
   - Faster than iterating PeerMap
   - Requires memory management (add/remove on peer changes)

3. **Batch ban checks**: Check multiple devices in single query
   - Useful for bulk operations
   - Requires DB query refactoring

4. **Periodic PeerMap cleanup**: Remove offline devices
   - Improves get_id_by_addr performance
   - Requires background task

### Security Enhancements

1. **Ban reason logging**: Store why device was banned
2. **Ban duration**: Temporary bans (unban after X hours)
3. **Ban history**: Track ban/unban events
4. **IP-based bans**: Block by IP instead of device ID

## Files Modified

- `src/database.rs`: Add `is_device_banned()` method
- `src/peer.rs`: Add ban checks and `get_id_by_addr()` method
- `src/rendezvous_server.rs`: Add initiator and target ban checks
- `Cargo.toml`: Add `rusqlite = "0.27"` dependency

## Build Script

Location: `hbbs-patch/build.sh`

Applies 8 patches:
1. Add rusqlite dependency
2. database.rs: is_device_banned()
3. peer.rs: update_pk ban check
4. peer.rs: get() load blocker
5. peer.rs: get_id_by_addr() method
6. rendezvous_server.rs: RequestRelay checks
7. rendezvous_server.rs: PunchHoleRequest checks
8. Compile and verify

## Support

For issues or questions:
- Check logs: `/var/log/rustdesk/signalserver.log` and `.error`
- Verify service: `sudo systemctl status rustdesksignal`
- Test connectivity: Desktop client connection attempts
- Console API: `curl http://YOUR_SERVER_IP:5000/api/devices`
