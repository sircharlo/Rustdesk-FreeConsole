#!/bin/bash
# =============================================================================
# BetterDesk Console - Database Schema Checker & Fixer
# =============================================================================
# This script checks if the database schema matches the required structure
# and fixes any issues found. Can be run independently from the installer.
#
# Usage:
#   ./check_and_fix_database.sh [database_path]
#
# If no path is provided, script will try to find the database automatically.
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
SCRIPT_VERSION="1.0.0"

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
# Required Schema Definition
# =============================================================================

# Define expected schema for each table
# Format: table_name:column1,column2,column3,...

declare -A REQUIRED_TABLES

REQUIRED_TABLES["users"]="id,username,password_hash,role,created_at,last_login,is_active"
REQUIRED_TABLES["sessions"]="token,user_id,created_at,expires_at,last_activity"
REQUIRED_TABLES["audit_log"]="id,user_id,action,device_id,details,ip_address,timestamp"

# Columns required in peer table (added by BetterDesk)
REQUIRED_PEER_COLUMNS="last_online,is_deleted,is_banned,banned_at,banned_by,ban_reason"

# =============================================================================
# Database Detection
# =============================================================================

find_database() {
    local db_path="$1"
    
    if [ -n "$db_path" ] && [ -f "$db_path" ]; then
        echo "$db_path"
        return 0
    fi
    
    # Search common locations
    local search_paths=(
        "/opt/rustdesk/db_v2.sqlite3"
        "/opt/rustdesk/db.sqlite3"
        "/var/lib/rustdesk/db_v2.sqlite3"
        "/data/db_v2.sqlite3"
        "/data/rustdesk/db_v2.sqlite3"
        "$HOME/.rustdesk/db_v2.sqlite3"
    )
    
    for path in "${search_paths[@]}"; do
        if [ -f "$path" ]; then
            echo "$path"
            return 0
        fi
    done
    
    # Try find command
    local found=$(find /opt /var /data /home -name "db_v2.sqlite3" -type f 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi
    
    return 1
}

# =============================================================================
# Schema Checking Functions
# =============================================================================

get_table_columns() {
    local db="$1"
    local table="$2"
    sqlite3 "$db" "PRAGMA table_info($table);" | cut -d'|' -f2 | tr '\n' ',' | sed 's/,$//'
}

table_exists() {
    local db="$1"
    local table="$2"
    sqlite3 "$db" "SELECT name FROM sqlite_master WHERE type='table' AND name='$table';" | grep -q "$table"
}

column_exists() {
    local db="$1"
    local table="$2"
    local column="$3"
    sqlite3 "$db" "PRAGMA table_info($table);" | grep -q "|$column|"
}

check_sessions_structure() {
    local db="$1"
    # Check if token is the first column (PRIMARY KEY)
    local first_col=$(sqlite3 "$db" "PRAGMA table_info(sessions);" | head -1 | cut -d'|' -f2)
    if [ "$first_col" = "token" ]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Fix Functions
# =============================================================================

fix_peer_table() {
    local db="$1"
    local issues_fixed=0
    
    print_info "Checking peer table columns..."
    
    IFS=',' read -ra COLUMNS <<< "$REQUIRED_PEER_COLUMNS"
    for col in "${COLUMNS[@]}"; do
        if ! column_exists "$db" "peer" "$col"; then
            print_warning "Missing column: peer.$col"
            
            case "$col" in
                "last_online")
                    sqlite3 "$db" "ALTER TABLE peer ADD COLUMN last_online TEXT;"
                    ;;
                "is_deleted")
                    sqlite3 "$db" "ALTER TABLE peer ADD COLUMN is_deleted INTEGER DEFAULT 0;"
                    ;;
                "is_banned")
                    sqlite3 "$db" "ALTER TABLE peer ADD COLUMN is_banned INTEGER DEFAULT 0;"
                    ;;
                "banned_at"|"banned_by"|"ban_reason")
                    sqlite3 "$db" "ALTER TABLE peer ADD COLUMN $col TEXT;"
                    ;;
            esac
            
            print_success "Added column: peer.$col"
            ((issues_fixed++))
        fi
    done
    
    return $issues_fixed
}

fix_users_table() {
    local db="$1"
    
    if ! table_exists "$db" "users"; then
        print_warning "users table does not exist - creating..."
        sqlite3 "$db" "
            CREATE TABLE users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username VARCHAR(50) UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                role VARCHAR(20) NOT NULL DEFAULT 'viewer',
                created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                last_login DATETIME,
                is_active BOOLEAN NOT NULL DEFAULT 1,
                CHECK (role IN ('admin', 'operator', 'viewer'))
            );
        "
        print_success "Created users table"
        return 1
    fi
    
    print_success "users table exists"
    return 0
}

fix_sessions_table() {
    local db="$1"
    local needs_recreate=false
    
    if ! table_exists "$db" "sessions"; then
        print_warning "sessions table does not exist - creating..."
        needs_recreate=true
    elif ! check_sessions_structure "$db"; then
        print_warning "sessions table has incorrect structure (old schema) - recreating..."
        sqlite3 "$db" "DROP TABLE IF EXISTS sessions;"
        needs_recreate=true
    elif ! column_exists "$db" "sessions" "last_activity"; then
        print_warning "sessions.last_activity column missing - adding..."
        sqlite3 "$db" "ALTER TABLE sessions ADD COLUMN last_activity DATETIME;"
        sqlite3 "$db" "UPDATE sessions SET last_activity = created_at WHERE last_activity IS NULL;"
        print_success "Added last_activity column"
        return 1
    fi
    
    if [ "$needs_recreate" = true ]; then
        sqlite3 "$db" "
            CREATE TABLE sessions (
                token VARCHAR(64) PRIMARY KEY,
                user_id INTEGER NOT NULL,
                created_at DATETIME NOT NULL,
                expires_at DATETIME NOT NULL,
                last_activity DATETIME NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            );
        "
        print_success "Created sessions table with correct structure"
        return 1
    fi
    
    print_success "sessions table is correct"
    return 0
}

