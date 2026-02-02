#!/bin/bash
# =============================================================================
# Quick Fix: Add missing peer table columns
# =============================================================================
# This script quickly adds missing columns to the peer table.
# Run this if you get errors like "no such column: updated_at"
#
# Usage: sudo ./fix_peer_columns.sh [database_path]
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Find database
DB_PATH="$1"
if [ -z "$DB_PATH" ]; then
    for path in "/opt/rustdesk/db_v2.sqlite3" "/var/lib/rustdesk/db_v2.sqlite3" "/data/db_v2.sqlite3"; do
        if [ -f "$path" ]; then
            DB_PATH="$path"
            break
        fi
    done
fi

if [ -z "$DB_PATH" ] || [ ! -f "$DB_PATH" ]; then
    print_error "Database not found!"
    echo "Usage: $0 [path_to_db_v2.sqlite3]"
    exit 1
fi

print_info "Database: $DB_PATH"

# Backup
cp "$DB_PATH" "${DB_PATH}.backup-$(date +%Y%m%d_%H%M%S)"
print_success "Backup created"

# Required columns for peer table
declare -A COLUMNS=(
    ["last_online"]="TEXT"
    ["is_deleted"]="INTEGER DEFAULT 0"
    ["deleted_at"]="INTEGER"
    ["updated_at"]="INTEGER"
    ["is_banned"]="INTEGER DEFAULT 0"
    ["banned_at"]="TEXT"
    ["banned_by"]="TEXT"
    ["ban_reason"]="TEXT"
)

echo ""
print_info "Checking peer table columns..."

for col in "${!COLUMNS[@]}"; do
    if ! sqlite3 "$DB_PATH" "PRAGMA table_info(peer);" | grep -q "|$col|"; then
        print_warning "Adding missing column: $col"
        sqlite3 "$DB_PATH" "ALTER TABLE peer ADD COLUMN $col ${COLUMNS[$col]};"
        print_success "Added: $col"
    else
        echo "  ✓ $col exists"
    fi
done

echo ""
print_success "All peer columns verified!"
echo ""
print_info "Restart BetterDesk service:"
echo "  sudo systemctl restart betterdesk.service"
echo ""
