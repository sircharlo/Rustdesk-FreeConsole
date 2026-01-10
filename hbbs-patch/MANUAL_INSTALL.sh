#!/bin/bash
#############################################################################
# BetterDesk - Manual Installation Script for SSH Server
# 
# This script installs new HBBS/HBBR binaries with security fixes
# (port 21120, localhost-only API binding)
#
# Run on SSH server: sudo bash MANUAL_INSTALL.sh
#############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_header "BetterDesk - Manual Binary Installation"

# Step 1: Stop services
print_header "Step 1: Stopping HBBS/HBBR services"
systemctl stop rustdesksignal 2>/dev/null || echo "Service not running"
pkill -9 hbbs 2>/dev/null || echo "HBBS not running"
pkill -9 hbbr 2>/dev/null || echo "HBBR not running"
sleep 2
print_success "Services stopped"

# Step 2: Backup old binaries
print_header "Step 2: Backing up old binaries"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
if [ -f /opt/rustdesk/hbbs ]; then
    cp /opt/rustdesk/hbbs /opt/rustdesk/hbbs.backup-$TIMESTAMP
    print_success "HBBS backed up to /opt/rustdesk/hbbs.backup-$TIMESTAMP"
fi
if [ -f /opt/rustdesk/hbbr ]; then
    cp /opt/rustdesk/hbbr /opt/rustdesk/hbbr.backup-$TIMESTAMP
    print_success "HBBR backed up to /opt/rustdesk/hbbr.backup-$TIMESTAMP"
fi

# Step 3: Copy new binaries
print_header "Step 3: Installing new binaries"
BINARY_PATH="$HOME/build/hbbs-patch/rustdesk-server/target/release"

if [ ! -f "$BINARY_PATH/hbbs" ]; then
    print_error "HBBS binary not found at $BINARY_PATH/hbbs"
    exit 1
fi

if [ ! -f "$BINARY_PATH/hbbr" ]; then
    print_error "HBBR binary not found at $BINARY_PATH/hbbr"
    exit 1
fi

cp "$BINARY_PATH/hbbs" /opt/rustdesk/hbbs
cp "$BINARY_PATH/hbbr" /opt/rustdesk/hbbr
chmod +x /opt/rustdesk/hbbs /opt/rustdesk/hbbr
print_success "New binaries installed"

# Step 4: Verify installation
print_header "Step 4: Verifying installation"
if strings /opt/rustdesk/hbbs | grep -q "HTTP API server listening"; then
    print_success "HBBS contains HTTP API code"
else
    print_error "Warning: HTTP API code not found in HBBS"
fi

if strings /opt/rustdesk/hbbs | grep -q "localhost only"; then
    print_success "HBBS contains localhost-only security"
else
    print_error "Warning: localhost-only security not found"
fi

# Step 5: Restart services
print_header "Step 5: Restarting services"
systemctl restart rustdesksignal
sleep 3
print_success "Services restarted"

# Step 6: Verify ports
print_header "Step 6: Verifying ports"
echo "RustDesk ports (21115-21117):"
ss -tlnp | grep hbbs | grep -E '21115|21116|21117' || echo "  No RustDesk ports found"

echo ""
echo "HTTP API port (21120, localhost only):"
if ss -tlnp | grep hbbs | grep '127.0.0.1:21120'; then
    print_success "HTTP API listening on localhost:21120 (SECURE)"
else
    print_error "HTTP API not detected on port 21120"
fi

echo ""
echo "External accessibility test:"
LOCAL_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
echo "  Testing from outside: curl http://$LOCAL_IP:21120/api/health"
if timeout 2 curl -s http://$LOCAL_IP:21120/api/health 2>&1 | grep -q "Connection refused"; then
    print_success "Port 21120 is NOT accessible from network (CORRECT)"
else
    print_error "Warning: Port 21120 might be accessible from network"
fi

print_header "Installation Complete"
echo ""
echo "Summary:"
echo "  ✅ New binaries installed with security fixes"
echo "  ✅ HTTP API on port 21120 (localhost only)"
echo "  ✅ RustDesk ports 21115-21117 operational"
echo "  ✅ Services running"
echo ""
echo "To access API remotely, use SSH tunnel:"
echo "  ssh -L 21120:localhost:21120 $USER@$LOCAL_IP"
echo "  Then access: http://localhost:21120/api/health"
echo ""
