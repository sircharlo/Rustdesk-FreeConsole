#!/bin/bash

#############################################################################
# BetterDesk Console - Update Script (v1.1.0)
# 
# This script updates existing BetterDesk installation to version 1.1.0
# with device banning system and soft delete functionality.
#
# Features:
# - Automatic database backup before migration
# - Executes database migrations (v1.0.1 soft delete + v1.1.0 bans)
# - Updates web console files (app.py, script.js, index.html)
# - Restarts BetterDesk service
# - Verifies installation
#
# Requirements:
# - Existing BetterDesk Console installation
# - Root/sudo access
# - Python 3.x with Flask
#
# Usage:
#   sudo ./update.sh [OPTIONS]
#   sudo ./update.sh --rustdesk-dir /custom/path/rustdesk
#   sudo ./update.sh --console-dir /custom/path/console
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
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration
RUSTDESK_DIR="/opt/rustdesk"
CONSOLE_DIR="/opt/BetterDeskConsole"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --rustdesk-dir)
            RUSTDESK_DIR="$2"
            shift 2
            ;;
        --console-dir)
            CONSOLE_DIR="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: sudo ./update.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --rustdesk-dir PATH    Path to RustDesk installation (default: /opt/rustdesk)"
            echo "  --console-dir PATH     Path to BetterDesk Console (default: /opt/BetterDeskConsole)"
            echo "  -h, --help            Show this help message"
            echo ""
            echo "Examples:"
            echo "  sudo ./update.sh"
            echo "  sudo ./update.sh --rustdesk-dir /custom/rustdesk"
            echo "  sudo ./update.sh --console-dir /var/www/betterdesk"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set derived paths
DB_PATH="$RUSTDESK_DIR/db_v2.sqlite3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/opt/betterdesk-backup-$(date +%Y%m%d-%H%M%S)"

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
    exit 1
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${CYAN}→ $1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
fi

print_header "BetterDesk Console - Update to v1.1.0"

echo -e "${CYAN}Configuration:${NC}"
echo "  RustDesk directory: $RUSTDESK_DIR"
echo "  Console directory:  $CONSOLE_DIR"
echo "  Database path:      $DB_PATH"
echo ""
echo -e "${CYAN}This update includes:${NC}"
echo "  • Soft delete system for devices (v1.0.1)"
echo "  • Device banning system (v1.1.0)"
echo "  • Enhanced UI with ban controls"
echo "  • Input validation and security improvements"
echo ""
echo -e "${YELLOW}⚠ WARNING: This will modify the database and restart services${NC}"
echo ""
read -p "Continue with update? [y/N]: " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Update cancelled."
    exit 0
fi

# Check if BetterDesk is installed
print_header "Step 1: Checking Installation"

if [ ! -d "$CONSOLE_DIR" ]; then
    print_error "BetterDesk Console not found at $CONSOLE_DIR"
fi
print_success "Found BetterDesk Console"

if [ ! -f "$DB_PATH" ]; then
    print_error "Database not found at $DB_PATH"
fi
print_success "Found database"

# Check if service exists
if ! systemctl list-unit-files | grep -q "betterdesk.service"; then
    print_warning "BetterDesk service not found, will skip restart"
    SERVICE_EXISTS=false
else
    print_success "Found BetterDesk service"
    SERVICE_EXISTS=true
fi

# Create backup
print_header "Step 2: Creating Backup"

mkdir -p "$BACKUP_DIR"
print_info "Backup directory: $BACKUP_DIR"

# Backup database
print_info "Backing up database..."
cp "$DB_PATH" "$BACKUP_DIR/db_v2.sqlite3.backup"
print_success "Database backed up"

# Backup web files
print_info "Backing up web console files..."
if [ -f "$CONSOLE_DIR/app.py" ]; then
    cp "$CONSOLE_DIR/app.py" "$BACKUP_DIR/app.py.backup"
fi
if [ -f "$CONSOLE_DIR/static/script.js" ]; then
    cp "$CONSOLE_DIR/static/script.js" "$BACKUP_DIR/script.js.backup"
fi
if [ -f "$CONSOLE_DIR/templates/index.html" ]; then
    cp "$CONSOLE_DIR/templates/index.html" "$BACKUP_DIR/index.html.backup"
fi
print_success "Web files backed up"

echo ""
print_success "Backup completed: $BACKUP_DIR"

# Execute migrations
print_header "Step 3: Database Migration"

print_info "Running migration v1.0.1 (soft delete)..."
if [ -f "$SCRIPT_DIR/migrations/v1.0.1_soft_delete.py" ]; then
    python3 "$SCRIPT_DIR/migrations/v1.0.1_soft_delete.py" <<EOF
