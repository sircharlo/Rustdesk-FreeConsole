#!/bin/bash

#############################################################################
# RustDesk HBBS/HBBR Windows Cross-Compilation Build Script
#
# This script cross-compiles RustDesk HBBS and HBBR for Windows (x86_64)
# with HTTP API and ban enforcement features.
#
# Requirements:
# - Linux environment
# - Rust toolchain with Windows target
# - MinGW-w64 cross-compiler
#
# Usage:
#   bash build-windows.sh
#
# Output:
#   - hbbs-ban-check-package/hbbs.exe (Windows)
#   - hbbs-ban-check-package/hbbr.exe (Windows)
#############################################################################

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
RUSTDESK_VERSION="1.1.14"
GITHUB_REPO="https://github.com/rustdesk/rustdesk-server.git"
WINDOWS_TARGET="x86_64-pc-windows-gnu"
OUTPUT_DIR="hbbs-ban-check-package"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}RustDesk Windows Build Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Add cargo to PATH if not already there
if [ -d "$HOME/.cargo/bin" ] && [[ ":$PATH:" != *":$HOME/.cargo/bin:"* ]]; then
    export PATH="$HOME/.cargo/bin:$PATH"
    echo "Added ~/.cargo/bin to PATH"
fi

# Check if we're on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo -e "${RED}✗ This script must be run on Linux${NC}"
    exit 1
fi

# Step 1: Check for Rust and add Windows target
echo -e "${BLUE}[1/8] Checking Rust installation and Windows target...${NC}"

# Check if cargo is available
if ! command -v cargo &> /dev/null; then
    echo -e "${RED}✗ Cargo not found. Please install Rust.${NC}"
    exit 1
fi

echo "Rust version: $(cargo --version)"

# Try to add Windows target (works with both rustup and standalone)
if command -v rustup &> /dev/null; then
    echo "Using rustup to add Windows target..."
    rustup target add $WINDOWS_TARGET 2>/dev/null || true
    echo -e "${GREEN}✓ Windows target configured via rustup${NC}"
else
    echo "Rustup not found - attempting standalone Rust cross-compilation..."
    echo -e "${YELLOW}⚠ Note: Without rustup, cross-compilation may require additional setup${NC}"
fi

# Step 2: Check for MinGW cross-compiler
echo -e "${BLUE}[2/8] Checking for MinGW-w64...${NC}"
if ! command -v x86_64-w64-mingw32-gcc &> /dev/null; then
    echo -e "${YELLOW}⚠ MinGW-w64 not found, attempting to install...${NC}"
    
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y mingw-w64
    elif command -v yum &> /dev/null; then
        sudo yum install -y mingw64-gcc mingw64-gcc-c++
    else
        echo -e "${RED}✗ Please install MinGW-w64 manually${NC}"
        exit 1
    fi
fi

if command -v x86_64-w64-mingw32-gcc &> /dev/null; then
    echo -e "${GREEN}✓ MinGW-w64 found: $(x86_64-w64-mingw32-gcc --version | head -n1)${NC}"
else
    echo -e "${RED}✗ MinGW-w64 installation failed${NC}"
    exit 1
fi

# Step 3: Clone or use existing rustdesk-server
echo -e "${BLUE}[3/8] Preparing RustDesk source...${NC}"
if [ ! -d "rustdesk-server-$RUSTDESK_VERSION" ]; then
    if [ ! -f "rustdesk-server-$RUSTDESK_VERSION.tar.gz" ]; then
        echo "Downloading RustDesk Server v$RUSTDESK_VERSION..."
        wget "https://github.com/rustdesk/rustdesk-server/archive/refs/tags/$RUSTDESK_VERSION.tar.gz" \
            -O "rustdesk-server-$RUSTDESK_VERSION.tar.gz"
    fi
    
    echo "Extracting archive..."
    tar -xzf "rustdesk-server-$RUSTDESK_VERSION.tar.gz"
fi

cd "rustdesk-server-$RUSTDESK_VERSION"

# Initialize git submodules (required for hbb_common)
echo "Initializing git submodules..."
if [ -d .git ]; then
    git submodule update --init --recursive 2>/dev/null || echo "Git submodules update failed (expected if not git clone)"
fi

# Check if libs/hbb_common is empty and clone if needed
if [ ! -f "libs/hbb_common/Cargo.toml" ]; then
    echo "hbb_common not found, cloning directly..."
    rm -rf libs/hbb_common
    mkdir -p libs/hbb_common
    
    # Try cloning the actual dependency (rustdesk-hbb_common)
    if ! git clone --depth 1 https://github.com/rustdesk-org/rustdesk-hbb_common.git libs/hbb_common 2>/dev/null; then
        echo -e "${YELLOW}⚠ Using tarball instead of git clone${NC}"
        
        # Download as tarball instead
        wget -q https://github.com/rustdesk-org/rustdesk-hbb_common/archive/refs/heads/master.tar.gz -O /tmp/hbb_common.tar.gz
        tar -xzf /tmp/hbb_common.tar.gz -C libs/
        mv libs/rustdesk-hbb_common-master libs/hbb_common
        rm /tmp/hbb_common.tar.gz
    fi
    
    if [ -f "libs/hbb_common/Cargo.toml" ]; then
        echo -e "${GREEN}✓ hbb_common ready${NC}"
    else
        echo -e "${RED}✗ Failed to get hbb_common${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ hbb_common already present${NC}"
fi

echo -e "${GREEN}✓ Source ready${NC}"

# Step 4: Copy custom source files
echo -e "${BLUE}[4/8] Applying custom modifications...${NC}"

