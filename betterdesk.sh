#!/bin/bash
#===============================================================================
#
#   BetterDesk Console Manager v2.0
#   All-in-One Interactive Tool for Linux
#
#   Features:
#     - Fresh installation
#     - Update existing installation  
#     - Repair/fix issues
#     - Validate installation
#     - Backup & restore
#     - Reset admin password
#     - Build custom binaries
#     - Full diagnostics
#
#   Usage: sudo ./betterdesk.sh
#
#===============================================================================

set -e

# Version
VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default paths (can be overridden by environment variables)
RUSTDESK_PATH="${RUSTDESK_PATH:-}"
CONSOLE_PATH="${CONSOLE_PATH:-}"
BACKUP_DIR="${BACKUP_DIR:-/opt/rustdesk-backups}"

# Common installation paths to search
COMMON_RUSTDESK_PATHS=(
    "/opt/rustdesk"
    "/usr/local/rustdesk"
    "/var/lib/rustdesk"
    "/home/rustdesk"
    "$HOME/rustdesk"
)

COMMON_CONSOLE_PATHS=(
    "/opt/BetterDeskConsole"
    "/opt/betterdesk"
    "/var/lib/betterdesk"
    "$HOME/BetterDeskConsole"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Logging
LOG_FILE="/tmp/betterdesk_$(date +%Y%m%d_%H%M%S).log"

#===============================================================================
# Helper Functions
#===============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

print_header() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                  ║"
    echo "║   ██████╗ ███████╗████████╗████████╗███████╗██████╗              ║"
    echo "║   ██╔══██╗██╔════╝╚══██╔══╝╚══██╔══╝██╔════╝██╔══██╗             ║"
    echo "║   ██████╔╝█████╗     ██║      ██║   █████╗  ██████╔╝             ║"
    echo "║   ██╔══██╗██╔══╝     ██║      ██║   ██╔══╝  ██╔══██╗             ║"
    echo "║   ██████╔╝███████╗   ██║      ██║   ███████╗██║  ██║             ║"
    echo "║   ╚═════╝ ╚══════╝   ╚═╝      ╚═╝   ╚══════╝╚═╝  ╚═╝             ║"
    echo "║                    ██████╗ ███████╗███████╗██╗  ██╗              ║"
    echo "║                    ██╔══██╗██╔════╝██╔════╝██║ ██╔╝              ║"
    echo "║                    ██║  ██║█████╗  ███████╗█████╔╝               ║"
    echo "║                    ██║  ██║██╔══╝  ╚════██║██╔═██╗               ║"
    echo "║                    ██████╔╝███████╗███████║██║  ██╗              ║"
    echo "║                    ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝              ║"
    echo "║                                                                  ║"
    echo "║                  Console Manager v${VERSION}                          ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() { echo -e "${GREEN}✓${NC} $1"; log "SUCCESS: $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; log "ERROR: $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; log "WARNING: $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; log "INFO: $1"; }
print_step() { echo -e "${MAGENTA}▶${NC} $1"; log "STEP: $1"; }

press_enter() {
    echo ""
    echo -e "${CYAN}Press Enter to continue...${NC}"
    read -r
}

confirm() {
    local prompt="${1:-Continue?}"
    echo -e "${YELLOW}${prompt} [y/N]${NC} "
    read -r response
    [[ "$response" =~ ^[TtYy]$ ]]
}

#===============================================================================
# Detection Functions
#===============================================================================

detect_installation() {
    INSTALL_STATUS="none"
    HBBS_RUNNING=false
    HBBR_RUNNING=false
    CONSOLE_RUNNING=false
    BINARIES_OK=false
    DATABASE_OK=false
    
    # Check paths
    if [ -d "$RUSTDESK_PATH" ]; then
        INSTALL_STATUS="partial"
        
        # Check binaries
        if [ -f "$RUSTDESK_PATH/hbbs" ] || [ -f "$RUSTDESK_PATH/hbbs-v8-api" ]; then
            BINARIES_OK=true
        fi
        
        # Check database
        if [ -f "$DB_PATH" ]; then
            DATABASE_OK=true
        fi
    fi
    
    if [ -d "$CONSOLE_PATH" ] && [ -f "$CONSOLE_PATH/app.py" ]; then
        if [ "$BINARIES_OK" = true ] && [ "$DATABASE_OK" = true ]; then
            INSTALL_STATUS="complete"
        fi
    fi
    
    # Check services
    if systemctl is-active --quiet rustdesksignal 2>/dev/null || \
       systemctl is-active --quiet hbbs 2>/dev/null; then
        HBBS_RUNNING=true
    fi
    
    if systemctl is-active --quiet rustdeskrelay 2>/dev/null || \
       systemctl is-active --quiet hbbr 2>/dev/null; then
        HBBR_RUNNING=true
    fi
    
    if systemctl is-active --quiet betterdesk 2>/dev/null; then
        CONSOLE_RUNNING=true
    fi
}

