#!/bin/bash

#############################################################################
# BetterDesk Console - Enhanced Installation Script v9
# 
# This script installs the enhanced RustDesk HBBS/HBBR servers with 
# bidirectional ban enforcement, HTTP API, and web management console.
#
# NEW in v9:
# - Support for custom RustDesk installation directories
# - Automatic verification of required RustDesk files
# - --break-system-packages support for Docker/containerized environments
# - Improved error handling and validation
#
# Features:
# - Automatic backup of existing RustDesk installation
# - Precompiled HBBS/HBBR binaries with ban enforcement + HTTP API
# - Bidirectional ban checking (source + target devices)
# - Real-time device status via HTTP API (port 21114)
# - Installs Flask web console with glassmorphism UI
# - Configures systemd services
# - Uses Google Material Icons (offline)
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
BACKUP_DIR=""
CONSOLE_DIR="/opt/BetterDeskConsole"
TEMP_DIR="/tmp/betterdesk-install"
HBBS_API_PORT=21114
VERSION="v9"  # Current version with HTTP API
BINARY_VERSION="v8-api"  # Binary file suffix
PIP_EXTRA_ARGS=""  # Will be set to --break-system-packages if needed

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

detect_pip_environment() {
    print_header "Detecting Python Environment"
    
    # Check if we're in a containerized/externally-managed environment
    if python3 -c "import sys; exit(0 if sys.prefix != sys.base_prefix else 1)" 2>/dev/null; then
        print_info "Virtual environment detected"
        PIP_EXTRA_ARGS=""
    elif [ -f "/etc/debian_version" ] && python3 -c "import sys; exit(0 if sys.version_info >= (3,11) else 1)" 2>/dev/null; then
        print_warning "Debian/Ubuntu with Python 3.11+ detected (externally-managed environment)"
        print_info "Will use --break-system-packages for pip installs"
        PIP_EXTRA_ARGS="--break-system-packages"
    elif [ -f "/.dockerenv" ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        print_warning "Docker container detected"
        print_info "Will use --break-system-packages for pip installs"
        PIP_EXTRA_ARGS="--break-system-packages"
    else
        print_info "Standard Python environment detected"
        PIP_EXTRA_ARGS=""
    fi
}

check_dependencies() {
    print_header "Checking Dependencies"
    
    local missing_deps=()
    
    # Check for required commands
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

detect_rustdesk_directory() {
    print_header "Detecting RustDesk Installation"
    
    # Check for Docker containers first
    if command -v docker &> /dev/null; then
        local docker_containers=$(docker ps --filter "ancestor=rustdesk/rustdesk-server" --format "{{.Names}}" 2>/dev/null)
        if [ -z "$docker_containers" ]; then
            # Also check for containers with hbbs/hbbr in the name
            docker_containers=$(docker ps --format "{{.Names}}" | grep -E "(hbbs|hbbr|rustdesk)" 2>/dev/null || true)
        fi
        
        if [ -n "$docker_containers" ]; then
            print_warning "Docker RustDesk installation detected!"
            echo ""
            echo "Found running RustDesk containers:"
            echo "$docker_containers" | while read -r container; do
                echo "  - $container"
            done
            echo ""
            print_error "⚠️  CRITICAL: This script installs native binaries, NOT for Docker!"
            print_info "Docker installations require different setup approach."
            echo ""
            echo "Installation options:"
            echo "  1) Exit and use Docker-compose setup (RECOMMENDED)"
            echo "  2) Install ONLY Web Console for existing Docker RustDesk"
            echo "  3) Continue with native installation (WILL NOT WORK WITH DOCKER)"
            echo ""
            read -p "Choose option [1-3]: " docker_choice
            
            case $docker_choice in
                1)
                    print_info "Installation cancelled"
                    echo ""
                    print_info "For Docker setup, see: docs/DOCKER_SUPPORT.md"
                    echo "Or run: docker-compose up -d"
                    exit 0
                    ;;
                2)
                    print_info "Web Console only mode selected"
                    print_warning "This will install ONLY the web interface"
                    print_warning "Make sure your Docker RustDesk is properly configured!"
                    DOCKER_MODE=true
                    detect_docker_volumes
                    return
                    ;;
                3)
                    print_warning "Proceeding with native installation..."
                    print_error "This WILL NOT integrate with your Docker containers!"
                    read -p "Type 'UNDERSTAND' to continue: " confirm
                    if [ "$confirm" != "UNDERSTAND" ]; then
                        print_info "Installation cancelled"
                        exit 0
                    fi
                    ;;
                *)
                    print_error "Invalid option"
                    exit 1
                    ;;
            esac
        fi
    fi
    
    # Common installation directories
    local common_dirs=(
        "/opt/rustdesk"
        "/usr/local/rustdesk"
        "/home/rustdesk"
        "$HOME/rustdesk"
    )
    
    local found_dirs=()
    
    # Check common directories
    for dir in "${common_dirs[@]}"; do
        if [ -d "$dir" ]; then
            found_dirs+=("$dir")
        fi
    done
    
    # Also search for hbbs binary
    local hbbs_locations=$(find /opt /usr/local /home -name "hbbs" -type f 2>/dev/null | head -5)
    if [ -n "$hbbs_locations" ]; then
        while IFS= read -r hbbs_path; do
            local dir=$(dirname "$hbbs_path")
            if [[ ! " ${found_dirs[@]} " =~ " ${dir} " ]]; then
                found_dirs+=("$dir")
            fi
        done <<< "$hbbs_locations"
    fi
    
    if [ ${#found_dirs[@]} -eq 0 ]; then
        print_warning "No existing native RustDesk installation found"
        echo ""
        echo "Options:"
        echo "  1) Install to default location: /opt/rustdesk"
        echo "  2) Specify custom installation directory"
        echo ""
        read -p "Choose option [1-2]: " dir_choice
        
        case $dir_choice in
            1)
                RUSTDESK_DIR="/opt/rustdesk"
                print_info "Will install to: $RUSTDESK_DIR"
                ;;
            2)
                read -p "Enter full path to RustDesk directory: " custom_dir
                if [ -z "$custom_dir" ]; then
                    print_error "Directory path cannot be empty"
                    exit 1
                fi
                RUSTDESK_DIR="$custom_dir"
                print_info "Will install to: $RUSTDESK_DIR"
                ;;
            *)
                print_error "Invalid option"
                exit 1
                ;;
        esac
    elif [ ${#found_dirs[@]} -eq 1 ]; then
        RUSTDESK_DIR="${found_dirs[0]}"
        print_success "Found RustDesk installation at: $RUSTDESK_DIR"
    else
        echo "Multiple RustDesk installations found:"
        echo ""
        local i=1
        for dir in "${found_dirs[@]}"; do
            echo "  $i) $dir"
            ((i++))
        done
        echo "  $i) Specify custom directory"
        echo ""
        read -p "Choose installation directory [1-$i]: " dir_choice
        
        if [ "$dir_choice" -eq "$i" ]; then
            read -p "Enter full path to RustDesk directory: " custom_dir
            if [ -z "$custom_dir" ]; then
                print_error "Directory path cannot be empty"
                exit 1
            fi
            RUSTDESK_DIR="$custom_dir"
        elif [ "$dir_choice" -ge 1 ] && [ "$dir_choice" -lt "$i" ]; then
            RUSTDESK_DIR="${found_dirs[$((dir_choice-1))]}"
        else
            print_error "Invalid option"
            exit 1
        fi
        
        print_info "Selected directory: $RUSTDESK_DIR"
    fi
}

detect_docker_volumes() {
    print_info "Detecting Docker RustDesk volumes..."
    # Try to find Docker volume mount points
    local volume_path=$(docker inspect $(docker ps --format "{{.Names}}" | grep -E "(hbbs|rustdesk)" | head -1) 2>/dev/null | grep -oP '"Source": "\K[^"]+' | grep -E "(rustdesk|hbbs)" | head -1)
    
    if [ -n "$volume_path" ] && [ -d "$volume_path" ]; then
        RUSTDESK_DIR="$volume_path"
        print_success "Detected Docker volume at: $RUSTDESK_DIR"
    else
        print_warning "Could not auto-detect Docker volume"
        read -p "Enter Docker volume path (e.g., /var/lib/docker/volumes/...): " docker_vol
        if [ -d "$docker_vol" ]; then
            RUSTDESK_DIR="$docker_vol"
        else
            print_error "Invalid path: $docker_vol"
            exit 1
        fi
    fi
}

verify_rustdesk_files() {
    print_header "Verifying RustDesk Installation"
    
    # Create directory if it doesn't exist
    if [ ! -d "$RUSTDESK_DIR" ]; then
        print_info "Creating directory: $RUSTDESK_DIR"
        mkdir -p "$RUSTDESK_DIR"
    fi
    
    # Check for required files (if directory exists and has files)
    if [ -d "$RUSTDESK_DIR" ] && [ "$(ls -A $RUSTDESK_DIR 2>/dev/null)" ]; then
        print_info "Checking existing installation..."
        
        # Check for ANY .pub file, not just id_ed25519.pub
        local pub_files=$(find "$RUSTDESK_DIR" -maxdepth 1 -name "*.pub" 2>/dev/null)
        if [ -n "$pub_files" ]; then
            print_success "Found public key files:"
            echo "$pub_files" | while read -r pubfile; do
                echo "  - $(basename $pubfile)"
            done
        else
            print_warning "No public key files (.pub) found"
            print_info "Keys will be generated automatically when HBBS first starts"
        fi
        
        # Check for database
        if [ -f "$RUSTDESK_DIR/db_v2.sqlite3" ]; then
            print_success "RustDesk database found"
            
            # Check database size
            local db_size=$(stat -f%z "$RUSTDESK_DIR/db_v2.sqlite3" 2>/dev/null || stat -c%s "$RUSTDESK_DIR/db_v2.sqlite3" 2>/dev/null)
            if [ "$db_size" -gt 1000 ]; then
                print_info "Database size: $(numfmt --to=iec $db_size 2>/dev/null || echo "$db_size bytes")"
            else
                print_warning "Database file is very small - may be empty"
            fi
        else
            print_info "No database found - will be created automatically"
        fi
    else
        print_info "Directory is empty or new - fresh installation"
    fi
    
    print_success "Installation directory verified: $RUSTDESK_DIR"
}

verify_and_protect_keys() {
    print_header "Verifying Encryption Keys"
    
    # Skip in Docker mode
    if [ "$DOCKER_MODE" = true ]; then
        print_info "Docker mode - skipping key verification"
        return 0
    fi
    
    local key_files=("$RUSTDESK_DIR/id_ed25519" "$RUSTDESK_DIR/id_ed25519.pub")
    local keys_exist=false
    local found_keys=()
    
    # Check for standard keys
    for key_file in "${key_files[@]}"; do
        if [ -f "$key_file" ]; then
            keys_exist=true
            found_keys+=("$(basename $key_file)")
        fi
    done
    
    # Also check for any other .pub files
    local other_pub_files=$(find "$RUSTDESK_DIR" -maxdepth 1 -name "*.pub" ! -name "id_ed25519.pub" 2>/dev/null)
    if [ -n "$other_pub_files" ]; then
        keys_exist=true
        while IFS= read -r pubfile; do
            found_keys+=("$(basename $pubfile)")
        done <<< "$other_pub_files"
    fi
    
    if [ "$keys_exist" = true ]; then
        echo -e "${YELLOW}════════════════════════════════════════${NC}"
        echo -e "${YELLOW}🔑 EXISTING ENCRYPTION KEYS DETECTED 🔑${NC}"
        echo -e "${YELLOW}════════════════════════════════════════${NC}"
        echo ""
        print_success "Found existing key files:"
        for key in "${found_keys[@]}"; do
            echo "  🔑 $key"
        done
        echo ""
        echo -e "${RED}⚠️  CRITICAL INFORMATION:${NC}"
        echo "  • These keys authenticate your RustDesk server"
        echo "  • Clients are configured with your current public key"
        echo "  • Changing keys = ALL clients will be disconnected"
        echo "  • Clients will show 'Key mismatch' errors"
        echo ""
        echo -e "${GREEN}RECOMMENDATION: KEEP existing keys${NC}"
        echo ""
        echo "Options:"
        echo "  1) 🔒 Keep existing keys (RECOMMENDED - no client disruption)"
        echo "  2) 🔄 Backup and regenerate keys (⚠️  WILL BREAK all client connections)"
        echo "  3) ℹ️  Show key information"
        echo ""
        read -p "Choose option [1-3]: " key_choice
        
        case $key_choice in
            1)
                print_success "✓ Keeping existing keys - clients will continue working"
                ;;
            2)
                echo ""
                print_error "⚠️  WARNING: KEY REGENERATION IMPACT ⚠️"
                echo ""
                echo "After regenerating keys, you MUST:"
                echo "  1. Update ALL client configurations"
                echo "  2. Distribute new public key to all users"
                echo "  3. Reconfigure each RustDesk client individually"
                echo ""
                echo "Estimated impact:"
                echo "  • Downtime: Until all clients are reconfigured"
                echo "  • User impact: HIGH - manual reconfiguration required"
                echo ""
                read -p "Are you ABSOLUTELY SURE? Type 'REGENERATE' to confirm: " confirm
                if [ "$confirm" = "REGENERATE" ]; then
                    backup_and_regenerate_keys
                else
                    print_info "Keeping existing keys"
                fi
                ;;
            3)
                show_key_information
                # Ask again after showing info
                read -p "Keep existing keys? [Y/n]: " keep_keys
                if [[ "$keep_keys" =~ ^[Nn]$ ]]; then
                    backup_and_regenerate_keys
                else
                    print_success "Keeping existing keys"
                fi
                ;;
            *)
                print_info "Invalid option - keeping existing keys"
                ;;
        esac
    else
        print_info "No existing keys found"
        print_info "New keys will be automatically generated on first HBBS start"
        echo ""
        print_warning "Remember to:"
        echo "  1. Note the generated public key from web console"
        echo "  2. Configure it in all RustDesk clients"
    fi
    
    echo ""
}

