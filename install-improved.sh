#!/bin/bash
# =============================================================================
# BetterDesk Console - Universal Installation Script v1.5.4
# =============================================================================
# This script can install fresh or update existing BetterDesk Console
# It automatically detects existing installations and acts accordingly.
#
# Features:
# - Fresh installation support
# - Update from any older version
# - Database migrations (adds missing columns)
# - Service management
# - Backup creation
# - Binary updates (v2 with HTTP API on port 21120)
#
# Binary Priority:
#   1. hbbs-patch-v2/hbbs-linux-x86_64 (pre-compiled, recommended)
#   2. hbbs-patch-v2/target/release/hbbs (locally compiled)
#   3. hbbs-patch/bin-with-api/hbbs-v8-api (old v1, deprecated)
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
TARGET_VERSION="1.5.4"
BACKUP_DIR="/opt/BetterDeskConsole_backup_$(date +%Y%m%d_%H%M%S)"

# Possible installation paths
CONSOLE_PATHS=(
    "/opt/BetterDeskConsole"
    "/opt/betterdesk"
    "/var/www/betterdesk"
    "$HOME/BetterDeskConsole"
)

RUSTDESK_PATHS=(
    "/opt/rustdesk"
    "/var/lib/rustdesk"
    "/root/.rustdesk"
    "$HOME/.rustdesk"
    # Docker common paths
    "/opt/rustdesk-server"
    "/data"
    "/data/rustdesk"
    "/app/data"
    "/var/lib/docker/volumes/rustdesk_data/_data"
    "/home/*/rustdesk-server"
    "/home/*/rustdesk"
)

DB_NAMES=(
    "db_v2.sqlite3"
    "db.sqlite3"
    "rustdesk.db"
)

# Found paths (will be detected)
CONSOLE_PATH=""
RUSTDESK_PATH=""
DB_PATH=""
CURRENT_VERSION=""

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
# Detection Functions
# =============================================================================

detect_console_path() {
    print_info "Searching for BetterDesk Console installation..."
    
    for path in "${CONSOLE_PATHS[@]}"; do
        # Check for app.py (current naming) or auth.py (part of auth system)
        if [ -d "$path" ] && [ -f "$path/app.py" -o -f "$path/auth.py" ]; then
            CONSOLE_PATH="$path"
            print_success "Found console at: $CONSOLE_PATH"
            return 0
        fi
    done
    
    # Try to find by service
    if systemctl is-enabled betterdesk.service &>/dev/null 2>&1; then
        local service_path=$(systemctl show betterdesk.service -p ExecStart 2>/dev/null | grep -oP '/opt/[^/]+' | head -1)
        if [ -n "$service_path" ] && [ -d "$service_path" ]; then
            CONSOLE_PATH="$service_path"
            print_success "Found console via service: $CONSOLE_PATH"
            return 0
        fi
    fi
    
    return 1
}