y
EOF
    print_success "Migration v1.0.1 completed"
else
    print_warning "Migration v1.0.1 script not found, skipping"
fi

echo ""
print_info "Running migration v1.1.0 (device bans)..."
if [ -f "$SCRIPT_DIR/migrations/v1.1.0_device_bans.py" ]; then
    python3 "$SCRIPT_DIR/migrations/v1.1.0_device_bans.py" <<EOF
y
EOF
    print_success "Migration v1.1.0 completed"
else
    print_error "Migration v1.1.0 script not found at $SCRIPT_DIR/migrations/"
fi

# Update web files
print_header "Step 4: Updating Web Console Files"

if [ ! -d "$SCRIPT_DIR/web" ]; then
    print_error "Web directory not found at $SCRIPT_DIR/web"
fi

# Update app.py
if [ -f "$SCRIPT_DIR/web/app.py" ]; then
    print_info "Updating app.py..."
    cp "$SCRIPT_DIR/web/app.py" "$CONSOLE_DIR/app.py"
    print_success "app.py updated"
else
    print_error "app.py not found in $SCRIPT_DIR/web/"
fi

# Update script.js
if [ -f "$SCRIPT_DIR/web/static/script.js" ]; then
    print_info "Updating script.js..."
    mkdir -p "$CONSOLE_DIR/static"
    cp "$SCRIPT_DIR/web/static/script.js" "$CONSOLE_DIR/static/script.js"
    print_success "script.js updated"
else
    print_error "script.js not found in $SCRIPT_DIR/web/static/"
fi

# Update index.html
if [ -f "$SCRIPT_DIR/web/templates/index.html" ]; then
    print_info "Updating index.html..."
    mkdir -p "$CONSOLE_DIR/templates"
    cp "$SCRIPT_DIR/web/templates/index.html" "$CONSOLE_DIR/templates/index.html"
    print_success "index.html updated"
else
    print_error "index.html not found in $SCRIPT_DIR/web/templates/"
fi

# Set proper permissions
print_info "Setting permissions..."
chown -R $(stat -c '%U:%G' "$CONSOLE_DIR") "$CONSOLE_DIR" 2>/dev/null || true
print_success "Permissions set"

# Restart service
if [ "$SERVICE_EXISTS" = true ]; then
    print_header "Step 5: Restarting Service"
    
    print_info "Stopping BetterDesk service..."
    systemctl stop betterdesk
    sleep 2
    
    print_info "Starting BetterDesk service..."
    systemctl start betterdesk
    sleep 3
    
    if systemctl is-active --quiet betterdesk; then
        print_success "BetterDesk service is running"
    else
        print_error "Failed to start BetterDesk service"
    fi
else
    print_header "Step 5: Service Restart (Skipped)"
    print_warning "Please restart BetterDesk manually"
fi

# Verify installation
print_header "Step 6: Verification"

# Check database schema
print_info "Verifying database schema..."
COLUMNS=$(sqlite3 "$DB_PATH" "PRAGMA table_info(peer);" | wc -l)
if [ "$COLUMNS" -ge 16 ]; then
    print_success "Database schema updated (16+ columns)"
else
    print_warning "Database may not have all new columns ($COLUMNS found)"
fi

# Check if web console is accessible (if service is running)
if [ "$SERVICE_EXISTS" = true ]; then
    print_info "Checking web console..."
    sleep 2
    if curl -s http://localhost:5000/api/stats > /dev/null 2>&1; then
        print_success "Web console is responding"
    else
        print_warning "Web console may not be responding on port 5000"
    fi
fi

# Install Ban Enforcer (optional but recommended)
print_header "Step 7: Install Ban Enforcer (Optional)"

echo -e "${CYAN}Ban Enforcer blocks banned devices from connecting to RustDesk.${NC}"
echo -e "${CYAN}RustDesk server doesn't check is_banned column by default.${NC}"
echo ""
echo -e "Without enforcer: Devices show as banned in UI but can still connect"
echo -e "With enforcer:    Devices are actively blocked from connecting"
echo ""

if [ -f "$CONSOLE_DIR/ban_enforcer.py" ] && systemctl is-active --quiet rustdesk-ban-enforcer 2>/dev/null; then
    print_info "Ban Enforcer is already installed and running"
    read -p "Do you want to update it? (y/N): " UPDATE_ENFORCER
    if [[ "$UPDATE_ENFORCER" =~ ^[Yy]$ ]]; then
        print_info "Updating Ban Enforcer..."
        cp ban_enforcer.py "$CONSOLE_DIR/"
        chmod +x "$CONSOLE_DIR/ban_enforcer.py"
        systemctl restart rustdesk-ban-enforcer
        print_success "Ban Enforcer updated"
    fi
