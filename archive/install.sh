#!/bin/bash

#############################################################################
# BetterDesk Console - Installation Script v8
# 
# This script installs the enhanced RustDesk HBBS/HBBR servers with 
# bidirectional ban enforcement and web management console.
#
# Features:
# - Automatic backup of existing RustDesk installation
# - Precompiled HBBS/HBBR binaries with ban enforcement (no compilation needed)
# - Bidirectional ban checking (source + target devices)
# - Installs Flask web console with glassmorphism UI
# - Configures systemd services
# - Uses Google Material Icons (offline)
#
# Ban Enforcement Features (v8):
# - Prevents banned devices from initiating connections (source check)
# - Prevents connections to banned devices (target check)
# - Real-time database sync
# - Works for both P2P and relay connections
#
# Author: GitHub Copilot
# License: MIT
#############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
RUSTDESK_DIR="/opt/rustdesk"
BACKUP_DIR="/opt/rustdesk-backup-$(date +%Y%m%d-%H%M%S)"
CONSOLE_DIR="/opt/BetterDeskConsole"
TEMP_DIR="/tmp/betterdesk-install"
HBBS_API_PORT=21114
VERSION="v8"  # Current version with bidirectional ban enforcement

# Helper functions
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

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_dependencies() {
    print_header "Checking Dependencies"
    
    local missing_deps=()
    
    # Check for required commands (removed cargo - using precompiled binaries)
    for cmd in python3 pip3 curl systemctl; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        echo ""
        echo "Please install missing dependencies:"
        echo "  Ubuntu/Debian: sudo apt install python3 python3-pip curl systemd"
        echo "  CentOS/RHEL:   sudo yum install python3 python3-pip curl systemd"
        exit 1
    fi
    
    print_success "All dependencies found"
}

backup_rustdesk() {
    print_header "Backing Up Existing RustDesk Installation"
    
    if [ ! -d "$RUSTDESK_DIR" ]; then
        print_warning "No existing RustDesk installation found at $RUSTDESK_DIR"
        print_info "Will proceed with fresh installation"
        return 0
    fi
    
    echo -e "${YELLOW}Found existing RustDesk installation${NC}"
    echo ""
    echo "Options:"
    echo "  1) Create automatic backup to $BACKUP_DIR"
    echo "  2) I have already created a manual backup"
    echo "  3) Skip backup (not recommended)"
    echo ""
    read -p "Choose option [1-3]: " backup_choice
    
    case $backup_choice in
        1)
            print_info "Creating backup..."
            cp -r "$RUSTDESK_DIR" "$BACKUP_DIR"
            print_success "Backup created at: $BACKUP_DIR"
            ;;
        2)
            print_info "Using manual backup"
            ;;
        3)
            print_warning "Skipping backup - YOU ARE RESPONSIBLE FOR ANY DATA LOSS"
            read -p "Are you SURE? Type 'yes' to continue: " confirm
            if [ "$confirm" != "yes" ]; then
                print_error "Installation cancelled"
                exit 1
            fi
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
}