detect_architecture() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) ARCH_NAME="x86_64" ;;
        aarch64|arm64) ARCH_NAME="aarch64" ;;
        armv7l) ARCH_NAME="armv7" ;;
        *) ARCH_NAME="unknown" ;;
    esac
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME="$NAME"
        OS_VERSION="$VERSION_ID"
    else
        OS_NAME="Unknown"
        OS_VERSION=""
    fi
}

# Auto-detect RustDesk installation path
auto_detect_paths() {
    local found=false
    
    # If RUSTDESK_PATH is already set (via env var), validate it
    if [ -n "$RUSTDESK_PATH" ]; then
        if [ -d "$RUSTDESK_PATH" ] && { [ -f "$RUSTDESK_PATH/hbbs" ] || [ -f "$RUSTDESK_PATH/hbbs-v8-api" ]; }; then
            print_info "Using configured RustDesk path: $RUSTDESK_PATH"
            found=true
        else
            print_warning "Configured RUSTDESK_PATH ($RUSTDESK_PATH) is invalid"
            RUSTDESK_PATH=""
        fi
    fi
    
    # Auto-detect if not found
    if [ -z "$RUSTDESK_PATH" ]; then
        for path in "${COMMON_RUSTDESK_PATHS[@]}"; do
            if [ -d "$path" ] && { [ -f "$path/hbbs" ] || [ -f "$path/hbbs-v8-api" ]; }; then
                RUSTDESK_PATH="$path"
                print_success "Detected RustDesk installation: $RUSTDESK_PATH"
                found=true
                break
            fi
        done
    fi
    
    # If still not found, use default for new installations
    if [ -z "$RUSTDESK_PATH" ]; then
        RUSTDESK_PATH="/opt/rustdesk"
        print_info "No installation detected. Default path: $RUSTDESK_PATH"
    fi
    
    # Auto-detect Console path
    if [ -n "$CONSOLE_PATH" ]; then
        if [ -d "$CONSOLE_PATH" ] && [ -f "$CONSOLE_PATH/app.py" ]; then
            print_info "Using configured Console path: $CONSOLE_PATH"
        else
            print_warning "Configured CONSOLE_PATH ($CONSOLE_PATH) is invalid"
            CONSOLE_PATH=""
        fi
    fi
    
    if [ -z "$CONSOLE_PATH" ]; then
        for path in "${COMMON_CONSOLE_PATHS[@]}"; do
            if [ -d "$path" ] && [ -f "$path/app.py" ]; then
                CONSOLE_PATH="$path"
                print_success "Detected Console installation: $CONSOLE_PATH"
                break
            fi
        done
    fi
    
    # Default Console path if not found
    if [ -z "$CONSOLE_PATH" ]; then
        CONSOLE_PATH="/opt/BetterDeskConsole"
    fi
    
    # Update DB_PATH based on detected RUSTDESK_PATH
    DB_PATH="$RUSTDESK_PATH/db_v2.sqlite3"
    
    return 0
}

# Interactive path configuration
configure_paths() {
    clear
    print_header
    echo ""
    echo -e "${WHITE}${BOLD}═══ Path Configuration ═══${NC}"
    echo ""
    echo -e "  Current RustDesk path: ${CYAN}${RUSTDESK_PATH:-Not set}${NC}"
    echo -e "  Current Console path:  ${CYAN}${CONSOLE_PATH:-Not set}${NC}"
    echo -e "  Database path:         ${CYAN}${DB_PATH:-Not set}${NC}"
    echo ""
    
    echo -e "${YELLOW}Options:${NC}"
    echo "  1. Auto-detect installation paths"
    echo "  2. Set RustDesk server path manually"
    echo "  3. Set Console path manually"
    echo "  4. Reset to defaults"
    echo "  0. Back to main menu"
    echo ""
    echo -n "Select option [0-4]: "
    read -r choice
    
    case $choice in
        1)
            RUSTDESK_PATH=""
            CONSOLE_PATH=""
            auto_detect_paths
            press_enter
            configure_paths
            ;;
        2)
            echo ""
            echo -n "Enter RustDesk server path (e.g., /opt/rustdesk): "
            read -r new_path
            if [ -n "$new_path" ]; then
                if [ -d "$new_path" ]; then
                    RUSTDESK_PATH="$new_path"
                    DB_PATH="$RUSTDESK_PATH/db_v2.sqlite3"
                    print_success "RustDesk path set to: $RUSTDESK_PATH"
                else
                    print_warning "Directory does not exist: $new_path"
                    if confirm "Create this directory?"; then
                        mkdir -p "$new_path"
                        RUSTDESK_PATH="$new_path"
                        DB_PATH="$RUSTDESK_PATH/db_v2.sqlite3"
                        print_success "Created and set RustDesk path: $RUSTDESK_PATH"
                    fi
                fi
            fi
            press_enter
            configure_paths
            ;;
        3)
            echo ""
            echo -n "Enter Console path (e.g., /opt/BetterDeskConsole): "
            read -r new_path
            if [ -n "$new_path" ]; then
                if [ -d "$new_path" ]; then
                    CONSOLE_PATH="$new_path"
                    print_success "Console path set to: $CONSOLE_PATH"
                else
                    print_warning "Directory does not exist: $new_path"
                    if confirm "Create this directory?"; then
                        mkdir -p "$new_path"
                        CONSOLE_PATH="$new_path"
                        print_success "Created and set Console path: $CONSOLE_PATH"
                    fi
                fi
            fi
            press_enter
            configure_paths
            ;;
        4)
            RUSTDESK_PATH="/opt/rustdesk"
            CONSOLE_PATH="/opt/BetterDeskConsole"
            DB_PATH="$RUSTDESK_PATH/db_v2.sqlite3"
            print_success "Paths reset to defaults"
            press_enter
            configure_paths
            ;;
        0|"")
            return
            ;;
        *)
            print_error "Invalid option"
            press_enter
            configure_paths
            ;;
    esac
}

