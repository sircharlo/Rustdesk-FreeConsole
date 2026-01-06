# Precompiled Binaries

This directory contains precompiled RustDesk server binaries with enhanced ban enforcement.

## Files

- **hbbs-v8** - Signal server (HBBS) with bidirectional ban enforcement
- **hbbr-v8** - Relay server (HBBR) with bidirectional ban enforcement

## Features (v8)

### Bidirectional Ban Enforcement

The v8 binaries include comprehensive ban checking:

1. **Source Device Ban Check**
   - Prevents banned devices from initiating any connections
   - Blocks at punch hole request stage (P2P)
   - Blocks at relay request stage (relay connections)

2. **Target Device Ban Check**
   - Prevents connections to banned devices
   - Protects banned devices from receiving unwanted connection attempts

3. **Real-time Database Sync**
   - Ban status checked against SQLite database
   - Instant enforcement when devices are banned via web console
   - No server restart required

### Technical Details

- **Base Version**: RustDesk Server v1.1.14
- **Compiled**: January 2026
- **Architecture**: x86_64 Linux
- **Dependencies**: rusqlite (for ban database access)
- **Build Script**: [build.sh](../build.sh)

## Patches Applied

These binaries include the following patches:

1. **Cargo.toml**: Add rusqlite dependency
2. **database.rs**: `is_device_banned()` async function
3. **peer.rs**: 
   - `update_pk()` - ban check at registration
   - `find_by_addr()` - map socket address to device ID
4. **rendezvous_server.rs**: `handle_punch_hole_request()` - dual ban check
5. **relay_server.rs**: `handle_relay_request()` - dual ban check

## Installation

These binaries are automatically used by [install.sh](../../install.sh):

```bash
sudo ./install.sh
```

The installer will:
1. Create backup of existing binaries
2. Copy hbbs-v8 and hbbr-v8 to /opt/rustdesk/
3. Set correct permissions
4. Restart services

## Manual Installation

If you prefer manual installation:

```bash
# Backup existing binaries
sudo cp /opt/rustdesk/hbbs /opt/rustdesk/hbbs.backup
sudo cp /opt/rustdesk/hbbr /opt/rustdesk/hbbr.backup

# Install new binaries
sudo cp hbbs-v8 /opt/rustdesk/hbbs
sudo cp hbbr-v8 /opt/rustdesk/hbbr
sudo chmod +x /opt/rustdesk/hbbs /opt/rustdesk/hbbr

# Restart services
sudo systemctl restart rustdesksignal.service
sudo systemctl restart rustdeskrelay.service
```

## Verification

After installation, verify ban enforcement:

```bash
# Check logs for ban enforcement messages
sudo tail -f /var/log/rustdesk/signalserver.log

# Ban a device via web console: http://YOUR_SERVER_IP:5000

# Look for these log messages:
# - "WARN Blocked loading banned device [ID] from database"
# - "Punch hole REJECTED - initiator [ID] is banned"
# - "Punch hole REJECTED - target [ID] is banned"
# - "Relay REJECTED - initiator [ID] is banned"
# - "Relay REJECTED - target [ID] is banned"
```

## Rebuild from Source

If you need to rebuild these binaries:

```bash
cd ../
./build.sh
```

The build script will:
1. Clone RustDesk Server v1.1.14
2. Apply all patches automatically
3. Compile HBBS and HBBR
4. Create installation package

Build time: ~15-20 minutes on modern hardware

## Security Notes

- These binaries are compiled from audited source code
- All patches are documented in [BAN_ENFORCEMENT.md](../BAN_ENFORCEMENT.md)
- Security audit available: [SECURITY_AUDIT.md](../SECURITY_AUDIT.md)
- No network calls except RustDesk protocol
- Database access is read-only for ban checks

## Compatibility

- **OS**: Linux x86_64 (tested on Ubuntu 20.04+, Debian 11+)
- **RustDesk Client**: All versions compatible with v1.1.14 server
- **Database**: SQLite 3 (db_v2.sqlite3 with ban columns)

## Support

For issues or questions:
- Check [BAN_ENFORCEMENT.md](../BAN_ENFORCEMENT.md) for troubleshooting
- Review [SECURITY_AUDIT.md](../SECURITY_AUDIT.md) for security concerns
- See [QUICKSTART.md](../QUICKSTART.md) for quick setup guide

## License

Same as RustDesk Server: AGPLv3
