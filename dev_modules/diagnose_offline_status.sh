#!/bin/bash
# BetterDesk Console - Diagnostic and Fix Script
# Version: 1.5.1
# 
# This script diagnoses why devices show as "Offline" and helps fix the issue.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo "=============================================="
echo "  BetterDesk Console - Diagnostic Tool v1.5.1"
echo "=============================================="
echo ""

# Default paths
RUSTDESK_DIR="${RUSTDESK_DIR:-/opt/rustdesk}"
DB_PATH="${DB_PATH:-$RUSTDESK_DIR/db_v2.sqlite3}"

# Detect script location for binary path
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BETTERDESK_HBBS=""
BETTERDESK_HBBR=""

# Try to find BetterDesk binaries
for path in "$SCRIPT_DIR/hbbs-patch-v2" "$SCRIPT_DIR/../hbbs-patch-v2" "/opt/betterdesk" "$HOME/Rustdesk-FreeConsole/hbbs-patch-v2"; do
    if [ -f "$path/hbbs-linux-x86_64" ]; then
        BETTERDESK_HBBS="$path/hbbs-linux-x86_64"
        BETTERDESK_HBBR="$path/hbbr-linux-x86_64"
        break
    fi
done

echo "📋 Configuration:"
echo "   RustDesk directory: $RUSTDESK_DIR"
echo "   Database: $DB_PATH"
echo "   BetterDesk binaries: ${BETTERDESK_HBBS:-NOT FOUND}"
echo ""

# ============================================
# STEP 1: Check if RustDesk directory exists
# ============================================
echo "🔍 Step 1: Checking RustDesk installation..."

if [ ! -d "$RUSTDESK_DIR" ]; then
    echo -e "${RED}❌ RustDesk directory not found: $RUSTDESK_DIR${NC}"
    echo "   Please set RUSTDESK_DIR environment variable or create the directory."
    exit 1
fi
echo -e "${GREEN}✓${NC} RustDesk directory exists"

# ============================================
# STEP 2: Check database
# ============================================
echo ""
echo "🔍 Step 2: Checking database..."

if [ ! -f "$DB_PATH" ]; then
    echo -e "${RED}❌ Database not found: $DB_PATH${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Database exists"

# Check if status column has any online devices
ONLINE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM peer WHERE status = 1;" 2>/dev/null || echo "0")
TOTAL_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM peer;" 2>/dev/null || echo "0")
echo "   Total devices: $TOTAL_COUNT"
echo "   Online (status=1): $ONLINE_COUNT"

if [ "$ONLINE_COUNT" = "0" ] && [ "$TOTAL_COUNT" != "0" ]; then
    echo -e "${YELLOW}⚠️  All devices show as offline - this indicates the original hbbs is being used${NC}"
fi

# ============================================
# STEP 3: Check which hbbs binary is installed
# ============================================
echo ""
echo "🔍 Step 3: Checking hbbs binary..."

CURRENT_HBBS="$RUSTDESK_DIR/hbbs"
if [ ! -f "$CURRENT_HBBS" ]; then
    echo -e "${RED}❌ hbbs binary not found at $CURRENT_HBBS${NC}"
    exit 1
fi

# Check if it's BetterDesk version
HBBS_HELP=$("$CURRENT_HBBS" --help 2>&1 || true)

if echo "$HBBS_HELP" | grep -q "BetterDesk"; then
    echo -e "${GREEN}✓${NC} BetterDesk Enhanced hbbs detected"
    HBBS_TYPE="betterdesk"
elif echo "$HBBS_HELP" | grep -q "api-port"; then
    echo -e "${GREEN}✓${NC} hbbs with API support detected"
    HBBS_TYPE="betterdesk"
else
    echo -e "${YELLOW}⚠️  Original RustDesk hbbs detected (without BetterDesk enhancements)${NC}"
    HBBS_TYPE="original"
fi

# Get version info
HBBS_VERSION=$("$CURRENT_HBBS" --version 2>&1 || echo "unknown")
echo "   Version: $HBBS_VERSION"
echo "   Type: $HBBS_TYPE"

# ============================================
# STEP 4: Check running processes
# ============================================
echo ""
echo "🔍 Step 4: Checking running processes..."

