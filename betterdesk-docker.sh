#!/bin/bash
#===============================================================================
#
#   BetterDesk Console Manager v2.1
#   All-in-One Interactive Tool for Docker
#
#   Features:
#     - Fresh installation with Docker Compose
#     - Update containers
#     - Repair/rebuild containers
#     - Validate installation
#     - Backup & restore volumes
#     - Reset admin password
#     - Build custom images
#     - Full diagnostics
#     - Migrate from existing RustDesk Docker
#
#   Usage: ./betterdesk-docker.sh
#
#===============================================================================

set -e

# Version
VERSION="2.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default paths (can be overridden by environment variables)
DATA_DIR="${DATA_DIR:-}"
BACKUP_DIR="${BACKUP_DIR:-/opt/betterdesk-backups}"
COMPOSE_FILE="${COMPOSE_FILE:-$SCRIPT_DIR/docker-compose.yml}"

# Common data directory paths to search
COMMON_DATA_PATHS=(
    "/opt/betterdesk-data"
    "/var/lib/betterdesk"
    "/opt/rustdesk-data"
    "/var/lib/rustdesk"
    "$HOME/betterdesk-data"
)

# Container names
HBBS_CONTAINER="betterdesk-hbbs"
HBBR_CONTAINER="betterdesk-hbbr"
CONSOLE_CONTAINER="betterdesk-console"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# Logging
LOG_FILE="/tmp/betterdesk_docker_$(date +%Y%m%d_%H%M%S).log"

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
    echo "║              Console Manager v${VERSION} (Docker)                     ║"
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

check_docker() {
    if ! command -v docker &> /dev/null; then
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        return 2
    fi
    
    return 0
}

check_docker_compose() {
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
        return 0
    elif docker-compose --version &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        return 0
    fi
    return 1
}

# Auto-detect data directory
auto_detect_docker_paths() {
    local found=false
    
    # If DATA_DIR is already set (via env var), validate it
    if [ -n "$DATA_DIR" ]; then
        if [ -d "$DATA_DIR" ] && [ -f "$DATA_DIR/db_v2.sqlite3" ]; then
            print_info "Using configured data path: $DATA_DIR"
            found=true
        else
            print_warning "Configured DATA_DIR ($DATA_DIR) is invalid or empty"
            DATA_DIR=""
        fi
    fi
    
    # Auto-detect if not found
    if [ -z "$DATA_DIR" ]; then
        for path in "${COMMON_DATA_PATHS[@]}"; do
            if [ -d "$path" ] && [ -f "$path/db_v2.sqlite3" ]; then
                DATA_DIR="$path"
                print_success "Detected data directory: $DATA_DIR"
                found=true
                break
            fi
        done
    fi
    
    # If still not found, use default for new installations
    if [ -z "$DATA_DIR" ]; then
        DATA_DIR="/opt/betterdesk-data"
        print_info "No data found. Default path: $DATA_DIR"
    fi
    
    # Check docker-compose.yml
    if [ -n "$COMPOSE_FILE" ] && [ -f "$COMPOSE_FILE" ]; then
        print_info "Using compose file: $COMPOSE_FILE"
    else
        # Try to find docker-compose.yml
        if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
            COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
        elif [ -f "./docker-compose.yml" ]; then
            COMPOSE_FILE="./docker-compose.yml"
        fi
    fi
    
    return 0
}

# Interactive path configuration for Docker
configure_docker_paths() {
    clear
    print_header
    echo ""
    echo -e "${WHITE}${BOLD}═══ Docker Path Configuration ═══${NC}"
    echo ""
    echo -e "  Data directory:     ${CYAN}${DATA_DIR:-Not set}${NC}"
    echo -e "  Backup directory:   ${CYAN}${BACKUP_DIR:-Not set}${NC}"
    echo -e "  Docker Compose file: ${CYAN}${COMPOSE_FILE:-Not set}${NC}"
    echo ""
    
    echo -e "${YELLOW}Options:${NC}"
    echo "  1. Auto-detect data directory"
    echo "  2. Set data directory manually"
    echo "  3. Set backup directory manually"
    echo "  4. Set docker-compose.yml path"
    echo "  5. Reset to defaults"
    echo "  0. Back to main menu"
    echo ""
    echo -n "Select option [0-5]: "
    read -r choice
    
    case $choice in
        1)
            DATA_DIR=""
            auto_detect_docker_paths
            press_enter
            configure_docker_paths
            ;;
        2)
            echo ""
            echo -n "Enter data directory path (e.g., /opt/betterdesk-data): "
            read -r new_path
            if [ -n "$new_path" ]; then
                if [ -d "$new_path" ]; then
                    DATA_DIR="$new_path"
                    print_success "Data directory set to: $DATA_DIR"
                else
                    print_warning "Directory does not exist: $new_path"
                    if confirm "Create this directory?"; then
                        mkdir -p "$new_path"
                        DATA_DIR="$new_path"
                        print_success "Created and set data directory: $DATA_DIR"
                    fi
                fi
            fi
            press_enter
            configure_docker_paths
            ;;
        3)
            echo ""
            echo -n "Enter backup directory path: "
            read -r new_path
            if [ -n "$new_path" ]; then
                if [ -d "$new_path" ]; then
                    BACKUP_DIR="$new_path"
                    print_success "Backup directory set to: $BACKUP_DIR"
                else
                    print_warning "Directory does not exist: $new_path"
                    if confirm "Create this directory?"; then
                        mkdir -p "$new_path"
                        BACKUP_DIR="$new_path"
                        print_success "Created and set backup directory: $BACKUP_DIR"
                    fi
                fi
            fi
            press_enter
            configure_docker_paths
            ;;
        4)
            echo ""
            echo -n "Enter docker-compose.yml path: "
            read -r new_path
            if [ -n "$new_path" ]; then
                if [ -f "$new_path" ]; then
                    COMPOSE_FILE="$new_path"
                    print_success "Compose file set to: $COMPOSE_FILE"
                else
                    print_error "File does not exist: $new_path"
                fi
            fi
            press_enter
            configure_docker_paths
            ;;
        5)
            DATA_DIR="/opt/betterdesk-data"
            BACKUP_DIR="/opt/betterdesk-backups"
            COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
            print_success "Paths reset to defaults"
            press_enter
            configure_docker_paths
            ;;
        0|"")
            return
            ;;
        *)
            print_error "Invalid option"
            press_enter
            configure_docker_paths
            ;;
    esac
}

