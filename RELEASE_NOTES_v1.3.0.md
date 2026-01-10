# 🎉 Release Notes - BetterDesk Console v1.3.0-secure

**Release Date:** 10 stycznia 2026  
**Focus:** Security Enhancement - Localhost-Only API Binding

---

## 🔒 What's New

### Critical Security Enhancement

**API Port Changed: 21114 → 21120**
- New port clearly indicates localhost-only service
- Avoids conflict with RustDesk Pro (which uses 21114 for public API)
- All documentation and examples updated

**Localhost-Only Binding: 0.0.0.0 → 127.0.0.1**
- API now binds **exclusively** to localhost (127.0.0.1)
- **Zero network exposure** - cannot be accessed from external networks
- Connection attempts from network properly refused
- No firewall configuration needed for port 21120

### New Features

✅ **--api-port Parameter**
- Command-line configuration support
- Flexible deployment options
- Example: `hbbs --api-port 21120`

✅ **SSH Tunnel Support**
- Remote access via secure tunnel
- Instructions in README and PORT_SECURITY.md
- Example: `ssh -L 21120:localhost:21120 user@server`

✅ **Updated Binaries**
- Linux: hbbs-v8-api (9.59 MB), hbbr-v8-api (4.73 MB)
- Built: 10.01.2026 10:25 UTC
- Contains security code: "localhost only" binding
- Windows binaries: Compatible (retained from previous build)

✅ **Enhanced Documentation**
- PORT_SECURITY.md - Complete port analysis
- Updated README with 6 security references
- SSH tunnel instructions
- Verification commands

---

## 📦 Download

### For Linux (Ubuntu 20.04+, Debian 11+)

```bash
git clone https://github.com/UNITRONIX/BetterDesk-Console.git
cd BetterDesk-Console
chmod +x install-improved.sh
sudo ./install-improved.sh
```

**Binaries included:**
- `hbbs-patch/bin-with-api/hbbs-v8-api` (9.59 MB)
- `hbbs-patch/bin-with-api/hbbr-v8-api` (4.73 MB)

### For Windows (Windows 10+, Server 2016+)

```powershell
git clone https://github.com/UNITRONIX/BetterDesk-Console.git
cd BetterDesk-Console
# Run as Administrator
.\install-improved.ps1
```

**Binaries included:**
- `hbbs-patch/bin-with-api/hbbs-v8-api.exe` (6.58 MB)
- `hbbs-patch/bin-with-api/hbbr-v8-api.exe` (2.76 MB)

---

## 🔐 Security

### What's Protected

✅ **API Endpoints:**
- `http://localhost:21120/api/health` - Service health check
- `http://localhost:21120/api/peers` - Device list

✅ **Access Control:**
- **Allowed:** localhost (127.0.0.1) only
- **Blocked:** All network/internet access
- **Firewall:** Port 21120 does NOT need to be opened

### What's Public (Unchanged)

RustDesk client ports remain publicly accessible (required):
- TCP 21115 - HBBS Signal Server
- TCP 21116 - HBBS Signal Server (NAT)
- TCP 21117 - HBBR Relay Server
- UDP 21116 - NAT Type Test

---

## 🔄 Upgrade from v1.2.0-v8

### Automatic Upgrade (Recommended)

```bash
cd BetterDesk-Console
git pull
sudo ./install-improved.sh
```

**What happens:**
1. Backups created automatically
2. New binaries installed
3. Systemd service updated (--api-port 21120)
4. Web console updated (port 21120)
5. Services restarted

### Manual Upgrade

**1. Update systemd service:**
```bash
sudo nano /etc/systemd/system/rustdesksignal.service
# Change: ExecStart=/opt/rustdesk/hbbs
# To: ExecStart=/opt/rustdesk/hbbs --api-port 21120
sudo systemctl daemon-reload
```