print_status() {
    detect_installation
    detect_architecture
    detect_os
    
    echo ""
    echo -e "${WHITE}${BOLD}═══ System Status ═══${NC}"
    echo ""
    echo -e "  System:       ${CYAN}$OS_NAME $OS_VERSION${NC}"
    echo -e "  Architecture: ${CYAN}$ARCH_NAME${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}═══ Configured Paths ═══${NC}"
    echo ""
    echo -e "  RustDesk:     ${CYAN}$RUSTDESK_PATH${NC}"
    echo -e "  Console:      ${CYAN}$CONSOLE_PATH${NC}"
    echo -e "  Database:     ${CYAN}$DB_PATH${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}═══ Installation Status ═══${NC}"
    echo ""
    
    # Installation status
    case "$INSTALL_STATUS" in
        "complete")
            echo -e "  Status:       ${GREEN}✓ Installed${NC}"
            ;;
        "partial")
            echo -e "  Status:       ${YELLOW}! Partial installation${NC}"
            ;;
        "none")
            echo -e "  Status:       ${RED}✗ Not installed${NC}"
            ;;
    esac
    
    # Components
    if [ "$BINARIES_OK" = true ]; then
        echo -e "  Binaries:      ${GREEN}✓ OK${NC}"
    else
        echo -e "  Binaries:      ${RED}✗ Not found${NC}"
    fi
    
    if [ "$DATABASE_OK" = true ]; then
        echo -e "  Database:  ${GREEN}✓ OK${NC}"
    else
        echo -e "  Database:  ${RED}✗ Not found${NC}"
    fi
    
    if [ -d "$CONSOLE_PATH" ]; then
        echo -e "  Web Console:  ${GREEN}✓ OK${NC}"
    else
        echo -e "  Web Console:  ${RED}✗ Not found${NC}"
    fi
    
    echo ""
    echo -e "${WHITE}${BOLD}═══ Services Status ═══${NC}"
    echo ""
    
    if [ "$HBBS_RUNNING" = true ]; then
        echo -e "  HBBS (Signal): ${GREEN}● Active${NC}"
    else
        echo -e "  HBBS (Signal): ${RED}○ Inactive${NC}"
    fi
    
    if [ "$HBBR_RUNNING" = true ]; then
        echo -e "  HBBR (Relay):  ${GREEN}● Active${NC}"
    else
        echo -e "  HBBR (Relay):  ${RED}○ Inactive${NC}"
    fi
    
    if [ "$CONSOLE_RUNNING" = true ]; then
        echo -e "  Web Console:   ${GREEN}● Active${NC}"
    else
        echo -e "  Web Console:   ${RED}○ Inactive${NC}"
    fi
    
    echo ""
}

#===============================================================================
# Installation Functions
#===============================================================================

install_dependencies() {
    print_step "Installing dependencies..."
    
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq python3 python3-pip python3-venv sqlite3 curl wget openssl
    elif command -v dnf &> /dev/null; then
        dnf install -y -q python3 python3-pip sqlite curl wget openssl
    elif command -v yum &> /dev/null; then
        yum install -y -q python3 python3-pip sqlite curl wget openssl
    elif command -v pacman &> /dev/null; then
        pacman -Sy --noconfirm python python-pip sqlite curl wget openssl
    else
        print_warning "Unknown package manager. Make sure Python 3 and SQLite are installed."
    fi
    
    print_success "Dependencies installed"
}

install_binaries() {
    print_step "Installing BetterDesk binaries..."
    
    mkdir -p "$RUSTDESK_PATH"
    
    # Check for pre-compiled binaries
    local bin_source=""
    
    if [ -f "$SCRIPT_DIR/hbbs-patch-v2/hbbs-linux-$ARCH_NAME" ]; then
        bin_source="$SCRIPT_DIR/hbbs-patch-v2"
        print_info "Found binaries in hbbs-patch-v2/"
    elif [ -f "$SCRIPT_DIR/server/binaries/linux/hbbs" ]; then
        bin_source="$SCRIPT_DIR/server/binaries/linux"
        print_info "Found binaries in server/binaries/linux/"
    else
        print_error "BetterDesk binaries not found!"
        print_info "Run 'Build binaries' option or download prebuilt files."
        return 1
    fi
    
    # Copy binaries
    if [ -f "$bin_source/hbbs-linux-$ARCH_NAME" ]; then
        cp "$bin_source/hbbs-linux-$ARCH_NAME" "$RUSTDESK_PATH/hbbs"
    elif [ -f "$bin_source/hbbs" ]; then
        cp "$bin_source/hbbs" "$RUSTDESK_PATH/hbbs"
    fi
    
    if [ -f "$bin_source/hbbr-linux-$ARCH_NAME" ]; then
        cp "$bin_source/hbbr-linux-$ARCH_NAME" "$RUSTDESK_PATH/hbbr"
    elif [ -f "$bin_source/hbbr" ]; then
        cp "$bin_source/hbbr" "$RUSTDESK_PATH/hbbr"
    fi
    
    chmod +x "$RUSTDESK_PATH/hbbs" "$RUSTDESK_PATH/hbbr"
    
    print_success "Binaries installed"
}

