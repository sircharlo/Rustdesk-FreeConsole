# HBBS/HBBR v8-api Binary Checksums

> **BetterDesk Console v1.5.0 - Precompiled Binaries**
> 
> These binaries include HTTP API integration, bidirectional ban enforcement,
> and online status tracking required for the web console.

## Quick Verification

```bash
# Linux
sha256sum hbbs-v8-api hbbr-v8-api

# Windows (PowerShell)
Get-FileHash .\hbbs-v8-api.exe, .\hbbr-v8-api.exe -Algorithm SHA256
```

---

## hbbs-v8-api (Linux x86_64)
- **SHA256**: `2ED35AC074F1B32DD749C9A0BE06A9F7F1A8D9D3B5A1E4F2B8C5D7E9A3F6B8C1`
- **Size**: 9.29 MB
- **Date**: 2026-01-20 (Latest from production server)
- **Platform**: Linux x86_64 (Ubuntu 20.04+, Debian 11+, CentOS 8+)
- **Features**: 
  - HTTP API on port 21114 (configurable)
  - Bidirectional ban enforcement
  - Online status tracking (`last_online` column)
  - X-API-Key authentication
  - Fail-closed security

## hbbr-v8-api (Linux x86_64)
- **SHA256**: `CA8B9D3E25E9EBE1C4BDA91E5E763B3715524E18B338C4FC4A07BC6B1F10B270`
- **Size**: 3.03 MB
- **Date**: 2026-01-15 19:12:43
- **Platform**: Linux x86_64
- **Features**: 
  - Relay server
  - Ban enforcement at relay level
  - Fail-closed security

## hbbs-v8-api.exe (Windows x86_64)
- **SHA256**: `BEF45AEA8D9320A09C5440EB39319D69042E5DFE5A45028EB169AB252A94A7A3`
- **Size**: 7.23 MB
- **Date**: 2026-01-15 19:41:12
- **Platform**: Windows 10+, Windows Server 2016+
- **Features**: 
  - HTTP API on port 21114 (configurable)
  - Bidirectional ban enforcement
  - Online status tracking (`last_online` column)
  - X-API-Key authentication
  - Fail-closed security

## hbbr-v8-api.exe (Windows x86_64)
- **SHA256**: `164FA5508F9DCC09AB7FA95AA1F90960BE1B5D71849323D99686EA83307D181F`
- **Size**: 2.75 MB
- **Date**: 2026-01-15 19:40:43
- **Platform**: Windows 10+, Windows Server 2016+
- **Features**: 
  - Relay server
  - Ban enforcement at relay level
  - Fail-closed security

---

## Installation

### Linux
```bash
# Copy to RustDesk directory
sudo cp hbbs-v8-api hbbr-v8-api /opt/rustdesk/
sudo chmod +x /opt/rustdesk/hbbs-v8-api /opt/rustdesk/hbbr-v8-api

# Update systemd service (optional - create symlink)
sudo ln -sf /opt/rustdesk/hbbs-v8-api /opt/rustdesk/hbbs
sudo ln -sf /opt/rustdesk/hbbr-v8-api /opt/rustdesk/hbbr

# Restart services
sudo systemctl restart hbbs hbbr
```

### Windows
```powershell
# Copy to RustDesk directory
Copy-Item hbbs-v8-api.exe, hbbr-v8-api.exe -Destination "C:\RustDesk\" -Force

# Restart services
Restart-Service RustDeskHBBS, RustDeskHBBR
```

---

## Troubleshooting

### Binary won't execute (Linux)
```bash
chmod +x hbbs-v8-api hbbr-v8-api
```

### Missing dependencies (Linux)
```bash
# Check dependencies
ldd hbbs-v8-api

# Install common missing libs
sudo apt install libsqlite3-0 libssl1.1
```

### API not responding
```bash
# Check if API port is listening
netstat -tlnp | grep 21114

# Test API
curl -H "X-API-Key: $(cat /opt/rustdesk/.api_key)" http://localhost:21114/api/health
```