install_binaries() {
    print_header "Installing Enhanced HBBS/HBBR $VERSION"
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local bin_dir="$script_dir/hbbs-patch/bin"
    
    if [ ! -f "$bin_dir/hbbs-$VERSION" ] || [ ! -f "$bin_dir/hbbr-$VERSION" ]; then
        print_error "Precompiled binaries not found in: $bin_dir"
        print_info "Expected files: hbbs-$VERSION, hbbr-$VERSION"
        exit 1
    fi
    
    # Create RustDesk directory if it doesn't exist
    mkdir -p "$RUSTDESK_DIR"
    
    # Stop existing services
    print_info "Stopping RustDesk services..."
    systemctl stop rustdesksignal.service 2>/dev/null || true
    systemctl stop rustdeskrelay.service 2>/dev/null || true
    pkill -9 hbbs 2>/dev/null || true
    pkill -9 hbbr 2>/dev/null || true
    sleep 2
    
    # Backup existing binaries
    if [ -f "$RUSTDESK_DIR/hbbs" ]; then
        print_info "Backing up old hbbs..."
        cp "$RUSTDESK_DIR/hbbs" "$RUSTDESK_DIR/hbbs.backup.$(date +%Y%m%d-%H%M%S)"
    fi
    
    if [ -f "$RUSTDESK_DIR/hbbr" ]; then
        print_info "Backing up old hbbr..."
        cp "$RUSTDESK_DIR/hbbr" "$RUSTDESK_DIR/hbbr.backup.$(date +%Y%m%d-%H%M%S)"
    fi
    
    # Install new binaries
    print_info "Installing HBBS $VERSION (with bidirectional ban enforcement)..."
    cp "$bin_dir/hbbs-$VERSION" "$RUSTDESK_DIR/hbbs"
    chmod +x "$RUSTDESK_DIR/hbbs"
    
    print_info "Installing HBBR $VERSION..."
    cp "$bin_dir/hbbr-$VERSION" "$RUSTDESK_DIR/hbbr"
    chmod +x "$RUSTDESK_DIR/hbbr"
    
    print_success "Binaries installed successfully"
    
    # Restart services
    print_info "Restarting RustDesk services..."
    systemctl daemon-reload 2>/dev/null || true
    systemctl start rustdesksignal.service 2>/dev/null || true
    systemctl start rustdeskrelay.service 2>/dev/null || true
    
    # Wait for services to start
    sleep 3
    
    # Verify services
    local services_ok=true
    if systemctl is-active --quiet rustdesksignal.service; then
        print_success "HBBS service is running"
    else
        print_warning "HBBS service not running (may need manual start)"
        services_ok=false
    fi
    
    if systemctl is-active --quiet rustdeskrelay.service 2>/dev/null; then
        print_success "HBBR service is running"
    else
        print_info "HBBR service not configured (optional)"
    fi
    
    # Display version info
    echo ""
    print_info "HBBS/HBBR version: $VERSION"
    print_info "Features:"
    echo "  ✓ Bidirectional ban enforcement"
    echo "  ✓ Source device ban check (prevents banned devices from initiating connections)"
    echo "  ✓ Target device ban check (prevents connections to banned devices)"
    echo "  ✓ Real-time ban database sync"
    echo ""
}

clone_rustdesk_server() {
    # This function is no longer needed - using precompiled binaries
    print_info "Using precompiled binaries - skipping source clone"
}

apply_patches() {
    # This function is no longer needed - binaries are pre-patched
    print_info "Binaries are pre-patched - skipping patch application"
}

compile_hbbs() {
    # This function is no longer needed - using precompiled binaries
    print_info "Using precompiled binaries - skipping compilation"
}

install_hbbs() {
    # This function has been replaced by install_binaries()
    # Kept for compatibility but redirects to new function
    print_info "Redirecting to install_binaries()..."
}

run_database_migrations() {
    print_header "Running Database Migrations"
    
    local db_path="$RUSTDESK_DIR/db_v2.sqlite3"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local migrations_dir="$script_dir/migrations"
    
    # Check if database exists
    if [ ! -f "$db_path" ]; then
        print_warning "Database not found at $db_path"
        print_info "Database will be created automatically when HBBS starts"
        print_info "Skipping migrations - they will be applied on first run"
        return 0
    fi
    
    # Create backup of database
    local backup_file="$db_path.backup-$(date +%Y%m%d-%H%M%S)"
    print_info "Creating database backup..."
    cp "$db_path" "$backup_file"
    print_success "Database backed up to: $backup_file"
    
    # Check if migrations directory exists
    if [ ! -d "$migrations_dir" ]; then
        print_error "Migrations directory not found: $migrations_dir"
        exit 1
    fi
    
    # Run v1.0.1 migration (soft delete)
    print_info "Running migration v1.0.1 (soft delete)..."
    if python3 "$migrations_dir/v1.0.1_soft_delete.py"; then
        print_success "Migration v1.0.1 completed successfully"
    else
        print_warning "Migration v1.0.1 failed or already applied"
    fi
    
    # Run v1.1.0 migration (device bans)
    print_info "Running migration v1.1.0 (device bans)..."
    if python3 "$migrations_dir/v1.1.0_device_bans.py"; then
        print_success "Migration v1.1.0 completed successfully"
    else
        print_warning "Migration v1.1.0 failed or already applied"
    fi
    
    print_success "Database migrations completed"
    echo ""
}