install_console() {
    print_step "Installing Web Console..."
    
    mkdir -p "$CONSOLE_PATH"
    
    # Copy web files
    if [ -d "$SCRIPT_DIR/web" ]; then
        cp -r "$SCRIPT_DIR/web/"* "$CONSOLE_PATH/"
    else
        print_error "web/ folder not found in project!"
        return 1
    fi
    
    # Setup Python environment
    print_step "Configuring Python environment..."
    
    cd "$CONSOLE_PATH"
    python3 -m venv venv 2>/dev/null || python3 -m virtualenv venv
    source venv/bin/activate
    
    pip install --quiet --upgrade pip
    pip install --quiet -r requirements.txt
    
    deactivate
    
    print_success "Web Console installed"
}

setup_services() {
    print_step "Configuring systemd services..."
    
    # Get server IP
    local server_ip
    server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "127.0.0.1")
    
    # HBBS service
    cat > /etc/systemd/system/rustdesksignal.service << EOF
[Unit]
Description=BetterDesk Signal Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$RUSTDESK_PATH
ExecStart=$RUSTDESK_PATH/hbbs -r $server_ip -k _ --api-port 21114
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # HBBR service  
    cat > /etc/systemd/system/rustdeskrelay.service << EOF
[Unit]
Description=BetterDesk Relay Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$RUSTDESK_PATH
ExecStart=$RUSTDESK_PATH/hbbr -k _
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Console service
    cat > /etc/systemd/system/betterdesk.service << EOF
[Unit]
Description=BetterDesk Web Console
After=network.target

[Service]
Type=simple
WorkingDirectory=$CONSOLE_PATH
ExecStart=$CONSOLE_PATH/venv/bin/python app.py
Environment=FLASK_ENV=production
Environment=RUSTDESK_PATH=$RUSTDESK_PATH
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    
    print_success "Services configured"
}

run_migrations() {
    print_step "Running database migrations..."
    
    if [ -d "$SCRIPT_DIR/migrations" ]; then
        cd "$SCRIPT_DIR/migrations"
        for migration in v*.py; do
            if [ -f "$migration" ]; then
                print_info "Migration: $migration"
                python3 "$migration" "$DB_PATH" 2>/dev/null || true
            fi
        done
    fi
    
    print_success "Migrations completed"
}

create_admin_user() {
    print_step "Creating admin user..."
    
    local admin_password
    admin_password=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
    
    # Create admin via Python
    python3 << EOF
import sqlite3
import bcrypt
from datetime import datetime

conn = sqlite3.connect('$DB_PATH')
cursor = conn.cursor()

# Check if users table exists
cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='users'")
if not cursor.fetchone():
    cursor.execute('''CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        role TEXT DEFAULT 'viewer',
        is_active INTEGER DEFAULT 1,
        created_at TEXT,
        last_login TEXT
    )''')

# Check if admin exists
cursor.execute("SELECT id FROM users WHERE username='admin'")
if cursor.fetchone():
    print("Admin already exists")
else:
    password_hash = bcrypt.hashpw('$admin_password'.encode(), bcrypt.gensalt()).decode()
    cursor.execute('''INSERT INTO users (username, password_hash, role, is_active, created_at)
                      VALUES ('admin', ?, 'admin', 1, ?)''', (password_hash, datetime.now().isoformat()))
    conn.commit()
    print("Admin created")

conn.close()
EOF

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            PANEL LOGIN CREDENTIALS                    ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  Login:    ${WHITE}admin${GREEN}                                     ║${NC}"
    echo -e "${GREEN}║  Password:    ${WHITE}${admin_password}${GREEN}                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Save credentials
    echo "admin:$admin_password" > "$RUSTDESK_PATH/.admin_credentials"
    chmod 600 "$RUSTDESK_PATH/.admin_credentials"
    
    print_info "Credentials saved in: $RUSTDESK_PATH/.admin_credentials"
}

start_services() {
    print_step "Starting services..."
    
    systemctl enable rustdesksignal rustdeskrelay betterdesk 2>/dev/null
    systemctl start rustdesksignal rustdeskrelay betterdesk
    
    sleep 2
    
    if systemctl is-active --quiet rustdesksignal && \
       systemctl is-active --quiet rustdeskrelay && \
       systemctl is-active --quiet betterdesk; then
        print_success "All services started"
    else
        print_warning "Some services may not be working properly"
    fi
}

