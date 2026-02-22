#!/bin/bash
#===============================================================================
#
#   BetterDesk Console Manager v2.3.0
#   All-in-One Interactive Tool for Linux
#
#   Features:
#     - Fresh installation (Node.js web console)
#     - Update existing installation  
#     - Repair/fix issues (enhanced with graceful shutdown)
#     - Validate installation
#     - Backup & restore
#     - Reset admin password
#     - Build custom binaries
#     - Full diagnostics
#     - SHA256 binary verification
#     - Auto mode (non-interactive)
#     - Enhanced service management with health verification
#     - Port conflict detection
#     - Fixed ban system (device-specific, not IP-based)
#     - RustDesk Client API (login, address book sync)
#     - TOTP Two-Factor Authentication
#     - SSL/TLS certificate configuration
#
#   Usage: 
#     Interactive: sudo ./betterdesk.sh
#     Auto mode:   sudo ./betterdesk.sh --auto
#
#===============================================================================

set -e

# Version
VERSION="2.3.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto mode flag
AUTO_MODE=false
SKIP_VERIFY=false
PREFERRED_CONSOLE_TYPE="nodejs"  # Always Node.js (Flask removed in v2.3.0)

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto|-a)
            AUTO_MODE=true
            shift
            ;;
        --skip-verify)
            SKIP_VERIFY=true
            shift
            ;;
        --nodejs)
            PREFERRED_CONSOLE_TYPE="nodejs"
            shift
            ;;
        --flask)
            echo "WARNING: Flask console is deprecated and no longer available in v2.3.0"
            echo "Node.js console will be installed instead."
            PREFERRED_CONSOLE_TYPE="nodejs"
            shift
            ;;
        --help|-h)
            echo "BetterDesk Console Manager v$VERSION"
            echo ""
            echo "Usage: sudo ./betterdesk.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --auto, -a      Run in automatic mode (non-interactive)"
            echo "  --skip-verify   Skip SHA256 verification of binaries"
            echo "  --nodejs        Install Node.js web console (default)"
            echo "  --help, -h      Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Binary checksums (SHA256) - v2.1.2
HBBS_LINUX_X86_64_SHA256="2B6C475A449ECBA3786D0DB46CBF4E038EDB74FC3497F9A45791ADDD5A28834C"
HBBR_LINUX_X86_64_SHA256="8E7492CB1695B3D812CA13ABAC9A31E4DEA95B50497128D8E128DA39FDAC243D"

# Default paths (can be overridden by environment variables)
RUSTDESK_PATH="${RUSTDESK_PATH:-}"
CONSOLE_PATH="${CONSOLE_PATH:-}"
CONSOLE_TYPE="none"  # none, nodejs
BACKUP_DIR="${BACKUP_DIR:-/opt/rustdesk-backups}"

# API configuration
API_PORT="${API_PORT:-21120}"

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
# Service Management Functions (Enhanced v2.1.2)
#===============================================================================

# Wait for a service to fully stop with timeout
wait_for_service_stop() {
    local service_name="$1"
    local timeout="${2:-30}"
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if ! systemctl is-active --quiet "$service_name" 2>/dev/null; then
            return 0
        fi
        sleep 1
        ((elapsed++))
    done
    
    print_warning "Service $service_name did not stop within ${timeout}s"
    return 1
}

# Kill any stale processes that might be holding files/ports
kill_stale_processes() {
    local process_name="$1"
    
    # Find and kill any remaining processes
    local pids=$(pgrep -f "$process_name" 2>/dev/null || true)
    
    if [ -n "$pids" ]; then
        print_warning "Found stale $process_name processes: $pids"
        
        # Try graceful termination first
        for pid in $pids; do
            kill -TERM "$pid" 2>/dev/null || true
        done
        sleep 2
        
        # Force kill if still running
        pids=$(pgrep -f "$process_name" 2>/dev/null || true)
        if [ -n "$pids" ]; then
            for pid in $pids; do
                kill -9 "$pid" 2>/dev/null || true
            done
            sleep 1
        fi
        
        print_info "Cleaned up stale $process_name processes"
    fi
}

# Check if a port is available
check_port_available() {
    local port="$1"
    local service_name="${2:-unknown}"
    
    if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
       netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
        local process=$(ss -tlnp 2>/dev/null | grep ":${port} " | awk '{print $NF}' || \
                       netstat -tlnp 2>/dev/null | grep ":${port} " | awk '{print $NF}')
        print_error "Port $port is already in use by: $process"
        return 1
    fi
    return 0
}

# Verify that a service is healthy (running and listening on expected port)
verify_service_health() {
    local service_name="$1"
    local expected_port="$2"
    local timeout="${3:-10}"
    local elapsed=0
    
    # First check if service is active
    if ! systemctl is-active --quiet "$service_name" 2>/dev/null; then
        print_error "Service $service_name is not running"
        show_service_logs "$service_name" 20
        return 1
    fi
    
    # If port specified, wait for it to be bound
    if [ -n "$expected_port" ]; then
        while [ $elapsed -lt $timeout ]; do
            if ss -tlnp 2>/dev/null | grep -q ":${expected_port} " || \
               netstat -tlnp 2>/dev/null | grep -q ":${expected_port} "; then
                return 0
            fi
            sleep 1
            ((elapsed++))
        done
        
        print_error "Service $service_name is running but not listening on port $expected_port"
        show_service_logs "$service_name" 20
        return 1
    fi
    
    return 0
}

