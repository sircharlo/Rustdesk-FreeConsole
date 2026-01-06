# Installation Guide - Version 8 (Precompiled Binaries)

## What's New in v8

### 🚀 Major Changes

1. **Precompiled Binaries** - No more compilation required!
   - Installation time reduced from ~20 minutes to ~2 minutes
   - No need for Rust/Cargo toolchain
   - Smaller dependency footprint
   - Faster deployments and updates

2. **Bidirectional Ban Enforcement**
   - Source ban check: Banned devices cannot initiate connections
   - Target ban check: Cannot connect to banned devices
   - Works for both P2P and relay connections
   - Real-time database sync

3. **Simplified Dependencies**
   - Removed: git, cargo (Rust toolchain)
   - Required: python3, pip3, curl, systemd
   - ~500MB disk space saved

## Installation Methods

### Method 1: Automatic Installation (Recommended)

```bash
# Clone repository
git clone https://github.com/UNITRONIX/Rustdesk-FreeConsole.git
cd Rustdesk-FreeConsole

# Run installer
sudo chmod +x install.sh
sudo ./install.sh
```

**What the installer does:**
1. Checks dependencies (python3, pip3, curl, systemctl)
2. Backs up existing RustDesk installation
3. Installs precompiled HBBS/HBBR v8 binaries
4. Installs web console with dependencies
5. Configures systemd services
6. Verifies installation

**Installation time:** ~2-3 minutes

### Method 2: Manual Installation

If you prefer manual installation or have a custom setup:

```bash
# 1. Backup existing installation
sudo cp /opt/rustdesk/hbbs /opt/rustdesk/hbbs.backup
sudo cp /opt/rustdesk/hbbr /opt/rustdesk/hbbr.backup

# 2. Stop services
sudo systemctl stop rustdesksignal.service
sudo systemctl stop rustdeskrelay.service

# 3. Install v8 binaries
sudo cp hbbs-patch/bin/hbbs-v8 /opt/rustdesk/hbbs
sudo cp hbbs-patch/bin/hbbr-v8 /opt/rustdesk/hbbr
sudo chmod +x /opt/rustdesk/hbbs /opt/rustdesk/hbbr

# 4. Start services
sudo systemctl start rustdesksignal.service
sudo systemctl start rustdeskrelay.service

# 5. Install web console
sudo mkdir -p /opt/BetterDeskConsole
sudo cp -r web/* /opt/BetterDeskConsole/
sudo pip3 install -r web/requirements.txt

# 6. Create systemd service for web console
sudo cp web/betterdesk.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable betterdesk.service
sudo systemctl start betterdesk.service
```

### Method 3: Upgrade from Previous Version

If you're upgrading from an older BetterDesk Console:

```bash
# Pull latest changes
cd Rustdesk-FreeConsole
git pull

# Run installer (it will detect existing installation and upgrade)
sudo ./install.sh
```

**What gets upgraded:**
- HBBS/HBBR binaries (v8 with bidirectional bans)
- Web console files
- Python dependencies

**What stays the same:**
- Your database (devices, bans, notes)
- Configuration files
- Service files (unless you choose to recreate)

## Verification

After installation, verify everything works:

### 1. Check Services

```bash
# HBBS service
sudo systemctl status rustdesksignal.service

# HBBR service (if using relay)
sudo systemctl status rustdeskrelay.service

# Web console
sudo systemctl status betterdesk.service
```

### 2. Check Ports

```bash
# RustDesk ports (should show hbbs/hbbr)
sudo netstat -tlnp | grep -E "21115|21116|21117|21118|21119"

# Web console port (default: 5000)
sudo netstat -tlnp | grep 5000
```

### 3. Test Web Console

Open in browser:
```
http://YOUR_SERVER_IP:5000
```

You should see the BetterDesk Console dashboard.

### 4. Test Ban Enforcement

```bash
# Watch logs
sudo tail -f /var/log/rustdesk/signalserver.log

# In web console: Ban a device
# Try to connect from that device
# You should see in logs:
# "WARN Blocked loading banned device [ID] from database"
# "Punch hole REJECTED - initiator [ID] is banned"
```

## Troubleshooting

### Services Won't Start

```bash
# Check logs
sudo journalctl -u rustdesksignal.service -n 50
sudo journalctl -u betterdesk.service -n 50

# Check HBBS manually
cd /opt/rustdesk
./hbbs -k _ -r YOUR_SERVER_IP:21117
```

### Web Console Connection Failed