do_install() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ FRESH INSTALLATION ══════════${NC}"
    echo ""
    
    detect_installation
    
    if [ "$INSTALL_STATUS" = "complete" ]; then
        print_warning "BetterDesk is already installed!"
        if ! confirm "Do you want to reinstall?"; then
            return
        fi
        do_backup
    fi
    
    echo ""
    print_info "Starting BetterDesk Console installation..."
    echo ""
    
    install_dependencies
    detect_architecture
    install_binaries
    install_console
    setup_services
    run_migrations
    create_admin_user
    start_services
    
    echo ""
    print_success "Installation completed successfully!"
    echo ""
    
    local server_ip
    server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_IP")
    local public_key=""
    if [ -f "$RUSTDESK_PATH/id_ed25519.pub" ]; then
        public_key=$(cat "$RUSTDESK_PATH/id_ed25519.pub")
    fi
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              INSTALLATION INFO                       ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  Panel Web:     ${WHITE}http://$server_ip:5000${CYAN}                   ║${NC}"
    echo -e "${CYAN}║  Server ID:     ${WHITE}$server_ip${CYAN}                              ║${NC}"
    echo -e "${CYAN}║  Key:         ${WHITE}${public_key:0:20}...${CYAN}                    ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    
    press_enter
}

#===============================================================================
# Update Functions
#===============================================================================

do_update() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ UPDATE ══════════${NC}"
    echo ""
    
    detect_installation
    
    if [ "$INSTALL_STATUS" = "none" ]; then
        print_error "BetterDesk is not installed!"
        print_info "Use 'FRESH INSTALLATION' option"
        press_enter
        return
    fi
    
    print_info "Creating backup before update..."
    do_backup_silent
    
    print_step "Stopping services..."
    systemctl stop rustdesksignal rustdeskrelay betterdesk 2>/dev/null || true
    
    detect_architecture
    install_binaries
    install_console
    run_migrations
    
    print_step "Starting services..."
    systemctl start rustdesksignal rustdeskrelay betterdesk
    
    print_success "Update completed!"
    press_enter
}

#===============================================================================
# Repair Functions
#===============================================================================

do_repair() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ REPAIR INSTALLATION ══════════${NC}"
    echo ""
    
    detect_installation
    print_status
    
    echo ""
    echo -e "${WHITE}What do you want to repair?${NC}"
    echo ""
    echo "  1. 🔧 Repair binaries (replace with BetterDesk)"
    echo "  2. 🗃️  Repair database (add missing columns)"
    echo "  3. ⚙️  Repair systemd services"
    echo "  4. 🔐 Repair file permissions"
    echo "  5. 🔄 Full repair (all of the above)"
    echo "  0. ↩️  Back"
    echo ""
    
    read -p "Select option: " repair_choice
    
    case $repair_choice in
        1) repair_binaries ;;
        2) repair_database ;;
        3) repair_services ;;
        4) repair_permissions ;;
        5) 
            repair_binaries
            repair_database
            repair_services
            repair_permissions
            print_success "Full repair completed!"
            ;;
        0) return ;;
    esac
    
    press_enter
}

repair_binaries() {
    print_step "Repair binaries..."
    
    systemctl stop rustdesksignal rustdeskrelay 2>/dev/null || true
    
    detect_architecture
    install_binaries
    
    systemctl start rustdesksignal rustdeskrelay 2>/dev/null || true
    
    print_success "Binaries repaired"
}

repair_database() {
    print_step "Repair database..."
    
    if [ ! -f "$DB_PATH" ]; then
        print_warning "Database does not exist, creating new one..."
        touch "$DB_PATH"
    fi
    
    # Add missing columns
    python3 << EOF
import sqlite3

conn = sqlite3.connect('$DB_PATH')
cursor = conn.cursor()

# Ensure peer table has required columns
columns_to_add = [
    ('status', 'INTEGER DEFAULT 0'),
    ('last_online', 'TEXT'),
    ('is_deleted', 'INTEGER DEFAULT 0'),
    ('deleted_at', 'TEXT'),
    ('updated_at', 'TEXT'),
    ('note', 'TEXT'),
    ('previous_ids', 'TEXT'),
    ('id_changed_at', 'TEXT'),
]

cursor.execute("PRAGMA table_info(peer)")
existing_columns = [col[1] for col in cursor.fetchall()]

for col_name, col_def in columns_to_add:
    if col_name not in existing_columns:
        try:
            cursor.execute(f"ALTER TABLE peer ADD COLUMN {col_name} {col_def}")
            print(f"  Added column: {col_name}")
        except Exception as e:
            pass

conn.commit()
conn.close()
print("Database repaired")
EOF

    print_success "Database repaired"
}

repair_services() {
    print_step "Repairing systemd services..."
    setup_services
    systemctl restart rustdesksignal rustdeskrelay betterdesk 2>/dev/null || true
    print_success "Services repaired"
}