detect_installation() {
    INSTALL_STATUS="none"
    HBBS_RUNNING=false
    HBBR_RUNNING=false
    CONSOLE_RUNNING=false
    IMAGES_BUILT=false
    DATA_EXISTS=false
    
    # Check if images exist
    if docker images | grep -q "betterdesk-hbbs\|betterdesk-hbbr\|betterdesk-console"; then
        IMAGES_BUILT=true
        INSTALL_STATUS="partial"
    fi
    
    # Check data directory
    if [ -d "$DATA_DIR" ] && [ -f "$DATA_DIR/db_v2.sqlite3" ]; then
        DATA_EXISTS=true
    fi
    
    # Check containers
    if docker ps --format '{{.Names}}' | grep -q "$HBBS_CONTAINER"; then
        HBBS_RUNNING=true
    fi
    
    if docker ps --format '{{.Names}}' | grep -q "$HBBR_CONTAINER"; then
        HBBR_RUNNING=true
    fi
    
    if docker ps --format '{{.Names}}' | grep -q "$CONSOLE_CONTAINER"; then
        CONSOLE_RUNNING=true
    fi
    
    if [ "$IMAGES_BUILT" = true ] && [ "$DATA_EXISTS" = true ] && \
       [ "$HBBS_RUNNING" = true ] && [ "$HBBR_RUNNING" = true ]; then
        INSTALL_STATUS="complete"
    fi
}

print_status() {
    detect_installation
    
    echo ""
    echo -e "${WHITE}${BOLD}═══ Status Docker ═══${NC}"
    echo ""
    
    # Docker status
    if check_docker; then
        echo -e "  Docker:         ${GREEN}✓ Installed and running${NC}"
    else
        echo -e "  Docker:         ${RED}✗ Not running${NC}"
    fi
    
    if check_docker_compose; then
        echo -e "  Docker Compose: ${GREEN}✓ Available${NC}"
    else
        echo -e "  Docker Compose: ${RED}✗ Not found${NC}"
    fi
    
    echo ""
    echo -e "${WHITE}${BOLD}═══ Image Status ═══${NC}"
    echo ""
    
    for image in "betterdesk-hbbs" "betterdesk-hbbr" "betterdesk-console"; do
        if docker images --format '{{.Repository}}' | grep -q "^$image$"; then
            local size=$(docker images --format '{{.Size}}' "$image:latest" 2>/dev/null)
            echo -e "  $image: ${GREEN}✓ Built${NC} ($size)"
        else
            echo -e "  $image: ${RED}✗ Not found${NC}"
        fi
    done
    
    echo ""
    echo -e "${WHITE}${BOLD}═══ Container Status ═══${NC}"
    echo ""
    
    if [ "$HBBS_RUNNING" = true ]; then
        echo -e "  HBBS (Signal):  ${GREEN}● Running${NC}"
    else
        echo -e "  HBBS (Signal):  ${RED}○ Stopped${NC}"
    fi
    
    if [ "$HBBR_RUNNING" = true ]; then
        echo -e "  HBBR (Relay):   ${GREEN}● Running${NC}"
    else
        echo -e "  HBBR (Relay):   ${RED}○ Stopped${NC}"
    fi
    
    if [ "$CONSOLE_RUNNING" = true ]; then
        echo -e "  Web Console:    ${GREEN}● Running${NC}"
    else
        echo -e "  Web Console:    ${RED}○ Stopped${NC}"
    fi
    
    echo ""
    echo -e "${WHITE}${BOLD}═══ Configured Paths ═══${NC}"
    echo ""
    echo -e "  Data directory:   ${CYAN}$DATA_DIR${NC}"
    echo -e "  Backup directory: ${CYAN}$BACKUP_DIR${NC}"
    echo -e "  Compose file:     ${CYAN}$COMPOSE_FILE${NC}"
    
    echo ""
    echo -e "${WHITE}${BOLD}═══ Data Status ═══${NC}"
    echo ""
    
    if [ "$DATA_EXISTS" = true ]; then
        echo -e "  Database: ${GREEN}✓ Found in $DATA_DIR${NC}"
    else
        echo -e "  Database: ${YELLOW}! Not found${NC}"
    fi
    
    echo ""
}

#===============================================================================
# Installation Functions
#===============================================================================