HBBS_RUNNING=$(pgrep -f "hbbs" 2>/dev/null | head -1 || echo "")
HBBR_RUNNING=$(pgrep -f "hbbr" 2>/dev/null | head -1 || echo "")

if [ -n "$HBBS_RUNNING" ]; then
    echo -e "${GREEN}✓${NC} hbbs is running (PID: $HBBS_RUNNING)"
    # Check if running with --api-port
    HBBS_CMD=$(ps -p "$HBBS_RUNNING" -o args= 2>/dev/null || echo "")
    if echo "$HBBS_CMD" | grep -q "api-port"; then
        echo -e "${GREEN}✓${NC} hbbs is running with --api-port"
    else
        echo -e "${YELLOW}⚠️  hbbs is NOT running with --api-port flag${NC}"
    fi
else
    echo -e "${RED}❌ hbbs is NOT running${NC}"
fi

if [ -n "$HBBR_RUNNING" ]; then
    echo -e "${GREEN}✓${NC} hbbr is running (PID: $HBBR_RUNNING)"
else
    echo -e "${RED}❌ hbbr is NOT running${NC}"
fi

# ============================================
# STEP 5: Check systemd services
# ============================================
echo ""
echo "🔍 Step 5: Checking systemd services..."

check_service() {
    local service=$1
    if systemctl list-unit-files | grep -q "^$service"; then
        STATUS=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        if [ "$STATUS" = "active" ]; then
            echo -e "${GREEN}✓${NC} $service: active"
        else
            echo -e "${YELLOW}⚠️${NC} $service: $STATUS"
        fi
        return 0
    else
        echo -e "${YELLOW}⚠️${NC} $service: not installed"
        return 1
    fi
}

SYSTEMD_HBBS=false
SYSTEMD_BETTERDESK=false

check_service "rustdesksignal" && SYSTEMD_HBBS=true
check_service "rustdesksignal.service" && SYSTEMD_HBBS=true
check_service "hbbs" && SYSTEMD_HBBS=true
check_service "hbbs.service" && SYSTEMD_HBBS=true
check_service "betterdesk" && SYSTEMD_BETTERDESK=true
check_service "betterdesk.service" && SYSTEMD_BETTERDESK=true
check_service "betterdesk-console" && SYSTEMD_BETTERDESK=true

# ============================================
# DIAGNOSIS SUMMARY
# ============================================
echo ""
echo "=============================================="
echo "  📊 DIAGNOSIS SUMMARY"
echo "=============================================="
echo ""

PROBLEMS_FOUND=0

if [ "$HBBS_TYPE" = "original" ]; then
    echo -e "${RED}❌ PROBLEM: Using original RustDesk hbbs${NC}"
    echo "   The original hbbs does NOT update the 'status' field in the database."
    echo "   This is why all devices show as 'Offline' in BetterDesk Console."
    echo ""
    PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
fi

if [ "$ONLINE_COUNT" = "0" ] && [ "$TOTAL_COUNT" != "0" ]; then
    echo -e "${RED}❌ PROBLEM: All devices are offline in database${NC}"
    echo "   No device has status=1 in the peer table."
    echo ""
    PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
fi

if [ -z "$HBBS_RUNNING" ]; then
    echo -e "${RED}❌ PROBLEM: hbbs is not running${NC}"
    PROBLEMS_FOUND=$((PROBLEMS_FOUND + 1))
fi

if [ "$PROBLEMS_FOUND" = "0" ]; then
    echo -e "${GREEN}✓ No major problems detected${NC}"
    echo ""
    exit 0
fi

# ============================================
# SUGGESTED FIX
# ============================================
echo ""
echo "=============================================="
echo "  🔧 SUGGESTED FIX"
echo "=============================================="
echo ""

