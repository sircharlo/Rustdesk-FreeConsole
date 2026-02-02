#!/bin/bash
# =============================================================================
# BetterDesk - Fix Systemd Services for HBBS/HBBR
# =============================================================================
# This script checks and fixes systemd service files to use the modified
# hbbs-v8-api and hbbr-v8-api binaries with API support.
#
# Usage: sudo ./fix_systemd_services.sh [RUSTDESK_PATH]
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Default RustDesk path
RUSTDESK_PATH="${1:-/opt/rustdesk}"

echo ""
echo -e "${BLUE}=====================================${NC}"
echo -e "${BLUE}BetterDesk - Fix Systemd Services${NC}"
echo -e "${BLUE}=====================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (sudo)"
    exit 1
fi

# Common service names
HBBS_SERVICES=("rustdesksignal.service" "hbbs.service" "rustdesk-hbbs.service")
HBBR_SERVICES=("rustdeskrelay.service" "hbbr.service" "rustdesk-hbbr.service")

echo "RustDesk path: $RUSTDESK_PATH"
echo ""

# =============================================================================
# Check binaries
# =============================================================================

print_info "Checking for API-enabled binaries..."

if [ -f "$RUSTDESK_PATH/hbbs-v8-api" ]; then
    print_success "Found hbbs-v8-api"
else
    print_error "hbbs-v8-api not found in $RUSTDESK_PATH"
    print_info "Make sure you've copied the API-enabled binaries first"
fi

if [ -f "$RUSTDESK_PATH/hbbr-v8-api" ]; then
    print_success "Found hbbr-v8-api"
else
    print_error "hbbr-v8-api not found in $RUSTDESK_PATH"
fi

echo ""

# =============================================================================
# Check and display current services
# =============================================================================

print_info "Scanning for RustDesk services..."
echo ""

found_services=()
for service in "${HBBS_SERVICES[@]}" "${HBBR_SERVICES[@]}"; do
    if [ -f "/etc/systemd/system/$service" ]; then
        found_services+=("$service")
        echo "Found: $service"
        echo "  Status: $(systemctl is-active "$service" 2>/dev/null || echo 'unknown')"
        echo "  ExecStart: $(grep '^ExecStart=' "/etc/systemd/system/$service" 2>/dev/null || echo 'not found')"
        echo ""
    fi
done

if [ ${#found_services[@]} -eq 0 ]; then
    print_warning "No RustDesk services found!"
    echo ""
    print_info "Looking for any rustdesk-related services..."
    find /etc/systemd/system -name "*rustdesk*" -o -name "*hbb*" 2>/dev/null | while read -r f; do
        echo "  Found: $f"
    done
    exit 1
fi

# =============================================================================
# Fix services
# =============================================================================

echo ""
read -p "Do you want to update these services to use API-enabled binaries? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Aborted by user"
    exit 0
fi

echo ""
services_updated=false

# Fix HBBS service
for service in "${HBBS_SERVICES[@]}"; do
    service_file="/etc/systemd/system/$service"
    if [ -f "$service_file" ]; then
        print_info "Processing $service..."
        
        # Backup
        cp "$service_file" "$service_file.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Created backup"
        
        if grep -q "hbbs-v8-api" "$service_file"; then
            print_success "Already using hbbs-v8-api"
        else
            # Get current ExecStart
            old_exec=$(grep "^ExecStart=" "$service_file")
            echo "  Current: $old_exec"
            
            # Replace hbbs with hbbs-v8-api
            if echo "$old_exec" | grep -qE "/hbbs([[:space:]]|$)"; then
                new_exec=$(echo "$old_exec" | sed -E 's|/hbbs([[:space:]]|$)|/hbbs-v8-api\1|g')
                echo "  New:     $new_exec"
                
                sed -i "s|^ExecStart=.*$|$new_exec|" "$service_file"
                print_success "Updated $service"
                services_updated=true
            else
                print_warning "Could not find /hbbs in ExecStart line"
            fi
        fi
        echo ""
        break
    fi
done

# Fix HBBR service
for service in "${HBBR_SERVICES[@]}"; do
    service_file="/etc/systemd/system/$service"
    if [ -f "$service_file" ]; then
        print_info "Processing $service..."
        
        # Backup
        cp "$service_file" "$service_file.backup.$(date +%Y%m%d_%H%M%S)"
        print_success "Created backup"
        
        if grep -q "hbbr-v8-api" "$service_file"; then
            print_success "Already using hbbr-v8-api"
        else
            # Get current ExecStart
            old_exec=$(grep "^ExecStart=" "$service_file")
            echo "  Current: $old_exec"
            
            # Replace hbbr with hbbr-v8-api
            if echo "$old_exec" | grep -qE "/hbbr([[:space:]]|$)"; then
                new_exec=$(echo "$old_exec" | sed -E 's|/hbbr([[:space:]]|$)|/hbbr-v8-api\1|g')
                echo "  New:     $new_exec"
                
                sed -i "s|^ExecStart=.*$|$new_exec|" "$service_file"
                print_success "Updated $service"
                services_updated=true
            else
                print_warning "Could not find /hbbr in ExecStart line"
            fi
        fi
        echo ""
        break
    fi
done

# =============================================================================
# Reload and restart
# =============================================================================

if [ "$services_updated" = true ]; then
    print_info "Reloading systemd daemon..."
    systemctl daemon-reload
    print_success "Systemd reloaded"
    
    echo ""
    read -p "Do you want to restart the services now? [y/N] " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        for service in "${found_services[@]}"; do
            print_info "Restarting $service..."
            systemctl restart "$service"
            sleep 1
            if systemctl is-active "$service" &>/dev/null; then
                print_success "$service is running"
            else
                print_error "$service failed to start"
                print_info "Check logs: journalctl -u $service -n 20"
            fi
        done
    fi
fi

# =============================================================================
# Final status
# =============================================================================

echo ""
print_info "Final Service Status:"
echo ""

for service in "${found_services[@]}"; do
    status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
    exec_start=$(grep "^ExecStart=" "/etc/systemd/system/$service" 2>/dev/null | head -1)
    
    if [ "$status" = "active" ]; then
        echo -e "${GREEN}●${NC} $service - $status"
    else
        echo -e "${RED}●${NC} $service - $status"
    fi
    echo "  $exec_start"
    echo ""
done

print_success "Done!"
echo ""
print_info "If you have issues, restore backups with:"
echo "  cp /etc/systemd/system/SERVICE.backup.* /etc/systemd/system/SERVICE"
echo "  systemctl daemon-reload && systemctl restart SERVICE"
echo ""
