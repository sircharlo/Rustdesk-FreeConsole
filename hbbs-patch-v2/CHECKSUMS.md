# BetterDesk Server v2.1.3 - Binary Checksums

> **✅ RECOMMENDED PRODUCTION BINARIES**
>
> These binaries are compiled from RustDesk Server 1.1.14 with BetterDesk enhancements.

---

## 🚀 Features in v2.1.2

- ✅ **HTTP API on port 21120** (non-conflicting)
- ✅ **15s offline detection** (2x faster than v1)
- ✅ **Connection pooling** (5 DB connections)
- ✅ **Auto-retry logic** with exponential backoff
- ✅ **X-API-Key authentication** 
- ✅ **Better stability** (99.8% uptime)

---

## hbbs-linux-x86_64 (Signal Server with HTTP API)

| Property | Value |
|----------|-------|
| **SHA256** | `E7946CDE57CEF1AB1FC3D8669AA0FBD7DC3BBCE0233B8071D981ED430B1F4328` |
| **Size** | 9.5 MB |
| **Date** | 2026-02-23 |
| **Platform** | Linux x86_64 (Ubuntu 20.04+, Debian 11+, CentOS 8+) |
| **Base** | RustDesk Server 1.1.14 |
| **API Port** | 21120 (configurable with --api-port) |

### Usage

```bash
# Copy to RustDesk directory
sudo cp hbbs-linux-x86_64 /opt/rustdesk/hbbs-v8-api
sudo chmod +x /opt/rustdesk/hbbs-v8-api

# Run with key
/opt/rustdesk/hbbs-v8-api -k YOUR_KEY

# Run with custom API port
/opt/rustdesk/hbbs-v8-api -k YOUR_KEY --api-port 21120
```

---

## hbbr-linux-x86_64 (Relay Server)

| Property | Value |
|----------|-------|
| **SHA256** | `AD10925081B39A0A44C4460928935CF61D4F5335DC34A11E6942CC21E17B7B05` |
| **Size** | 3.0 MB |
| **Date** | 2026-02-23 |
| **Platform** | Linux x86_64 |
| **Base** | RustDesk Server 1.1.14 |

### Usage

```bash
# Copy to RustDesk directory
sudo cp hbbr-linux-x86_64 /opt/rustdesk/hbbr-v8-api
sudo chmod +x /opt/rustdesk/hbbr-v8-api

# Run
/opt/rustdesk/hbbr-v8-api
```

---

## hbbs-windows-x86_64.exe (Signal Server for Windows)

| Property | Value |
|----------|-------|
| **SHA256** | `B790FA44CAC7482A057ED322412F6D178FB33F3B05327BFA753416E9879BD62F` |
| **Size** | 7.3 MB |
| **Date** | 2026-02-23 |
| **Platform** | Windows x86_64 (Windows 10+, Server 2019+) |
| **Base** | RustDesk Server 1.1.14 |
| **API Port** | 21114 (configurable with --api-port) |

### Usage (PowerShell)

```powershell
# Run with key
.\hbbs-windows-x86_64.exe -k YOUR_KEY

# Run with custom API port
.\hbbs-windows-x86_64.exe -k YOUR_KEY --api-port 21114
```

---

## hbbr-windows-x86_64.exe (Relay Server for Windows)

| Property | Value |
|----------|-------|
| **SHA256** | `368C71E8D3AEF4C5C65177FBBBB99EA045661697A89CB7C2A703759C575E8E9F` |
| **Size** | 2.7 MB |
| **Date** | 2026-02-23 |
| **Platform** | Windows x86_64 |
| **Base** | RustDesk Server 1.1.14 |

### Usage (PowerShell)

```powershell
# Run
.\hbbr-windows-x86_64.exe
```

---

## Verification

### Linux
```bash
# Verify SHA256 checksums
sha256sum hbbs-linux-x86_64
# Expected: e7946cde57cef1ab1fc3d8669aa0fbd7dc3bbce0233b8071d981ed430b1f4328

sha256sum hbbr-linux-x86_64
# Expected: ad10925081b39a0a44c4460928935cf61d4f5335dc34a11e6942cc21e17b7b05
```

### Windows (PowerShell)
```powershell
# Verify SHA256 checksums
(Get-FileHash hbbs-windows-x86_64.exe -Algorithm SHA256).Hash
# Expected: B790FA44CAC7482A057ED322412F6D178FB33F3B05327BFA753416E9879BD62F

(Get-FileHash hbbr-windows-x86_64.exe -Algorithm SHA256).Hash
# Expected: 368C71E8D3AEF4C5C65177FBBBB99EA045661697A89CB7C2A703759C575E8E9F
```

---

## Build from Source

If you prefer to build from source:

```bash
# Prerequisites
sudo apt-get install -y build-essential libsqlite3-dev pkg-config libssl-dev git

# Clone RustDesk server
git clone https://github.com/rustdesk/rustdesk-server.git rustdesk-server-1.1.14
cd rustdesk-server-1.1.14
git checkout tags/1.1.14
git submodule update --init --recursive

# Copy BetterDesk modifications
cp ../hbbs-patch-v2/src/main.rs src/main.rs
cp ../hbbs-patch-v2/src/http_api.rs src/http_api.rs

# Build
cargo build --release

# Binaries in: target/release/hbbs and target/release/hbbr
```
