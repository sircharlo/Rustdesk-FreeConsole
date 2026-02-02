#!/bin/bash
# =============================================================================
# BetterDesk Console - Docker Installation Script v1.5.0
# =============================================================================
# This script installs BetterDesk Console in Docker environments.
# It can work with existing RustDesk Docker containers or standalone setups.
#
# Features:
# - Auto-detection of RustDesk Docker containers
# - Custom path selection for RustDesk data
# - Volume mounting support
# - Web console installation
# - Service configuration
# - Database migration
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_VERSION="1.5.0"

# Installation paths
RUSTDESK_PATH=""
CONSOLE_PATH="/opt/BetterDeskConsole"
DOCKER_CONTAINER=""
INSTALL_MODE="host" # host, container, or volume

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo ""
    echo -e "${CYAN}=====================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}=====================================${NC}"
    echo ""
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

# =============================================================================
# Docker Detection Functions
# =============================================================================

detect_docker_environment() {
    print_header "Detecting Docker Environment"
    
    # Check if we're inside a container
    if [ -f /.dockerenv ]; then
        print_info "Running inside Docker container"
        INSTALL_MODE="container"
        return 0
    fi
    
    # Check if Docker is available
    if command -v docker &>/dev/null; then
        print_info "Docker is available on this host"
        
        # Look for RustDesk containers
        local containers=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -E "(hbbs|hbbr|rustdesk)" || true)
        if [ -n "$containers" ]; then
            print_success "Found RustDesk containers:"
            echo "$containers" | sed 's/^/  - /'
            INSTALL_MODE="volume"
            return 0
        fi
    fi
    
    print_info "No Docker environment detected - using host mode"
    INSTALL_MODE="host"
}

select_rustdesk_path() {
    print_header "RustDesk Path Selection"
    
    echo "Please choose your RustDesk installation type:"
    echo ""
    echo "1) Docker container with mounted volume (recommended)"
    echo "2) Docker container - install inside container"  
    echo "3) Custom path (manual selection)"
    echo "4) Auto-detect from running containers"
    echo ""
    
    read -p "Select option [1-4]: " -n 1 -r choice
    echo ""
    
    case $choice in
        1)
            select_volume_path
            ;;
        2) 
            select_container_install
            ;;
        3)
            select_custom_path
            ;;
        4)
            auto_detect_containers
            ;;
        *)
            print_error "Invalid choice. Defaulting to auto-detect."
            auto_detect_containers
            ;;
    esac
}

select_volume_path() {
    print_info "Docker Volume Mode Selected"
    echo ""
    echo "Common Docker volume paths:"
    echo "  /var/lib/docker/volumes/rustdesk-data/_data"
    echo "  /opt/docker/rustdesk/data"
    echo "  /data/rustdesk"
    echo "  ~/docker/rustdesk/data"
    echo ""
    
    read -p "Enter RustDesk data path: " custom_path
    
    if [ -z "$custom_path" ]; then
        print_error "Path cannot be empty"
        select_volume_path
        return
    fi
    
    if [ ! -d "$custom_path" ]; then
        print_error "Directory does not exist: $custom_path"
        read -p "Create it? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            mkdir -p "$custom_path"
            print_success "Created directory: $custom_path"
        else
            select_volume_path
            return
        fi
    fi
    
    RUSTDESK_PATH="$custom_path"
    INSTALL_MODE="volume"
    validate_rustdesk_installation
}

