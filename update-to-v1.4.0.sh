#!/bin/bash

#############################################################################
# BetterDesk Console - Update Script to v1.4.0
# 
# This script updates existing BetterDesk Console installation to v1.4.0
# with authentication system, sidebar menu, and security improvements.
#
# Features:
# - Automatic version detection
# - Safe database migration with backup
# - Updates web console files
# - Installs new dependencies (bcrypt, markupsafe)
# - Preserves existing configuration
# - Creates default admin user
#
# Author: GitHub Copilot + UNITRONIX
# License: MIT
#############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CONSOLE_DIR="/opt/BetterDeskConsole"
WEB_DIR="$CONSOLE_DIR/web"
BACKUP_DIR="/opt/betterdesk-backup-$(date +%Y%m%d-%H%M%S)"
CURRENT_VERSION_FILE="$CONSOLE_DIR/VERSION"
TARGET_VERSION="1.4.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

detect_current_version() {
    if [ -f "$CURRENT_VERSION_FILE" ]; then
        CURRENT_VERSION=$(cat "$CURRENT_VERSION_FILE")
        print_info "Current version: $CURRENT_VERSION"
        return 0
    fi
    
    # Try to detect from files
    if [ -f "$WEB_DIR/app.py" ]; then
        if grep -q "require_auth" "$WEB_DIR/app.py"; then
            CURRENT_VERSION="1.4.0+"
        elif grep -q "is_banned" "$WEB_DIR/app.py"; then
            CURRENT_VERSION="1.3.0"
        else
            CURRENT_VERSION="1.2.0 or older"
        fi
        print_warning "Version file not found. Detected: $CURRENT_VERSION (approximate)"
        return 0
    fi
    
    print_error "Could not detect current version"
    return 1
}

