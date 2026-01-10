# Binary Checksums - v1.3.0-secure

Verification checksums for BetterDesk Console binaries with secure API (port 21120, localhost-only binding).

## SHA256 Checksums

### Linux Binaries (x86_64)

```
7B09A6C024188AF5AAC8E94C64B4B97D68A92ABF7F902B34A7D91A9D99E44558  hbbs-v8-api
DF1B3FD3EF8793FD3A786E2BFBB330EE43A6C92D1A5915414F36011BE778E3FB  hbbr-v8-api
```

**Build Date:** 10.01.2026 10:25  
**Size:** HBBS 9.59 MB, HBBR 4.73 MB  
**Platform:** Linux x86_64 (Ubuntu 20.04+, Debian 11+)

### Windows Binaries (x64)

```
EE1AB9C341B078D852EA32ED33CCD8664BC6A3D6EA818D321529B9654C69CD74  hbbs-v8-api.exe
37F452AE97407992DE1561B5F90747D9396E591C21E70B27897EEBEB652C1D25  hbbr-v8-api.exe
```

**Build Date:** 10.01.2026 04:42  
**Size:** HBBS 6.58 MB, HBBR 2.76 MB  
**Platform:** Windows x64 (Windows 10+, Server 2016+)

## Verification

### Linux/macOS

```bash
# Verify single file
sha256sum hbbs-v8-api
# Compare with checksum above

# Verify all Linux binaries
sha256sum hbbs-v8-api hbbr-v8-api
```

### Windows (PowerShell)

```powershell
# Verify single file
Get-FileHash hbbs-v8-api.exe -Algorithm SHA256

# Verify all Windows binaries
Get-ChildItem *.exe | ForEach-Object { Get-FileHash $_.Name -Algorithm SHA256 }
```

## Security Features

All binaries (both Linux and Windows) include:

✅ **Port 21120 API** - Changed from default 21114  
✅ **Localhost-only binding** - API accessible only from 127.0.0.1  
✅ **--api-port parameter** - Command-line configuration support  
✅ **Zero network exposure** - API cannot be accessed from external networks  
✅ **Bidirectional ban enforcement** - Source + target ban checks  
✅ **Real-time database sync** - No restart required for ban changes

## Build Information

- **Base Version:** RustDesk Server 1.1.14
- **Compiler:** cargo 1.92.0, rustc 1.92.0
- **Source:** Modified hbbs-patch with security enhancements
- **Configuration:** 
  - HTTP API on port 21120 (instead of 21114)
  - Binding to 127.0.0.1 only (not 0.0.0.0)
  - API endpoints: `/api/health`, `/api/peers`

## Verification Log

```bash
# Example successful verification
$ sha256sum hbbs-v8-api
7B09A6C024188AF5AAC8E94C64B4B97D68A92ABF7F902B34A7D91A9D99E44558  hbbs-v8-api
✓ Checksum matches
```

## Troubleshooting

### Checksum Mismatch

If checksums don't match:

1. **Re-download the binary** - May be corrupted during transfer
2. **Check file size** - Should match sizes listed above
3. **Verify platform** - Don't mix Linux/Windows binaries
4. **Check Git LFS** - Ensure large files downloaded correctly

### Binary Won't Execute

**Linux:**
```bash
chmod +x hbbs-v8-api hbbr-v8-api
./hbbs-v8-api --help
```

**Windows:**
```powershell
# Run as Administrator
.\hbbs-v8-api.exe --help
```

## Change Log

### v1.3.0-secure (10.01.2026)

- Changed API port from 21114 to 21120
- Added localhost-only binding (127.0.0.1)
- Security enhancement: API not exposed to network
- Added --api-port command-line parameter
- Updated Linux binaries (10:25 UTC)
- Retained Windows binaries from previous build (compatible)

### Previous Versions

See [CHANGELOG.md](../../CHANGELOG.md) for full history.