# Show recent service logs for debugging
show_service_logs() {
    local service_name="$1"
    local lines="${2:-30}"
    
    echo ""
    echo -e "${YELLOW}═══ Recent logs for $service_name ═══${NC}"
    journalctl -u "$service_name" -n "$lines" --no-pager 2>/dev/null || \
        print_warning "Could not retrieve logs for $service_name"
    echo -e "${YELLOW}═══════════════════════════════════════${NC}"
    echo ""
}

# Gracefully stop all BetterDesk services with proper cleanup
graceful_stop_services() {
    print_step "Stopping services gracefully..."
    
    local services=("betterdesk" "rustdesksignal" "rustdeskrelay")
    
    # Stop services in order
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            print_info "Stopping $service..."
            systemctl stop "$service" 2>/dev/null || true
        fi
    done
    
    # Wait for each service to stop
    for service in "${services[@]}"; do
        wait_for_service_stop "$service" 15
    done
    
    # Kill any stale processes
    kill_stale_processes "hbbs"
    kill_stale_processes "hbbr"
    
    # Verify ports are free
    sleep 2
    
    print_success "All services stopped"
}

# Start services with health verification
start_services_with_verification() {
    print_step "Starting services with health verification..."
    
    local has_errors=false
    
    # Check ports before starting
    if ! check_port_available "21116" "hbbs"; then
        print_error "Port 21116 (ID server) is not available"
        has_errors=true
    fi
    
    if ! check_port_available "21117" "hbbr"; then
        print_error "Port 21117 (relay) is not available"
        has_errors=true
    fi
    
    if [ "$has_errors" = true ]; then
        print_error "Cannot start services - ports are in use"
        print_info "Try: sudo lsof -i :21116 and sudo lsof -i :21117 to find conflicts"
        return 1
    fi
    
    # Enable services
    systemctl enable rustdesksignal rustdeskrelay betterdesk 2>/dev/null || true
    
    # Start HBBS first (signal server)
    print_info "Starting rustdesksignal (hbbs)..."
    systemctl start rustdesksignal
    sleep 2
    
    if ! verify_service_health "rustdesksignal" "21116" 10; then
        print_error "Failed to start rustdesksignal"
        return 1
    fi
    print_success "rustdesksignal started and healthy"
    
    # Start HBBR (relay server)
    print_info "Starting rustdeskrelay (hbbr)..."
    systemctl start rustdeskrelay
    sleep 2
    
    if ! verify_service_health "rustdeskrelay" "21117" 10; then
        print_error "Failed to start rustdeskrelay"
        return 1
    fi
    print_success "rustdeskrelay started and healthy"
    
    # Start console
    print_info "Starting betterdesk (web console)..."
    systemctl start betterdesk
    sleep 2
    
    if ! verify_service_health "betterdesk" "5000" 10; then
        print_warning "Web console may not be running correctly"
        # Don't fail for console - it's not critical
    else
        print_success "betterdesk console started and healthy"
    fi
    
    print_success "All services started and verified"
    return 0
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
    CONSOLE_TYPE="none"
    
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
    
    # Detect console type
    if [ -d "$CONSOLE_PATH" ]; then
        if [ -f "$CONSOLE_PATH/server.js" ] || [ -f "$CONSOLE_PATH/package.json" ]; then
            CONSOLE_TYPE="nodejs"
        elif [ -f "$CONSOLE_PATH/app.py" ]; then
            CONSOLE_TYPE="nodejs"  # Flask detected, will be migrated to Node.js
            print_warning "Legacy Flask console detected. It will be migrated to Node.js on update."
        fi
        
        if [ "$CONSOLE_TYPE" != "none" ] && [ "$BINARIES_OK" = true ] && [ "$DATABASE_OK" = true ]; then
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
    
    # Auto-detect Console path and type
    CONSOLE_TYPE="none"
    
    if [ -n "$CONSOLE_PATH" ]; then
        # Check for Node.js console first
        if [ -d "$CONSOLE_PATH" ] && { [ -f "$CONSOLE_PATH/server.js" ] || [ -f "$CONSOLE_PATH/package.json" ]; }; then
            CONSOLE_TYPE="nodejs"
            print_info "Using configured Node.js Console path: $CONSOLE_PATH"
        elif [ -d "$CONSOLE_PATH" ] && [ -f "$CONSOLE_PATH/app.py" ]; then
            CONSOLE_TYPE="nodejs"  # Legacy Flask, will be migrated
            print_warning "Legacy Flask console detected at $CONSOLE_PATH — will be migrated to Node.js"
        else
            print_warning "Configured CONSOLE_PATH ($CONSOLE_PATH) is invalid"
            CONSOLE_PATH=""
        fi
    fi
    
    if [ -z "$CONSOLE_PATH" ]; then
        for path in "${COMMON_CONSOLE_PATHS[@]}"; do
            # Check for Node.js console first
            if [ -d "$path" ] && { [ -f "$path/server.js" ] || [ -f "$path/package.json" ]; }; then
                CONSOLE_PATH="$path"
                CONSOLE_TYPE="nodejs"
                print_success "Detected Node.js Console: $CONSOLE_PATH"
                break
            fi
            # Check for legacy Flask console (will be migrated)
            if [ -d "$path" ] && [ -f "$path/app.py" ]; then
                CONSOLE_PATH="$path"
                CONSOLE_TYPE="nodejs"
                print_warning "Legacy Flask console detected at $CONSOLE_PATH — will be migrated to Node.js"
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
        case "$CONSOLE_TYPE" in
            nodejs) echo -e "  Web Console:  ${GREEN}✓ OK${NC} (Node.js)" ;;
            *) echo -e "  Web Console:  ${GREEN}✓ OK${NC}" ;;
        esac
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
# Binary Verification Functions
#===============================================================================

