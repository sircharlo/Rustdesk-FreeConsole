#!/bin/bash
# Complete the implementation - copy and patch rendezvous_server.rs

set -e

echo "======================================"
echo "BetterDesk v2 - Complete Implementation"
echo "======================================"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if original file exists
ORIGINAL="../hbbs-patch/src/rendezvous_server.rs"
TARGET="src/rendezvous_server.rs"

if [ ! -f "$ORIGINAL" ]; then
    echo -e "${RED}Error: Original file not found: $ORIGINAL${NC}"
    echo "Please ensure you have the hbbs-patch source in the parent directory"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found original file: $ORIGINAL"
echo ""

# Backup if target exists
if [ -f "$TARGET" ]; then
    BACKUP="${TARGET}.backup.$(date +%Y%m%d_%H%M%S)"
    echo "Backing up existing file to: $BACKUP"
    cp "$TARGET" "$BACKUP"
fi

# Copy original file
echo "Copying original file..."
cp "$ORIGINAL" "$TARGET"
echo -e "${GREEN}✓${NC} File copied"
echo ""

# Apply patches
echo "Applying performance patches..."
echo ""

# Patch 1: REG_TIMEOUT
echo "1. Changing REG_TIMEOUT from 30s to 15s..."
sed -i 's/const REG_TIMEOUT: i32 = 30_000/const REG_TIMEOUT: i32 = 15_000/' "$TARGET"
echo -e "   ${GREEN}✓${NC} Done"

# Patch 2: Heartbeat interval
echo "2. Changing heartbeat interval from 5s to 3s..."
sed -i 's/interval(Duration::from_secs(5))/interval(Duration::from_secs(3))/' "$TARGET"
echo -e "   ${GREEN}✓${NC} Done"

# Patch 3: TCP timeout
echo "3. Changing TCP timeout from 30s to 20s..."
sed -i 's/next_timeout(30_000)/next_timeout(20_000)/' "$TARGET"
echo -e "   ${GREEN}✓${NC} Done"

# Patch 4: WS/TCP timeout in listeners
echo "4. Changing WebSocket/TCP timeouts from 30s to 20s..."
sed -i 's/timeout(30_000/timeout(20_000/' "$TARGET"
echo -e "   ${GREEN}✓${NC} Done"

echo ""
echo -e "${GREEN}======================================"
echo "All patches applied successfully!"
echo "======================================${NC}"
echo ""

# Verify changes
echo "Verifying changes..."
if grep -q "REG_TIMEOUT: i32 = 15_000" "$TARGET"; then
    echo -e "${GREEN}✓${NC} REG_TIMEOUT: 15s"
else
    echo -e "${RED}✗${NC} REG_TIMEOUT patch may have failed"
fi

if grep -q "Duration::from_secs(3))" "$TARGET"; then
    echo -e "${GREEN}✓${NC} Heartbeat: 3s"
else
    echo -e "${RED}✗${NC} Heartbeat patch may have failed"
fi

if grep -q "timeout(20_000" "$TARGET"; then
    echo -e "${GREEN}✓${NC} Timeouts: 20s"
else
    echo -e "${RED}✗${NC} Timeout patches may have failed"
fi

echo ""
echo "======================================"
echo "Next steps:"
echo "======================================"
echo ""
echo "1. Build the project:"
echo "   cargo build --release"
echo ""
echo "2. Test the binary:"
echo "   ./target/release/hbbs --help"
echo ""
echo "3. Install:"
echo "   sudo cp target/release/hbbs /opt/rustdesk/hbbs-v2"
echo ""
echo "For more information, see QUICKSTART.md"
echo ""