repair_permissions() {
    print_step "Repairing permissions..."
    
    chown -R root:root "$RUSTDESK_PATH" 2>/dev/null || true
    chmod 755 "$RUSTDESK_PATH"
    chmod +x "$RUSTDESK_PATH/hbbs" "$RUSTDESK_PATH/hbbr" 2>/dev/null || true
    chmod 644 "$DB_PATH" 2>/dev/null || true
    
    print_success "Permissions repaired"
}

#===============================================================================
# Validation Functions
#===============================================================================

do_validate() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ INSTALLATION VALIDATION ══════════${NC}"
    echo ""
    
    local errors=0
    local warnings=0
    
    detect_installation
    detect_architecture
    
    echo -e "${WHITE}Checking components...${NC}"
    echo ""
    
    # Check directories
    echo -n "  RustDesk directory ($RUSTDESK_PATH): "
    if [ -d "$RUSTDESK_PATH" ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ Not found${NC}"
        ((errors++))
    fi
    
    echo -n "  Console directory ($CONSOLE_PATH): "
    if [ -d "$CONSOLE_PATH" ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ Not found${NC}"
        ((errors++))
    fi
    
    # Check binaries
    echo -n "  HBBS binary: "
    if [ -x "$RUSTDESK_PATH/hbbs" ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ Not found or missing permissions${NC}"
        ((errors++))
    fi
    
    echo -n "  HBBR binary: "
    if [ -x "$RUSTDESK_PATH/hbbr" ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ Not found or missing permissions${NC}"
        ((errors++))
    fi
    
    # Check database
    echo -n "  Database: "
    if [ -f "$DB_PATH" ]; then
        echo -e "${GREEN}✓${NC}"
        
        # Check tables
        echo -n "    - Table peer: "
        if sqlite3 "$DB_PATH" "SELECT 1 FROM peer LIMIT 1" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${YELLOW}! Empty or not found${NC}"
            ((warnings++))
        fi
        
        echo -n "    - Table users: "
        if sqlite3 "$DB_PATH" "SELECT 1 FROM users LIMIT 1" 2>/dev/null; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${YELLOW}! Empty or not found${NC}"
            ((warnings++))
        fi
    else
        echo -e "${RED}✗ Not found${NC}"
        ((errors++))
    fi
    
    # Check keys
    echo -n "  Public key: "
    if [ -f "$RUSTDESK_PATH/id_ed25519.pub" ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}! Will be generated on first start${NC}"
        ((warnings++))
    fi
    
    # Check services
    echo ""
    echo -e "${WHITE}Checking services...${NC}"
    echo ""
    
    for service in rustdesksignal rustdeskrelay betterdesk; do
        echo -n "  $service: "
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "${GREEN}● Active${NC}"
        elif systemctl is-enabled --quiet "$service" 2>/dev/null; then
            echo -e "${YELLOW}○ Enabled but inactive${NC}"
            ((warnings++))
        else
            echo -e "${RED}○ Disabled${NC}"
            ((errors++))
        fi
    done
    
    # Check ports
    echo ""
    echo -e "${WHITE}Checking ports...${NC}"
    echo ""
    
    for port in 21114 21115 21116 21117 5000; do
        echo -n "  Port $port: "
        if ss -tlnp 2>/dev/null | grep -q ":$port " || netstat -tlnp 2>/dev/null | grep -q ":$port "; then
            echo -e "${GREEN}● Listening${NC}"
        else
            echo -e "${YELLOW}○ Free${NC}"
            ((warnings++))
        fi
    done
    
    # Summary
    echo ""
    echo -e "${WHITE}═══════════════════════════════════════${NC}"
    
    if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
        echo -e "${GREEN}✓ Installation correct - no problems found${NC}"
    elif [ $errors -eq 0 ]; then
        echo -e "${YELLOW}! Found $warnings warnings${NC}"
    else
        echo -e "${RED}✗ Found $errors errors and $warnings warnings${NC}"
        echo ""
        echo -e "${CYAN}Use 'REPAIR INSTALLATION' option to fix problems${NC}"
    fi
    
    press_enter
}

#===============================================================================
# Backup Functions
#===============================================================================

do_backup() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ BACKUP ══════════${NC}"
    echo ""
    
    do_backup_silent
    
    print_success "Backup completed!"
    press_enter
}

do_backup_silent() {
    local backup_name="betterdesk_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$backup_path"
    
    print_step "Creating backup: $backup_name"
    
    # Backup database
    if [ -f "$DB_PATH" ]; then
        cp "$DB_PATH" "$backup_path/"
        print_info "  - Database"
    fi
    
    # Backup keys
    if [ -f "$RUSTDESK_PATH/id_ed25519" ]; then
        cp "$RUSTDESK_PATH/id_ed25519"* "$backup_path/"
        print_info "  - Keys"
    fi
    
    # Backup API key
    if [ -f "$RUSTDESK_PATH/.api_key" ]; then
        cp "$RUSTDESK_PATH/.api_key" "$backup_path/"
        print_info "  - API key"
    fi
    
    # Backup credentials
    if [ -f "$RUSTDESK_PATH/.admin_credentials" ]; then
        cp "$RUSTDESK_PATH/.admin_credentials" "$backup_path/"
        print_info "  - Login credentials"
    fi
    
    # Create archive
    cd "$BACKUP_DIR"
    tar -czf "$backup_name.tar.gz" "$backup_name"
    rm -rf "$backup_name"
    
    print_success "Backup saved: $BACKUP_DIR/$backup_name.tar.gz"
}

#===============================================================================
# Password Reset Functions
#===============================================================================

do_reset_password() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ ADMIN PASSWORD RESET ══════════${NC}"
    echo ""
    
    if [ ! -f "$DB_PATH" ]; then
        print_error "Database does not exist!"
        press_enter
        return
    fi
    
    echo "Select option:"
    echo ""
    echo "  1. Generate new random password"
    echo "  2. Set custom password"
    echo "  0. Back"
    echo ""
    
    read -p "Choice: " pw_choice
    
    local new_password
    
    case $pw_choice in
        1)
            new_password=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
            ;;
        2)
            echo ""
            read -sp "Enter new password (min. 8 characters): " new_password
            echo ""
            if [ ${#new_password} -lt 8 ]; then
                print_error "Password must be at least 8 characters!"
                press_enter
                return
            fi
            ;;
        0)
            return
            ;;
        *)
            return
            ;;
    esac
    
    # Update password
    python3 << EOF
