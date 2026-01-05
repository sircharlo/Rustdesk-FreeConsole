#!/bin/bash

#############################################################################
# BetterDesk Console - Installation Script
# 
# This script installs the enhanced RustDesk HBBS server with HTTP API
# and the web management console.
#
# Features:
# - Automatic backup of existing RustDesk installation
# - Compiles patched HBBS with real-time device status API
# - Installs Flask web console with glassmorphism UI
# - Configures systemd services
# - Uses Google Material Icons (offline)
#
# Author: UNITRONIX (Krzysztof Nienartowicz) and Claude Sunnet
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
    
    # Check for required commands
    for cmd in git cargo python3 pip3 curl systemctl; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        echo ""
        echo "Please install missing dependencies:"
        echo "  Ubuntu/Debian: sudo apt install git cargo python3 python3-pip curl systemd"
        echo "  CentOS/RHEL:   sudo yum install git cargo python3 python3-pip curl systemd"
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

clone_rustdesk_server() {
    print_header "Cloning RustDesk Server Repository"
    
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    if [ -d "rustdesk-server" ]; then
        print_info "Cleaning old repository..."
        rm -rf rustdesk-server
    fi
    
    print_info "Cloning rustdesk-server from GitHub..."
    git clone https://github.com/rustdesk/rustdesk-server.git
    cd rustdesk-server
    
    print_success "Repository cloned successfully"
}

apply_patches() {
    print_header "Applying HBBS Patches"
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local patch_dir="$script_dir/hbbs-patch/src"
    
    if [ ! -d "$patch_dir" ]; then
        print_error "Patch directory not found: $patch_dir"
        exit 1
    fi
    
    print_info "Copying patched files..."
    cp "$patch_dir/http_api.rs" "$TEMP_DIR/rustdesk-server/src/"
    cp "$patch_dir/main.rs" "$TEMP_DIR/rustdesk-server/src/"
    cp "$patch_dir/peer.rs" "$TEMP_DIR/rustdesk-server/src/"
    cp "$patch_dir/rendezvous_server.rs" "$TEMP_DIR/rustdesk-server/src/"
    
    print_success "Patches applied successfully"
}

compile_hbbs() {
    print_header "Compiling HBBS with HTTP API"
    
    cd "$TEMP_DIR/rustdesk-server"
    
    print_info "Adding dependencies..."
    cargo add axum --features "http1,json,tokio"
    cargo add tower-http --features "cors"
    cargo add tokio --features "full"
    
    print_info "Compiling HBBS (this may take several minutes)..."
    cargo build --release --bin hbbs
    
    if [ ! -f "target/release/hbbs" ]; then
        print_error "Compilation failed - hbbs binary not found"
        exit 1
    fi
    
    print_success "HBBS compiled successfully"
}

install_hbbs() {
    print_header "Installing Enhanced HBBS"
    
    # Stop existing service
    if systemctl is-active --quiet rustdesksignal.service; then
        print_info "Stopping existing RustDesk signal service..."
        systemctl stop rustdesksignal.service
    fi
    
    # Install new binary
    print_info "Installing new HBBS binary..."
    cp "$TEMP_DIR/rustdesk-server/target/release/hbbs" "$RUSTDESK_DIR/hbbs"
    chmod +x "$RUSTDESK_DIR/hbbs"
    
    # Update systemd service if needed
    if [ -f "/etc/systemd/system/rustdesksignal.service" ]; then
        print_info "Reloading systemd configuration..."
        systemctl daemon-reload
    fi
    
    # Start service
    print_info "Starting RustDesk signal service..."
    systemctl start rustdesksignal.service
    
    # Wait for service to be ready
    sleep 3
    
    if systemctl is-active --quiet rustdesksignal.service; then
        print_success "HBBS service is running"
    else
        print_error "HBBS service failed to start"
        systemctl status rustdesksignal.service
        exit 1
    fi
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
    echo "  • GitHub: https://github.com/yourusername/BetterDeskConsole"
    echo ""
    
    print_info "Enjoy your enhanced RustDesk experience!"
}

# Main installation flow
main() {
    clear
    print_header "BetterDesk Console Installer"
    echo "This script will install:"
    echo "  • Enhanced RustDesk HBBS with HTTP API"
    echo "  • Web Management Console with Material Design"
    echo "  • Real-time device status monitoring"
    echo ""
    
    check_root
    check_dependencies
    backup_rustdesk
    clone_rustdesk_server
    apply_patches
    compile_hbbs
    install_hbbs
    install_web_console
    test_installation
    cleanup
    show_summary
}

# Run main function
main "$@"