select_container_install() {
    print_info "Container Installation Mode"
    
    # List running containers
    local containers=$(docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -E "(hbbs|hbbr|rustdesk)" || true)
    
    if [ -z "$containers" ]; then
        print_warning "No RustDesk containers found running"
        echo "Available containers:"
        docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
        echo ""
        read -p "Enter container name to install into: " container_name
    else
        echo "RustDesk containers found:"
        echo "$containers"
        echo ""
        read -p "Enter container name: " container_name
    fi
    
    if [ -z "$container_name" ]; then
        print_error "Container name cannot be empty"
        select_container_install
        return
    fi
    
    # Verify container exists and is running
    if ! docker ps --format "{{.Names}}" | grep -q "^${container_name}$"; then
        print_error "Container '$container_name' not found or not running"
        select_container_install
        return
    fi
    
    DOCKER_CONTAINER="$container_name"
    RUSTDESK_PATH="/root" # Standard path inside RustDesk containers
    INSTALL_MODE="container"
    
    # Check if container has RustDesk files
    print_info "Checking container contents..."
    if docker exec "$container_name" ls /root/*.pub &>/dev/null; then
        print_success "Found RustDesk files in container"
    else
        print_warning "No RustDesk public key found - this might not be a RustDesk container"
    fi
}

select_custom_path() {
    print_info "Custom Path Mode"
    echo ""
    echo "Enter the full path to your RustDesk installation directory."
    echo "This should contain files like: id_ed25519.pub, db_v2.sqlite3, etc."
    echo ""
    
    read -p "RustDesk path: " custom_path
    
    if [ -z "$custom_path" ]; then
        print_error "Path cannot be empty"
        select_custom_path
        return
    fi
    
    # Expand ~ to home directory
    custom_path="${custom_path/#\~/$HOME}"
    
    if [ ! -d "$custom_path" ]; then
        print_error "Directory does not exist: $custom_path"
        select_custom_path
        return
    fi
    
    RUSTDESK_PATH="$custom_path"
    INSTALL_MODE="host"
    validate_rustdesk_installation
}

auto_detect_containers() {
    print_info "Auto-detecting RustDesk containers..."
    
    local hbbs_container=$(docker ps --format "{{.Names}}" | grep -E "(hbbs|rustdesk)" | head -1 || true)
    
    if [ -n "$hbbs_container" ]; then
        print_success "Found RustDesk container: $hbbs_container"
        
        # Check if container has volumes mounted
        local mounts=$(docker inspect "$hbbs_container" --format='{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}' 2>/dev/null || true)
        
        if [ -n "$mounts" ]; then
            echo ""
            echo "Container volume mounts:"
            echo "$mounts"
            echo ""
            
            # Try to find the mount that contains RustDesk data
            local data_mount=$(echo "$mounts" | grep -E "(root|rustdesk)" | head -1 | cut -d' ' -f1 || true)
            
            if [ -n "$data_mount" ] && [ -d "$data_mount" ]; then
                print_success "Found data volume: $data_mount"
                RUSTDESK_PATH="$data_mount"
                INSTALL_MODE="volume"
                validate_rustdesk_installation
                return
            fi
        fi
        
        print_info "No suitable volume mount found, using container mode"
        DOCKER_CONTAINER="$hbbs_container"
        RUSTDESK_PATH="/root"
        INSTALL_MODE="container"
    else
        print_warning "No RustDesk containers found"
        select_custom_path
    fi
}

validate_rustdesk_installation() {
    print_info "Validating RustDesk installation at: $RUSTDESK_PATH"
    
    case $INSTALL_MODE in
        container)
            validate_container_installation
            ;;
        volume|host)
            validate_host_installation
            ;;
    esac
}

validate_container_installation() {
    local found_files=0
    
    # Check for public key
    if docker exec "$DOCKER_CONTAINER" test -f /root/id_ed25519.pub 2>/dev/null; then
        print_success "Found public key"
        ((found_files++))
    fi
    
    # Check for database
    if docker exec "$DOCKER_CONTAINER" test -f /root/db_v2.sqlite3 2>/dev/null; then
        print_success "Found database"
        ((found_files++))
    fi
    
    # Check for HBBS binary
    if docker exec "$DOCKER_CONTAINER" test -f /root/hbbs 2>/dev/null; then
        print_success "Found HBBS binary"
        ((found_files++))
    fi
    
    if [ $found_files -lt 1 ]; then
        print_error "No RustDesk files found in container"
        print_info "Container contents:"
        docker exec "$DOCKER_CONTAINER" ls -la /root/ 2>/dev/null || true
        return 1
    fi
    
    print_success "RustDesk installation validated ($found_files files found)"
}

validate_host_installation() {
    local found_files=0
    
    # Check for public key (any .pub file)
    if ls "$RUSTDESK_PATH"/*.pub &>/dev/null; then
        local pub_files=$(ls "$RUSTDESK_PATH"/*.pub | wc -l)
        print_success "Found $pub_files public key(s)"
        ((found_files++))
    fi
    
    # Check for database
    for db in db_v2.sqlite3 db.sqlite3 rustdesk.db; do
        if [ -f "$RUSTDESK_PATH/$db" ]; then
            print_success "Found database: $db"
            ((found_files++))
            break
        fi
    done
    
    # Check for HBBS binary or executable
    for binary in hbbs hbbs.exe hbbs-v8-api; do
        if [ -f "$RUSTDESK_PATH/$binary" ]; then
            print_success "Found binary: $binary"
            ((found_files++))
            break
        fi
    done
    
    if [ $found_files -lt 1 ]; then
        print_error "No RustDesk files found in: $RUSTDESK_PATH"
        print_info "Directory contents:"
        ls -la "$RUSTDESK_PATH" 2>/dev/null || true
        echo ""
        print_warning "This doesn't appear to be a RustDesk installation directory"
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    else
        print_success "RustDesk installation validated ($found_files files found)"
    fi
}

# =============================================================================
# Installation Functions  
# =============================================================================

create_backup() {
    print_header "Creating Backup"
    
    local backup_dir="/opt/BetterDesk_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    case $INSTALL_MODE in
        container)
            print_info "Backing up container data..."
            # Backup container's RustDesk data
            docker exec "$DOCKER_CONTAINER" tar czf /tmp/rustdesk_backup.tar.gz /root/*.{pub,sqlite3,key} 2>/dev/null || true
            docker cp "$DOCKER_CONTAINER:/tmp/rustdesk_backup.tar.gz" "$backup_dir/" 2>/dev/null || true
            docker exec "$DOCKER_CONTAINER" rm -f /tmp/rustdesk_backup.tar.gz 2>/dev/null || true
            ;;
        volume|host)
            print_info "Backing up RustDesk data..."
            # Backup important files
            for file in "$RUSTDESK_PATH"/*.pub "$RUSTDESK_PATH"/*.sqlite3 "$RUSTDESK_PATH"/.api_key "$RUSTDESK_PATH"/id_ed25519*; do
                if [ -f "$file" ]; then
                    cp "$file" "$backup_dir/" 2>/dev/null || true
                fi
            done
            
            # Backup binaries
            for binary in hbbs hbbr; do
                if [ -f "$RUSTDESK_PATH/$binary" ]; then
                    cp "$RUSTDESK_PATH/$binary" "$backup_dir/$binary.backup" 2>/dev/null || true
                fi
            done
            ;;
    esac
    
    # Backup existing web console if it exists
    if [ -d "$CONSOLE_PATH" ]; then
        print_info "Backing up web console..."
        cp -r "$CONSOLE_PATH" "$backup_dir/console_backup" 2>/dev/null || true
    fi
    
    print_success "Backup created at: $backup_dir"
    echo "  Restore command: cp -r $backup_dir/* $RUSTDESK_PATH/"
}

install_dependencies() {
    print_header "Installing Dependencies"
    
    # Detect package manager
    if command -v apt &>/dev/null; then
        print_info "Using apt package manager"
        apt update -qq
        apt install -y python3 python3-pip sqlite3 curl
    elif command -v yum &>/dev/null; then
        print_info "Using yum package manager"  
        yum install -y python3 python3-pip sqlite3 curl
    elif command -v apk &>/dev/null; then
        print_info "Using apk package manager (Alpine)"
        apk update
        apk add python3 py3-pip sqlite curl
    else
        print_warning "Unknown package manager - you may need to install dependencies manually"
        print_info "Required: python3, python3-pip, sqlite3, curl"
    fi
    
    # Install Python packages
    print_info "Installing Python packages..."
    pip3 install --quiet --break-system-packages \
        flask flask-wtf flask-limiter bcrypt markupsafe requests \
        2>/dev/null || \
    pip3 install --quiet \
        flask flask-wtf flask-limiter bcrypt markupsafe requests \
        2>/dev/null || \
        print_warning "Some Python packages might not be installed"
    
    print_success "Dependencies installed"
}

install_binaries() {
    print_header "Installing BetterDesk Binaries"
    
    if [ ! -d "$SCRIPT_DIR/hbbs-patch/bin-with-api" ]; then
        print_error "Binary directory not found: $SCRIPT_DIR/hbbs-patch/bin-with-api"
        return 1
    fi
    
    case $INSTALL_MODE in
        container)
            install_binaries_container
            ;;
        volume|host)
            install_binaries_host
            ;;
    esac
}

install_binaries_container() {
    print_info "Installing binaries into container: $DOCKER_CONTAINER"
    
    # Copy binaries to container
    if [ -f "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbs-v8-api" ]; then
        docker cp "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbs-v8-api" "$DOCKER_CONTAINER:/usr/local/bin/hbbs-betterdesk"
        docker exec "$DOCKER_CONTAINER" chmod +x /usr/local/bin/hbbs-betterdesk
        print_success "Installed hbbs-betterdesk"
    fi
    
    if [ -f "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbr-v8-api" ]; then
        docker cp "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbr-v8-api" "$DOCKER_CONTAINER:/usr/local/bin/hbbr-betterdesk"  
        docker exec "$DOCKER_CONTAINER" chmod +x /usr/local/bin/hbbr-betterdesk
        print_success "Installed hbbr-betterdesk"
    fi
    
    # Create backup of original binaries
    docker exec "$DOCKER_CONTAINER" sh -c '
        if [ -f /usr/local/bin/hbbs ]; then
            cp /usr/local/bin/hbbs /usr/local/bin/hbbs.original
        fi
        if [ -f /usr/local/bin/hbbr ]; then
            cp /usr/local/bin/hbbr /usr/local/bin/hbbr.original  
        fi
    ' 2>/dev/null || true
}

install_binaries_host() {
    print_info "Installing binaries to: $RUSTDESK_PATH"
    
    # Backup existing binaries
    for binary in hbbs hbbr; do
        if [ -f "$RUSTDESK_PATH/$binary" ]; then
            cp "$RUSTDESK_PATH/$binary" "$RUSTDESK_PATH/$binary.backup-$(date +%Y%m%d-%H%M%S)"
            print_info "Backed up $binary"
        fi
    done
    
    # Copy new binaries
    if [ -f "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbs-v8-api" ]; then
        cp "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbs-v8-api" "$RUSTDESK_PATH/hbbs-betterdesk"
        chmod +x "$RUSTDESK_PATH/hbbs-betterdesk"
        
        # Create/update symlink
        if [ -f "$RUSTDESK_PATH/hbbs" ]; then
            ln -sf "$RUSTDESK_PATH/hbbs-betterdesk" "$RUSTDESK_PATH/hbbs"
            print_success "Updated hbbs → hbbs-betterdesk"
        else
            ln -sf "$RUSTDESK_PATH/hbbs-betterdesk" "$RUSTDESK_PATH/hbbs"
            print_success "Installed hbbs-betterdesk"
        fi
    fi
    
    if [ -f "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbr-v8-api" ]; then
        cp "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbr-v8-api" "$RUSTDESK_PATH/hbbr-betterdesk"
        chmod +x "$RUSTDESK_PATH/hbbr-betterdesk"
        
        # Create/update symlink
        if [ -f "$RUSTDESK_PATH/hbbr" ]; then
            ln -sf "$RUSTDESK_PATH/hbbr-betterdesk" "$RUSTDESK_PATH/hbbr"
            print_success "Updated hbbr → hbbr-betterdesk"
        else
            ln -sf "$RUSTDESK_PATH/hbbr-betterdesk" "$RUSTDESK_PATH/hbbr"
            print_success "Installed hbbr-betterdesk"
        fi
    fi
}

install_web_console() {
    print_header "Installing Web Console"
    
    if [ ! -d "$SCRIPT_DIR/web" ]; then
        print_error "Web directory not found: $SCRIPT_DIR/web"
        return 1
    fi
    
    # Create console directory
    mkdir -p "$CONSOLE_PATH"
    
    # Copy web files
    cp -r "$SCRIPT_DIR/web/"* "$CONSOLE_PATH/"
    
    # Set permissions
    chmod +x "$CONSOLE_PATH/app.py" 2>/dev/null || true
    
    # Create VERSION file
    echo "v$TARGET_VERSION" > "$CONSOLE_PATH/VERSION"
    
    print_success "Web console installed to: $CONSOLE_PATH"
}

run_database_migration() {
    print_header "Running Database Migration"
    
    # Find database
    local db_path=""
    
    case $INSTALL_MODE in
        container)
            # Run migration inside container
            print_info "Running migration inside container..."
            docker exec "$DOCKER_CONTAINER" python3 -c "
import sqlite3
import os

# Find database
db_paths = ['/root/db_v2.sqlite3', '/root/db.sqlite3']
db_path = None

for path in db_paths:
    if os.path.exists(path):
        db_path = path
        break

if not db_path:
    print('❌ Database not found')
    exit(1)

print(f'📂 Found database: {db_path}')
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Get existing columns
cursor.execute('PRAGMA table_info(peer)')
columns = [row[1] for row in cursor.fetchall()]
print(f'📋 Existing columns: {columns}')

changes = 0

# Add missing columns
if 'last_online' not in columns:
    cursor.execute('ALTER TABLE peer ADD COLUMN last_online TEXT')
    print('✓ Added last_online column')
    changes += 1

if 'is_deleted' not in columns:
    cursor.execute('ALTER TABLE peer ADD COLUMN is_deleted INTEGER DEFAULT 0')  
    print('✓ Added is_deleted column')
    changes += 1

if 'is_banned' not in columns:
    cursor.execute('ALTER TABLE peer ADD COLUMN is_banned INTEGER DEFAULT 0')
    cursor.execute('ALTER TABLE peer ADD COLUMN banned_at TEXT')
    cursor.execute('ALTER TABLE peer ADD COLUMN banned_by TEXT')
    cursor.execute('ALTER TABLE peer ADD COLUMN ban_reason TEXT')
    print('✓ Added ban columns')
    changes += 1

conn.commit()
conn.close()
print(f'✅ Migration complete: {changes} changes made')
"
            ;;
        volume|host)
            # Run migration using external script
            if [ -f "$SCRIPT_DIR/migrations/v1.5.0_fix_online_status.py" ]; then
                python3 "$SCRIPT_DIR/migrations/v1.5.0_fix_online_status.py" "$RUSTDESK_PATH/db_v2.sqlite3" || \
                python3 "$SCRIPT_DIR/migrations/v1.5.0_fix_online_status.py" "$RUSTDESK_PATH/db.sqlite3" || \
                print_warning "Could not run database migration - database may be missing"
            else
                print_warning "Migration script not found - you may need to run it manually"
            fi
            ;;
    esac
}

create_systemd_service() {
    print_header "Creating Systemd Service"
    
    if [ "$INSTALL_MODE" = "container" ]; then
        print_info "Skipping systemd service creation for container mode"
        print_info "Use docker-compose or docker commands to manage the container"
        return 0
    fi
    
    # Create BetterDesk Console service
    cat > /etc/systemd/system/betterdesk.service << EOF
[Unit]
Description=BetterDesk Console
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONSOLE_PATH
Environment=PYTHONPATH=$CONSOLE_PATH
ExecStart=/usr/bin/python3 $CONSOLE_PATH/app.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Reload daemon and enable service
    print_info "Reloading systemd daemon..."
    systemctl daemon-reload
    
    print_info "Enabling betterdesk service..."
    systemctl enable betterdesk.service
    
    print_success "Created and enabled betterdesk.service"
}

# =============================================================================
# Main Installation Flow
# =============================================================================

main() {
    print_header "BetterDesk Console - Docker Installation v$TARGET_VERSION"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ] && [ "$INSTALL_MODE" != "container" ]; then
        print_error "This script must be run as root (use sudo)"
        print_info "Exception: Container mode doesn't require root on host"
        exit 1
    fi
    
    # Detect environment and select paths
    detect_docker_environment
    select_rustdesk_path
    
    # Summary
    print_header "Installation Summary"
    echo "  Install Mode:    $INSTALL_MODE"
    echo "  RustDesk Path:   $RUSTDESK_PATH"
    echo "  Console Path:    $CONSOLE_PATH"
    if [ -n "$DOCKER_CONTAINER" ]; then
        echo "  Container:       $DOCKER_CONTAINER"
    fi
    echo "  Target Version:  $TARGET_VERSION"
    echo ""
    
    # Confirmation
    read -p "Proceed with installation? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    # Run installation steps
    create_backup
    install_dependencies
    install_binaries
    install_web_console
    run_database_migration
    
    if [ "$INSTALL_MODE" != "container" ]; then
        create_systemd_service
        
        # Start service
        print_info "Starting BetterDesk Console..."
        systemctl start betterdesk.service
        
        if systemctl is-active betterdesk.service &>/dev/null; then
            print_success "BetterDesk Console started successfully"
        else
            print_warning "Service may not have started correctly"
            print_info "Check logs: journalctl -u betterdesk.service -n 20"
        fi
    fi
    
    # Final instructions
    print_header "Installation Complete!"
    echo ""
    print_success "BetterDesk Console v$TARGET_VERSION installed successfully"
    echo ""
    
    case $INSTALL_MODE in
        container)
            echo "Next steps for container mode:"
            echo "  1. Restart the RustDesk container to load new binaries"
            echo "  2. Start the web console container (see DOCKER_SUPPORT.md)"
            echo "  3. Configure port forwarding for web access"
            ;;
        volume)
            echo "Next steps for volume mode:"
            echo "  1. Restart RustDesk containers: docker-compose restart"
            echo "  2. Access web console: http://localhost:5000"
            echo "  3. Default admin login will be shown in container logs"
            ;;
        host)
            echo "Next steps for host mode:"
            echo "  1. Access web console: http://localhost:5000"
            echo "  2. Default admin login: admin / (check logs for password)"
            echo "  3. Check service status: systemctl status betterdesk"
            ;;
    esac
    
    echo ""
    print_info "Documentation: https://github.com/UNITRONIX/Rustdesk-FreeConsole"
    print_info "Issues: https://github.com/UNITRONIX/Rustdesk-FreeConsole/issues"
    echo ""
}

main "$@"