install_docker() {
    print_step "Installing Docker..."
    
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq docker.io docker-compose-plugin
    elif command -v dnf &> /dev/null; then
        dnf install -y -q docker docker-compose-plugin
    elif command -v yum &> /dev/null; then
        yum install -y -q docker docker-compose-plugin
    else
        print_error "Unsupported system. Install Docker manually."
        return 1
    fi
    
    systemctl enable docker
    systemctl start docker
    
    print_success "Docker installed"
}

create_compose_file() {
    print_step "Creating docker-compose.yml..."
    
    local server_ip
    server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "127.0.0.1")
    
    cat > "$COMPOSE_FILE" << EOF
version: '3.8'

services:
  hbbs:
    container_name: $HBBS_CONTAINER
    build:
      context: .
      dockerfile: Dockerfile.hbbs
    pull_policy: never
    ports:
      - "21120:21120"
      - "21115:21115"
      - "21116:21116"
      - "21116:21116/udp"
    volumes:
      - $DATA_DIR:/opt/rustdesk
    environment:
      - RELAY_SERVER=$server_ip
    restart: unless-stopped
    networks:
      - betterdesk

  hbbr:
    container_name: $HBBR_CONTAINER
    build:
      context: .
      dockerfile: Dockerfile.hbbr
    pull_policy: never
    ports:
      - "21117:21117"
    volumes:
      - $DATA_DIR:/opt/rustdesk
    restart: unless-stopped
    networks:
      - betterdesk

  console:
    container_name: $CONSOLE_CONTAINER
    build:
      context: .
      dockerfile: Dockerfile.console
    pull_policy: never
    ports:
      - "5000:5000"
    volumes:
      - $DATA_DIR:/opt/rustdesk
    environment:
      - RUSTDESK_PATH=/opt/rustdesk
      - DATABASE_PATH=/opt/rustdesk/db_v2.sqlite3
    depends_on:
      - hbbs
    restart: unless-stopped
    networks:
      - betterdesk

networks:
  betterdesk:
    driver: bridge
EOF

    print_success "docker-compose.yml created"
}

build_images() {
    print_step "Building Docker images..."
    
    cd "$SCRIPT_DIR"
    
    $COMPOSE_CMD build --no-cache
    
    print_success "Images built"
}

start_containers() {
    print_step "Starting containers..."
    
    cd "$SCRIPT_DIR"
    
    $COMPOSE_CMD up -d
    
    sleep 5
    
    detect_installation
    
    if [ "$HBBS_RUNNING" = true ] && [ "$HBBR_RUNNING" = true ] && [ "$CONSOLE_RUNNING" = true ]; then
        print_success "All containers running"
    else
        print_warning "Some containers might not be working properly"
    fi
}

stop_containers() {
    print_step "Stopping containers..."
    
    cd "$SCRIPT_DIR"
    
    $COMPOSE_CMD down 2>/dev/null || true
    
    print_success "Containers stopped"
}

create_admin_user() {
    print_step "Creating admin user..."
    
    local admin_password
    admin_password=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
    
    # Wait for database to be created
    sleep 3
    
    # Create admin via console container
    docker exec "$CONSOLE_CONTAINER" python3 << EOF
import sqlite3
import bcrypt
from datetime import datetime

db_path = '/opt/rustdesk/db_v2.sqlite3'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute('''CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT DEFAULT 'viewer',
    is_active INTEGER DEFAULT 1,
    created_at TEXT,
    last_login TEXT
)''')

cursor.execute("SELECT id FROM users WHERE username='admin'")
if not cursor.fetchone():
    password_hash = bcrypt.hashpw('$admin_password'.encode(), bcrypt.gensalt()).decode()
    cursor.execute('''INSERT INTO users (username, password_hash, role, is_active, created_at)
                      VALUES ('admin', ?, 'admin', 1, ?)''', (password_hash, datetime.now().isoformat()))
    conn.commit()

conn.close()
EOF

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║            PANEL LOGIN CREDENTIALS                     ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  Login:    ${WHITE}admin${GREEN}                                     ║${NC}"
    echo -e "${GREEN}║  Password: ${WHITE}${admin_password}${GREEN}                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Save credentials
    mkdir -p "$DATA_DIR"
    echo "admin:$admin_password" > "$DATA_DIR/.admin_credentials"
    chmod 600 "$DATA_DIR/.admin_credentials"
    
    print_info "Credentials saved in: $DATA_DIR/.admin_credentials"
}

do_install() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ FRESH DOCKER INSTALLATION ══════════${NC}"
    echo ""
    
    # Check Docker
    if ! check_docker; then
        print_warning "Docker is not installed or not running"
        if confirm "Do you want to install Docker?"; then
            install_docker
        else
            press_enter
            return
        fi
    fi
    
    if ! check_docker_compose; then
        print_error "Docker Compose is not available!"
        press_enter
        return
    fi
    
    detect_installation
    
    if [ "$INSTALL_STATUS" = "complete" ]; then
        print_warning "BetterDesk Docker is already installed!"
        if ! confirm "Do you want to reinstall?"; then
            return
        fi
        do_backup_silent
        stop_containers
    fi
    
    # Create data directory
    mkdir -p "$DATA_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Check for existing compose file or create new
    if [ ! -f "$COMPOSE_FILE" ]; then
        create_compose_file
    fi
    
    build_images
    start_containers
    create_admin_user
    
    echo ""
    print_success "Docker installation completed successfully!"
    echo ""
    
    local server_ip
    server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_IP")
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              Information about installation               ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  Web Panel:     ${WHITE}http://$server_ip:5000${CYAN}                   ║${NC}"
    echo -e "${CYAN}║  Server ID:     ${WHITE}$server_ip${CYAN}                              ║${NC}"
    echo -e "${CYAN}║  Data:          ${WHITE}$DATA_DIR${CYAN}                      ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    
    press_enter
}