import sqlite3
import bcrypt

conn = sqlite3.connect('$DB_PATH')
cursor = conn.cursor()

password_hash = bcrypt.hashpw('$new_password'.encode(), bcrypt.gensalt()).decode()
cursor.execute("UPDATE users SET password_hash = ? WHERE username = 'admin'", (password_hash,))

if cursor.rowcount == 0:
    cursor.execute('''INSERT INTO users (username, password_hash, role, is_active)
                      VALUES ('admin', ?, 'admin', 1)''', (password_hash,))

conn.commit()
conn.close()
EOF

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              NEW LOGIN CREDENTIALS                       ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  Login:    ${WHITE}admin${GREEN}                                     ║${NC}"
    echo -e "${GREEN}║  Password: ${WHITE}${new_password}${GREEN}                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    
    # Save credentials
    echo "admin:$new_password" > "$RUSTDESK_PATH/.admin_credentials"
    chmod 600 "$RUSTDESK_PATH/.admin_credentials"
    
    press_enter
}

#===============================================================================
# Build Functions
#===============================================================================

do_build() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ Build binaries ══════════${NC}"
    echo ""
    
    # Check Rust
    if ! command -v cargo &> /dev/null; then
        print_warning "Rust is not installed!"
        echo ""
        if confirm "Do you want to install Rust?"; then
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source "$HOME/.cargo/env"
        else
            press_enter
            return
        fi
    fi
    
    print_info "Rust: $(cargo --version)"
    echo ""
    
    local build_dir="/tmp/betterdesk_build_$$"
    mkdir -p "$build_dir"
    cd "$build_dir"
    
    print_step "Downloading RustDesk Server sources..."
    git clone --depth 1 --branch 1.1.14 https://github.com/rustdesk/rustdesk-server.git
    cd rustdesk-server
    git submodule update --init --recursive
    
    print_step "Applying BetterDesk modifications..."
    
    # Copy modified sources
    if [ -d "$SCRIPT_DIR/hbbs-patch-v2/src" ]; then
        cp "$SCRIPT_DIR/hbbs-patch-v2/src/main.rs" src/ 2>/dev/null || true
        cp "$SCRIPT_DIR/hbbs-patch-v2/src/http_api.rs" src/ 2>/dev/null || true
        cp "$SCRIPT_DIR/hbbs-patch-v2/src/database.rs" src/ 2>/dev/null || true
        cp "$SCRIPT_DIR/hbbs-patch-v2/src/peer.rs" src/ 2>/dev/null || true
        cp "$SCRIPT_DIR/hbbs-patch-v2/src/rendezvous_server.rs" src/ 2>/dev/null || true
    else
        print_error "Modified sources not found in hbbs-patch-v2/src/"
        press_enter
        return
    fi
    
    print_step "Compiling (may take several minutes)..."
    cargo build --release
    
    # Copy results
    print_step "Copying binaries..."
    
    detect_architecture
    mkdir -p "$SCRIPT_DIR/hbbs-patch-v2"
    
    cp target/release/hbbs "$SCRIPT_DIR/hbbs-patch-v2/hbbs-linux-$ARCH_NAME"
    cp target/release/hbbr "$SCRIPT_DIR/hbbs-patch-v2/hbbr-linux-$ARCH_NAME"
    
    # Cleanup
    cd /
    rm -rf "$build_dir"
    
    print_success "Compilation completed!"
    print_info "Binaries saved in: $SCRIPT_DIR/hbbs-patch-v2/"
    
    echo ""
    if confirm "Do you want to install the new binaries?"; then
        install_binaries
        systemctl restart rustdesksignal rustdeskrelay 2>/dev/null || true
    fi
    
    press_enter
}