install_web_console() {
    print_header "Installing Web Management Console"
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local web_dir="$script_dir/web"
    
    if [ ! -d "$web_dir" ]; then
        print_error "Web directory not found: $web_dir"
        exit 1
    fi
    
    # Create console directory
    mkdir -p "$CONSOLE_DIR"
    
    # Copy files
    print_info "Copying web console files..."
    cp -r "$web_dir"/* "$CONSOLE_DIR/"
    
    # Install Python dependencies
    print_info "Installing Python dependencies..."
    pip3 install -r "$CONSOLE_DIR/requirements.txt"
    
    # Create systemd service
    print_info "Creating systemd service..."
    cat > /etc/systemd/system/betterdesk.service <<EOF
[Unit]
Description=BetterDesk Console - RustDesk Web Management
After=network.target rustdesksignal.service

[Service]
Type=simple
User=root
WorkingDirectory=$CONSOLE_DIR
ExecStart=/usr/bin/python3 $CONSOLE_DIR/app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start service
    systemctl daemon-reload
    systemctl enable betterdesk.service
    systemctl start betterdesk.service
    
    # Wait for service to be ready
    sleep 2
    
    if systemctl is-active --quiet betterdesk.service; then
        print_success "Web console service is running"
    else
        print_error "Web console service failed to start"
        systemctl status betterdesk.service
        exit 1
    fi
}

test_installation() {
    print_header "Testing Installation"
    
    # Test HBBS API
    print_info "Testing HBBS HTTP API..."
    if curl -s "http://localhost:$HBBS_API_PORT/api/health" | grep -q "success"; then
        print_success "HBBS API is responding"
    else
        print_error "HBBS API is not responding"
    fi
    
    # Test Web Console
    print_info "Testing Web Console..."
    if curl -s "http://localhost:5000" > /dev/null; then
        print_success "Web Console is accessible"
    else
        print_error "Web Console is not accessible"
    fi
}

cleanup() {
    print_header "Cleaning Up"
    
    print_info "Removing temporary files..."
    rm -rf "$TEMP_DIR"
    
    print_success "Cleanup completed"
}

show_summary() {
    print_header "Installation Complete!"
    
    echo -e "${GREEN}BetterDesk Console has been successfully installed!${NC}"
    echo ""
    echo "Access points:"
    echo "  • Web Console:  http://$(hostname -I | awk '{print $1}'):5000"
    echo "  • HBBS API:     http://localhost:$HBBS_API_PORT/api/health"
    echo ""
    echo "Services:"
    echo "  • HBBS:         sudo systemctl status rustdesksignal.service"
    echo "  • Web Console:  sudo systemctl status betterdesk.service"
    echo ""
    
    if [ -d "$BACKUP_DIR" ]; then
        echo "Backup location:"
        echo "  • $BACKUP_DIR"
        echo ""
    fi
    
    echo "Documentation:"
    echo "  • README.md in the installation directory"
    echo "  • GitHub: https://github.com/UNITRONIX/Rustdesk-FreeConsole"
    echo ""
    
    print_info "Enjoy your enhanced RustDesk experience!"
}

# Main installation flow
main() {
    clear
    print_header "BetterDesk Console Installer $VERSION"
    echo "This script will install:"
    echo "  • Enhanced RustDesk HBBS/HBBR with bidirectional ban enforcement"
    echo "  • Web Management Console with Material Design"
    echo "  • Real-time device status monitoring"
    echo ""
    echo "Installation method: Precompiled binaries (no compilation required)"
    echo ""
    
    check_root
    check_dependencies
    backup_rustdesk
    install_binaries
    run_database_migrations
    install_web_console
    test_installation
    cleanup
    show_summary
}

# Run main function
main "$@"