#===============================================================================
# Update Functions
#===============================================================================

do_update() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ DOCKER UPDATE ══════════${NC}"
    echo ""
    
    detect_installation
    
    if [ "$INSTALL_STATUS" = "none" ]; then
        print_error "BetterDesk Docker is not installed!"
        print_info "Use 'Fresh Installation' option"
        press_enter
        return
    fi
    
    print_info "Creating backup before update..."
    do_backup_silent
    
    stop_containers
    build_images
    start_containers
    
    print_success "Update completed!"
    press_enter
}

#===============================================================================
# Repair Functions
#===============================================================================

do_repair() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ DOCKER REPAIR ══════════${NC}"
    echo ""
    
    detect_installation
    print_status
    
    echo ""
    echo -e "${WHITE}What do you want to repair?${NC}"
    echo ""
    echo "  1. 🔄 Rebuild images"
    echo "  2. 🔃 Restart containers"
    echo "  3. 🗃️  Repair database"
    echo "  4. 🧹 Clean Docker (images, volumes)"
    echo "  5. 🔄 Full repair (everything)"
    echo "  0. ↩️  Back"
    echo ""
    
    read -p "Select option: " repair_choice
    
    case $repair_choice in
        1) 
            stop_containers
            build_images
            start_containers
            ;;
        2)
            stop_containers
            start_containers
            ;;
        3)
            repair_database_docker
            ;;
        4)
            if confirm "Are you sure you want to clean up unused Docker resources?"; then
                docker system prune -f
                print_success "Docker cleaned"
            fi
            ;;
        5)
            stop_containers
            docker system prune -f
            build_images
            start_containers
            repair_database_docker
            print_success "Full repair completed!"
            ;;
        0) return ;;
    esac
    
    press_enter
}

repair_database_docker() {
    print_step "Repair database..."
    
    if [ ! -f "$DATA_DIR/db_v2.sqlite3" ]; then
        print_warning "Database does not exist"
        return
    fi
    
    docker exec "$CONSOLE_CONTAINER" python3 << 'EOF'
import sqlite3

conn = sqlite3.connect('/opt/rustdesk/db_v2.sqlite3')
cursor = conn.cursor()

columns_to_add = [
    ('status', 'INTEGER DEFAULT 0'),
    ('last_online', 'DATETIME DEFAULT NULL'),
    ('is_deleted', 'INTEGER DEFAULT 0'),
    ('deleted_at', 'DATETIME DEFAULT NULL'),
    ('updated_at', 'DATETIME DEFAULT NULL'),
    ('note', 'TEXT DEFAULT '''),
    ('previous_ids', 'TEXT DEFAULT '''),
    ('id_changed_at', 'TEXT'),
]

cursor.execute("PRAGMA table_info(peer)")
existing_columns = [col[1] for col in cursor.fetchall()]

for col_name, col_def in columns_to_add:
    if col_name not in existing_columns:
        try:
            cursor.execute(f"ALTER TABLE peer ADD COLUMN {col_name} {col_def}")
            print(f"  Added column: {col_name}")
        except:
            pass

conn.commit()
conn.close()
print("Database repaired")
EOF

    print_success "Database repaired"
}

#===============================================================================
# Validation Functions
#===============================================================================

do_validate() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ DOCKER VALIDATION ══════════${NC}"
    echo ""
    
    local errors=0
    local warnings=0
    
    # Check Docker
    echo -e "${WHITE}Checking Docker...${NC}"
    echo ""
    
    echo -n "  Docker daemon: "
    if check_docker; then
        echo -e "${GREEN}✓ Running${NC}"
    else
        echo -e "${RED}✗ Not running${NC}"
        ((errors++))
    fi
    
    echo -n "  Docker Compose: "
    if check_docker_compose; then
        echo -e "${GREEN}✓ Available${NC}"
    else
        echo -e "${RED}✗ Not found${NC}"
        ((errors++))
    fi
    
    # Check images
    echo ""
    echo -e "${WHITE}Checking images...${NC}"
    echo ""
    
    for image in "betterdesk-hbbs" "betterdesk-hbbr" "betterdesk-console"; do
        echo -n "  $image: "
        if docker images --format '{{.Repository}}' | grep -q "^$image$"; then
            echo -e "${GREEN}✓ Built${NC}"
        else
            echo -e "${RED}✗ Not found${NC}"
            ((errors++))
        fi
    done
    
    # Check containers
    echo ""
    echo -e "${WHITE}Checking containers...${NC}"
    echo ""
    
    detect_installation
    
    echo -n "  HBBS: "
    if [ "$HBBS_RUNNING" = true ]; then
        echo -e "${GREEN}● Running${NC}"
    else
        echo -e "${RED}○ Stopped${NC}"
        ((errors++))
    fi
    
    echo -n "  HBBR: "
    if [ "$HBBR_RUNNING" = true ]; then
        echo -e "${GREEN}● Running${NC}"
    else
        echo -e "${RED}○ Stopped${NC}"
        ((errors++))
    fi
    
    echo -n "  Console: "
    if [ "$CONSOLE_RUNNING" = true ]; then
        echo -e "${GREEN}● Running${NC}"
    else
        echo -e "${RED}○ Stopped${NC}"
        ((errors++))
    fi
    
    # Check data
    echo ""
    echo -e "${WHITE}Checking data...${NC}"
    echo ""
    
    echo -n "  Data directory: "
    if [ -d "$DATA_DIR" ]; then
        echo -e "${GREEN}✓ Exists${NC}"
    else
        echo -e "${RED}✗ Not found${NC}"
        ((errors++))
    fi
    
    echo -n "  Database: "
    if [ -f "$DATA_DIR/db_v2.sqlite3" ]; then
        echo -e "${GREEN}✓ Exists${NC}"
    else
        echo -e "${YELLOW}! Will be created on first start${NC}"
        ((warnings++))
    fi
    
    # Check ports
    echo ""
    echo -e "${WHITE}Checking ports...${NC}"
    echo ""
    
    for port in 21120 21115 21116 21117 5000; do
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
        echo -e "${CYAN}Use 'Repair' option to fix problems${NC}"
    fi
    
    press_enter
}

