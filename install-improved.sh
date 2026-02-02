#!/bin/bash
# =============================================================================
# BetterDesk Console - Universal Installation Script v1.5.0
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
# - Binary updates
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
    
    if [ -d "$SCRIPT_DIR/hbbs-patch/bin-with-api" ]; then
        print_info "Found precompiled binaries..."
        
        # Backup existing binaries
        for bin in hbbs hbbr hbbs-v8-api hbbr-v8-api; do
            if [ -f "$RUSTDESK_PATH/$bin" ]; then
                cp "$RUSTDESK_PATH/$bin" "$BACKUP_DIR/" 2>/dev/null || true
            fi
        done
        
        # Copy new binaries
        if [ -f "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbs-v8-api" ]; then
            cp "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbs-v8-api" "$RUSTDESK_PATH/"
            chmod +x "$RUSTDESK_PATH/hbbs-v8-api"
            print_success "Updated hbbs-v8-api"
        fi
        
        if [ -f "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbr-v8-api" ]; then
            cp "$SCRIPT_DIR/hbbs-patch/bin-with-api/hbbr-v8-api" "$RUSTDESK_PATH/"
            chmod +x "$RUSTDESK_PATH/hbbr-v8-api"
            print_success "Updated hbbr-v8-api"
        fi
        
        # Create symlinks if original binaries are being used
        if [ -f "$RUSTDESK_PATH/hbbs" ] && [ ! -L "$RUSTDESK_PATH/hbbs" ]; then
            mv "$RUSTDESK_PATH/hbbs" "$RUSTDESK_PATH/hbbs.original"
            ln -sf "$RUSTDESK_PATH/hbbs-v8-api" "$RUSTDESK_PATH/hbbs"
            print_success "Created hbbs symlink"
        fi
    else
        print_warning "No precompiled binaries found in hbbs-patch/bin-with-api/"
        print_info "You may need to copy binaries manually"
    fi
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
    
    # Restart HBBS
    if systemctl is-enabled hbbs.service &>/dev/null 2>&1; then
        print_info "Restarting HBBS..."
        systemctl restart hbbs.service
        print_success "HBBS restarted"
    fi
    
    # Restart HBBR
    if systemctl is-enabled hbbr.service &>/dev/null 2>&1; then
        print_info "Restarting HBBR..."
        systemctl restart hbbr.service
        print_success "HBBR restarted"
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