#===============================================================================
# Diagnostics Functions
#===============================================================================

do_diagnostics() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ DIAGNOSTICS ══════════${NC}"
    echo ""
    
    print_status
    
    echo ""
    echo -e "${WHITE}${BOLD}═══ Service logs (last 10 lines) ═══${NC}"
    echo ""
    
    echo -e "${CYAN}--- rustdesksignal ---${NC}"
    journalctl -u rustdesksignal -n 10 --no-pager 2>/dev/null || echo "No logs found"
    
    echo ""
    echo -e "${CYAN}--- rustdeskrelay ---${NC}"
    journalctl -u rustdeskrelay -n 10 --no-pager 2>/dev/null || echo "No logs found"
    
    echo ""
    echo -e "${CYAN}--- betterdesk ---${NC}"
    journalctl -u betterdesk -n 10 --no-pager 2>/dev/null || echo "No logs found"
    
    echo ""
    echo -e "${WHITE}${BOLD}═══ Database statistics ═══${NC}"
    echo ""
    
    if [ -f "$DB_PATH" ]; then
        local device_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM peer WHERE is_deleted = 0" 2>/dev/null || echo "0")
        local online_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM peer WHERE status = 1 AND is_deleted = 0" 2>/dev/null || echo "0")
        local user_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users" 2>/dev/null || echo "0")
        
        echo "  Devices:           $device_count"
        echo "  Online:            $online_count"
        echo "  Users:             $user_count"
    else
        echo "  Database does not exist"
    fi
    
    echo ""
    echo -e "${WHITE}${BOLD}═══ Network connections ═══${NC}"
    echo ""
    
    ss -tlnp 2>/dev/null | grep -E "21114|21115|21116|21117|5000" || \
    netstat -tlnp 2>/dev/null | grep -E "21114|21115|21116|21117|5000" || \
    echo "  No active connections on RustDesk ports"
    
    echo ""
    echo -e "${CYAN}Diagnostics log saved: $LOG_FILE${NC}"
    
    press_enter
}

#===============================================================================
# Uninstall Functions
#===============================================================================

do_uninstall() {
    print_header
    echo -e "${RED}${BOLD}══════════ UNINSTALL ══════════${NC}"
    echo ""
    
    print_warning "This operation will remove BetterDesk Console!"
    echo ""
    
    if ! confirm "Are you sure you want to continue?"; then
        return
    fi
    
    if confirm "Create backup before uninstall?"; then
        do_backup_silent
    fi
    
    print_step "Stopping services..."
    systemctl stop rustdesksignal rustdeskrelay betterdesk 2>/dev/null || true
    systemctl disable rustdesksignal rustdeskrelay betterdesk 2>/dev/null || true
    
    print_step "Removing service files..."
    rm -f /etc/systemd/system/rustdesksignal.service
    rm -f /etc/systemd/system/rustdeskrelay.service
    rm -f /etc/systemd/system/betterdesk.service
    systemctl daemon-reload
    
    if confirm "Remove installation files ($RUSTDESK_PATH)?"; then
        rm -rf "$RUSTDESK_PATH"
        print_info "Removed: $RUSTDESK_PATH"
    fi
    
    if confirm "Remove Web Console ($CONSOLE_PATH)?"; then
        rm -rf "$CONSOLE_PATH"
        print_info "Removed: $CONSOLE_PATH"
    fi
    
    print_success "BetterDesk has been uninstalled"
    press_enter
}

#===============================================================================
# Main Menu
#===============================================================================

show_menu() {
    print_header
    print_status
    
    echo -e "${WHITE}${BOLD}══════════ MAIN MENU ══════════${NC}"
    echo ""
    echo "  1. 🚀 FRESH INSTALLATION"
    echo "  2. ⬆️  UPDATE"
    echo "  3. 🔧 REPAIR INSTALLATION"
    echo "  4. ✅ INSTALLATION VALIDATION"
    echo "  5. 💾 Backup"
    echo "  6. 🔐 Reset admin password"
    echo "  7. 🔨 Build binaries"
    echo "  8. 📊 DIAGNOSTICS"
    echo "  9. 🗑️  UNINSTALL"
    echo ""
    echo "  S. ⚙️  Settings (paths)"
    echo "  0. ❌ Exit"
    echo ""
}

main() {
    # Check root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}This script requires root privileges!${NC}"
        echo "Run: sudo $0"
        exit 1
    fi
    
    # Auto-detect paths on startup
    echo -e "${CYAN}Detecting installation...${NC}"
    auto_detect_paths
    echo ""
    sleep 1
    
    while true; do
        show_menu
        read -p "Select option: " choice
        
        case $choice in
            1) do_install ;;
            2) do_update ;;
            3) do_repair ;;
            4) do_validate ;;
            5) do_backup ;;
            6) do_reset_password ;;
            7) do_build ;;
            8) do_diagnostics ;;
            9) do_uninstall ;;
            [Ss]) configure_paths ;;
            0) 
                echo ""
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_warning "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Run
main "$@"