**2. Update web console:**
```bash
sudo nano /opt/BetterDeskConsole/app.py
# Change: HBBS_API_URL = 'http://localhost:21114/api'
# To: HBBS_API_URL = 'http://localhost:21120/api'
```

**3. Restart services:**
```bash
sudo systemctl restart rustdesksignal betterdesk
```

---

## ✅ Verification

### 1. Check API Binding

```bash
ss -tlnp | grep 21120
```

**Expected:** `127.0.0.1:21120` (localhost only) ✅

### 2. Test Local Access

```bash
curl http://localhost:21120/api/health
```

**Expected:** `{"success":true,"data":"RustDesk API is running","error":null}` ✅

### 3. Test External Access

```bash
curl http://YOUR_SERVER_IP:21120/api/health
```

**Expected:** Connection refused ✅ (this is correct - security working)

### 4. Verify RustDesk Ports

```bash
ss -tlnp | grep -E '21115|21116|21117'
```

**Expected:** All ports listening on 0.0.0.0 (public access) ✅

---

## 🌐 Remote Access

For remote API access (e.g., development workstation to production server):

### SSH Tunnel Method

```bash
# Create tunnel
ssh -L 21120:localhost:21120 user@your-server.com

# In another terminal, access API
curl http://localhost:21120/api/health
```

### Web Console Access

```bash
# Tunnel both API and web console
ssh -L 21120:localhost:21120 -L 5000:localhost:5000 user@your-server.com

# Open browser
http://localhost:5000
```

---

## 📊 Checksums

Verify binary integrity with SHA256:

### Linux Binaries

```
7B09A6C024188AF5AAC8E94C64B4B97D68A92ABF7F902B34A7D91A9D99E44558  hbbs-v8-api
DF1B3FD3EF8793FD3A786E2BFBB330EE43A6C92D1A5915414F36011BE778E3FB  hbbr-v8-api
```

### Windows Binaries

```
EE1AB9C341B078D852EA32ED33CCD8664BC6A3D6EA818D321529B9654C69CD74  hbbs-v8-api.exe
37F452AE97407992DE1561B5F90747D9396E591C21E70B27897EEBEB652C1D25  hbbr-v8-api.exe
```

**Verification:**
```bash
# Linux
sha256sum hbbs-v8-api hbbr-v8-api

# Windows (PowerShell)
Get-FileHash hbbs-v8-api.exe -Algorithm SHA256
```

See [CHECKSUMS.md](hbbs-patch/bin-with-api/CHECKSUMS.md) for details.

---

## 🐛 Known Issues

None reported. All tests passed:
- ✅ API responds on localhost
- ✅ External access blocked
- ✅ RustDesk clients connect normally
- ✅ Web console operational
- ✅ Ban enforcement working (bidirectional)

---

## 📝 Full Changelog

See [CHANGELOG.md](CHANGELOG.md) for complete version history.

### Summary of Changes

**Changed:**
- API port: 21114 → 21120
- API binding: 0.0.0.0 → 127.0.0.1
- Systemd service: Added --api-port parameter
- Web console: Updated to port 21120

**Added:**
- PORT_SECURITY.md documentation
- SSH tunnel instructions
- CHECKSUMS.md for binary verification
- Security badges in README

**Fixed:**
- Port conflict with RustDesk Pro
- Network security (eliminated accidental exposure)

**Security:**
- Zero network exposure
- Localhost-only API access
- No private data in documentation

---

## 🤝 Contributing

Contributions welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Report issues:**
- GitHub Issues: https://github.com/UNITRONIX/BetterDesk-Console/issues

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details.

---

## 🙏 Credits

- **RustDesk Team** - Original server implementation
- **Community** - Testing and feedback
- **Contributors** - Security enhancements and documentation

---

## 🔗 Links

- **Repository:** https://github.com/UNITRONIX/BetterDesk-Console
- **Documentation:** [README.md](README.md)
- **Security:** [PORT_SECURITY.md](PORT_SECURITY.md)
- **RustDesk:** https://rustdesk.com/