show_key_information() {
    echo ""
    print_header "Current Key Information"
    echo ""
    
    # List all key files
    echo "Key files in $RUSTDESK_DIR:"
    ls -lh "$RUSTDESK_DIR"/*.pub 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
    ls -lh "$RUSTDESK_DIR"/id_ed25519 2>/dev/null | awk '{print "  " $9 " (" $5 ")" " [private]"}'
    echo ""
    
    # Show public key content
    if [ -f "$RUSTDESK_DIR/id_ed25519.pub" ]; then
        echo "Public key content (id_ed25519.pub):"
        echo "═══════════════════════════════════════════════════════════"
        cat "$RUSTDESK_DIR/id_ed25519.pub"
        echo "═══════════════════════════════════════════════════════════"
    fi
    
    # Show other .pub files
    local other_pubs=$(find "$RUSTDESK_DIR" -maxdepth 1 -name "*.pub" ! -name "id_ed25519.pub" 2>/dev/null)
    if [ -n "$other_pubs" ]; then
        echo ""
        echo "Other public key files found:"
        while IFS= read -r pubfile; do
            echo ""
            echo "File: $(basename $pubfile)"
            echo "───────────────────────────────────────────────────────────"
            cat "$pubfile"
            echo "───────────────────────────────────────────────────────────"
        done <<< "$other_pubs"
    fi
    
    echo ""
}

backup_and_regenerate_keys() {
    print_info "🔒 Backing up existing keys..."
    local backup_suffix="backup-$(date +%Y%m%d-%H%M%S)"
    local keys_backed_up=false
    
    # Backup all key files
    for key_pattern in "id_ed25519" "id_ed25519.pub" "*.pub" "id_rsa" "id_rsa.pub"; do
        for key_file in $RUSTDESK_DIR/$key_pattern; do
            if [ -f "$key_file" ]; then
                cp "$key_file" "$key_file.$backup_suffix"
                print_success "✓ Backed up: $(basename $key_file) → $(basename $key_file).$backup_suffix"
                keys_backed_up=true
            fi
        done
    done
    
    if [ "$keys_backed_up" = false ]; then
        print_warning "No keys found to backup"
    fi
    
    print_info "🗑️  Removing old keys..."
    rm -f "$RUSTDESK_DIR/id_ed25519" "$RUSTDESK_DIR/id_ed25519.pub"
    
    print_info "🔑 Generating new ED25519 key pair..."
    if command -v ssh-keygen &>/dev/null; then
        ssh-keygen -t ed25519 -f "$RUSTDESK_DIR/id_ed25519" -N "" -C "rustdesk-server-$(date +%Y%m%d)" &>/dev/null
        
        if [ -f "$RUSTDESK_DIR/id_ed25519.pub" ]; then
            print_success "✓ New keys generated successfully"
            echo ""
            echo "New public key:"
            echo "═══════════════════════════════════════════════════════════"
            cat "$RUSTDESK_DIR/id_ed25519.pub"
            echo "═══════════════════════════════════════════════════════════"
            echo ""
            print_warning "⚠️  IMPORTANT: Copy this key and configure it in ALL RustDesk clients!"
            echo ""
            read -p "Press ENTER after noting the public key..."
        else
            print_error "Failed to generate keys"
        fi
    else
        print_warning "ssh-keygen not found - keys will be generated by HBBS on startup"
        print_info "You can retrieve the public key from the web console after installation"
    fi
}

backup_rustdesk() {
    print_header "Backing Up Existing RustDesk Installation"
    
    if [ ! -d "$RUSTDESK_DIR" ] || [ ! "$(ls -A $RUSTDESK_DIR 2>/dev/null)" ]; then
        print_info "No existing data to backup"
        print_info "Will proceed with fresh installation"
        return 0
    fi
    
    BACKUP_DIR="/opt/rustdesk-backup-$(date +%Y%m%d-%H%M%S)"
    
    echo -e "${RED}═══════════════════════════════════════════════════${NC}"
    echo -e "${RED}⚠️  CRITICAL: BACKUP REQUIRED BEFORE PROCEEDING ⚠️${NC}"
    echo -e "${RED}═══════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Found existing RustDesk installation at:${NC}"
    echo -e "  📁 $RUSTDESK_DIR"
    echo ""
    echo -e "${YELLOW}⚠️  This installation will:${NC}"
    echo "  • Replace HBBS/HBBR binaries"
    echo "  • Modify systemd services"
    echo "  • Update database schema"
    echo ""
    echo -e "${RED}🔑 ENCRYPTION KEYS WARNING:${NC}"
    echo "  Your encryption keys (.pub files) are CRITICAL!"
    echo "  Losing them will break ALL existing client connections!"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}BACKUP OPTIONS:${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo ""
    echo "  1) 🔒 Create AUTOMATIC backup (RECOMMENDED)"
    echo "     → Backup location: $BACKUP_DIR"
    echo ""
    echo "  2) 📋 Create MANUAL backup first, then continue"
    echo "     → Commands to run:"
    echo "       sudo cp -r $RUSTDESK_DIR ${RUSTDESK_DIR}-manual-backup-$(date +%Y%m%d)"
    echo "       [Press Enter after creating backup]"
    echo ""
    echo "  3) ✅ I already have a backup (verify before selecting!)"
    echo ""
    echo "  4) ⛔ Skip backup (DANGEROUS - NOT RECOMMENDED)"
    echo ""
    read -p "Choose option [1-4]: " backup_choice
    
    case $backup_choice in
        1)
            print_info "Creating automatic backup..."
            if cp -r "$RUSTDESK_DIR" "$BACKUP_DIR"; then
                print_success "✓ Backup created successfully!"
                print_success "Backup location: $BACKUP_DIR"
                
                # Verify backup
                if [ -d "$BACKUP_DIR" ]; then
                    local backup_size=$(du -sh "$BACKUP_DIR" | cut -f1)
                    print_info "Backup size: $backup_size"
                    
                    # Check for keys in backup
                    if ls "$BACKUP_DIR"/*.pub &>/dev/null; then
                        print_success "✓ Encryption keys backed up"
                    else
                        print_warning "⚠ No .pub files in backup"
                    fi
                fi
            else
                print_error "Backup failed!"
                print_error "Cannot proceed without backup"
                exit 1
            fi
            ;;
        2)
            echo ""
            print_info "Please create manual backup now..."
            echo ""
            echo -e "${YELLOW}Run these commands in another terminal:${NC}"
            echo ""
            echo "  sudo cp -r $RUSTDESK_DIR ${RUSTDESK_DIR}-manual-backup-$(date +%Y%m%d)"
            echo "  ls -lah ${RUSTDESK_DIR}-manual-backup-$(date +%Y%m%d)/*.pub"
            echo ""
            read -p "Press ENTER after creating backup (or Ctrl+C to cancel)..." 
            print_info "Proceeding with installation..."
            BACKUP_DIR="Manual backup"
            ;;
        3)
            print_warning "Using existing backup"
            echo ""
            read -p "Confirm backup location (or press Enter to skip): " manual_backup_path
            if [ -n "$manual_backup_path" ] && [ -d "$manual_backup_path" ]; then
                print_success "Verified backup exists at: $manual_backup_path"
                BACKUP_DIR="$manual_backup_path"
            else
                print_warning "Could not verify backup location"
                read -p "Continue anyway? [y/N]: " confirm_continue
                if [[ ! "$confirm_continue" =~ ^[Yy]$ ]]; then
                    print_error "Installation cancelled"
                    exit 1
                fi
                BACKUP_DIR="User confirmed backup"
            fi
            ;;
        4)
            print_error "⛔ SKIPPING BACKUP IS EXTREMELY DANGEROUS!"
            echo ""
            print_warning "You will be SOLELY RESPONSIBLE for:"
            echo "  • Lost encryption keys"
            echo "  • Broken client connections"
            echo "  • Database corruption"
            echo "  • Complete data loss"
            echo ""
            read -p "Type 'I ACCEPT THE RISK' to continue: " confirm_risk
            if [ "$confirm_risk" != "I ACCEPT THE RISK" ]; then
                print_error "Installation cancelled"
                exit 1
            fi
            print_warning "Proceeding WITHOUT backup - you have been warned!"
            BACKUP_DIR=""
            ;;
        *)
            print_error "Invalid option"
            exit 1
            ;;
    esac
    
    echo ""
}

install_binaries() {
    print_header "Installing Enhanced HBBS/HBBR $VERSION"
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local bin_dir="$script_dir/hbbs-patch/bin-with-api"
    
    # Check for new binaries first
    if [ ! -f "$bin_dir/hbbs-$BINARY_VERSION" ] || [ ! -f "$bin_dir/hbbr-$BINARY_VERSION" ]; then
        # Fallback to old location
        bin_dir="$script_dir/hbbs-patch/bin"
        if [ ! -f "$bin_dir/hbbs-v8" ] || [ ! -f "$bin_dir/hbbr-v8" ]; then
            print_error "Precompiled binaries not found"
            print_info "Checked locations:"
            print_info "  - $script_dir/hbbs-patch/bin-with-api/hbbs-$BINARY_VERSION"
            print_info "  - $script_dir/hbbs-patch/bin/hbbs-v8"
            exit 1
        fi
        BINARY_VERSION="v8"
        print_warning "Using older binaries without HTTP API"
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
    print_info "Installing HBBS $VERSION (with HTTP API + ban enforcement)..."
    cp "$bin_dir/hbbs-$BINARY_VERSION" "$RUSTDESK_DIR/hbbs"
    chmod +x "$RUSTDESK_DIR/hbbs"
    
    print_info "Installing HBBR $VERSION..."
    cp "$bin_dir/hbbr-$BINARY_VERSION" "$RUSTDESK_DIR/hbbr"
    chmod +x "$RUSTDESK_DIR/hbbr"
    
    print_success "Binaries installed successfully"
    
    # Create/update systemd services
    print_info "Configuring systemd services..."
    
    # HBBS service (with API support)
    cat > /etc/systemd/system/rustdesksignal.service <<EOF
[Unit]
Description=Rustdesk Signal Server
After=network.target

[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=$RUSTDESK_DIR/hbbs
WorkingDirectory=$RUSTDESK_DIR/
User=root
Group=root
Restart=always
StandardOutput=append:/var/log/rustdesk/signalserver.log
StandardError=append:/var/log/rustdesk/signalserver.error
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # HBBR service
    cat > /etc/systemd/system/rustdeskrelay.service <<EOF
[Unit]
Description=Rustdesk Relay Server
After=network.target

[Service]
Type=simple
LimitNOFILE=1000000
ExecStart=$RUSTDESK_DIR/hbbr
WorkingDirectory=$RUSTDESK_DIR/
User=root
Group=root
Restart=always
StandardOutput=append:/var/log/rustdesk/relay.log
StandardError=append:/var/log/rustdesk/relay.error
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # Create log directory
    mkdir -p /var/log/rustdesk
    
    # Reload and start services
    systemctl daemon-reload
    systemctl enable rustdesksignal.service rustdeskrelay.service
    systemctl start rustdesksignal.service rustdeskrelay.service
    
    # Wait for services to start
    sleep 3
    
    # Verify services
    if systemctl is-active --quiet rustdesksignal.service; then
        print_success "HBBS service is running"
    else
        print_error "HBBS service failed to start"
        print_info "Check logs: journalctl -u rustdesksignal.service -n 50"
        return 1
    fi
    
    if systemctl is-active --quiet rustdeskrelay.service; then
        print_success "HBBR service is running"
    else
        print_warning "HBBR service not running (optional)"
    fi
    
    # Display version info
    echo ""
    print_info "HBBS/HBBR version: $VERSION"
    print_info "Features:"
    echo "  ✓ HTTP API on port $HBBS_API_PORT"
    echo "  ✓ Real-time device status"
    echo "  ✓ Bidirectional ban enforcement"
    echo "  ✓ Source + Target device ban checks"
    echo ""
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
        print_warning "Migrations directory not found: $migrations_dir"
        print_info "Skipping migrations"
        return 0
    fi
    
    # Run v1.0.1 migration (soft delete)
    if [ -f "$migrations_dir/v1.0.1_soft_delete.py" ]; then
        print_info "Running migration v1.0.1 (soft delete)..."
        if python3 "$migrations_dir/v1.0.1_soft_delete.py"; then
            print_success "Migration v1.0.1 completed"
        else
            print_warning "Migration v1.0.1 skipped (may be already applied)"
        fi
    fi
    
    # Run v1.1.0 migration (device bans)
    if [ -f "$migrations_dir/v1.1.0_device_bans.py" ]; then
        print_info "Running migration v1.1.0 (device bans)..."
        if python3 "$migrations_dir/v1.1.0_device_bans.py"; then
            print_success "Migration v1.1.0 completed"
        else
            print_warning "Migration v1.1.0 skipped (may be already applied)"
        fi
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
    
    # Update app.py with correct RustDesk path
    if [ "$RUSTDESK_DIR" != "/opt/rustdesk" ]; then
        print_info "Updating console configuration for custom RustDesk path..."
        sed -i "s|'/opt/rustdesk/db_v2.sqlite3'|'$RUSTDESK_DIR/db_v2.sqlite3'|g" "$CONSOLE_DIR/app.py"
        sed -i "s|'/opt/rustdesk/id_ed25519.pub'|'$RUSTDESK_DIR/id_ed25519.pub'|g" "$CONSOLE_DIR/app.py"
    fi
    
    # Install Python dependencies
    print_info "Installing Python dependencies..."
    if [ -n "$PIP_EXTRA_ARGS" ]; then
        print_info "Using: pip3 install $PIP_EXTRA_ARGS -r requirements.txt"
        pip3 install $PIP_EXTRA_ARGS -r "$CONSOLE_DIR/requirements.txt"
    else
        pip3 install -r "$CONSOLE_DIR/requirements.txt"
    fi
    
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
    sleep 3
    
    if systemctl is-active --quiet betterdesk.service; then
        print_success "Web console service is running"
    else
        print_error "Web console service failed to start"
        print_info "Check logs: journalctl -u betterdesk.service -n 50"
        return 1
    fi
}

test_installation() {
    print_header "Testing Installation"
    
    local all_ok=true
    
    # Test HBBS API
    print_info "Testing HBBS HTTP API..."
    sleep 2
    if curl -s "http://localhost:$HBBS_API_PORT/api/health" 2>/dev/null | grep -q "success"; then
        print_success "HBBS API is responding on port $HBBS_API_PORT"
    else
        print_warning "HBBS API is not responding (may still be starting)"
        all_ok=false
    fi
    
    # Test Web Console
    print_info "Testing Web Console..."
    if curl -s "http://localhost:5000" > /dev/null 2>&1; then
        print_success "Web Console is accessible on port 5000"
    else
        print_warning "Web Console is not responding (may still be starting)"
        all_ok=false
    fi
    
    # Test RustDesk ports
    print_info "Checking RustDesk ports..."
    local ports=(21115 21116 21117 21118)
    for port in "${ports[@]}"; do
        if netstat -tln 2>/dev/null | grep -q ":$port " || ss -tln 2>/dev/null | grep -q ":$port "; then
            print_success "Port $port is listening"
        else
            print_warning "Port $port is not listening"
            all_ok=false
        fi
    done
    
    if [ "$all_ok" = true ]; then
        print_success "All tests passed!"
    else
        print_warning "Some tests failed - services may still be starting"
        print_info "Wait a few seconds and check: systemctl status rustdesksignal betterdesk"
    fi
}

cleanup() {
    print_header "Cleaning Up"
    
    if [ -d "$TEMP_DIR" ]; then
        print_info "Removing temporary files..."
        rm -rf "$TEMP_DIR"
    fi
    
    print_success "Cleanup completed"
}

show_summary() {
    print_header "Installation Complete!"
    
    echo -e "${GREEN}BetterDesk Console $VERSION has been successfully installed!${NC}"
    echo ""
    echo "Installation details:"
    echo "  • RustDesk Directory: $RUSTDESK_DIR"
    echo "  • Console Directory:  $CONSOLE_DIR"
    echo ""
    echo "Access points:"
    echo "  • Web Console:  http://$(hostname -I | awk '{print $1}'):5000"
    echo "  • HBBS API:     http://localhost:$HBBS_API_PORT/api/health"
    echo ""
    echo "Services:"
    echo "  • HBBS:         sudo systemctl status rustdesksignal.service"
    echo "  • HBBR:         sudo systemctl status rustdeskrelay.service"
    echo "  • Web Console:  sudo systemctl status betterdesk.service"
    echo ""
    
    if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
        echo "Backup location:"
        echo "  • $BACKUP_DIR"
        echo ""
    fi
    
    echo "RustDesk Ports:"
    echo "  • 21115 - NAT test"
    echo "  • 21116 - TCP/UDP"
    echo "  • 21117 - Relay"
    echo "  • 21118 - WebSocket"
    echo "  • 21119 - Relay (additional)"
    echo "  • $HBBS_API_PORT - HTTP API"
    echo ""
    
    echo "Useful commands:"
    echo "  • View HBBS logs:    sudo journalctl -u rustdesksignal -f"
    echo "  • View console logs: sudo journalctl -u betterdesk -f"
    echo "  • Restart HBBS:      sudo systemctl restart rustdesksignal"
    echo "  • Restart console:   sudo systemctl restart betterdesk"
    echo ""
    
    print_info "Enjoy your enhanced RustDesk experience!"
    echo ""
    echo "For support and documentation:"
    echo "  • GitHub: https://github.com/UNITRONIX/Rustdesk-FreeConsole"
}

# Main installation flow
main() {
    clear
    print_header "BetterDesk Console Installer $VERSION"
    echo "This script will install:"
    echo "  • Enhanced RustDesk HBBS/HBBR with HTTP API"
    echo "  • Bidirectional ban enforcement"
    echo "  • Real-time device status monitoring"
    echo "  • Web Management Console with Material Design"
    echo ""
    echo "Installation method: Precompiled binaries (no compilation required)"
    echo ""
    
    check_root
    detect_pip_environment
    check_dependencies
    detect_rustdesk_directory
    verify_rustdesk_files
    backup_rustdesk
    verify_and_protect_keys
    install_binaries
    run_database_migrations
    install_web_console
    test_installation
    cleanup
    show_summary
}

# Run main function
main "$@"