if [ "$HBBS_TYPE" = "original" ]; then
    echo "To fix the 'all devices offline' issue, you need to:"
    echo ""
    echo "1. Stop the current hbbs:"
    echo -e "   ${BLUE}sudo pkill -f hbbs || true${NC}"
    echo ""
    
    if [ -n "$BETTERDESK_HBBS" ]; then
        echo "2. Replace with BetterDesk enhanced binary:"
        echo -e "   ${BLUE}sudo cp '$CURRENT_HBBS' '$CURRENT_HBBS.backup-original'${NC}"
        echo -e "   ${BLUE}sudo cp '$BETTERDESK_HBBS' '$CURRENT_HBBS'${NC}"
        echo -e "   ${BLUE}sudo chmod +x '$CURRENT_HBBS'${NC}"
        echo ""
        echo "3. Start hbbs WITH the --api-port flag:"
        echo -e "   ${BLUE}cd $RUSTDESK_DIR && sudo ./hbbs -k _ --api-port 21114 &${NC}"
        echo ""
    else
        echo "2. Download BetterDesk enhanced binaries:"
        echo -e "   ${BLUE}git clone https://github.com/UNITRONIX/Rustdesk-FreeConsole.git${NC}"
        echo -e "   ${BLUE}cd Rustdesk-FreeConsole${NC}"
        echo ""
        echo "3. Copy the enhanced binary:"
        echo -e "   ${BLUE}sudo cp hbbs-patch-v2/hbbs-linux-x86_64 $RUSTDESK_DIR/hbbs${NC}"
        echo -e "   ${BLUE}sudo cp hbbs-patch-v2/hbbr-linux-x86_64 $RUSTDESK_DIR/hbbr${NC}"
        echo -e "   ${BLUE}sudo chmod +x $RUSTDESK_DIR/hbbs $RUSTDESK_DIR/hbbr${NC}"
        echo ""
        echo "4. Start hbbs WITH the --api-port flag:"
        echo -e "   ${BLUE}cd $RUSTDESK_DIR && sudo ./hbbs -k _ --api-port 21114 &${NC}"
        echo ""
    fi
    
    echo "=============================================="
    echo ""
    
    read -p "Would you like to apply the fix automatically? [y/N] " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "🔧 Applying fix..."
        
        # Stop current hbbs
        echo "   Stopping current hbbs..."
        sudo pkill -f "hbbs" 2>/dev/null || true
        sleep 2
        
        # Backup original
        echo "   Creating backup..."
        sudo cp "$CURRENT_HBBS" "$CURRENT_HBBS.backup-original-$(date +%Y%m%d-%H%M%S)"
        
        if [ -n "$BETTERDESK_HBBS" ]; then
            # Copy BetterDesk binary
            echo "   Installing BetterDesk hbbs..."
            sudo cp "$BETTERDESK_HBBS" "$CURRENT_HBBS"
            sudo chmod +x "$CURRENT_HBBS"
            
            # Also update hbbr if available
            if [ -n "$BETTERDESK_HBBR" ] && [ -f "$RUSTDESK_DIR/hbbr" ]; then
                echo "   Installing BetterDesk hbbr..."
                sudo pkill -f "hbbr" 2>/dev/null || true
                sleep 1
                sudo cp "$RUSTDESK_DIR/hbbr" "$RUSTDESK_DIR/hbbr.backup-original-$(date +%Y%m%d-%H%M%S)"
                sudo cp "$BETTERDESK_HBBR" "$RUSTDESK_DIR/hbbr"
                sudo chmod +x "$RUSTDESK_DIR/hbbr"
            fi
            
            echo ""
            echo -e "${GREEN}✓ BetterDesk binaries installed!${NC}"
            echo ""
            echo "Now start the servers:"
            echo ""
            echo "  cd $RUSTDESK_DIR"
            echo "  sudo ./hbbs -k _ --api-port 21114 &"
            echo "  sudo ./hbbr &"
            echo ""
            echo "Or create systemd services (recommended):"
            echo "  See: https://github.com/UNITRONIX/Rustdesk-FreeConsole/blob/main/templates/"
            
        else
            echo -e "${RED}❌ BetterDesk binaries not found!${NC}"
            echo "   Please download from: https://github.com/UNITRONIX/Rustdesk-FreeConsole"
        fi
    fi
fi

echo ""
echo "=============================================="
echo "  📖 Documentation"
echo "=============================================="
echo ""
echo "For more help, see:"
echo "  - https://github.com/UNITRONIX/Rustdesk-FreeConsole#troubleshooting"
echo "  - https://github.com/UNITRONIX/Rustdesk-FreeConsole/blob/main/docs/TROUBLESHOOTING_EN.md"
echo ""