verify_binary_checksum() {
    local file_path="$1"
    local expected_hash="$2"
    local file_name=$(basename "$file_path")
    
    if [ ! -f "$file_path" ]; then
        print_error "File not found: $file_path"
        return 1
    fi
    
    print_info "Verifying $file_name..."
    local actual_hash
    actual_hash=$(sha256sum "$file_path" | awk '{print toupper($1)}')
    
    if [ "$actual_hash" = "$expected_hash" ]; then
        print_success "$file_name: SHA256 OK"
        return 0
    else
        print_error "$file_name: SHA256 MISMATCH!"
        print_error "  Expected: $expected_hash"
        print_error "  Got:      $actual_hash"
        return 1
    fi
}

verify_binaries() {
    print_step "Verifying BetterDesk binaries..."
    
    local bin_source="$SCRIPT_DIR/hbbs-patch-v2"
    local errors=0
    
    if [ "$SKIP_VERIFY" = true ]; then
        print_warning "Verification skipped (--skip-verify)"
        return 0
    fi
    
    # Verify based on architecture
    case "$ARCH_NAME" in
        x86_64)
            if [ -f "$bin_source/hbbs-linux-x86_64" ]; then
                verify_binary_checksum "$bin_source/hbbs-linux-x86_64" "$HBBS_LINUX_X86_64_SHA256" || ((errors++))
            fi
            if [ -f "$bin_source/hbbr-linux-x86_64" ]; then
                verify_binary_checksum "$bin_source/hbbr-linux-x86_64" "$HBBR_LINUX_X86_64_SHA256" || ((errors++))
            fi
            ;;
        aarch64)
            print_warning "ARM64 binaries - checksum verification not available"
            print_info "Consider building from source for ARM64"
            ;;
        *)
            print_warning "Unknown architecture - checksum verification skipped"
            ;;
    esac
    
    if [ $errors -gt 0 ]; then
        print_error "Binary verification failed! $errors error(s)"
        print_warning "Binaries may be corrupted or outdated."
        if [ "$AUTO_MODE" = false ]; then
            if ! confirm "Continue anyway?"; then
                return 1
            fi
        else
            return 1
        fi
    else
        print_success "All binaries verified"
    fi
    
    return 0
}

#===============================================================================
# Installation Functions
#===============================================================================

install_dependencies() {
    print_step "Installing dependencies..."
    
    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq python3 python3-pip python3-venv sqlite3 curl wget openssl build-essential
    elif command -v dnf &> /dev/null; then
        dnf install -y -q python3 python3-pip sqlite curl wget openssl gcc gcc-c++ make
    elif command -v yum &> /dev/null; then
        yum install -y -q python3 python3-pip sqlite curl wget openssl gcc gcc-c++ make
    elif command -v pacman &> /dev/null; then
        pacman -Sy --noconfirm python python-pip sqlite curl wget openssl base-devel
    else
        print_warning "Unknown package manager. Make sure Python 3 and SQLite are installed."
    fi
    
    print_success "Dependencies installed"
}

#===============================================================================
# Node.js Installation Functions
#===============================================================================

install_nodejs() {
    print_step "Checking Node.js installation..."
    
    # Check if Node.js is already installed and version is sufficient
    if command -v node &> /dev/null; then
        local node_version=$(node --version | sed 's/v//' | cut -d'.' -f1)
        if [ "$node_version" -ge 18 ]; then
            print_success "Node.js v$(node --version) already installed"
            return 0
        else
            print_warning "Node.js version $node_version is too old (need 18+). Upgrading..."
        fi
    fi
    
    print_step "Installing Node.js 20 LTS..."
    
    # Detect OS and install Node.js
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu - use NodeSource
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y -qq nodejs
    elif command -v dnf &> /dev/null; then
        # Fedora/RHEL 8+
        curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
        dnf install -y -q nodejs
    elif command -v yum &> /dev/null; then
        # RHEL/CentOS 7
        curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
        yum install -y -q nodejs
    elif command -v pacman &> /dev/null; then
        # Arch Linux
        pacman -Sy --noconfirm nodejs npm
    elif command -v apk &> /dev/null; then
        # Alpine Linux
        apk add --no-cache nodejs npm
    else
        print_error "Cannot install Node.js automatically. Please install Node.js 18+ manually."
        return 1
    fi
    
    # Verify installation
    if command -v node &> /dev/null; then
        print_success "Node.js $(node --version) installed"
        print_info "npm $(npm --version)"
        return 0
    else
        print_error "Node.js installation failed!"
        return 1
    fi
}