fix_audit_log_table() {
    local db="$1"
    local needs_recreate=false
    
    if ! table_exists "$db" "audit_log"; then
        print_warning "audit_log table does not exist - creating..."
        needs_recreate=true
    elif ! column_exists "$db" "audit_log" "device_id" || ! column_exists "$db" "audit_log" "timestamp"; then
        print_warning "audit_log table has incorrect structure - recreating..."
        sqlite3 "$db" "DROP TABLE IF EXISTS audit_log;"
        needs_recreate=true
    fi
    
    if [ "$needs_recreate" = true ]; then
        sqlite3 "$db" "
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
        print_success "Created audit_log table with correct structure"
        return 1
    fi
    
    print_success "audit_log table is correct"
    return 0
}

create_admin_user() {
    local db="$1"
    
    local admin_exists=$(sqlite3 "$db" "SELECT COUNT(*) FROM users WHERE username='admin';")
    if [ "$admin_exists" = "0" ]; then
        print_warning "No admin user found - creating..."
        
        # Check for bcrypt
        if ! python3 -c "import bcrypt" 2>/dev/null; then
            print_error "bcrypt not installed. Install with: pip3 install bcrypt"
            print_info "Then run this script again or create admin manually."
            return 1
        fi
        
        local admin_password=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
        local password_hash=$(python3 -c "import bcrypt; print(bcrypt.hashpw('$admin_password'.encode(), bcrypt.gensalt()).decode())")
        
        sqlite3 "$db" "INSERT INTO users (username, password_hash, role, is_active, created_at) VALUES ('admin', '$password_hash', 'admin', 1, datetime('now'));"
        
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
        return 1
    fi
    
    print_success "Admin user exists"
    return 0
}

# =============================================================================
# Main Report Function
# =============================================================================

generate_report() {
    local db="$1"
    
    print_header "Database Schema Report"
    
    echo "Database: $db"
    echo "Size: $(du -h "$db" | cut -f1)"
    echo ""
    
    echo "Tables found:"
    sqlite3 "$db" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;" | while read table; do
        local col_count=$(sqlite3 "$db" "PRAGMA table_info($table);" | wc -l)
        local row_count=$(sqlite3 "$db" "SELECT COUNT(*) FROM $table;" 2>/dev/null || echo "0")
        echo "  - $table ($col_count columns, $row_count rows)"
    done
    echo ""
    
    echo "Auth tables detail:"
    for table in users sessions audit_log; do
        if table_exists "$db" "$table"; then
            echo ""
            echo "  [$table]"
            sqlite3 "$db" "PRAGMA table_info($table);" | while IFS='|' read cid name type notnull dflt pk; do
                local pk_mark=""
                [ "$pk" = "1" ] && pk_mark=" (PK)"
                echo "    - $name: $type$pk_mark"
            done
        else
            echo "  [$table] - NOT FOUND"
        fi
    done
}

# =============================================================================
# Main
# =============================================================================

main() {
    print_header "BetterDesk Database Schema Checker v$SCRIPT_VERSION"
    
    # Check for sqlite3
    if ! command -v sqlite3 &>/dev/null; then
        print_error "sqlite3 is required but not installed"
        print_info "Install with: apt install sqlite3"
        exit 1
    fi
    
    # Find database
    local db_path=$(find_database "$1")
    if [ -z "$db_path" ]; then
        print_error "Could not find RustDesk database"
        echo ""
        print_info "Usage: $0 [path_to_database]"
        echo ""
        print_info "Example:"
        echo "  $0 /opt/rustdesk/db_v2.sqlite3"
        exit 1
    fi
    
    print_success "Found database: $db_path"
    
    # Check if peer table exists (basic RustDesk requirement)
    if ! table_exists "$db_path" "peer"; then
        print_error "This does not appear to be a valid RustDesk database (no peer table)"
        exit 1
    fi
    
    # Create backup
    local backup_path="${db_path}.backup-$(date +%Y%m%d_%H%M%S)"
    cp "$db_path" "$backup_path"
    print_success "Created backup: $backup_path"
    
    # Run checks and fixes
    print_header "Checking & Fixing Schema"
    
    local total_fixes=0
    
    # Fix peer table
    fix_peer_table "$db_path" || ((total_fixes++))
    
    # Fix auth tables
    fix_users_table "$db_path" && true || ((total_fixes++))
    fix_sessions_table "$db_path" && true || ((total_fixes++))
    fix_audit_log_table "$db_path" && true || ((total_fixes++))
    
    # Create admin if needed
    create_admin_user "$db_path" && true || ((total_fixes++))
    
    # Generate report
    generate_report "$db_path"
    
    # Summary
    print_header "Summary"
    
    if [ $total_fixes -gt 0 ]; then
        print_success "Fixed $total_fixes issue(s)"
        print_info "Backup saved at: $backup_path"
    else
        print_success "Database schema is correct - no fixes needed"
        # Remove backup if no changes were made
        rm -f "$backup_path"
    fi
    
    echo ""
    print_info "If you still have login issues, restart the BetterDesk service:"
    echo "  sudo systemctl restart betterdesk.service"
    echo ""
}

main "$@"