```bash
# Verify Python dependencies
pip3 list | grep -E "flask|requests"

# Check if port 5000 is blocked
sudo ufw allow 5000/tcp  # if using ufw

# Test manually
cd /opt/BetterDeskConsole
python3 app.py
```

### Ban Enforcement Not Working

```bash
# Verify database has ban columns
sqlite3 /opt/rustdesk/db_v2.sqlite3 "PRAGMA table_info(peer);"
# Should show: is_banned, ban_reason, banned_by, banned_at

# Check if v8 binary is actually running
ps aux | grep hbbs
lsof -p $(pgrep hbbs) | grep db_v2.sqlite3  # should show database access
```

### Binary Architecture Mismatch

If you get "cannot execute binary file":

```bash
# Check your architecture
uname -m  # should be x86_64

# If you have ARM or different architecture, rebuild from source:
cd hbbs-patch
./build.sh
```

## Rollback

If something goes wrong and you need to rollback:

```bash
# Restore from automatic backup
sudo cp /opt/rustdesk/hbbs.backup.TIMESTAMP /opt/rustdesk/hbbs
sudo cp /opt/rustdesk/hbbr.backup.TIMESTAMP /opt/rustdesk/hbbr
sudo systemctl restart rustdesksignal.service
sudo systemctl restart rustdeskrelay.service

# Or restore from full backup directory
sudo cp -r /opt/rustdesk-backup-TIMESTAMP/* /opt/rustdesk/
sudo systemctl restart rustdesksignal.service
```

## Uninstallation

To completely remove BetterDesk Console:

```bash
# Stop services
sudo systemctl stop betterdesk.service
sudo systemctl disable betterdesk.service

# Remove web console
sudo rm -rf /opt/BetterDeskConsole
sudo rm /etc/systemd/system/betterdesk.service
sudo systemctl daemon-reload

# Restore original RustDesk (if you have backup)
sudo cp /opt/rustdesk/hbbs.backup /opt/rustdesk/hbbs
sudo cp /opt/rustdesk/hbbr.backup /opt/rustdesk/hbbr
sudo systemctl restart rustdesksignal.service
sudo systemctl restart rustdeskrelay.service
```

## Binary Information

The precompiled binaries are:

- **Source**: Compiled from RustDesk Server v1.1.14 + v8 patches
- **Architecture**: Linux x86_64
- **Compiled**: January 2026
- **Size**: 
  - HBBS: ~9.5 MB
  - HBBR: ~5.0 MB
- **Patches**: 8 patches applied (see [build.sh](hbbs-patch/build.sh))
- **Location**: `hbbs-patch/bin/`

## Security Notes

1. **Binary Authenticity**: All patches are documented and auditable
2. **No Obfuscation**: Binaries compiled with standard Rust toolchain
3. **Open Source**: Full source and build script available
4. **Rebuild Option**: You can always rebuild from source using `build.sh`
5. **Checksum Verification**: Generate checksums for your binaries:
   ```bash
   sha256sum hbbs-patch/bin/*
   ```

## Next Steps

After successful installation:

1. **Configure Firewall**: Allow ports 21115-21119 and 5000
2. **Setup SSL** (optional): Use nginx/caddy as reverse proxy for HTTPS
3. **Create Admin Account**: Add authentication to web console (recommended)
4. **Backup Strategy**: Setup automated backups of `/opt/rustdesk/db_v2.sqlite3`
5. **Monitor Logs**: Setup log rotation and monitoring

## Getting Help

- **Documentation**: See [docs/](docs/) directory
- **Security Audit**: [SECURITY_AUDIT.md](hbbs-patch/SECURITY_AUDIT.md)
- **Ban Enforcement**: [BAN_ENFORCEMENT.md](hbbs-patch/BAN_ENFORCEMENT.md)
- **Build from Source**: [build.sh](hbbs-patch/build.sh)
- **Issues**: Create GitHub issue

## Performance

Expected performance with v8 precompiled binaries:

- **Installation**: ~2 minutes (vs ~20 min compilation)
- **Memory**: Same as vanilla RustDesk (~50-100 MB)
- **CPU**: Minimal impact (<1% on modern hardware)
- **Ban Check**: ~1ms per connection attempt
- **Database**: Same queries as before + 1 ban check

## Compatibility

- **RustDesk Clients**: All versions compatible with v1.1.14 server
- **Operating Systems**: 
  - ✅ Ubuntu 20.04, 22.04, 24.04
  - ✅ Debian 11, 12
  - ✅ CentOS 8, 9
  - ✅ Rocky Linux 8, 9
  - ✅ Other x86_64 Linux distributions
- **Python**: 3.8+ required
- **Database**: SQLite 3