install_nodejs_console() {
    print_step "Installing Node.js Web Console..."
    
    # Install Node.js if not present
    if ! install_nodejs; then
        print_error "Cannot proceed without Node.js"
        return 1
    fi
    
    mkdir -p "$CONSOLE_PATH"
    
    # Check for web-nodejs folder first, then web folder
    local source_folder=""
    if [ -d "$SCRIPT_DIR/web-nodejs" ]; then
        source_folder="$SCRIPT_DIR/web-nodejs"
        print_info "Found Node.js console in web-nodejs/"
    elif [ -d "$SCRIPT_DIR/web" ] && [ -f "$SCRIPT_DIR/web/server.js" ]; then
        source_folder="$SCRIPT_DIR/web"
        print_info "Found Node.js console in web/"
    else
        print_error "Node.js web console not found!"
        print_info "Expected: $SCRIPT_DIR/web-nodejs/ or $SCRIPT_DIR/web/server.js"
        return 1
    fi
    
    # Copy web files
    cp -r "$source_folder/"* "$CONSOLE_PATH/"
    
    # Install npm dependencies
    print_step "Installing npm dependencies..."
    cd "$CONSOLE_PATH"
    
    npm install --production 2>&1 | while read line; do
        echo -ne "\r[npm] $line                    \r"
    done
    echo ""
    
    # Create data directory for databases
    mkdir -p "$CONSOLE_PATH/data"
    
    # Generate admin password for Node.js console
    local nodejs_admin_password
    nodejs_admin_password=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
    
    # Create .env file (always update to ensure correct paths)
    cat > "$CONSOLE_PATH/.env" << EOF
# BetterDesk Node.js Console Configuration
PORT=5000
NODE_ENV=production

# RustDesk paths (critical for key/QR code generation)
RUSTDESK_DIR=$RUSTDESK_PATH
KEYS_PATH=$RUSTDESK_PATH
DB_PATH=$RUSTDESK_PATH/db_v2.sqlite3
PUB_KEY_PATH=$RUSTDESK_PATH/id_ed25519.pub
API_KEY_PATH=$RUSTDESK_PATH/.api_key

# Auth database location
DATA_DIR=$CONSOLE_PATH/data

# HBBS API
HBBS_API_URL=http://localhost:$API_PORT/api

# Default admin credentials (used only on first startup)
DEFAULT_ADMIN_USERNAME=admin
DEFAULT_ADMIN_PASSWORD=$nodejs_admin_password

# Session
SESSION_SECRET=$(openssl rand -hex 32)

# HTTPS (set to true and provide certificate paths to enable)
HTTPS_ENABLED=false
HTTPS_PORT=5443
SSL_CERT_PATH=
SSL_KEY_PATH=
SSL_CA_PATH=
HTTP_REDIRECT_HTTPS=true
EOF
    print_info "Created .env configuration file"
    
    # Save Node.js admin credentials for display
    echo "admin:$nodejs_admin_password" > "$CONSOLE_PATH/data/.admin_credentials"
    chmod 600 "$CONSOLE_PATH/data/.admin_credentials"
    
    # Set permissions
    chown -R root:root "$CONSOLE_PATH"
    chmod -R 755 "$CONSOLE_PATH"
    chmod 600 "$CONSOLE_PATH/.env" 2>/dev/null || true
    
    CONSOLE_TYPE="nodejs"
    print_success "Node.js Web Console installed"
}

install_binaries() {
    print_step "Installing BetterDesk binaries..."
    
    # Ensure architecture is detected
    if [ -z "$ARCH_NAME" ]; then
        detect_architecture
    fi
    
    # Safety: stop services before copying (prevents "Text file busy")
    if systemctl is-active --quiet rustdesksignal 2>/dev/null || \
       systemctl is-active --quiet rustdeskrelay 2>/dev/null; then
        print_info "Stopping running services before binary installation..."
        graceful_stop_services
    fi
    
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
        print_info "Expected: $SCRIPT_DIR/hbbs-patch-v2/hbbs-linux-$ARCH_NAME"
        print_info "Architecture detected: $ARCH_NAME"
        print_info "Run 'Build binaries' option or download prebuilt files."
        return 1
    fi
    
    # Verify binaries before installation
    if ! verify_binaries; then
        print_error "Aborting installation due to verification failure"
        return 1
    fi
    
    # Copy binaries
    if [ -f "$bin_source/hbbs-linux-$ARCH_NAME" ]; then
        cp "$bin_source/hbbs-linux-$ARCH_NAME" "$RUSTDESK_PATH/hbbs"
        print_success "Installed hbbs (signal server)"
    elif [ -f "$bin_source/hbbs" ]; then
        cp "$bin_source/hbbs" "$RUSTDESK_PATH/hbbs"
    fi
    
    if [ -f "$bin_source/hbbr-linux-$ARCH_NAME" ]; then
        cp "$bin_source/hbbr-linux-$ARCH_NAME" "$RUSTDESK_PATH/hbbr"
        print_success "Installed hbbr (relay server)"
    elif [ -f "$bin_source/hbbr" ]; then
        cp "$bin_source/hbbr" "$RUSTDESK_PATH/hbbr"
    fi
    
    chmod +x "$RUSTDESK_PATH/hbbs" "$RUSTDESK_PATH/hbbr"
    
    print_success "BetterDesk binaries v$VERSION installed"
}

install_flask_console() {
    print_step "Installing Flask (Python) Web Console..."
    
    mkdir -p "$CONSOLE_PATH"
    
    # Copy web files
    if [ -d "$SCRIPT_DIR/web" ] && [ -f "$SCRIPT_DIR/web/app.py" ]; then
        cp -r "$SCRIPT_DIR/web/"* "$CONSOLE_PATH/"
    else
        print_error "Flask web/ folder not found in project!"
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
    
    CONSOLE_TYPE="flask"
    print_success "Flask Web Console installed"
}