# Copy HTTP API module
if [ -f "../src/http_api.rs" ]; then
    echo "Copying http_api.rs..."
    cp "../src/http_api.rs" "src/http_api.rs"
else
    echo -e "${RED}✗ http_api.rs not found${NC}"
    exit 1
fi

# Copy modified main.rs
if [ -f "../src/main.rs" ]; then
    echo "Copying main.rs..."
    cp "../src/main.rs" "src/main.rs"
else
    echo -e "${RED}✗ main.rs not found${NC}"
    exit 1
fi

# Copy modified peer.rs
if [ -f "../src/peer.rs" ]; then
    echo "Copying peer.rs..."
    cp "../src/peer.rs" "src/peer.rs"
fi

# Copy modified rendezvous_server.rs
if [ -f "../src/rendezvous_server.rs" ]; then
    echo "Copying rendezvous_server.rs..."
    cp "../src/rendezvous_server.rs" "src/rendezvous_server.rs"
fi

echo -e "${GREEN}✓ Custom files copied${NC}"

# Step 5: Patch lib.rs to include HTTP API module
echo -e "${BLUE}[5/8] Patching lib.rs...${NC}"
if ! grep -q "pub mod http_api;" src/lib.rs; then
    # Add after the last 'pub mod' declaration
    sed -i '/^pub mod /a pub mod http_api;' src/lib.rs
    echo -e "${GREEN}✓ lib.rs patched${NC}"
else
    echo -e "${GREEN}✓ lib.rs already patched${NC}"
fi

# Step 6: Update Cargo.toml dependencies
echo -e "${BLUE}[6/8] Updating Cargo.toml...${NC}"

# Check if dependencies already exist
if ! grep -q "axum = " Cargo.toml; then
    echo "Adding axum dependency..."
    sed -i '/\[dependencies\]/a axum = "0.5"' Cargo.toml
fi

if ! grep -q "sqlx = " Cargo.toml; then
    echo "Adding sqlx dependency..."
    sed -i '/\[dependencies\]/a sqlx = { version = "0.6", features = ["sqlite", "runtime-tokio-native-tls"] }' Cargo.toml
fi

echo -e "${GREEN}✓ Dependencies updated${NC}"

# Step 7: Configure Cargo for Windows cross-compilation
echo -e "${BLUE}[7/8] Configuring Cargo for Windows...${NC}"
mkdir -p .cargo

cat > .cargo/config.toml << 'EOF'
[target.x86_64-pc-windows-gnu]
linker = "x86_64-w64-mingw32-gcc"
ar = "x86_64-w64-mingw32-ar"

[build]
rustflags = ["-C", "target-feature=+crt-static"]
EOF

echo -e "${GREEN}✓ Cargo configured${NC}"

# Step 8: Build for Windows
echo -e "${BLUE}[8/8] Building for Windows (this may take several minutes)...${NC}"
echo ""

# Set environment variables for cross-compilation
export CC_x86_64_pc_windows_gnu=x86_64-w64-mingw32-gcc
export CXX_x86_64_pc_windows_gnu=x86_64-w64-mingw32-g++
export AR_x86_64_pc_windows_gnu=x86_64-w64-mingw32-ar
export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=x86_64-w64-mingw32-gcc

# Build with release profile
cargo build --release --target $WINDOWS_TARGET

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Build successful!${NC}"
else
    echo ""
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi

# Step 9: Package binaries
echo -e "${BLUE}Packaging binaries...${NC}"
cd ..

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Copy Windows executables
cp "rustdesk-server-$RUSTDESK_VERSION/target/$WINDOWS_TARGET/release/hbbs.exe" "$OUTPUT_DIR/"
cp "rustdesk-server-$RUSTDESK_VERSION/target/$WINDOWS_TARGET/release/hbbr.exe" "$OUTPUT_DIR/"

# Copy to bin-with-api for installer
mkdir -p bin-with-api
cp "$OUTPUT_DIR/hbbs.exe" "bin-with-api/hbbs-v8-api.exe"
cp "$OUTPUT_DIR/hbbr.exe" "bin-with-api/hbbr-v8-api.exe"

# Calculate sizes
hbbs_size=$(stat -f%z "$OUTPUT_DIR/hbbs.exe" 2>/dev/null || stat -c%s "$OUTPUT_DIR/hbbs.exe" 2>/dev/null)
hbbr_size=$(stat -f%z "$OUTPUT_DIR/hbbr.exe" 2>/dev/null || stat -c%s "$OUTPUT_DIR/hbbr.exe" 2>/dev/null)

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Build Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Windows binaries created:"
echo "  • $OUTPUT_DIR/hbbs.exe ($(numfmt --to=iec $hbbs_size 2>/dev/null || echo "$hbbs_size bytes"))"
echo "  • $OUTPUT_DIR/hbbr.exe ($(numfmt --to=iec $hbbr_size 2>/dev/null || echo "$hbbr_size bytes"))"
echo ""
echo "Also copied to bin-with-api/ for installer:"
echo "  • bin-with-api/hbbs-v8-api.exe"
echo "  • bin-with-api/hbbr-v8-api.exe"
echo ""
echo -e "${BLUE}Features included:${NC}"
echo "  ✓ HTTP API on port 21114"
echo "  ✓ Real-time device status"
echo "  ✓ Bidirectional ban enforcement"
echo "  ✓ 20-second timeout synchronization"
echo ""
echo -e "${YELLOW}Note: Windows binaries compiled on Linux using MinGW${NC}"
echo -e "${YELLOW}Test them on a Windows system to verify functionality${NC}"
echo ""