check_if_update_needed() {
    if [ "$CURRENT_VERSION" == "$TARGET_VERSION" ]; then
        print_info "Already running version $TARGET_VERSION"
        echo ""
        read -p "Force re-install? [y/N]: " force
        if [[ ! "$force" =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
    
    print_success "Update needed: $CURRENT_VERSION → $TARGET_VERSION"
}

create_backup() {
    print_header "Creating Backup"
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup web console
    if [ -d "$CONSOLE_DIR" ]; then
        print_info "Backing up web console..."
        cp -r "$CONSOLE_DIR" "$BACKUP_DIR/BetterDeskConsole"
        print_success "Web console backed up"
    fi
    
    # Backup database
    if [ -f "/opt/rustdesk/db_v2.sqlite3" ]; then
        print_info "Backing up database..."
        cp "/opt/rustdesk/db_v2.sqlite3" "$BACKUP_DIR/db_v2.sqlite3"
        print_success "Database backed up"
    fi
    
    print_success "Backup created at: $BACKUP_DIR"
}

install_dependencies() {
    print_header "Installing Dependencies"
    
    # Detect Python environment
    PIP_EXTRA_ARGS=""
    if [ -f "/etc/debian_version" ] && python3 -c "import sys; exit(0 if sys.version_info >= (3,11) else 1)" 2>/dev/null; then
        PIP_EXTRA_ARGS="--break-system-packages"
    fi
    
    # Install bcrypt
    if python3 -c "import bcrypt" 2>/dev/null; then
        print_success "bcrypt already installed"
    else
        print_info "Installing bcrypt..."
        pip3 install bcrypt $PIP_EXTRA_ARGS
        print_success "bcrypt installed"
    fi
    
    # Install markupsafe
    if python3 -c "import markupsafe" 2>/dev/null; then
        print_success "markupsafe already installed"
    else
        print_info "Installing markupsafe..."
        pip3 install markupsafe $PIP_EXTRA_ARGS
        print_success "markupsafe installed"
    fi
    
    # Install Flask-WTF for CSRF protection
    if python3 -c "import flask_wtf" 2>/dev/null; then
        print_success "Flask-WTF already installed"
    else
        print_info "Installing Flask-WTF..."
        pip3 install Flask-WTF $PIP_EXTRA_ARGS
        print_success "Flask-WTF installed"
    fi
    
    # Install Flask-Limiter for rate limiting
    if python3 -c "import flask_limiter" 2>/dev/null; then
        print_success "Flask-Limiter already installed"
    else
        print_info "Installing Flask-Limiter..."
        pip3 install Flask-Limiter $PIP_EXTRA_ARGS
        print_success "Flask-Limiter installed"
    fi
}

update_web_files() {
    print_header "Updating Web Console Files"
    
    # Stop service if running
    if systemctl is-active --quiet betterdesk 2>/dev/null; then
        print_info "Stopping BetterDesk service..."
        systemctl stop betterdesk
    fi
    
    # Create directories
    mkdir -p "$WEB_DIR/templates"
    mkdir -p "$WEB_DIR/static"
    
    # Copy new files
    print_info "Copying authentication module..."
    cp "$SCRIPT_DIR/web/auth.py" "$WEB_DIR/"
    
    print_info "Copying updated app.py..."
    cp "$SCRIPT_DIR/web/app_v14.py" "$WEB_DIR/app.py"
    
    print_info "Copying login template..."
    cp "$SCRIPT_DIR/web/templates/login.html" "$WEB_DIR/templates/"
    
    print_info "Copying updated index template..."
    cp "$SCRIPT_DIR/web/templates/index_v14.html" "$WEB_DIR/templates/index.html"
    
    print_info "Copying sidebar styles..."
    cp "$SCRIPT_DIR/web/static/sidebar.css" "$WEB_DIR/static/"
    
    print_info "Copying sidebar JavaScript..."
    cp "$SCRIPT_DIR/web/static/sidebar.js" "$WEB_DIR/static/"
    
    print_info "Copying updated script.js..."
    cp "$SCRIPT_DIR/web/static/script_v14.js" "$WEB_DIR/static/script.js"
    
    # Set permissions
    chown -R root:root "$WEB_DIR"
    chmod 755 "$WEB_DIR"
    chmod 644 "$WEB_DIR"/*.py
    chmod 644 "$WEB_DIR"/templates/*.html
    chmod 644 "$WEB_DIR"/static/*
    
    print_success "Web files updated"
}

run_database_migration() {
    print_header "Running Database Migration"
    
    if [ ! -f "$SCRIPT_DIR/migrations/v1.4.0_auth_system.py" ]; then
        print_error "Migration script not found!"
        exit 1
    fi
    
    print_info "Running migration v1.4.0..."
    python3 "$SCRIPT_DIR/migrations/v1.4.0_auth_system.py"
    
    if [ $? -eq 0 ]; then
        print_success "Database migration completed"
        
        # Show admin credentials if generated
        if [ -f "$CONSOLE_DIR/admin_credentials.txt" ]; then
            echo ""
            print_warning "=" * 60
            print_warning "DEFAULT ADMIN CREDENTIALS GENERATED!"
            print_warning "=" * 60
            cat "$CONSOLE_DIR/admin_credentials.txt"
            echo ""
            print_warning "⚠️  IMPORTANT: Change the password immediately after first login!"
            print_warning "⚠️  Delete this file after saving credentials: $CONSOLE_DIR/admin_credentials.txt"
        fi
    else
        print_error "Database migration failed!"
        print_info "Check the error messages above"
        print_info "Your backup is at: $BACKUP_DIR"
        exit 1
    fi
}

update_version_file() {
    echo "$TARGET_VERSION" > "$CURRENT_VERSION_FILE"
    print_success "Version file updated to $TARGET_VERSION"
}

configure_api_security() {
    print_header "Configuring API Security"
    
    # Detect RustDesk directory
    RUSTDESK_DIR="/opt/rustdesk"
    if [ ! -d "$RUSTDESK_DIR" ]; then
        print_warning "RustDesk directory not found, trying alternate locations..."
        if [ -d "/var/lib/rustdesk" ]; then
            RUSTDESK_DIR="/var/lib/rustdesk"
        else
            print_error "Could not find RustDesk installation directory"
            return 1
        fi
    fi
    
    API_KEY_FILE="$RUSTDESK_DIR/.api_key"
    
    # Generate API key if it doesn't exist
    if [ -f "$API_KEY_FILE" ]; then
        print_info "API key already exists, keeping existing key"
        API_KEY=$(cat "$API_KEY_FILE")
    else
        print_info "Generating new API key..."
        API_KEY=$(openssl rand -base64 48 | tr -d '/+=' | cut -c1-64)
        echo -n "$API_KEY" > "$API_KEY_FILE"
        chmod 600 "$API_KEY_FILE"
        print_success "API key generated and saved to $API_KEY_FILE"
    fi
    
    # Update betterdesk.service with API key environment variable
    SERVICE_FILE="/etc/systemd/system/betterdesk.service"
    if [ -f "$SERVICE_FILE" ]; then
        # Check if HBBS_API_KEY is already configured
        if grep -q "HBBS_API_KEY" "$SERVICE_FILE"; then
            print_info "Service file already contains HBBS_API_KEY"
        else
            print_info "Adding HBBS_API_KEY to betterdesk.service..."
            
            # Add environment variable after [Service] section
            sed -i "/^\[Service\]/a Environment=\"HBBS_API_KEY=$API_KEY\"" "$SERVICE_FILE"
            
            # Also ensure Flask is configured for LAN access
            if ! grep -q "FLASK_HOST=0.0.0.0" "$SERVICE_FILE"; then
                sed -i "/^\[Service\]/a Environment=\"FLASK_HOST=0.0.0.0\"" "$SERVICE_FILE"
                sed -i "/^\[Service\]/a Environment=\"FLASK_PORT=5000\"" "$SERVICE_FILE"
                sed -i "/^\[Service\]/a Environment=\"FLASK_DEBUG=False\"" "$SERVICE_FILE"
            fi
            
            systemctl daemon-reload
            print_success "Service file updated with API security configuration"
        fi
    else
        print_warning "betterdesk.service not found - skipping service configuration"
    fi
    
    # Update rustdesksignal.service to bind API to LAN (0.0.0.0)
    HBBS_SERVICE="/etc/systemd/system/rustdesksignal.service"
    if [ -f "$HBBS_SERVICE" ]; then
        # Check if API is already configured for LAN access
        if grep -q "\-\-api-port" "$HBBS_SERVICE"; then
            print_info "HBBS API port already configured"
            
            # Check if binding to 0.0.0.0
            if grep -q "0.0.0.0" "$HBBS_SERVICE"; then
                print_info "HBBS API already configured for LAN access"
            else
                print_warning "HBBS API found but may be localhost-only"
                print_info "Note: New HBBS binaries bind to 0.0.0.0 by default with API key authentication"
            fi
        fi
    fi
    
    print_success "API security configuration complete"
    echo ""
    print_info "Security notes:"
    echo "  • API key stored in: $API_KEY_FILE"
    echo "  • Web console uses API key for HBBS requests"
    echo "  • HBBS API accessible on LAN with X-API-Key header authentication"
    echo "  • Web console accessible on: http://$(hostname -I | awk '{print $1}'):5000"
}

restart_services() {
    print_header "Restarting Services"
    
    # Restart BetterDesk web console
    if [ -f "/etc/systemd/system/betterdesk.service" ]; then
        print_info "Restarting BetterDesk service..."
        systemctl daemon-reload
        systemctl restart betterdesk
        systemctl status betterdesk --no-pager
        print_success "BetterDesk service restarted"
    else
        print_warning "BetterDesk service not found (manual start may be needed)"
    fi
}

show_completion_message() {
    print_header "Update Complete!"
    
    echo -e "${GREEN}✅ BetterDesk Console has been updated to v$TARGET_VERSION${NC}"
    echo ""
    echo "New Features:"
    echo "  • User authentication with login system"
    echo "  • Role-based access control (admin/operator/viewer)"
    echo "  • Sidebar navigation menu with Users management"
    echo "  • Password-protected public key access"
    echo "  • Audit logging"
    echo "  • API key authentication for HBBS API"
    echo "  • LAN access for web console and API"
    echo "  • Enhanced security across all components"
    echo ""
    echo "Security Enhancements:"
    echo "  • Fail-closed policy for ban checks (HIGH)"
    echo "  • CSRF protection with Flask-WTF"
    echo "  • Rate limiting on login (5 per minute)"
    echo "  • Password requirements: 8+ chars, letters + numbers"
    echo "  • Content Security Policy headers"
    echo "  • Secure audit logging"
    echo ""
    echo "Access your console:"
    echo "  • Web Console: http://$(hostname -I | awk '{print $1}'):5000"
    echo "  • HBBS API: http://$(hostname -I | awk '{print $1}'):21120/api/health"
    echo "  • See admin credentials above (if new installation)"
    echo ""
    echo "Security:"
    echo "  • API key: /opt/rustdesk/.api_key"
    echo "  • All API requests now require X-API-Key header"
    echo ""
    echo "Backup location: $BACKUP_DIR"
    echo "Keep this backup until you verify everything works correctly!"
    echo ""
    
    if [ -f "$CONSOLE_DIR/admin_credentials.txt" ]; then
        echo -e "${YELLOW}⚠️  Don't forget to:${NC}"
        echo "  1. Login with default credentials"
        echo "  2. Change the admin password"
        echo "  3. Delete $CONSOLE_DIR/admin_credentials.txt"
        echo ""
    fi
}

rollback() {
    print_error "Update failed! Rolling back..."
    
    if [ -d "$BACKUP_DIR/BetterDeskConsole" ]; then
        rm -rf "$CONSOLE_DIR"
        cp -r "$BACKUP_DIR/BetterDeskConsole" "$CONSOLE_DIR"
        print_success "Web console restored from backup"
    fi
    
    if [ -f "$BACKUP_DIR/db_v2.sqlite3" ]; then
        cp "$BACKUP_DIR/db_v2.sqlite3" "/opt/rustdesk/db_v2.sqlite3"
        print_success "Database restored from backup"
    fi
    
    # Restart services
    if [ -f "/etc/systemd/system/betterdesk.service" ]; then
        systemctl restart betterdesk
    fi
    
    print_info "Rollback complete. Your backup is preserved at: $BACKUP_DIR"
    exit 1
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    print_header "BetterDesk Console Update to v$TARGET_VERSION"
    
    # Set trap for errors
    trap rollback ERR
    
    # Checks
    check_root
    
    # Detect current version
    if ! detect_current_version; then
        print_error "Installation directory not found: $CONSOLE_DIR"
        echo ""
        echo "This script updates existing BetterDesk Console installations."
        echo "For new installations, use install-improved.sh"
        exit 1
    fi
    
    # Check if update needed
    check_if_update_needed
    
    # Confirm update
    echo ""
    echo "This will update BetterDesk Console from $CURRENT_VERSION to $TARGET_VERSION"
    echo "A backup will be created before making any changes."
    echo ""
    read -p "Continue with update? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Update cancelled by user"
        exit 0
    fi
    
    # Execute update steps
    create_backup
    install_dependencies
    update_web_files
    run_database_migration
    update_version_file
    configure_api_security
    restart_services
    show_completion_message
    
    # Disable error trap
    trap - ERR
}

# Run main function
main "$@"
