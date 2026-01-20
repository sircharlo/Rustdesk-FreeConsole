# Build Notes - BetterDesk Server v2

## Build Requirements

### System Dependencies

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install -y \
    build-essential \
    libsqlite3-dev \
    pkg-config \
    libssl-dev \
    git
```

**CentOS/RHEL:**
```bash
sudo yum install -y \
    gcc \
    gcc-c++ \
    make \
    sqlite-devel \
    pkgconfig \
    openssl-devel \
    git
```

**Windows:**
- Visual Studio 2019+ with C++ tools
- SQLite3 (download from sqlite.org)
- OpenSSL (use vcpkg or pre-built binaries)

### Rust Toolchain

```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Update to latest
rustup update

# Minimum version: 1.70.0
rustc --version
```

## Build Process

### 1. Obtain RustDesk Server Source

This project extends the original RustDesk server, so you need the base source:

```bash
cd ..
git clone https://github.com/rustdesk/rustdesk-server.git
cd rustdesk-server
git checkout tags/1.1.14  # Or latest stable version
cd ../hbbs-patch-v2
```

### 2. Verify Directory Structure

```
parent-directory/
├── rustdesk-server-1.1.14/   # Original RustDesk server
│   ├── hbb_common/
│   ├── hbbs/
│   └── ...
└── hbbs-patch-v2/             # This project
    ├── src/
    ├── Cargo.toml
    └── build.sh
```

### 3. Build

**Using the build script (recommended):**
```bash
chmod +x build.sh
./build.sh           # Release build
./build.sh debug     # Debug build
```

**Manual build:**
```bash
# Debug build (faster compile, larger binary, debug symbols)
cargo build

# Release build (slower compile, optimized, smaller binary)
cargo build --release
```

## Build Outputs

### Release Build
- **Location:** `target/release/hbbs`
- **Size:** ~15-20 MB (stripped)
- **Optimizations:** Full (Level 3, LTO enabled)
- **Build time:** 5-15 minutes (depends on CPU)

### Debug Build
- **Location:** `target/debug/hbbs`
- **Size:** ~50-80 MB (with debug symbols)
- **Optimizations:** None
- **Build time:** 2-5 minutes

## Troubleshooting Build Issues

### Error: "can't find crate for hbb_common"

**Cause:** RustDesk server source not found or wrong path

**Solution:**
```bash
# Check if source exists
ls ../rustdesk-server-1.1.14/hbb_common

# If not, clone it
cd ..
git clone https://github.com/rustdesk/rustdesk-server.git rustdesk-server-1.1.14
cd hbbs-patch-v2

# Or update path in Cargo.toml
```

### Error: "failed to run custom build command for sqlx"

**Cause:** SQLite development files not installed

**Solution:**
```bash
# Ubuntu/Debian
sudo apt-get install libsqlite3-dev

# CentOS/RHEL
sudo yum install sqlite-devel

# Check installation
pkg-config --modversion sqlite3
```

### Error: "could not find OpenSSL"

**Cause:** OpenSSL development files not installed

**Solution:**
```bash
# Ubuntu/Debian
sudo apt-get install libssl-dev pkg-config

# CentOS/RHEL
sudo yum install openssl-devel

# Set environment if needed
export OPENSSL_DIR=/usr/local/ssl
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
```

### Error: "linker `cc` not found"

**Cause:** C compiler not installed

**Solution:**
```bash
# Ubuntu/Debian
sudo apt-get install build-essential

# CentOS/RHEL
sudo yum groupinstall "Development Tools"
```

### Warning: Large binary size

**Cause:** Debug build or debug symbols not stripped

**Solution:**
```bash
# Use release build
cargo build --release

# Strip manually if needed
strip target/release/hbbs

# Result should be ~15-20 MB
```

## Cross-Compilation

### For ARM (Raspberry Pi, etc.)

```bash
# Add target
rustup target add armv7-unknown-linux-gnueabihf

# Install cross-compiler
sudo apt-get install gcc-arm-linux-gnueabihf

# Build
cargo build --release --target=armv7-unknown-linux-gnueabihf