install_console() {
    # Always install Node.js console (Flask removed in v2.3.0)
    local console_choice="nodejs"
    
    print_info "Installing Node.js web console..."
    
    # Check for existing Flask console and migrate
    if [ -d "$CONSOLE_PATH" ]; then
        if [ -f "$CONSOLE_PATH/app.py" ] && ! [ -f "$CONSOLE_PATH/server.js" ]; then
            print_warning "Legacy Flask console detected at $CONSOLE_PATH"
            if [ "$AUTO_MODE" = false ]; then
                if confirm "Migrate from Flask to Node.js?"; then
                    migrate_console "flask" "nodejs"
                else
                    print_info "Flask is deprecated. Installing Node.js alongside..."
                fi
            else
                print_info "Auto mode: Migrating from Flask to Node.js"
                migrate_console "flask" "nodejs"
            fi
        fi
    fi
    
    install_nodejs_console
}

migrate_console() {
    local from_type="$1"
    local to_type="$2"
    
    print_step "Migrating from $from_type to $to_type..."
    
    # Backup existing console
    local backup_path="$BACKUP_DIR/console_${from_type}_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_path"
    
    # Backup user database (auth.db) if exists
    if [ -f "$CONSOLE_PATH/data/auth.db" ]; then
        cp "$CONSOLE_PATH/data/auth.db" "$backup_path/"
        print_info "Backed up user database"
    fi
    
    # Backup .env if exists
    if [ -f "$CONSOLE_PATH/.env" ]; then
        cp "$CONSOLE_PATH/.env" "$backup_path/"
    fi
    
    # Stop old console service
    systemctl stop betterdesk 2>/dev/null || true
    
    # Remove old console files but preserve data
    rm -rf "$CONSOLE_PATH/venv" 2>/dev/null || true
    rm -rf "$CONSOLE_PATH/node_modules" 2>/dev/null || true
    rm -f "$CONSOLE_PATH/app.py" "$CONSOLE_PATH/server.js" 2>/dev/null || true
    
    print_success "Old $from_type console backed up to $backup_path"
}

setup_services() {
    print_step "Configuring systemd services..."
    
    # Get server IP
    local server_ip
    server_ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "127.0.0.1")
    
    print_info "Server IP: $server_ip"
    print_info "API Port: $API_PORT"
    
    # HBBS service (Signal Server with HTTP API)
    cat > /etc/systemd/system/rustdesksignal.service << EOF
[Unit]
Description=BetterDesk Signal Server v$VERSION
Documentation=https://github.com/UNITRONIX/Rustdesk-FreeConsole
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$RUSTDESK_PATH
ExecStart=$RUSTDESK_PATH/hbbs -r $server_ip -k _ --api-port $API_PORT
Restart=always
RestartSec=5
LimitNOFILE=1000000
Environment=RUST_BACKTRACE=1

[Install]
WantedBy=multi-user.target
EOF

    # HBBR service (Relay Server)
    cat > /etc/systemd/system/rustdeskrelay.service << EOF
[Unit]
Description=BetterDesk Relay Server v$VERSION
Documentation=https://github.com/UNITRONIX/Rustdesk-FreeConsole
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$RUSTDESK_PATH
ExecStart=$RUSTDESK_PATH/hbbr -k _
Restart=always
RestartSec=5
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

    # Console service (Web Interface) - depends on console type
    if [ "$CONSOLE_TYPE" = "nodejs" ]; then
        cat > /etc/systemd/system/betterdesk.service << EOF
[Unit]
Description=BetterDesk Web Console (Node.js)
Documentation=https://github.com/UNITRONIX/Rustdesk-FreeConsole
After=network.target rustdesksignal.service

[Service]
Type=simple
User=root
WorkingDirectory=$CONSOLE_PATH
EnvironmentFile=-$CONSOLE_PATH/.env
ExecStart=/usr/bin/node server.js
Environment=NODE_ENV=production
Environment=RUSTDESK_DIR=$RUSTDESK_PATH
Environment=KEYS_PATH=$RUSTDESK_PATH
Environment=DATA_DIR=$CONSOLE_PATH/data
Environment=DB_PATH=$RUSTDESK_PATH/db_v2.sqlite3
Environment=HBBS_API_URL=http://localhost:$API_PORT/api
Environment=PORT=5000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        print_info "Created Node.js console service"
    fi

    systemctl daemon-reload
    
    print_success "Systemd services configured"
    print_info "Services: rustdesksignal, rustdeskrelay, betterdesk"
}

run_migrations() {
    print_step "Running database migrations..."
    
    if [ -d "$SCRIPT_DIR/migrations" ]; then
        cd "$SCRIPT_DIR/migrations"
        
        # Export auto mode flag for migration scripts
        if [ "$AUTO_MODE" = true ]; then
            export BETTERDESK_AUTO=1
        fi
        
        for migration in v*.py; do
            if [ -f "$migration" ]; then
                print_info "Migration: $migration"
                # Pass database path as argument
                python3 "$migration" "$DB_PATH" 2>&1 || {
                    print_warning "Migration $migration returned non-zero exit code (may already be applied)"
                }
            fi
        done
        
        unset BETTERDESK_AUTO
    fi
    
    print_success "Migrations completed"
}