#===============================================================================
# Backup Functions
#===============================================================================

do_backup() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ DOCKER BACKUP ══════════${NC}"
    echo ""
    
    do_backup_silent
    
    print_success "Backup completed!"
    press_enter
}

do_backup_silent() {
    local backup_name="betterdesk_docker_backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$backup_path"
    
    print_step "Creating backup: $backup_name"
    
    # Backup data directory
    if [ -d "$DATA_DIR" ]; then
        cp -r "$DATA_DIR"/* "$backup_path/" 2>/dev/null || true
        print_info "  - Dane ($DATA_DIR)"
    fi
    
    # Backup compose file
    if [ -f "$COMPOSE_FILE" ]; then
        cp "$COMPOSE_FILE" "$backup_path/"
        print_info "  - docker-compose.yml"
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
    
    detect_installation
    
    if [ "$CONSOLE_RUNNING" != true ]; then
        print_error "Console container is not running!"
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
    docker exec "$CONSOLE_CONTAINER" python3 << EOF
import sqlite3
import bcrypt

conn = sqlite3.connect('/opt/rustdesk/db_v2.sqlite3')
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
    echo -e "${GREEN}║              NEW LOGIN CREDENTIALS                      ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║  Login:    ${WHITE}admin${GREEN}                                     ║${NC}"
    echo -e "${GREEN}║  Password: ${WHITE}${new_password}${GREEN}                         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    
    # Save credentials
    echo "admin:$new_password" > "$DATA_DIR/.admin_credentials"
    chmod 600 "$DATA_DIR/.admin_credentials"
    
    press_enter
}

#===============================================================================
# Build Functions
#===============================================================================

do_build() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ BUILD IMAGES ══════════${NC}"
    echo ""
    
    echo "Select option:"
    echo ""
    echo "  1. Rebuild all images"
    echo "  2. Rebuild only HBBS"
    echo "  3. Rebuild only HBBR"  
    echo "  4. Rebuild only Console"
    echo "  0. Back"
    echo ""
    
    read -p "Choice: " build_choice
    
    cd "$SCRIPT_DIR"
    
    case $build_choice in
        1)
            print_step "Building all images..."
            $COMPOSE_CMD build --no-cache
            ;;
        2)
            print_step "Building HBBS..."
            $COMPOSE_CMD build --no-cache hbbs
            ;;
        3)
            print_step "Building HBBR..."
            $COMPOSE_CMD build --no-cache hbbr
            ;;
        4)
            print_step "Building Console..."
            $COMPOSE_CMD build --no-cache console
            ;;
        0)
            return
            ;;
    esac
    
    print_success "Build completed!"
    
    if confirm "Do you want to restart containers?"; then
        stop_containers
        start_containers
    fi
    
    press_enter
}

#===============================================================================
# Diagnostics Functions
#===============================================================================

do_diagnostics() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ DOCKER DIAGNOSTICS ══════════${NC}"
    echo ""
    
    print_status
    
    echo ""
    echo -e "${WHITE}${BOLD}═══ Container logs (last 15 lines) ═══${NC}"
    echo ""
    
    for container in "$HBBS_CONTAINER" "$HBBR_CONTAINER" "$CONSOLE_CONTAINER"; do
        echo -e "${CYAN}--- $container ---${NC}"
        docker logs --tail 15 "$container" 2>&1 || echo "Container does not exist"
        echo ""
    done
    
    echo -e "${WHITE}${BOLD}═══ Resource usage ═══${NC}"
    echo ""
    
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | grep -E "NAME|betterdesk" || echo "No running containers found"
    
    echo ""
    echo -e "${WHITE}${BOLD}═══ Database statistics ═══${NC}"
    echo ""
    
    if [ "$CONSOLE_RUNNING" = true ]; then
        docker exec "$CONSOLE_CONTAINER" python3 << 'EOF'
import sqlite3
try:
    conn = sqlite3.connect('/opt/rustdesk/db_v2.sqlite3')
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM peer WHERE is_deleted = 0")
    devices = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM peer WHERE status = 1 AND is_deleted = 0")
    online = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM users")
    users = cursor.fetchone()[0]
    print(f"  Devices:           {devices}")
    print(f"  Online:            {online}")
    print(f"  Users:             {users}")
    conn.close()
except Exception as e:
    print(f"  Database read error: {e}")
EOF
    else
        echo "  Console container is not running"
    fi
    
    echo ""
    echo -e "${CYAN}Diagnostics log saved: $LOG_FILE${NC}"
    
    press_enter
}

#===============================================================================
# Uninstall Functions
#===============================================================================

do_uninstall() {
    print_header
    echo -e "${RED}${BOLD}══════════ UNINSTALL DOCKER ══════════${NC}"
    echo ""
    
    print_warning "This operation will remove BetterDesk Docker!"
    echo ""
    
    if ! confirm "Are you sure you want to continue?"; then
        return
    fi
    
    if confirm "Create backup before uninstall?"; then
        do_backup_silent
    fi
    
    print_step "Stopping containers..."
    cd "$SCRIPT_DIR"
    $COMPOSE_CMD down -v 2>/dev/null || true
    
    if confirm "Remove Docker images?"; then
        docker rmi betterdesk-hbbs betterdesk-hbbr betterdesk-console 2>/dev/null || true
        print_info "Images removed"
    fi
    
    if confirm "Remove data ($DATA_DIR)?"; then
        rm -rf "$DATA_DIR"
        print_info "Removed: $DATA_DIR"
    fi
    
    print_success "BetterDesk Docker has been uninstalled"
    press_enter
}

#===============================================================================
# Migration Functions
#===============================================================================

# Detect existing standard RustDesk Docker installation
detect_existing_rustdesk() {
    EXISTING_FOUND=false
    EXISTING_CONTAINERS=()
    EXISTING_DATA_DIR=""
    EXISTING_COMPOSE_FILE=""
    EXISTING_KEY_FILE=""
    EXISTING_DB_FILE=""
    
    print_step "Scanning for existing RustDesk Docker installations..."
    echo ""
    
    # 1. Search for RustDesk containers (common naming patterns)
    local container_patterns=("hbbs" "hbbr" "rustdesk" "s6")
    local found_containers=()
    
    for pattern in "${container_patterns[@]}"; do
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            # Skip BetterDesk containers
            if [[ "$line" == *"betterdesk"* ]]; then
                continue
            fi
            found_containers+=("$line")
        done < <(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -i "$pattern" || true)
    done
    
    # Deduplicate
    local unique_containers=()
    for c in "${found_containers[@]}"; do
        local is_dup=false
        for u in "${unique_containers[@]}"; do
            if [ "$c" = "$u" ]; then
                is_dup=true
                break
            fi
        done
        if [ "$is_dup" = false ]; then
            unique_containers+=("$c")
        fi
    done
    EXISTING_CONTAINERS=("${unique_containers[@]}")
    
    if [ ${#EXISTING_CONTAINERS[@]} -gt 0 ]; then
        print_info "Found RustDesk containers:"
        for c in "${EXISTING_CONTAINERS[@]}"; do
            local status
            status=$(docker inspect --format '{{.State.Status}}' "$c" 2>/dev/null || echo "unknown")
            echo -e "    ${CYAN}•${NC} $c (${status})"
        done
        echo ""
    fi
    
    # 2. Try to find data directory from container mounts
    for c in "${EXISTING_CONTAINERS[@]}"; do
        local mounts
        mounts=$(docker inspect --format '{{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}' "$c" 2>/dev/null || true)
        
        for mount in $mounts; do
            local src="${mount%%:*}"
            local dst="${mount##*:}"
            
            # Look for RustDesk data mounts (typically /root or /data or /opt/rustdesk)
            if [[ "$dst" == "/root" ]] || [[ "$dst" == "/data" ]] || [[ "$dst" == "/opt/rustdesk" ]]; then
                if [ -d "$src" ]; then
                    # Check for key files
                    if [ -f "$src/id_ed25519" ] || [ -f "$src/id_ed25519.pub" ] || [ -f "$src/db_v2.sqlite3" ]; then
                        EXISTING_DATA_DIR="$src"
                        break 2
                    fi
                fi
            fi
        done
    done
    
    # 3. If no data dir from mounts, search common locations
    if [ -z "$EXISTING_DATA_DIR" ]; then
        local search_paths=(
            "./data"
            "./rustdesk-data"
            "/opt/rustdesk"
            "/opt/rustdesk-data"
            "$HOME/rustdesk"
            "$HOME/data"
        )
        
        for path in "${search_paths[@]}"; do
            if [ -d "$path" ] && [ -f "$path/id_ed25519" ]; then
                EXISTING_DATA_DIR="$path"
                break
            fi
        done
    fi
    
    # 4. Search for existing docker-compose files
    local compose_search_paths=(
        "."
        "$HOME"
        "/opt/rustdesk"
        "/opt"
    )
    
    for base in "${compose_search_paths[@]}"; do
        for fname in "docker-compose.yml" "docker-compose.yaml" "compose.yml" "compose.yaml"; do
            local candidate="$base/$fname"
            if [ -f "$candidate" ] && grep -qi "rustdesk\|hbbs\|hbbr" "$candidate" 2>/dev/null; then
                # Skip BetterDesk's own compose file
                if grep -qi "betterdesk" "$candidate" 2>/dev/null; then
                    continue
                fi
                EXISTING_COMPOSE_FILE="$candidate"
                break 2
            fi
        done
    done
    
    # 5. Verify found data
    if [ -n "$EXISTING_DATA_DIR" ]; then
        [ -f "$EXISTING_DATA_DIR/id_ed25519" ] && EXISTING_KEY_FILE="$EXISTING_DATA_DIR/id_ed25519"
        [ -f "$EXISTING_DATA_DIR/db_v2.sqlite3" ] && EXISTING_DB_FILE="$EXISTING_DATA_DIR/db_v2.sqlite3"
    fi
    
    # Determine if we found anything useful
    if [ ${#EXISTING_CONTAINERS[@]} -gt 0 ] || [ -n "$EXISTING_DATA_DIR" ]; then
        EXISTING_FOUND=true
    fi
}

do_migrate() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ MIGRATE FROM EXISTING RUSTDESK ══════════${NC}"
    echo ""
    echo -e "${CYAN}This wizard will migrate your existing RustDesk Docker installation${NC}"
    echo -e "${CYAN}to BetterDesk Console with enhanced features and web management.${NC}"
    echo ""
    
    # Check Docker
    if ! check_docker; then
        print_error "Docker is not available!"
        press_enter
        return
    fi
    
    if ! check_docker_compose; then
        print_error "Docker Compose is not available!"
        press_enter
        return
    fi
    
    # Detect existing installation
    detect_existing_rustdesk
    
    if [ "$EXISTING_FOUND" = false ]; then
        echo ""
        print_warning "No existing RustDesk Docker installation detected automatically."
        echo ""
        echo "You can specify the data directory manually."
        echo -e "${CYAN}The data directory should contain files like: id_ed25519, id_ed25519.pub, db_v2.sqlite3${NC}"
        echo ""
        
        read -p "Enter path to existing RustDesk data directory (or press Enter to cancel): " manual_path
        
        if [ -z "$manual_path" ]; then
            press_enter
            return
        fi
        
        if [ ! -d "$manual_path" ]; then
            print_error "Directory not found: $manual_path"
            press_enter
            return
        fi
        
        EXISTING_DATA_DIR="$manual_path"
        [ -f "$EXISTING_DATA_DIR/id_ed25519" ] && EXISTING_KEY_FILE="$EXISTING_DATA_DIR/id_ed25519"
        [ -f "$EXISTING_DATA_DIR/db_v2.sqlite3" ] && EXISTING_DB_FILE="$EXISTING_DATA_DIR/db_v2.sqlite3"
    fi
    
    # Show migration summary
    echo ""
    echo -e "${WHITE}${BOLD}═══ Migration Summary ═══${NC}"
    echo ""
    
    if [ ${#EXISTING_CONTAINERS[@]} -gt 0 ]; then
        echo -e "  ${CYAN}Containers found:${NC}"
        for c in "${EXISTING_CONTAINERS[@]}"; do
            echo "    • $c"
        done
    fi
    
    if [ -n "$EXISTING_DATA_DIR" ]; then
        echo -e "  ${CYAN}Data directory:${NC}  $EXISTING_DATA_DIR"
    fi
    
    if [ -n "$EXISTING_COMPOSE_FILE" ]; then
        echo -e "  ${CYAN}Compose file:${NC}    $EXISTING_COMPOSE_FILE"
    fi
    
    echo ""
    echo -e "  ${CYAN}Key files found:${NC}"
    
    local key_found=false
    if [ -n "$EXISTING_KEY_FILE" ]; then
        echo -e "    ${GREEN}✓${NC} id_ed25519 (encryption key)"
        key_found=true
    else
        echo -e "    ${RED}✗${NC} id_ed25519 (not found)"
    fi
    
    if [ -f "$EXISTING_DATA_DIR/id_ed25519.pub" ]; then
        echo -e "    ${GREEN}✓${NC} id_ed25519.pub (public key)"
    else
        echo -e "    ${YELLOW}!${NC} id_ed25519.pub (not found - will be regenerated)"
    fi
    
    if [ -n "$EXISTING_DB_FILE" ]; then
        local peer_count
        peer_count=$(sqlite3 "$EXISTING_DB_FILE" "SELECT COUNT(*) FROM peer;" 2>/dev/null || echo "?")
        echo -e "    ${GREEN}✓${NC} db_v2.sqlite3 (${peer_count} devices)"
    else
        echo -e "    ${YELLOW}!${NC} db_v2.sqlite3 (not found - new DB will be created)"
    fi
    
    echo ""
    
    if [ "$key_found" = false ]; then
        print_warning "No encryption key found! Without the key, existing clients"
        print_warning "will need to be reconfigured. Continue anyway?"
        echo ""
    fi
    
    echo -e "${YELLOW}${BOLD}IMPORTANT:${NC} This will:"
    echo "  1. Create a backup of existing data"
    echo "  2. Stop existing RustDesk containers (if found)"
    echo "  3. Copy data to BetterDesk data directory"
    echo "  4. Build and start BetterDesk containers"
    echo "  5. Create a web admin account"
    echo ""
    echo -e "${CYAN}Your existing RustDesk data will NOT be deleted.${NC}"
    echo ""
    
    if ! confirm "Do you want to proceed with the migration?"; then
        press_enter
        return
    fi
    
    echo ""
    
    # === Step 1: Backup existing data ===
    print_step "[1/6] Backing up existing data..."
    
    local migration_backup="$BACKUP_DIR/pre_migration_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$migration_backup"
    
    if [ -n "$EXISTING_DATA_DIR" ] && [ -d "$EXISTING_DATA_DIR" ]; then
        cp -r "$EXISTING_DATA_DIR"/* "$migration_backup/" 2>/dev/null || true
        print_success "  Backup saved to: $migration_backup"
    fi
    
    if [ -n "$EXISTING_COMPOSE_FILE" ] && [ -f "$EXISTING_COMPOSE_FILE" ]; then
        cp "$EXISTING_COMPOSE_FILE" "$migration_backup/old_docker-compose.yml" 2>/dev/null || true
        print_info "  Old compose file backed up"
    fi
    
    # === Step 2: Stop existing containers ===
    print_step "[2/6] Stopping existing RustDesk containers..."
    
    if [ ${#EXISTING_CONTAINERS[@]} -gt 0 ]; then
        for c in "${EXISTING_CONTAINERS[@]}"; do
            docker stop "$c" 2>/dev/null && print_info "  Stopped: $c" || true
        done
    else
        print_info "  No containers to stop"
    fi
    
    # === Step 3: Prepare BetterDesk data directory ===
    print_step "[3/6] Preparing BetterDesk data directory..."
    
    if [ -z "$DATA_DIR" ]; then
        DATA_DIR="/opt/betterdesk-data"
    fi
    
    mkdir -p "$DATA_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Copy key files
    if [ -n "$EXISTING_DATA_DIR" ] && [ "$EXISTING_DATA_DIR" != "$DATA_DIR" ]; then
        # Copy encryption keys (critical)
        for keyfile in id_ed25519 id_ed25519.pub; do
            if [ -f "$EXISTING_DATA_DIR/$keyfile" ]; then
                cp "$EXISTING_DATA_DIR/$keyfile" "$DATA_DIR/"
                print_success "  Copied: $keyfile"
            fi
        done
        
        # Copy database
        if [ -f "$EXISTING_DATA_DIR/db_v2.sqlite3" ]; then
            cp "$EXISTING_DATA_DIR/db_v2.sqlite3" "$DATA_DIR/"
            print_success "  Copied: db_v2.sqlite3"
        fi
        
        # Copy any other relevant files (.api_key etc.)
        for extra in .api_key; do
            if [ -f "$EXISTING_DATA_DIR/$extra" ]; then
                cp "$EXISTING_DATA_DIR/$extra" "$DATA_DIR/"
                print_info "  Copied: $extra"
            fi
        done
    elif [ "$EXISTING_DATA_DIR" = "$DATA_DIR" ]; then
        print_info "  Data already in target directory: $DATA_DIR"
    else
        print_warning "  No source data to copy"
    fi
    
    # === Step 4: Create BetterDesk compose file ===
    print_step "[4/6] Creating BetterDesk Docker Compose configuration..."
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        create_compose_file
    else
        print_info "  Compose file already exists: $COMPOSE_FILE"
    fi
    
    # === Step 5: Build and start ===
    print_step "[5/6] Building BetterDesk Docker images..."
    
    build_images
    start_containers
    
    # === Step 6: Create admin user ===
    print_step "[6/6] Setting up BetterDesk web console..."
    
    create_admin_user
    
    # === Migration complete ===
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                  MIGRATION COMPLETED SUCCESSFULLY               ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    
    local server_ip
    server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR_IP")
    
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║  Web Panel:     ${WHITE}http://$server_ip:5000${GREEN}                           ║${NC}"
    echo -e "${GREEN}║  Data Dir:      ${WHITE}$DATA_DIR${GREEN}                              ║${NC}"
    echo -e "${GREEN}║  Backup:        ${WHITE}$migration_backup${GREEN}       ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ -n "$EXISTING_KEY_FILE" ]; then
        print_success "Encryption key preserved - existing clients will continue to work!"
    else
        print_warning "No key was migrated - existing clients may need reconfiguration."
    fi
    
    echo ""
    print_info "Your old data is preserved in: $migration_backup"
    print_info "Old containers are stopped but not removed."
    echo ""
    echo -e "${CYAN}To remove old containers later, run:${NC}"
    for c in "${EXISTING_CONTAINERS[@]}"; do
        echo "  docker rm $c"
    done
    
    echo ""
    press_enter
}

#===============================================================================
# Main Menu
#===============================================================================

show_menu() {
    print_header
    print_status
    
    echo -e "${WHITE}${BOLD}══════════ MAIN MENU (Docker) ══════════${NC}"
    echo ""
    echo "  1. 🚀 Fresh Installation"
    echo "  2. ⬆️  Update"
    echo "  3. 🔧 Repair"
    echo "  4. ✅ Validation"
    echo "  5. 💾 Backup"
    echo "  6. 🔐 Reset admin password"
    echo "  7. 🔨 Build images"
    echo "  8. 📊 Diagnostics"
    echo "  9. 🗑️  UNINSTALL"
    echo ""
    echo "  M. 🔄 Migrate from existing RustDesk"
    echo "  S. ⚙️  Settings (paths)"
    echo "  0. ❌ Exit"
    echo ""
}

main() {
    # Check root for some operations
    if [ "$EUID" -ne 0 ]; then
        print_warning "Some operations may require root privileges (sudo)"
    fi
    
    # Check docker compose
    if ! check_docker_compose; then
        print_error "Docker Compose is not available!"
        exit 1
    fi
    
    # Auto-detect paths on startup
    echo -e "${CYAN}Detecting installation...${NC}"
    auto_detect_docker_paths
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
            [Mm]) do_migrate ;;
            [Ss]) configure_docker_paths ;;
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