# Binary location
target/armv7-unknown-linux-gnueabihf/release/hbbs
```

### For ARM64

```bash
# Add target
rustup target add aarch64-unknown-linux-gnu

# Install cross-compiler
sudo apt-get install gcc-aarch64-linux-gnu

# Build
cargo build --release --target=aarch64-unknown-linux-gnu

# Binary location
target/aarch64-unknown-linux-gnu/release/hbbs
```

### Using Cross (easier for cross-compilation)

```bash
# Install cross
cargo install cross

# Build for ARM
cross build --release --target=armv7-unknown-linux-gnueabihf

# Build for ARM64
cross build --release --target=aarch64-unknown-linux-gnu
```

## Build Optimization

### Smaller Binary Size

Add to Cargo.toml:
```toml
[profile.release]
opt-level = "z"     # Optimize for size
lto = true
codegen-units = 1
strip = true
panic = "abort"
```

Current settings already optimize for this.

### Faster Compile Times (Development)

```bash
# Use cargo watch for auto-rebuild
cargo install cargo-watch
cargo watch -x build

# Use sccache for caching
cargo install sccache
export RUSTC_WRAPPER=sccache

# Use mold linker (Linux only, very fast)
sudo apt-get install mold
export RUSTFLAGS="-C link-arg=-fuse-ld=mold"
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: Build

on: [push, pull_request]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y libsqlite3-dev libssl-dev
      - name: Build
        run: cargo build --release
      - name: Test
        run: cargo test --release
      - name: Upload artifact
        uses: actions/upload-artifact@v3
        with:
          name: hbbs-v2
          path: target/release/hbbs
```

## Build Artifacts

After successful build, you should have:

```
target/
├── release/
│   ├── hbbs              # Main binary
│   ├── hbbs.d            # Dependency info
│   └── ...
└── debug/
    └── hbbs              # Debug binary (if built)
```

## Testing Build

```bash
# Quick test
./target/release/hbbs --help

# Version check
./target/release/hbbs --version

# Smoke test (will fail without config, but should start)
./target/release/hbbs -k test_key &
sleep 2
killall hbbs

# Should see startup logs
```

## Distribution

### Creating a Release Package

```bash
# Create package directory
mkdir -p betterdesk-v2-linux-x64
cp target/release/hbbs betterdesk-v2-linux-x64/
cp README.md QUICKSTART.md INSTALLATION.md betterdesk-v2-linux-x64/

# Create tarball
tar czf betterdesk-v2-linux-x64.tar.gz betterdesk-v2-linux-x64/

# Create checksums
sha256sum betterdesk-v2-linux-x64.tar.gz > betterdesk-v2-linux-x64.tar.gz.sha256
```

### Docker Build (Optional)

```dockerfile
FROM rust:1.70 as builder
WORKDIR /app
COPY . .
RUN apt-get update && apt-get install -y libsqlite3-dev libssl-dev
RUN cargo build --release

FROM debian:bullseye-slim
RUN apt-get update && apt-get install -y libsqlite3-0 libssl1.1 && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/hbbs /usr/local/bin/
EXPOSE 21116 21115 21118
CMD ["hbbs"]
```

## Build Performance

Typical build times on various systems:

| System | CPU | RAM | Release Build | Debug Build |
|--------|-----|-----|---------------|-------------|
| Modern Desktop | i7-10700 | 16GB | ~8 min | ~3 min |
| Laptop | i5-8250U | 8GB | ~12 min | ~5 min |
| Raspberry Pi 4 | ARM Cortex-A72 | 4GB | ~45 min | ~20 min |
| VPS | 2 vCPU | 4GB | ~15 min | ~7 min |

*Note: Times for clean build. Incremental builds are much faster.*

## Support

If you encounter build issues:

1. Check this file first
2. Verify all dependencies are installed
3. Try a clean build: `cargo clean && cargo build --release`
4. Check GitHub Issues
5. Create a new issue with:
   - OS and version
   - Rust version (`rustc --version`)
   - Full error message
   - Output of `cargo build --release --verbose`