create_admin_user() {
    print_step "Creating admin user..."
    
    # Node.js console only (Flask removed in v2.3.0)
    if [ ! -f "$CONSOLE_PATH/server.js" ]; then
        print_warning "No Node.js console detected, skipping admin creation"
        return
    fi
    
    # Node.js console - admin is created automatically on startup
    # Read the password saved during install_nodejs_console
    local creds_file="$CONSOLE_PATH/data/.admin_credentials"
    
    if [ -f "$creds_file" ]; then
        local admin_password
        admin_password=$(cat "$creds_file" | cut -d':' -f2)
        
        echo ""
        echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║            PANEL LOGIN CREDENTIALS                    ║${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║  Login:    ${WHITE}admin${GREEN}                                     ║${NC}"
        echo -e "${GREEN}║  Password: ${WHITE}${admin_password}${GREEN}                         ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # Also save to main RustDesk path for consistency
        echo "admin:$admin_password" > "$RUSTDESK_PATH/.admin_credentials"
        chmod 600 "$RUSTDESK_PATH/.admin_credentials"
        
        print_info "Credentials saved in: $RUSTDESK_PATH/.admin_credentials"
    else
        print_warning "No Node.js admin credentials found"
        print_info "Default credentials: admin / admin"
        print_info "Please change password after first login!"
    fi
}

start_services() {
    # Use enhanced start function with health verification
    start_services_with_verification
}

do_install() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ FRESH INSTALLATION ══════════${NC}"
    echo ""
    
    detect_installation
    
    if [ "$INSTALL_STATUS" = "complete" ]; then
        print_warning "BetterDesk is already installed!"
        if [ "$AUTO_MODE" = false ]; then
            if ! confirm "Do you want to reinstall?"; then
                return
            fi
        fi
        do_backup_silent
    fi
    
    echo ""
    print_info "Starting BetterDesk Console v$VERSION installation..."
    echo ""
    
    # Stop services if running (prevents "Text file busy" error)
    graceful_stop_services
    
    install_dependencies
    detect_architecture
    install_binaries || { print_error "Binary installation failed"; return 1; }
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
    echo -e "${CYAN}║              INSTALLATION INFO                             ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║  Panel Web:     ${WHITE}http://$server_ip:5000${CYAN}                        ║${NC}"
    echo -e "${CYAN}║  API Port:      ${WHITE}$API_PORT${CYAN}                                     ║${NC}"
    echo -e "${CYAN}║  Server ID:     ${WHITE}$server_ip${CYAN}                                    ║${NC}"
    echo -e "${CYAN}║  Key:           ${WHITE}${public_key:0:20}...${CYAN}                          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    
    if [ "$AUTO_MODE" = false ]; then
        press_enter
    fi
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
    
    # Stop services gracefully
    graceful_stop_services
    
    detect_architecture
    install_binaries
    install_console
    run_migrations
    
    # Update systemd services with latest configuration
    setup_services
    
    # Ensure admin user exists (especially for Node.js console migration)
    create_admin_user
    
    # Start services with verification
    start_services_with_verification
    
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
    print_step "Repairing binaries (enhanced v2.1.2)..."
    
    detect_architecture
    
    # Verify we have binaries to install
    local bin_source="$SCRIPT_DIR/hbbs-patch-v2"
    if [ ! -f "$bin_source/hbbs-linux-$ARCH_NAME" ] || [ ! -f "$bin_source/hbbr-linux-$ARCH_NAME" ]; then
        print_error "BetterDesk binaries not found in $bin_source/"
        print_info "Expected: hbbs-linux-$ARCH_NAME and hbbr-linux-$ARCH_NAME"
        return 1
    fi
    
    # Create backup before repair
    if [ -f "$RUSTDESK_PATH/hbbs" ]; then
        cp "$RUSTDESK_PATH/hbbs" "$RUSTDESK_PATH/hbbs.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    fi
    if [ -f "$RUSTDESK_PATH/hbbr" ]; then
        cp "$RUSTDESK_PATH/hbbr" "$RUSTDESK_PATH/hbbr.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    fi
    
    # Gracefully stop all services
    graceful_stop_services
    
    # Extra safety: wait and verify files are not in use
    sleep 2
    
    # Check if binaries are still locked (Text file busy prevention)
    if lsof "$RUSTDESK_PATH/hbbs" 2>/dev/null | grep -q .; then
        print_error "hbbs binary is still in use!"
        kill_stale_processes "hbbs"
        sleep 2
    fi
    
    if lsof "$RUSTDESK_PATH/hbbr" 2>/dev/null | grep -q .; then
        print_error "hbbr binary is still in use!"
        kill_stale_processes "hbbr"
        sleep 2
    fi
    
    # Now install binaries
    if ! install_binaries; then
        print_error "Failed to install binaries"
        return 1
    fi
    
    # Start services with health verification
    if ! start_services_with_verification; then
        print_error "Services failed to start after binary repair"
        print_info "Check logs above for details"
        return 1
    fi
    
    print_success "Binaries repaired and services verified!"
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
    print_step "Repairing systemd services (enhanced v2.1.2)..."
    
    # Stop services gracefully first
    graceful_stop_services
    
    # Backup existing service files
    for svc in rustdesksignal rustdeskrelay betterdesk; do
        if [ -f "/etc/systemd/system/${svc}.service" ]; then
            cp "/etc/systemd/system/${svc}.service" "/etc/systemd/system/${svc}.service.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        fi
    done
    
    # Verify paths exist
    if [ ! -f "$RUSTDESK_PATH/hbbs" ]; then
        print_error "hbbs binary not found at $RUSTDESK_PATH/hbbs"
        print_info "Run 'Repair binaries' first"
        return 1
    fi
    
    if [ ! -f "$RUSTDESK_PATH/hbbr" ]; then
        print_error "hbbr binary not found at $RUSTDESK_PATH/hbbr"
        print_info "Run 'Repair binaries' first"
        return 1
    fi
    
    # Regenerate service files
    setup_services
    
    # Start services with health verification
    if ! start_services_with_verification; then
        print_error "Services failed to start after repair"
        print_info "Restoring backup service files..."
        
        for svc in rustdesksignal rustdeskrelay betterdesk; do
            backup_file=$(ls -t /etc/systemd/system/${svc}.service.backup.* 2>/dev/null | head -1)
            if [ -n "$backup_file" ]; then
                cp "$backup_file" "/etc/systemd/system/${svc}.service"
            fi
        done
        systemctl daemon-reload
        
        return 1
    fi
    
    print_success "Services repaired and verified!"
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
    
    # Refresh detection
    auto_detect_paths
    
    if [ "$CONSOLE_TYPE" = "none" ]; then
        print_error "No console installation detected!"
        press_enter
        return
    fi
    
    echo -e "Detected console type: ${CYAN}${CONSOLE_TYPE}${NC}"
    echo ""
    
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
    
    local success=false
    
    if [ "$CONSOLE_TYPE" = "nodejs" ]; then
        # Node.js console - update auth.db
        local auth_db_path="$CONSOLE_PATH/data/auth.db"
        
        # Also check in RUSTDESK_PATH for auth.db (alternative location)
        if [ ! -f "$auth_db_path" ]; then
            auth_db_path="$RUSTDESK_PATH/auth.db"
        fi
        
        print_info "Auth database: $auth_db_path"
        
        # Use Node.js reset-password script if available
        local reset_script="$CONSOLE_PATH/scripts/reset-password.js"
        if [ -f "$reset_script" ] && command -v node &> /dev/null; then
            print_info "Using reset-password.js script..."
            pushd "$CONSOLE_PATH" > /dev/null
            DATA_DIR="$(dirname "$auth_db_path")" node "$reset_script" "$new_password" admin
            if [ $? -eq 0 ]; then
                success=true
            fi
            popd > /dev/null
        fi
        
        # Fallback: use Python with bcrypt to update auth.db directly
        if [ "$success" = "false" ]; then
            print_info "Using direct database update..."
            python3 << EOF
import sqlite3
import bcrypt
import os

auth_db_path = '$auth_db_path'

# Create parent directory if needed
os.makedirs(os.path.dirname(auth_db_path), exist_ok=True)

conn = sqlite3.connect(auth_db_path)
cursor = conn.cursor()

# Ensure table exists (for fresh installations)
cursor.execute('''CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT DEFAULT 'admin',
    created_at TEXT DEFAULT (datetime('now')),
    last_login TEXT
)''')

new_password = '$new_password'
password_hash = bcrypt.hashpw(new_password.encode(), bcrypt.gensalt(12)).decode()

cursor.execute("UPDATE users SET password_hash = ? WHERE username = 'admin'", (password_hash,))

if cursor.rowcount == 0:
    cursor.execute('''INSERT INTO users (username, password_hash, role)
                      VALUES ('admin', ?, 'admin')''', (password_hash,))

conn.commit()
conn.close()
print("Password updated successfully")
EOF
            if [ $? -eq 0 ]; then
                success=true
            fi
        fi
    fi

    echo ""
    if [ "$success" = "true" ]; then
        echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║              NEW LOGIN CREDENTIALS                       ║${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║  Login:    ${WHITE}admin${GREEN}                                     ║${NC}"
        echo -e "${GREEN}║  Password: ${WHITE}${new_password}${GREEN}                         ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
        
        # Save credentials
        echo "admin:$new_password" > "$RUSTDESK_PATH/.admin_credentials"
        chmod 600 "$RUSTDESK_PATH/.admin_credentials"
    else
        print_error "Failed to reset password!"
        print_info "Make sure Python with bcrypt is installed, or Node.js for Node.js console"
    fi
    
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
# SSL Certificate Configuration
#===============================================================================

do_configure_ssl() {
    print_header
    echo -e "${WHITE}${BOLD}══════════ SSL CERTIFICATE CONFIGURATION ══════════${NC}"
    echo ""
    
    if [ ! -f "$CONSOLE_PATH/.env" ]; then
        print_error "Node.js console .env not found at $CONSOLE_PATH/.env"
        print_info "Please install BetterDesk first (option 1)"
        press_enter
        return
    fi
    
    echo -e "  ${WHITE}Configure SSL/TLS certificates for BetterDesk Console.${NC}"
    echo -e "  ${WHITE}This enables HTTPS for both the admin panel and the RustDesk Client API.${NC}"
    echo ""
    echo -e "  ${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}1.${NC} Let's Encrypt (automatic, requires domain name + port 80)"
    echo -e "  ${GREEN}2.${NC} Custom certificate (provide your own cert + key files)"
    echo -e "  ${GREEN}3.${NC} Self-signed certificate (for testing only)"
    echo -e "  ${RED}4.${NC} Disable SSL (revert to HTTP)"
    echo ""
    
    read -p "Choice [1]: " ssl_choice
    
    case "${ssl_choice:-1}" in
        1)
            # Let's Encrypt
            echo ""
            read -p "Enter your domain name (e.g., betterdesk.example.com): " domain
            if [ -z "$domain" ]; then
                print_error "Domain name required for Let's Encrypt"
                press_enter
                return
            fi
            
            # Install certbot if needed
            if ! command -v certbot &> /dev/null; then
                print_step "Installing certbot..."
                if command -v apt-get &> /dev/null; then
                    apt-get install -y certbot
                elif command -v dnf &> /dev/null; then
                    dnf install -y certbot
                elif command -v yum &> /dev/null; then
                    yum install -y certbot
                elif command -v pacman &> /dev/null; then
                    pacman -Sy --noconfirm certbot
                else
                    print_error "Could not install certbot. Please install it manually."
                    press_enter
                    return
                fi
            fi
            
            print_step "Requesting certificate for $domain..."
            print_info "Port 80 must be accessible from the internet"
            
            certbot certonly --standalone --preferred-challenges http \
                -d "$domain" --non-interactive --agree-tos \
                --email "admin@$domain" 2>&1 || {
                    print_error "Certificate request failed. Make sure port 80 is open and the domain points to this server."
                    press_enter
                    return
                }
            
            local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
            local key_path="/etc/letsencrypt/live/$domain/privkey.pem"
            
            # Update .env
            sed -i "s|^HTTPS_ENABLED=.*|HTTPS_ENABLED=true|" "$CONSOLE_PATH/.env"
            sed -i "s|^SSL_CERT_PATH=.*|SSL_CERT_PATH=$cert_path|" "$CONSOLE_PATH/.env"
            sed -i "s|^SSL_KEY_PATH=.*|SSL_KEY_PATH=$key_path|" "$CONSOLE_PATH/.env"
            sed -i "s|^HTTP_REDIRECT_HTTPS=.*|HTTP_REDIRECT_HTTPS=true|" "$CONSOLE_PATH/.env"
            
            # Setup auto-renewal
            if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
                (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl restart betterdesk'") | crontab -
                print_info "Auto-renewal cron job added (daily at 3:00 AM)"
            fi
            
            print_success "Let's Encrypt certificate configured for $domain"
            ;;
        2)
            # Custom certificate
            echo ""
            read -p "Path to certificate file (PEM): " cert_path
            read -p "Path to private key file (PEM): " key_path
            read -p "Path to CA bundle (optional, press Enter to skip): " ca_path
            
            if [ ! -f "$cert_path" ]; then
                print_error "Certificate file not found: $cert_path"
                press_enter
                return
            fi
            if [ ! -f "$key_path" ]; then
                print_error "Key file not found: $key_path"
                press_enter
                return
            fi
            
            sed -i "s|^HTTPS_ENABLED=.*|HTTPS_ENABLED=true|" "$CONSOLE_PATH/.env"
            sed -i "s|^SSL_CERT_PATH=.*|SSL_CERT_PATH=$cert_path|" "$CONSOLE_PATH/.env"
            sed -i "s|^SSL_KEY_PATH=.*|SSL_KEY_PATH=$key_path|" "$CONSOLE_PATH/.env"
            if [ -n "$ca_path" ] && [ -f "$ca_path" ]; then
                sed -i "s|^SSL_CA_PATH=.*|SSL_CA_PATH=$ca_path|" "$CONSOLE_PATH/.env"
            fi
            sed -i "s|^HTTP_REDIRECT_HTTPS=.*|HTTP_REDIRECT_HTTPS=true|" "$CONSOLE_PATH/.env"
            
            print_success "Custom SSL certificate configured"
            ;;
        3)
            # Self-signed
            local ssl_dir="$CONSOLE_PATH/ssl"
            mkdir -p "$ssl_dir"
            
            print_step "Generating self-signed certificate..."
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$ssl_dir/selfsigned.key" \
                -out "$ssl_dir/selfsigned.crt" \
                -subj "/CN=localhost/O=BetterDesk/C=PL" 2>&1
            
            chmod 600 "$ssl_dir/selfsigned.key"
            
            sed -i "s|^HTTPS_ENABLED=.*|HTTPS_ENABLED=true|" "$CONSOLE_PATH/.env"
            sed -i "s|^SSL_CERT_PATH=.*|SSL_CERT_PATH=$ssl_dir/selfsigned.crt|" "$CONSOLE_PATH/.env"
            sed -i "s|^SSL_KEY_PATH=.*|SSL_KEY_PATH=$ssl_dir/selfsigned.key|" "$CONSOLE_PATH/.env"
            sed -i "s|^HTTP_REDIRECT_HTTPS=.*|HTTP_REDIRECT_HTTPS=true|" "$CONSOLE_PATH/.env"
            
            print_success "Self-signed certificate generated"
            print_warning "Browsers will show security warning. Use Let's Encrypt for production."
            ;;
        4)
            # Disable SSL
            sed -i "s|^HTTPS_ENABLED=.*|HTTPS_ENABLED=false|" "$CONSOLE_PATH/.env"
            sed -i "s|^SSL_CERT_PATH=.*|SSL_CERT_PATH=|" "$CONSOLE_PATH/.env"
            sed -i "s|^SSL_KEY_PATH=.*|SSL_KEY_PATH=|" "$CONSOLE_PATH/.env"
            sed -i "s|^HTTP_REDIRECT_HTTPS=.*|HTTP_REDIRECT_HTTPS=false|" "$CONSOLE_PATH/.env"
            
            print_success "SSL disabled. Running in HTTP mode."
            ;;
        *)
            print_warning "Invalid option"
            press_enter
            return
            ;;
    esac
    
    echo ""
    if confirm "Restart BetterDesk to apply changes?"; then
        systemctl restart betterdesk 2>/dev/null || true
        print_success "BetterDesk restarted"
    fi
    
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
    echo "  C. 🔒 Configure SSL certificates"
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
    
    # Auto mode - run installation directly
    if [ "$AUTO_MODE" = true ]; then
        print_info "Running in AUTO mode..."
        do_install
        exit $?
    fi
    
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
            [Cc]) do_configure_ssl ;;
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
