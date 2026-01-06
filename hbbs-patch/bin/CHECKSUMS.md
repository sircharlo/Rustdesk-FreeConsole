# SHA256 Checksums for BetterDesk Console v8 Binaries

Generated: 2026-01-06

## Binaries

### hbbs-v8 (Signal Server)
```
SHA256: 402964335B0AA4B57E37FA52E55C41F386FE5C13487F9CA9319D6A03420A56AA
Size: 9,501,528 bytes (9.5 MB)
File: hbbs-v8
```

### hbbr-v8 (Relay Server)
```
SHA256: 9C9CB8F1BF1C5800A7419592A24BA9A00ECBB075D903D2DB09B3F5F936DB3A71
Size: 4,961,976 bytes (5.0 MB)
File: hbbr-v8
```

## Verification

### Linux/macOS
```bash
sha256sum hbbs-v8 hbbr-v8
```

### Windows (PowerShell)
```powershell
Get-FileHash hbbs-v8, hbbr-v8 -Algorithm SHA256 | Format-Table
```

### Expected Output
```
402964335b0aa4b57e37fa52e55c41f386fe5c13487f9ca9319d6a03420a56aa  hbbs-v8
9c9cb8f1bf1c5800a7419592a24ba9a00ecbb075d903d2db09b3f5f936db3a71  hbbr-v8
```

## Build Information

- **Base Version**: RustDesk Server v1.1.14
- **Build Date**: 2026-01-06
- **Architecture**: x86_64-unknown-linux-gnu
- **Compiler**: rustc 1.75+ (stable channel)
- **Patches Applied**: 8 (see build.sh)
- **Build Script**: ../build.sh

## Security Notes

1. **Authenticity**: These binaries were compiled from open source code
2. **Reproducibility**: You can rebuild using `../build.sh` and verify patches
3. **Source Verification**: All patches documented in source files
4. **No Obfuscation**: Standard Rust compilation, no custom modifications
5. **Audit Available**: See ../SECURITY_AUDIT.md for security review

## Re-compilation

If you want to verify the binaries or compile for different architecture:

```bash
cd ..
./build.sh
```

This will:
1. Clone RustDesk Server v1.1.14
2. Apply all 8 patches automatically
3. Compile HBBS and HBBR
4. Generate new binaries in build directory

Compare checksums of your compiled binaries with these to verify integrity.

## Version History

- **v8** (2026-01-06): Bidirectional ban enforcement
- **v7** (2026-01-06): IP-based source tracking (not released)
- **v6** (2026-01-05): HBBR ban enforcement (not released)
- **v5** (2026-01-05): Relay server compilation (not released)
- **v2-v4**: Development versions (not released)

Only v8 binaries are included in this repository for production use.