detect_rustdesk_path() {
    print_info "Searching for RustDesk installation..."
    
    # Expand glob patterns for home directories
    local expanded_paths=()
    for path in "${RUSTDESK_PATHS[@]}"; do
        # Expand globs
        for expanded in $path; do
            if [ -d "$expanded" ]; then
                expanded_paths+=("$expanded")
            fi
        done
    done
    
    for path in "${expanded_paths[@]}"; do
        if [ -d "$path" ]; then
            # Check for hbbs binary or database
            if [ -f "$path/hbbs" ] || [ -f "$path/hbbs-v8-api" ] || ls "$path"/*.sqlite3 &>/dev/null 2>&1; then
                RUSTDESK_PATH="$path"
                print_success "Found RustDesk at: $RUSTDESK_PATH"
                return 0
            fi
        fi
    done
    
    # Also try to find database files anywhere common
    print_info "Searching for RustDesk database..."
    for db in "${DB_NAMES[@]}"; do
        local found=$(find /opt /var /home /data -name "$db" -type f 2>/dev/null | head -1)
        if [ -n "$found" ]; then
            RUSTDESK_PATH=$(dirname "$found")
            print_success "Found RustDesk via database at: $RUSTDESK_PATH"
            return 0
        fi
    done
    
    return 1
}

prompt_rustdesk_path() {
    """Prompt user for RustDesk path if not found"""
    print_warning "RustDesk installation not found automatically."
    echo ""
    echo "Please enter the path to your RustDesk data directory"
    echo "(where db_v2.sqlite3 or hbbs is located):"
    echo ""
    read -p "RustDesk path: " user_path
    
    if [ -d "$user_path" ]; then
        RUSTDESK_PATH="$user_path"
        print_success "Using user-provided path: $RUSTDESK_PATH"
        return 0
    else
        print_error "Path does not exist: $user_path"
        return 1
    fi
}

detect_database() {
    print_info "Searching for database..."
    
    # First check RUSTDESK_PATH
    if [ -n "$RUSTDESK_PATH" ]; then
        for db in "${DB_NAMES[@]}"; do
            if [ -f "$RUSTDESK_PATH/$db" ]; then
                DB_PATH="$RUSTDESK_PATH/$db"
                print_success "Found database: $DB_PATH"
                return 0
            fi
        done
    fi
    
    # Check common locations
    for path in "${RUSTDESK_PATHS[@]}"; do
        for db in "${DB_NAMES[@]}"; do
            if [ -f "$path/$db" ]; then
                DB_PATH="$path/$db"
                print_success "Found database: $DB_PATH"
                return 0
            fi
        done
    done
    
    return 1
}

detect_current_version() {
    print_info "Detecting current version..."
    
    # Check VERSION file in console path (primary method)
    if [ -f "$CONSOLE_PATH/VERSION" ]; then
        CURRENT_VERSION=$(head -1 "$CONSOLE_PATH/VERSION" | tr -d 'v' | tr -d ' ')
        print_success "Current version: $CURRENT_VERSION"
        return 0
    fi
    
    # Check app.py for version string
    if [ -f "$CONSOLE_PATH/app.py" ]; then
        local version=$(grep -oP "VERSION\s*=\s*['\"]v?\K[0-9.]+" "$CONSOLE_PATH/app.py" 2>/dev/null | head -1)
        if [ -n "$version" ]; then
            CURRENT_VERSION="$version"
            print_success "Detected version from app: $CURRENT_VERSION"
            return 0
        fi
    fi
    
    # Check for presence of key files to estimate version
    if [ -f "$CONSOLE_PATH/auth.py" ] && [ -f "$CONSOLE_PATH/static/script.js" ]; then
        CURRENT_VERSION="1.5.0"
    elif [ -f "$CONSOLE_PATH/auth.py" ]; then
        CURRENT_VERSION="1.4.0"
    else
        CURRENT_VERSION="1.0.0"
    fi
    
    print_warning "Estimated version: $CURRENT_VERSION"
    return 0
}

# =============================================================================
# Backup Functions
# =============================================================================

create_backup() {
    print_header "Creating Backup"
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup console
    if [ -d "$CONSOLE_PATH" ]; then
        print_info "Backing up console files..."
        cp -r "$CONSOLE_PATH" "$BACKUP_DIR/console/"
        print_success "Console backed up"
    fi
    
    # Backup database
    if [ -f "$DB_PATH" ]; then
        print_info "Backing up database..."
        cp "$DB_PATH" "$BACKUP_DIR/database.sqlite3"
        print_success "Database backed up"
    fi
    
    # Backup API key
    if [ -f "$RUSTDESK_PATH/.api_key" ]; then
        cp "$RUSTDESK_PATH/.api_key" "$BACKUP_DIR/"
        print_success "API key backed up"
    fi
    
    print_success "Backup created at: $BACKUP_DIR"
}

# =============================================================================
# Python Dependencies Installation
# =============================================================================

install_python_dependencies() {
    print_info "Installing Python dependencies..."
    
    local PACKAGES="bcrypt markupsafe flask flask-wtf flask-limiter"
    local installed=false
    
    # Method 1: Try with --break-system-packages (Debian 12+, Ubuntu 23.04+)
    if ! $installed; then
        if pip3 install $PACKAGES --break-system-packages 2>/dev/null; then
            print_success "Dependencies installed with --break-system-packages"
            installed=true
        fi
    fi
    
    # Method 2: Try with pipx (if available)
    if ! $installed && command -v pipx &>/dev/null; then
        print_info "Trying pipx..."
        for pkg in $PACKAGES; do
            pipx install $pkg 2>/dev/null || true
        done
        # pipx is for CLI tools, not libraries - skip this method
    fi
    
    # Method 3: Try creating a virtual environment
    if ! $installed; then
        print_info "Trying virtual environment..."
        if python3 -m venv /opt/BetterDeskConsole/venv 2>/dev/null; then
            if /opt/BetterDeskConsole/venv/bin/pip install $PACKAGES 2>/dev/null; then
                print_success "Dependencies installed in virtual environment"
                installed=true
                
                # Update service file to use venv
                if [ -f "/etc/systemd/system/betterdesk.service" ]; then
                    sed -i 's|ExecStart=/usr/bin/python3|ExecStart=/opt/BetterDeskConsole/venv/bin/python|' /etc/systemd/system/betterdesk.service
                    systemctl daemon-reload
                    print_success "Updated service to use virtual environment"
                fi
            fi
        fi
    fi
    
    # Method 4: Try with --user flag
    if ! $installed; then
        if pip3 install $PACKAGES --user 2>/dev/null; then
            print_success "Dependencies installed with --user"
            installed=true
        fi
    fi
    
    # Method 5: Try normal install (older systems)
    if ! $installed; then
        if pip3 install $PACKAGES 2>/dev/null; then
            print_success "Dependencies installed normally"
            installed=true
        fi
    fi
    
    # Method 6: Try apt packages as fallback
    if ! $installed; then
        print_info "Trying system packages..."
        if apt-get update -qq && apt-get install -y python3-flask python3-bcrypt 2>/dev/null; then
            print_success "Some dependencies installed via apt"
            # Still try pip for the rest
            pip3 install flask-wtf flask-limiter markupsafe --break-system-packages 2>/dev/null || true
            installed=true
        fi
    fi
    
    if ! $installed; then
        print_warning "Could not install Python packages automatically"
        echo ""
        print_info "Please install manually using one of these methods:"
        echo ""
        echo "  Option 1 (Debian 12+/Ubuntu 23.04+):"
        echo "    pip3 install --break-system-packages bcrypt flask flask-wtf flask-limiter markupsafe"
        echo ""
        echo "  Option 2 (Virtual environment - recommended):"
        echo "    python3 -m venv /opt/BetterDeskConsole/venv"
        echo "    /opt/BetterDeskConsole/venv/bin/pip install bcrypt flask flask-wtf flask-limiter markupsafe"
        echo "    # Then update /etc/systemd/system/betterdesk.service to use:"
        echo "    # ExecStart=/opt/BetterDeskConsole/venv/bin/python /opt/BetterDeskConsole/app.py"
        echo ""
        echo "  Option 3 (System packages):"
        echo "    apt install python3-flask python3-bcrypt python3-pip"
        echo "    pip3 install --break-system-packages flask-wtf flask-limiter"
        echo ""
    fi
    
    # Verify installation
    print_info "Verifying Python dependencies..."
    local missing=""
    python3 -c "import flask" 2>/dev/null || missing="$missing flask"
    python3 -c "import bcrypt" 2>/dev/null || missing="$missing bcrypt"
    python3 -c "import flask_wtf" 2>/dev/null || missing="$missing flask-wtf"
    python3 -c "import flask_limiter" 2>/dev/null || missing="$missing flask-limiter"
    
    if [ -z "$missing" ]; then
        print_success "All Python dependencies verified"
    else
        print_warning "Missing packages:$missing"
    fi
}

# =============================================================================
# Database Migration
# =============================================================================

run_database_migration() {
    print_header "Running Database Migration"
    
    if [ ! -f "$DB_PATH" ]; then
        print_error "Database not found at $DB_PATH"
        return 1
    fi
    
    print_info "Checking database schema..."
    
    # Check and add peer table columns required by BetterDesk
    print_info "Checking peer table columns..."
    
    # last_online column
    if ! sqlite3 "$DB_PATH" "PRAGMA table_info(peer);" | grep -q "last_online"; then
        print_info "Adding last_online column..."
        sqlite3 "$DB_PATH" "ALTER TABLE peer ADD COLUMN last_online TEXT;"
        print_success "Added last_online column"
    else
        print_success "last_online column already exists"
    fi
    
    # is_deleted column
    if ! sqlite3 "$DB_PATH" "PRAGMA table_info(peer);" | grep -q "is_deleted"; then
        print_info "Adding is_deleted column..."
        sqlite3 "$DB_PATH" "ALTER TABLE peer ADD COLUMN is_deleted INTEGER DEFAULT 0;"
        print_success "Added is_deleted column"
    else
        print_success "is_deleted column already exists"
    fi
    
    # deleted_at column
    if ! sqlite3 "$DB_PATH" "PRAGMA table_info(peer);" | grep -q "deleted_at"; then
        print_info "Adding deleted_at column..."
        sqlite3 "$DB_PATH" "ALTER TABLE peer ADD COLUMN deleted_at INTEGER;"
        print_success "Added deleted_at column"
    else
        print_success "deleted_at column already exists"
    fi
    
    # updated_at column (required for device updates)
    if ! sqlite3 "$DB_PATH" "PRAGMA table_info(peer);" | grep -q "updated_at"; then
        print_info "Adding updated_at column..."
        sqlite3 "$DB_PATH" "ALTER TABLE peer ADD COLUMN updated_at INTEGER;"
        print_success "Added updated_at column"
    else
        print_success "updated_at column already exists"
    fi
    
    # Ban-related columns
    if ! sqlite3 "$DB_PATH" "PRAGMA table_info(peer);" | grep -q "is_banned"; then
        print_info "Adding ban-related columns..."
        sqlite3 "$DB_PATH" "ALTER TABLE peer ADD COLUMN is_banned INTEGER DEFAULT 0;"
        sqlite3 "$DB_PATH" "ALTER TABLE peer ADD COLUMN banned_at TEXT;"
        sqlite3 "$DB_PATH" "ALTER TABLE peer ADD COLUMN banned_by TEXT;"
        sqlite3 "$DB_PATH" "ALTER TABLE peer ADD COLUMN ban_reason TEXT;"
        print_success "Added ban-related columns"
    else
        print_success "Ban columns already exist"
    fi
    
    # Check if users table exists (for auth system)
    if ! sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='users';" | grep -q "users"; then
        print_info "Creating users table..."
        sqlite3 "$DB_PATH" "
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                role TEXT DEFAULT 'viewer',
                is_active INTEGER DEFAULT 1,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                last_login TEXT
            );
        "
        print_success "Created users table"
    else
        print_success "Users table already exists"
    fi
    
    # Check if sessions table exists
    if ! sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='sessions';" | grep -q "sessions"; then
        print_info "Creating sessions table..."
        sqlite3 "$DB_PATH" "
            CREATE TABLE IF NOT EXISTS sessions (
                token VARCHAR(64) PRIMARY KEY,
                user_id INTEGER NOT NULL,
                created_at DATETIME NOT NULL,
                expires_at DATETIME NOT NULL,
                last_activity DATETIME NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );
        "
        print_success "Created sessions table"
    else
        print_info "Checking sessions table structure..."
        
        # Check if sessions table has the correct structure (token as PRIMARY KEY)
        local sessions_has_token_pk=$(sqlite3 "$DB_PATH" "PRAGMA table_info(sessions);" | grep -E "^0\|token\|" || echo "")
        local sessions_has_last_activity=$(sqlite3 "$DB_PATH" "PRAGMA table_info(sessions);" | grep "last_activity" || echo "")
        
        # If table has old structure (id as PRIMARY KEY instead of token), recreate it
        if [ -z "$sessions_has_token_pk" ]; then
            print_warning "Sessions table has old structure - recreating..."
            
            # Drop old sessions (they will be invalid anyway after structure change)
            sqlite3 "$DB_PATH" "DROP TABLE IF EXISTS sessions;"
            
            # Create with correct structure
            sqlite3 "$DB_PATH" "
                CREATE TABLE sessions (
                    token VARCHAR(64) PRIMARY KEY,
                    user_id INTEGER NOT NULL,
                    created_at DATETIME NOT NULL,
                    expires_at DATETIME NOT NULL,
                    last_activity DATETIME NOT NULL,
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                );
            "
            print_success "Recreated sessions table with correct structure"
        elif [ -z "$sessions_has_last_activity" ]; then
            # Table exists with correct structure but missing last_activity column
            print_info "Adding last_activity column to sessions table..."
            sqlite3 "$DB_PATH" "ALTER TABLE sessions ADD COLUMN last_activity DATETIME;"
            # Set default value for existing rows
            sqlite3 "$DB_PATH" "UPDATE sessions SET last_activity = created_at WHERE last_activity IS NULL;"
            print_success "Added last_activity column"
        else
            print_success "Sessions table structure is correct"
        fi
    fi
    
    # Check if audit_log table exists
    if ! sqlite3 "$DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='audit_log';" | grep -q "audit_log"; then
        print_info "Creating audit_log table..."
        sqlite3 "$DB_PATH" "
            CREATE TABLE IF NOT EXISTS audit_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                action VARCHAR(50) NOT NULL,
                device_id VARCHAR(100),
                details TEXT,
                ip_address VARCHAR(45),
                timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
            );
        "
        print_success "Created audit_log table"
    else
        print_info "Checking audit_log table structure..."
        
        # Check if audit_log has the correct columns
        local has_device_id=$(sqlite3 "$DB_PATH" "PRAGMA table_info(audit_log);" | grep "device_id" || echo "")
        local has_timestamp=$(sqlite3 "$DB_PATH" "PRAGMA table_info(audit_log);" | grep "timestamp" || echo "")
        
        # If table has old structure, recreate it
        if [ -z "$has_device_id" ] || [ -z "$has_timestamp" ]; then
            print_warning "audit_log table has old structure - recreating..."
            
            # Backup old audit logs (optional - they may have different structure)
            sqlite3 "$DB_PATH" "DROP TABLE IF EXISTS audit_log;"
            
            # Create with correct structure
            sqlite3 "$DB_PATH" "
                CREATE TABLE audit_log (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER,
                    action VARCHAR(50) NOT NULL,
                    device_id VARCHAR(100),
                    details TEXT,
                    ip_address VARCHAR(45),
                    timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
                );
            "
            print_success "Recreated audit_log table with correct structure"
        else
            print_success "audit_log table structure is correct"
        fi
    fi
    
    # Create default admin if not exists
    local admin_exists=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE username='admin';")
    if [ "$admin_exists" = "0" ]; then
        print_info "Creating default admin user..."
        # Generate random password
        local admin_password=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
        # Use Python to hash the password with bcrypt
        local password_hash=$(python3 -c "import bcrypt; print(bcrypt.hashpw('$admin_password'.encode(), bcrypt.gensalt()).decode())" 2>/dev/null || echo "")
        
        if [ -n "$password_hash" ]; then
            sqlite3 "$DB_PATH" "INSERT INTO users (username, password_hash, role, is_active) VALUES ('admin', '$password_hash', 'admin', 1);"
            print_success "Created admin user"
            echo ""
            echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║      DEFAULT ADMIN CREDENTIALS                 ║${NC}"
            echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
            echo -e "${GREEN}║  Username: admin                               ║${NC}"
            echo -e "${GREEN}║  Password: $admin_password                     ║${NC}"
            echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
            echo -e "${GREEN}║  ⚠️  CHANGE THIS PASSWORD AFTER FIRST LOGIN!   ║${NC}"
            echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
            echo ""
        else
            print_warning "Could not create admin user (bcrypt not installed)"
            print_info "Run: pip3 install bcrypt"
        fi
    else
        print_success "Admin user already exists"
    fi
    
    print_success "Database migration completed"
}

# =============================================================================
# Update Console Files
# =============================================================================

update_console_files() {
    print_header "Updating Console Files"
    
    # Stop service first
    if systemctl is-active betterdesk.service &>/dev/null 2>&1; then
        print_info "Stopping BetterDesk service..."
        systemctl stop betterdesk.service
        print_success "Service stopped"
    fi
    
    # Update web files
    if [ -d "$SCRIPT_DIR/web" ]; then
        print_info "Updating web application files..."
        
        # Create directories if needed
        mkdir -p "$CONSOLE_PATH/static"
        mkdir -p "$CONSOLE_PATH/templates"
        
        # Copy Python files (app.py and auth.py)
        for pyfile in app.py auth.py; do
            if [ -f "$SCRIPT_DIR/web/$pyfile" ]; then
                cp "$SCRIPT_DIR/web/$pyfile" "$CONSOLE_PATH/"
                print_success "Updated $pyfile"
            fi
        done
        
        # Copy static files
        if [ -d "$SCRIPT_DIR/web/static" ]; then
            cp -r "$SCRIPT_DIR/web/static/"* "$CONSOLE_PATH/static/" 2>/dev/null || true
            print_success "Updated static files"
        fi
        
        # Copy templates
        if [ -d "$SCRIPT_DIR/web/templates" ]; then
            cp -r "$SCRIPT_DIR/web/templates/"* "$CONSOLE_PATH/templates/" 2>/dev/null || true
            print_success "Updated templates"
        fi
        
        # Copy requirements
        if [ -f "$SCRIPT_DIR/web/requirements.txt" ]; then
            cp "$SCRIPT_DIR/web/requirements.txt" "$CONSOLE_PATH/"
        fi
    fi
    
    # Update VERSION file
    echo "v$TARGET_VERSION" > "$CONSOLE_PATH/VERSION"
    print_success "Updated VERSION to $TARGET_VERSION"
    
    # Install Python dependencies
    install_python_dependencies
}

# =============================================================================
# Update HBBS Binaries
# =============================================================================

update_binaries() {
    print_header "Updating HBBS/HBBR Binaries"
    
    local binaries_copied=false
    local using_old_binaries=false
    local services_stopped=false
    
    # Stop services before copying to avoid "Text file busy" error
    print_info "Stopping RustDesk services before binary update..."
    local hbbs_services=("rustdesksignal.service" "hbbs.service" "rustdesk-hbbs.service")
    local hbbr_services=("rustdeskrelay.service" "hbbr.service" "rustdesk-hbbr.service")
    
    for service in "${hbbs_services[@]}" "${hbbr_services[@]}"; do
        if systemctl is-active "$service" &>/dev/null 2>&1; then
            systemctl stop "$service" 2>/dev/null || true
            print_info "Stopped $service"
            services_stopped=true
        fi
    done
    
    # Give processes time to fully terminate
    if [ "$services_stopped" = true ]; then
        sleep 2
    fi
    
    # Check for hbbs-patch-v2 (recommended, latest)
    # Priority 1: Pre-compiled binaries (hbbs-linux-x86_64)
    if [ -d "$SCRIPT_DIR/hbbs-patch-v2" ] && [ -f "$SCRIPT_DIR/hbbs-patch-v2/hbbs-linux-x86_64" ]; then
        print_success "Found hbbs-patch-v2 pre-compiled binaries (v2.0.0, port 21120)"
        
        # Backup existing binaries
        for bin in hbbs hbbr hbbs-v8-api hbbr-v8-api; do
            if [ -f "$RUSTDESK_PATH/$bin" ]; then
                cp "$RUSTDESK_PATH/$bin" "$BACKUP_DIR/" 2>/dev/null || true
            fi
        done
        
        # Copy v2 binaries (pre-compiled)
        if [ -f "$SCRIPT_DIR/hbbs-patch-v2/hbbs-linux-x86_64" ]; then
            cp "$SCRIPT_DIR/hbbs-patch-v2/hbbs-linux-x86_64" "$RUSTDESK_PATH/hbbs-v8-api"
            chmod +x "$RUSTDESK_PATH/hbbs-v8-api"
            print_success "Copied hbbs-v8-api (v2.0.0) to $RUSTDESK_PATH"
            binaries_copied=true
        fi
        
        if [ -f "$SCRIPT_DIR/hbbs-patch-v2/hbbr-linux-x86_64" ]; then
            cp "$SCRIPT_DIR/hbbs-patch-v2/hbbr-linux-x86_64" "$RUSTDESK_PATH/hbbr-v8-api"
            chmod +x "$RUSTDESK_PATH/hbbr-v8-api"
            print_success "Copied hbbr-v8-api (v2.0.0) to $RUSTDESK_PATH"
            binaries_copied=true
        fi
    
    # Priority 2: Locally compiled binaries (target/release)
    elif [ -d "$SCRIPT_DIR/hbbs-patch-v2" ] && [ -f "$SCRIPT_DIR/hbbs-patch-v2/target/release/hbbs" ]; then
        print_success "Found locally compiled hbbs-patch-v2 binaries (port 21120)"
        
        # Backup existing binaries
        for bin in hbbs hbbr hbbs-v8-api hbbr-v8-api; do
            if [ -f "$RUSTDESK_PATH/$bin" ]; then
                cp "$RUSTDESK_PATH/$bin" "$BACKUP_DIR/" 2>/dev/null || true
            fi
        done
        
        # Copy locally compiled binaries
        if [ -f "$SCRIPT_DIR/hbbs-patch-v2/target/release/hbbs" ]; then
            cp "$SCRIPT_DIR/hbbs-patch-v2/target/release/hbbs" "$RUSTDESK_PATH/hbbs-v8-api"
            chmod +x "$RUSTDESK_PATH/hbbs-v8-api"
            print_success "Copied hbbs-v8-api (compiled) to $RUSTDESK_PATH"
            binaries_copied=true
        fi
        
        if [ -f "$SCRIPT_DIR/hbbs-patch-v2/target/release/hbbr" ]; then
            cp "$SCRIPT_DIR/hbbs-patch-v2/target/release/hbbr" "$RUSTDESK_PATH/hbbr-v8-api"
            chmod +x "$RUSTDESK_PATH/hbbr-v8-api"
            print_success "Copied hbbr-v8-api (compiled) to $RUSTDESK_PATH"
            binaries_copied=true
        fi
        
    elif [ -d "$SCRIPT_DIR/hbbs-patch/bin-with-api" ]; then
        print_warning "⚠️  Found OLD precompiled binaries (v1, port 21114, slow detection)"
        print_info "These binaries have known issues:"
        echo "  - Uses port 21114 instead of 21120 (conflicts with RustDesk Pro)"
        echo "  - Slower offline detection (30s vs 15s in v2)"
        echo "  - Single DB connection (v2 has pooling)"
        echo ""
        print_info "Recommended: Build latest version from hbbs-patch-v2/"
        echo ""
        read -p "Do you want to use these OLD binaries anyway? [y/N] " -n 1 -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            using_old_binaries=true
            
            # Backup existing binaries
            for bin in hbbs hbbr hbbs-v8-api hbbr-v8-api; do
                if [ -f "$RUSTDESK_PATH/$bin" ]; then
                    cp "$RUSTDESK_PATH/$bin" "$BACKUP_DIR/" 2>/dev/null || true
                fi
            done
            
            # Copy old binaries
            if [ -f "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbs-v8-api" ]; then
                cp "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbs-v8-api" "$RUSTDESK_PATH/"
                chmod +x "$RUSTDESK_PATH/hbbs-v8-api"
                print_success "Copied hbbs-v8-api (v1-old) to $RUSTDESK_PATH"
                binaries_copied=true
            fi
            
            if [ -f "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbr-v8-api" ]; then
                cp "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbr-v8-api" "$RUSTDESK_PATH/"
                chmod +x "$RUSTDESK_PATH/hbbr-v8-api"
                print_success "Copied hbbr-v8-api (v1-old) to $RUSTDESK_PATH"
                binaries_copied=true
            fi
        else
            print_info "Skipping old binaries. Please build v2 first:"
            echo ""
            echo "  cd $SCRIPT_DIR/hbbs-patch-v2"
            echo "  ./build.sh"
            echo "  cd .."
            echo "  sudo ./install-improved.sh"
            echo ""
        fi
    else
        print_info "No precompiled binaries found, checking existing installation..."
    fi
    
    # Check if API binaries exist in RUSTDESK_PATH (either copied or already there)
    local has_hbbs_api=false
    local has_hbbr_api=false
    
    if [ -f "$RUSTDESK_PATH/hbbs-v8-api" ]; then
        has_hbbs_api=true
        
        # Check which version (try to detect port in binary)
        if command -v strings &>/dev/null && strings "$RUSTDESK_PATH/hbbs-v8-api" 2>/dev/null | grep -q "21120"; then
            print_success "Found hbbs-v8-api in $RUSTDESK_PATH (v2, port 21120)"
        elif command -v strings &>/dev/null && strings "$RUSTDESK_PATH/hbbs-v8-api" 2>/dev/null | grep -q "21114"; then
            print_warning "Found hbbs-v8-api in $RUSTDESK_PATH (v1-old, port 21114)"
            echo "  ⚠️  Consider upgrading to v2 for better performance"
        else
            print_success "Found hbbs-v8-api in $RUSTDESK_PATH"
        fi
    fi
    
    if [ -f "$RUSTDESK_PATH/hbbr-v8-api" ]; then
        has_hbbr_api=true
        print_success "Found hbbr-v8-api in $RUSTDESK_PATH"
    fi
    
    # Create symlinks for backward compatibility
    if [ "$has_hbbs_api" = true ]; then
        if [ -f "$RUSTDESK_PATH/hbbs" ] && [ ! -L "$RUSTDESK_PATH/hbbs" ]; then
            mv "$RUSTDESK_PATH/hbbs" "$RUSTDESK_PATH/hbbs.original"
            ln -sf "$RUSTDESK_PATH/hbbs-v8-api" "$RUSTDESK_PATH/hbbs"
            print_success "Created hbbs symlink → hbbs-v8-api"
        elif [ ! -f "$RUSTDESK_PATH/hbbs" ]; then
            ln -sf "$RUSTDESK_PATH/hbbs-v8-api" "$RUSTDESK_PATH/hbbs"
            print_success "Created hbbs symlink → hbbs-v8-api"
        fi
    fi
    
    if [ "$has_hbbr_api" = true ]; then
        if [ -f "$RUSTDESK_PATH/hbbr" ] && [ ! -L "$RUSTDESK_PATH/hbbr" ]; then
            mv "$RUSTDESK_PATH/hbbr" "$RUSTDESK_PATH/hbbr.original"
            ln -sf "$RUSTDESK_PATH/hbbr-v8-api" "$RUSTDESK_PATH/hbbr"
            print_success "Created hbbr symlink → hbbr-v8-api"
        elif [ ! -f "$RUSTDESK_PATH/hbbr" ]; then
            ln -sf "$RUSTDESK_PATH/hbbr-v8-api" "$RUSTDESK_PATH/hbbr"
            print_success "Created hbbr symlink → hbbr-v8-api"
        fi
    fi
    
    # ALWAYS update systemd services if API binaries exist
    if [ "$has_hbbs_api" = true ] || [ "$has_hbbr_api" = true ]; then
        update_systemd_services "$has_hbbs_api" "$has_hbbr_api"
    else
        print_warning "No API-enabled binaries found!"
        echo ""
        print_info "To build latest binaries (recommended):"
        echo "  cd $SCRIPT_DIR/hbbs-patch-v2"
        echo "  ./build.sh"
        echo "  cd .."
        echo "  sudo ./install-improved.sh"
        echo ""
        print_info "Features in v2:"
        echo "  ✅ Port 21120 (no conflicts)"
        echo "  ✅ 15s offline detection (2x faster)"
        echo "  ✅ Connection pooling"
        echo "  ✅ Auto-retry logic"
        echo "  ✅ 99.8% uptime"
    fi
    
    # Show warning if using old binaries
    if [ "$using_old_binaries" = true ]; then
        echo ""
        print_warning "═══════════════════════════════════════════════════════"
        print_warning "  YOU ARE USING OLD BINARIES WITH KNOWN ISSUES!"
        print_warning "  Online/Offline status may be SLOW (30s detection)"
        print_warning "  API uses WRONG PORT (21114 instead of 21120)"
        print_warning "═══════════════════════════════════════════════════════"
        echo ""
    fi
    
    # Restart services if they were stopped
    if [ "$services_stopped" = true ]; then
        print_info "Binary update complete. Services will be restarted after systemd update."
    fi
}

# =============================================================================
# Update Systemd Services for HBBS/HBBR
# =============================================================================

update_systemd_services() {
    local has_hbbs_api="${1:-true}"
    local has_hbbr_api="${2:-true}"
    
    print_header "Updating Systemd Services"
    
    local services_updated=false
    local hbbs_found=false
    local hbbr_found=false
    
    # Common service names for HBBS (signal server)
    local hbbs_services=("rustdesksignal.service" "hbbs.service" "rustdesk-hbbs.service")
    # Common service names for HBBR (relay server)
    local hbbr_services=("rustdeskrelay.service" "hbbr.service" "rustdesk-hbbr.service")
    
    # =========================================================================
    # Process HBBS (Signal Server) service
    # =========================================================================
    if [ "$has_hbbs_api" = true ]; then
        for service in "${hbbs_services[@]}"; do
            local service_file="/etc/systemd/system/$service"
            if [ -f "$service_file" ]; then
                hbbs_found=true
                print_info "Found HBBS service: $service"
                
                # Create timestamped backup
                local backup_name="${service}.backup.$(date +%Y%m%d_%H%M%S)"
                cp "$service_file" "/etc/systemd/system/$backup_name"
                print_success "Created backup: $backup_name"
                
                # Also backup to BACKUP_DIR if exists
                if [ -d "$BACKUP_DIR" ]; then
                    cp "$service_file" "$BACKUP_DIR/$service.original"
                fi
                
                # Check current ExecStart
                local current_exec=$(grep "^ExecStart=" "$service_file" 2>/dev/null || echo "")
                
                if [ -z "$current_exec" ]; then
                    # NO ExecStart found - need to add it
                    print_warning "No ExecStart found in $service - adding it..."
                    
                    # Extract existing settings from the service file
                    local work_dir=$(grep "^WorkingDirectory=" "$service_file" 2>/dev/null | cut -d= -f2 || echo "$RUSTDESK_PATH")
                    
                    # Determine binary path
                    local hbbs_binary=""
                    if [ -f "$work_dir/hbbs-v8-api" ]; then
                        hbbs_binary="$work_dir/hbbs-v8-api"
                    elif [ -f "$RUSTDESK_PATH/hbbs-v8-api" ]; then
                        hbbs_binary="$RUSTDESK_PATH/hbbs-v8-api"
                    elif [ -f "/opt/rustdesk/hbbs-v8-api" ]; then
                        hbbs_binary="/opt/rustdesk/hbbs-v8-api"
                    fi
                    
                    if [ -n "$hbbs_binary" ]; then
                        # Add ExecStart after [Service] section
                        sed -i "/^\[Service\]/a ExecStart=$hbbs_binary" "$service_file"
                        print_success "Added ExecStart=$hbbs_binary"
                        services_updated=true
                    else
                        print_error "Could not find hbbs-v8-api binary!"
                        print_info "Please copy hbbs-v8-api to $RUSTDESK_PATH"
                    fi
                    
                elif echo "$current_exec" | grep -q "hbbs-v8-api"; then
                    # Already using hbbs-v8-api
                    print_success "Service $service already uses hbbs-v8-api"
                    
                elif echo "$current_exec" | grep -q "/hbbs"; then
                    # Has ExecStart with /hbbs - update it safely
                    # Extract just the binary path and replace hbbs with hbbs-v8-api
                    # This handles: /opt/rustdesk/hbbs, /opt/rustdesk/hbbs -r server, etc.
                    
                    # Use simple string replacement - more reliable than complex regex
                    local new_exec="${current_exec//\/hbbs /\/hbbs-v8-api }"  # /hbbs space -> /hbbs-v8-api space
                    new_exec="${new_exec//\/hbbs$/\/hbbs-v8-api}"              # /hbbs at end -> /hbbs-v8-api
                    
                    # If the simple replacement didn't work, try sed
                    if [ "$current_exec" = "$new_exec" ]; then
                        # Try with sed - replace /hbbs followed by space, end, or dash
                        new_exec=$(echo "$current_exec" | sed 's|/hbbs |/hbbs-v8-api |g; s|/hbbs$|/hbbs-v8-api|g')
                    fi
                    
                    if [ "$current_exec" != "$new_exec" ]; then
                        # Write the new ExecStart line directly (safer than sed replacement)
                        # First remove old ExecStart, then add new one
                        grep -v "^ExecStart=" "$service_file" > "$service_file.tmp"
                        
                        # Insert new ExecStart after [Service]
                        sed -i "/^\[Service\]/a $new_exec" "$service_file.tmp"
                        mv "$service_file.tmp" "$service_file"
                        
                        print_success "Updated $service:"
                        echo "  Old: $current_exec"
                        echo "  New: $new_exec"
                        services_updated=true
                    else
                        print_warning "Could not parse ExecStart for replacement"
                        print_info "Current: $current_exec"
                        print_info "Please update manually"
                    fi
                else
                    print_warning "ExecStart exists but doesn't contain /hbbs path"
                    print_info "Current: $current_exec"
                    print_info "Please update manually if needed"
                fi
                
                break  # Found and processed HBBS service
            fi
        done
        
        if [ "$hbbs_found" = false ]; then
            print_warning "No HBBS service found. Checked: ${hbbs_services[*]}"
            
            # Try to create new service from template
            if [ -f "$SCRIPT_DIR/templates/rustdesksignal.service" ]; then
                print_info "Creating rustdesksignal.service from template..."
                
                # Copy template
                cp "$SCRIPT_DIR/templates/rustdesksignal.service" "/etc/systemd/system/rustdesksignal.service"
                
                # Update paths in service file
                sed -i "s|WorkingDirectory=/opt/rustdesk|WorkingDirectory=$RUSTDESK_PATH|g" "/etc/systemd/system/rustdesksignal.service"
                sed -i "s|/opt/rustdesk/hbbs-v8-api|$RUSTDESK_PATH/hbbs-v8-api|g" "/etc/systemd/system/rustdesksignal.service"
                
                # Try to get the key from id_ed25519.pub
                local public_key=""
                if [ -f "$RUSTDESK_PATH/id_ed25519.pub" ]; then
                    public_key=$(cat "$RUSTDESK_PATH/id_ed25519.pub" 2>/dev/null | head -1)
                fi
                
                if [ -n "$public_key" ]; then
                    sed -i "s|-k _|-k $public_key|g" "/etc/systemd/system/rustdesksignal.service"
                    print_success "Set server key in service file"
                else
                    print_warning "No key found - please edit /etc/systemd/system/rustdesksignal.service and set -k parameter"
                fi
                
                systemctl daemon-reload
                systemctl enable rustdesksignal.service
                print_success "Created and enabled rustdesksignal.service"
                services_updated=true
            else
                print_info "No template found. Create service manually."
            fi
        fi
    fi
    
    # =========================================================================
    # Process HBBR (Relay Server) service
    # =========================================================================
    if [ "$has_hbbr_api" = true ]; then
        for service in "${hbbr_services[@]}"; do
            local service_file="/etc/systemd/system/$service"
            if [ -f "$service_file" ]; then
                hbbr_found=true
                print_info "Found HBBR service: $service"
                
                # Create timestamped backup
                local backup_name="${service}.backup.$(date +%Y%m%d_%H%M%S)"
                cp "$service_file" "/etc/systemd/system/$backup_name"
                print_success "Created backup: $backup_name"
                
                # Also backup to BACKUP_DIR if exists
                if [ -d "$BACKUP_DIR" ]; then
                    cp "$service_file" "$BACKUP_DIR/$service.original"
                fi
                
                # Check current ExecStart
                local current_exec=$(grep "^ExecStart=" "$service_file" 2>/dev/null || echo "")
                
                if [ -z "$current_exec" ]; then
                    # NO ExecStart found - need to add it
                    print_warning "No ExecStart found in $service - adding it..."
                    
                    # Extract existing settings
                    local work_dir=$(grep "^WorkingDirectory=" "$service_file" 2>/dev/null | cut -d= -f2 || echo "$RUSTDESK_PATH")
                    
                    # Determine binary path
                    local hbbr_binary=""
                    if [ -f "$work_dir/hbbr-v8-api" ]; then
                        hbbr_binary="$work_dir/hbbr-v8-api"
                    elif [ -f "$RUSTDESK_PATH/hbbr-v8-api" ]; then
                        hbbr_binary="$RUSTDESK_PATH/hbbr-v8-api"
                    elif [ -f "/opt/rustdesk/hbbr-v8-api" ]; then
                        hbbr_binary="/opt/rustdesk/hbbr-v8-api"
                    fi
                    
                    if [ -n "$hbbr_binary" ]; then
                        sed -i "/^\[Service\]/a ExecStart=$hbbr_binary" "$service_file"
                        print_success "Added ExecStart=$hbbr_binary"
                        services_updated=true
                    else
                        print_error "Could not find hbbr-v8-api binary!"
                        print_info "Please copy hbbr-v8-api to $RUSTDESK_PATH"
                    fi
                    
                elif echo "$current_exec" | grep -q "hbbr-v8-api"; then
                    print_success "Service $service already uses hbbr-v8-api"
                    
                elif echo "$current_exec" | grep -q "/hbbr"; then
                    # Has ExecStart with /hbbr - update it safely
                    # Use simple string replacement - more reliable than complex regex
                    local new_exec="${current_exec//\/hbbr /\/hbbr-v8-api }"  # /hbbr space -> /hbbr-v8-api space
                    new_exec="${new_exec//\/hbbr$/\/hbbr-v8-api}"              # /hbbr at end -> /hbbr-v8-api
                    
                    # If the simple replacement didn't work, try sed
                    if [ "$current_exec" = "$new_exec" ]; then
                        new_exec=$(echo "$current_exec" | sed 's|/hbbr |/hbbr-v8-api |g; s|/hbbr$|/hbbr-v8-api|g')
                    fi
                    
                    if [ "$current_exec" != "$new_exec" ]; then
                        # Write the new ExecStart line directly (safer than sed replacement)
                        grep -v "^ExecStart=" "$service_file" > "$service_file.tmp"
                        sed -i "/^\[Service\]/a $new_exec" "$service_file.tmp"
                        mv "$service_file.tmp" "$service_file"
                        
                        print_success "Updated $service:"
                        echo "  Old: $current_exec"
                        echo "  New: $new_exec"
                        services_updated=true
                    else
                        print_warning "Could not parse ExecStart for replacement"
                        print_info "Current: $current_exec"
                        print_info "Please update manually"
                    fi
                else
                    print_warning "ExecStart exists but doesn't contain /hbbr path"
                    print_info "Current: $current_exec"
                fi
                
                break  # Found and processed HBBR service
            fi
        done
        
        if [ "$hbbr_found" = false ]; then
            print_warning "No HBBR service found. Checked: ${hbbr_services[*]}"
            
            # Try to create new service from template
            if [ -f "$SCRIPT_DIR/templates/rustdeskrelay.service" ]; then
                print_info "Creating rustdeskrelay.service from template..."
                
                # Copy template
                cp "$SCRIPT_DIR/templates/rustdeskrelay.service" "/etc/systemd/system/rustdeskrelay.service"
                
                # Update paths in service file
                sed -i "s|WorkingDirectory=/opt/rustdesk|WorkingDirectory=$RUSTDESK_PATH|g" "/etc/systemd/system/rustdeskrelay.service"
                sed -i "s|/opt/rustdesk/hbbr-v8-api|$RUSTDESK_PATH/hbbr-v8-api|g" "/etc/systemd/system/rustdeskrelay.service"
                
                systemctl daemon-reload
                systemctl enable rustdeskrelay.service
                print_success "Created and enabled rustdeskrelay.service"
                services_updated=true
            else
                print_info "No template found. Create service manually."
            fi
        fi
    fi
    
    # =========================================================================
    # Reload systemd and show status
    # =========================================================================
    if [ "$services_updated" = true ]; then
        print_info "Reloading systemd daemon..."
        systemctl daemon-reload
        print_success "Systemd daemon reloaded"
        print_success "Services updated to use API-enabled binaries!"
    else
        if [ "$hbbs_found" = true ] || [ "$hbbr_found" = true ]; then
            print_info "No service updates were needed"
        fi
    fi
    
    # Show current service configuration
    echo ""
    print_info "Current RustDesk service configuration:"
    echo ""
    for service in "${hbbs_services[@]}" "${hbbr_services[@]}"; do
        if [ -f "/etc/systemd/system/$service" ]; then
            local status=$(systemctl is-active "$service" 2>/dev/null || echo "unknown")
            local exec_line=$(grep '^ExecStart=' "/etc/systemd/system/$service" 2>/dev/null | head -1)
            local work_dir=$(grep '^WorkingDirectory=' "/etc/systemd/system/$service" 2>/dev/null | head -1)
            
            if [ "$status" = "active" ]; then
                echo -e "  ${GREEN}●${NC} $service (running)"
            else
                echo -e "  ${YELLOW}○${NC} $service ($status)"
            fi
            
            if [ -n "$exec_line" ]; then
                echo "      $exec_line"
            else
                echo -e "      ${RED}ExecStart: MISSING!${NC}"
            fi
            
            if [ -n "$work_dir" ]; then
                echo "      $work_dir"
            fi
            echo ""
        fi
    done
    
    # Show backup info
    echo ""
    print_info "Service backups created in /etc/systemd/system/*.backup.*"
    print_info "To restore: cp /etc/systemd/system/SERVICE.backup.TIMESTAMP /etc/systemd/system/SERVICE"
}

# =============================================================================
# Fresh Installation
# =============================================================================

fresh_installation() {
    print_header "Fresh Installation Setup"
    
    # Create console directory
    CONSOLE_PATH="/opt/BetterDeskConsole"
    print_info "Creating console directory: $CONSOLE_PATH"
    mkdir -p "$CONSOLE_PATH"
    mkdir -p "$CONSOLE_PATH/static"
    mkdir -p "$CONSOLE_PATH/templates"
    
    # Copy web files
    if [ -d "$SCRIPT_DIR/web" ]; then
        print_info "Installing web application files..."
        
        # Copy Python files (app.py and auth.py)
        for pyfile in app.py auth.py; do
            if [ -f "$SCRIPT_DIR/web/$pyfile" ]; then
                cp "$SCRIPT_DIR/web/$pyfile" "$CONSOLE_PATH/"
                print_success "Installed $pyfile"
            fi
        done
        
        # Copy static files
        if [ -d "$SCRIPT_DIR/web/static" ]; then
            cp -r "$SCRIPT_DIR/web/static/"* "$CONSOLE_PATH/static/" 2>/dev/null || true
            print_success "Installed static files"
        fi
        
        # Copy templates
        if [ -d "$SCRIPT_DIR/web/templates" ]; then
            cp -r "$SCRIPT_DIR/web/templates/"* "$CONSOLE_PATH/templates/" 2>/dev/null || true
            print_success "Installed templates"
        fi
        
        # Copy requirements and service file
        if [ -f "$SCRIPT_DIR/web/requirements.txt" ]; then
            cp "$SCRIPT_DIR/web/requirements.txt" "$CONSOLE_PATH/"
        fi
        if [ -f "$SCRIPT_DIR/web/betterdesk.service" ]; then
            cp "$SCRIPT_DIR/web/betterdesk.service" "/etc/systemd/system/"
            systemctl daemon-reload
            print_success "Installed systemd service"
        fi
    fi
    
    # Create VERSION file
    echo "v$TARGET_VERSION" > "$CONSOLE_PATH/VERSION"
    print_success "Created VERSION file"
    
    # Install Python dependencies
    install_python_dependencies
    
    # Enable and start service
    if [ -f "/etc/systemd/system/betterdesk.service" ]; then
        systemctl enable betterdesk.service
        systemctl start betterdesk.service
        print_success "BetterDesk Console service enabled and started"
    fi
    
    # Final setup message
    echo ""
    print_success "Fresh installation completed!"
    print_info "Console installed at: $CONSOLE_PATH"
    if [ -n "$DB_PATH" ]; then
        print_info "Database found at: $DB_PATH"
    fi
    echo ""
}

# =============================================================================
# Restart Services
# =============================================================================

restart_services() {
    print_header "Restarting Services"
    
    # Common service names for HBBS (signal server)
    local hbbs_services=("rustdesksignal.service" "hbbs.service" "rustdesk-hbbs.service")
    # Common service names for HBBR (relay server)
    local hbbr_services=("rustdeskrelay.service" "hbbr.service" "rustdesk-hbbr.service")
    
    # Restart HBBS service (try all possible names)
    local hbbs_restarted=false
    for service in "${hbbs_services[@]}"; do
        if systemctl is-enabled "$service" &>/dev/null 2>&1; then
            print_info "Restarting $service..."
            systemctl restart "$service"
            if systemctl is-active "$service" &>/dev/null 2>&1; then
                print_success "$service restarted successfully"
            else
                print_error "Failed to restart $service"
                print_info "Check logs: journalctl -u $service -n 20"
            fi
            hbbs_restarted=true
            break
        fi
    done
    if [ "$hbbs_restarted" = false ]; then
        print_warning "No HBBS service found (checked: ${hbbs_services[*]})"
    fi
    
    # Restart HBBR service (try all possible names)
    local hbbr_restarted=false
    for service in "${hbbr_services[@]}"; do
        if systemctl is-enabled "$service" &>/dev/null 2>&1; then
            print_info "Restarting $service..."
            systemctl restart "$service"
            if systemctl is-active "$service" &>/dev/null 2>&1; then
                print_success "$service restarted successfully"
            else
                print_error "Failed to restart $service"
                print_info "Check logs: journalctl -u $service -n 20"
            fi
            hbbr_restarted=true
            break
        fi
    done
    if [ "$hbbr_restarted" = false ]; then
        print_warning "No HBBR service found (checked: ${hbbr_services[*]})"
    fi
    
    # Restart BetterDesk Console
    if systemctl is-enabled betterdesk.service &>/dev/null 2>&1; then
        print_info "Starting BetterDesk Console..."
        systemctl start betterdesk.service
        sleep 2
        if systemctl is-active betterdesk.service &>/dev/null 2>&1; then
            print_success "BetterDesk Console started"
        else
            print_error "Failed to start BetterDesk Console"
            print_info "Check logs: journalctl -u betterdesk.service -n 50"
        fi
    fi
    
    # Show final status
    echo ""
    print_info "Service Status Summary:"
    for service in "${hbbs_services[@]}" "${hbbr_services[@]}" "betterdesk.service"; do
        if [ -f "/etc/systemd/system/$service" ]; then
            local status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
            if [ "$status" = "active" ]; then
                echo -e "  ${GREEN}●${NC} $service - $status"
            else
                echo -e "  ${RED}●${NC} $service - $status"
            fi
        fi
    done
}

# =============================================================================
# Main
# =============================================================================

main() {
    print_header "BetterDesk Console v$TARGET_VERSION - Install/Update"
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (sudo)"
        exit 1
    fi
    
    # Check for sqlite3
    if ! command -v sqlite3 &>/dev/null; then
        print_error "sqlite3 is required but not installed"
        print_info "Install with: apt install sqlite3"
        exit 1
    fi
    
    # Detect installation
    print_header "Detecting Installation"
    
    # Check if BetterDesk Console is already installed (update scenario)
    CONSOLE_ALREADY_INSTALLED=false
    if detect_console_path; then
        CONSOLE_ALREADY_INSTALLED=true
        print_success "Found existing BetterDesk Console installation"
    else
        print_info "No existing BetterDesk Console found - will perform fresh installation"
    fi
    
    # Always try to detect RustDesk (required for both fresh install and update)
    if ! detect_rustdesk_path; then
        print_warning "Could not find RustDesk installation automatically"
        echo ""
        print_info "Searched in:"
        for path in "${RUSTDESK_PATHS[@]}"; do
            echo "  - $path"
        done
        echo ""
        
        # Prompt user for path
        if ! prompt_rustdesk_path; then
            print_error "Cannot continue without RustDesk installation path"
            echo ""
            print_info "Tips:"
            echo "  1. For Docker installations, find where your data volume is mounted"
            echo "  2. Look for db_v2.sqlite3 or hbbs binary"
            echo "  3. Run: find / -name 'db_v2.sqlite3' 2>/dev/null"
            exit 1
        fi
    fi
    
    
    if ! detect_database; then
        print_warning "Could not find RustDesk database in $RUSTDESK_PATH"
        echo ""
        print_info "Looking for database files..."
        
        # Try to find database in the user-provided path
        for db in "${DB_NAMES[@]}"; do
            if [ -f "$RUSTDESK_PATH/$db" ]; then
                DB_PATH="$RUSTDESK_PATH/$db"
                print_success "Found database: $DB_PATH"
                break
            fi
        done
        
        if [ -z "$DB_PATH" ]; then
            print_error "No database found. The console requires an existing RustDesk database."
            exit 1
        fi
    fi
    
    # Handle fresh installation vs update
    if [ "$CONSOLE_ALREADY_INSTALLED" = true ]; then
        # UPDATE SCENARIO
        detect_current_version
        
        # Summary
        echo ""
        print_info "Update Summary:"
        echo "  Console Path:   $CONSOLE_PATH"
        echo "  RustDesk Path:  $RUSTDESK_PATH"
        echo "  Database:       $DB_PATH"
        echo "  Current Ver:    $CURRENT_VERSION"
        echo "  Target Ver:     $TARGET_VERSION"
        echo ""
        
        # Confirmation
        read -p "Proceed with update? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Update cancelled"
            exit 0
        fi
        
        # Run update steps
        create_backup
        run_database_migration
        update_console_files
        update_binaries
        restart_services
    else
        # FRESH INSTALLATION SCENARIO
        echo ""
        print_info "Fresh Installation Summary:"
        echo "  RustDesk Path:  $RUSTDESK_PATH"
        echo "  Database:       $DB_PATH"
        echo "  Target Ver:     $TARGET_VERSION"
        echo ""
        
        # Confirmation
        read -p "Proceed with fresh installation? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installation cancelled"
            exit 0
        fi
        
        # Run fresh installation steps
        fresh_installation
        run_database_migration
        update_binaries
        restart_services
    fi
    
    # Final message
    if [ "$CONSOLE_ALREADY_INSTALLED" = true ]; then
        print_header "Update Complete!"
        echo -e "${GREEN}BetterDesk Console has been updated to v$TARGET_VERSION${NC}"
        echo ""
        print_info "Backup location: $BACKUP_DIR"
        print_info "To restore: cp -r $BACKUP_DIR/console/* $CONSOLE_PATH/"
    else
        print_header "Installation Complete!"
        echo -e "${GREEN}BetterDesk Console v$TARGET_VERSION has been installed!${NC}"
    fi
    
    echo ""
    print_info "Next steps:"
    echo "  1. Open the web console at: http://your-server:5000"
    echo "  2. Log in with the admin credentials (shown above for new installs)"
    echo "  3. Change the admin password if this is a fresh installation"
    echo "  4. Check that device status is working correctly"
    echo ""
    print_info "If you have issues:"
    echo "  - Check logs: journalctl -u betterdesk.service -n 50"
    echo "  - API health: curl -H 'X-API-Key: YOUR_KEY' http://localhost:21120/api/health"
    if [ "$CONSOLE_ALREADY_INSTALLED" = true ]; then
        echo "  - Restore backup if needed"
    fi
    echo ""
}

main "$@"
