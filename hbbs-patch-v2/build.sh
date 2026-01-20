#!/bin/bash
# Build script for BetterDesk Server v2

set -e

echo "======================================"
echo "BetterDesk Server v2 - Build Script"
echo "======================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for Rust
if ! command -v cargo &> /dev/null; then
    echo -e "${RED}Error: Rust/Cargo not found${NC}"
    echo "Please install Rust from https://rustup.rs/"
    exit 1
fi

echo -e "${GREEN}✓${NC} Rust found: $(rustc --version)"

# Check for dependencies
echo ""
echo "Checking system dependencies..."

DEPS_MISSING=0

if ! pkg-config --exists sqlite3; then
    echo -e "${RED}✗${NC} SQLite3 development files not found"
    echo "  Install with: sudo apt-get install libsqlite3-dev"
    DEPS_MISSING=1
else
    echo -e "${GREEN}✓${NC} SQLite3 found"
fi

if ! pkg-config --exists openssl; then
    echo -e "${RED}✗${NC} OpenSSL development files not found"
    echo "  Install with: sudo apt-get install libssl-dev"
    DEPS_MISSING=1
else
    echo -e "${GREEN}✓${NC} OpenSSL found"
fi

if [ $DEPS_MISSING -eq 1 ]; then
    echo ""
    echo -e "${RED}Missing dependencies. Please install them first.${NC}"
    exit 1
fi

# Check if we have the RustDesk server source
if [ ! -d "../rustdesk-server-1.1.14" ]; then
    echo ""
    echo -e "${YELLOW}Warning: RustDesk server source not found at ../rustdesk-server-1.1.14${NC}"
    echo "The build may fail without the original RustDesk server source."
    echo ""
    echo "Please ensure you have the rustdesk-server source code in the parent directory."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Build
echo ""
echo "======================================"
echo "Building BetterDesk Server v2..."
echo "======================================"
echo ""

BUILD_TYPE="${1:-release}"

if [ "$BUILD_TYPE" = "debug" ]; then
    echo "Building in DEBUG mode..."
    cargo build
    BINARY_PATH="target/debug/hbbs"
else
    echo "Building in RELEASE mode (optimized)..."
    cargo build --release
    BINARY_PATH="target/release/hbbs"
fi

# Check if build succeeded
if [ ! -f "$BINARY_PATH" ]; then
    echo ""
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}======================================"
echo "Build successful!"
echo "======================================${NC}"
echo ""
echo "Binary location: $BINARY_PATH"
echo "Binary size: $(du -h $BINARY_PATH | cut -f1)"
echo ""

# Show version
echo "Version information:"
$BINARY_PATH --version 2>/dev/null || echo "  BetterDesk Server v2.0.0"
echo ""

# Installation instructions
echo "======================================"
echo "Next steps:"
echo "======================================"
echo ""
echo "1. Install the binary:"
echo "   sudo cp $BINARY_PATH /opt/rustdesk/hbbs-v2"
echo "   sudo chmod +x /opt/rustdesk/hbbs-v2"
echo ""
echo "2. Test it:"
echo "   /opt/rustdesk/hbbs-v2 --help"
echo ""
echo "3. Run it:"
echo "   /opt/rustdesk/hbbs-v2 -k YOUR_KEY"
echo ""
echo "4. Or install as systemd service:"
echo "   See INSTALLATION.md for details"
echo ""
echo "For more information, see:"
echo "  - QUICKSTART.md  - Quick start guide"
echo "  - INSTALLATION.md - Detailed installation"
echo "  - CHANGES.md     - What's new in v2"
echo ""