else
    read -p "Install Ban Enforcer? (y/N): " INSTALL_ENFORCER
    
    if [[ "$INSTALL_ENFORCER" =~ ^[Yy]$ ]]; then
        if [ -f "ban_enforcer.py" ] && [ -f "rustdesk-ban-enforcer.service" ]; then
            print_info "Installing Ban Enforcer..."
            
            # Copy files
            cp ban_enforcer.py "$CONSOLE_DIR/"
            chmod +x "$CONSOLE_DIR/ban_enforcer.py"
            
            # Configure and install service
            sed "s|Environment=\"DB_PATH=/opt/rustdesk/db_v2.sqlite3\"|Environment=\"DB_PATH=$DB_PATH\"|g" \
                rustdesk-ban-enforcer.service > /tmp/rustdesk-ban-enforcer.service
            cp /tmp/rustdesk-ban-enforcer.service /etc/systemd/system/
            chmod 644 /etc/systemd/system/rustdesk-ban-enforcer.service
            rm /tmp/rustdesk-ban-enforcer.service
            
            # Enable and start
            systemctl daemon-reload
            systemctl enable rustdesk-ban-enforcer
            systemctl start rustdesk-ban-enforcer
            
            sleep 2
            if systemctl is-active --quiet rustdesk-ban-enforcer; then
                print_success "Ban Enforcer installed and running"
            else
                print_warning "Ban Enforcer installed but failed to start"
                echo "Check logs: sudo journalctl -u rustdesk-ban-enforcer -n 50"
            fi
        else
            print_warning "Ban Enforcer files not found in current directory"
            print_info "You can install it later using: ./install_ban_enforcer.sh"
        fi
    else
        print_info "Ban Enforcer installation skipped"
        print_warning "Banned devices will show in UI but may still connect"
        echo ""
        echo "To install later, run:"
        echo "  sudo ./install_ban_enforcer.sh"
        echo ""
        echo "Or manually:"
        echo "  sudo cp ban_enforcer.py $CONSOLE_DIR/"
        echo "  sudo cp rustdesk-ban-enforcer.service /etc/systemd/system/"
        echo "  sudo systemctl daemon-reload"
        echo "  sudo systemctl enable --now rustdesk-ban-enforcer"
    fi
fi

# Final summary
print_header "Update Complete!"

echo -e "${GREEN}✓ Database migrated to v1.1.0${NC}"
echo -e "${GREEN}✓ Web console files updated${NC}"
echo -e "${GREEN}✓ Backup created: $BACKUP_DIR${NC}"
if [ "$SERVICE_EXISTS" = true ]; then
    echo -e "${GREEN}✓ Service restarted${NC}"
fi
if systemctl is-active --quiet rustdesk-ban-enforcer 2>/dev/null; then
    echo -e "${GREEN}✓ Ban Enforcer active${NC}"
fi
echo ""
echo -e "${CYAN}New Features:${NC}"
echo "  • Soft delete for devices (is_deleted, deleted_at, updated_at)"
echo "  • Device banning system (is_banned, banned_at, banned_by, ban_reason)"
echo "  • Ban/Unban buttons in web interface"
echo "  • Enhanced input validation and security"
echo "  • Banned devices statistics card"
if systemctl is-active --quiet rustdesk-ban-enforcer 2>/dev/null; then
    echo "  • Active connection blocking for banned devices ✓"
fi
echo ""
echo -e "${CYAN}Access the console:${NC}"
echo "  http://localhost:5000"
echo ""
if systemctl is-active --quiet rustdesk-ban-enforcer 2>/dev/null; then
    echo -e "${CYAN}Ban Enforcer Status:${NC}"
    echo "  Service: $(systemctl is-active rustdesk-ban-enforcer)"
    echo "  Logs:    sudo journalctl -u rustdesk-ban-enforcer -f"
    echo ""
fi
echo -e "${YELLOW}Rollback Instructions (if needed):${NC}"
echo "  1. Stop service: sudo systemctl stop betterdesk"
echo "  2. Restore database: sudo cp $BACKUP_DIR/db_v2.sqlite3.backup $DB_PATH"
echo "  3. Restore files: sudo cp $BACKUP_DIR/*.backup $CONSOLE_DIR/"
echo "  4. Start service: sudo systemctl start betterdesk"
echo ""
print_success "Update completed successfully!"
