# BetterDesk Server v2.0.0 - Binary Checksums

> **✅ RECOMMENDED PRODUCTION BINARIES**
>
> These binaries are compiled from RustDesk Server 1.1.14 with BetterDesk enhancements.

---

## 🚀 Features in v2.0.0

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
| **SHA256** | `2D99FE55378AC6CDED8A4D5BDA717367BBCF17B83B6AADA0D080C02C3BF1B2C1` |
| **Size** | 9.4 MB |
| **Date** | 2026-02-02 |
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
| **SHA256** | `C7197CF9FCBFB47BB4C9F6D4663DF29B27D2A9AB008FF7AE32A13C6150024528` |
| **Size** | 2.9 MB |
| **Date** | 2026-02-02 |
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
| **SHA256** | `50BA3BCE44AC607917C2B6870B2859D2F5DB59769E79F6BFB3E757244A53A7F7` |
| **Size** | 6.6 MB |
| **Date** | 2026-02-04 |
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
| **SHA256** | `78E7B0F61B7DF8FD780550B8AB9F81F802C3C63CD8171BD93194EC23CA51EB94` |
| **Size** | 2.7 MB |
| **Date** | 2026-02-04 |
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
# Expected: 2d99fe55378ac6cded8a4d5bda717367bbcf17b83b6aada0d080c02c3bf1b2c1

sha256sum hbbr-linux-x86_64
# Expected: c7197cf9fcbfb47bb4c9f6d4663df29b27d2a9ab008ff7ae32a13c6150024528
```

### Windows (PowerShell)
```powershell
# Verify SHA256 checksums
(Get-FileHash hbbs-windows-x86_64.exe -Algorithm SHA256).Hash
# Expected: 50BA3BCE44AC607917C2B6870B2859D2F5DB59769E79F6BFB3E757244A53A7F7

(Get-FileHash hbbr-windows-x86_64.exe -Algorithm SHA256).Hash
# Expected: 78E7B0F61B7DF8FD780550B8AB9F81F802C3C63CD8171BD93194EC23CA51EB94
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
