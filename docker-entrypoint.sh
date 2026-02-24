#!/bin/bash
# Docker Entrypoint for BetterDesk Console (Node.js)
set -e

echo "🚀 BetterDesk Console - Container Startup"
echo "========================================"

# Configuration
DB_PATH="${DB_PATH:-/opt/rustdesk/db_v2.sqlite3}"
DATA_DIR="${DATA_DIR:-/app/data}"

# Support legacy ADMIN_PASSWORD environment variable
if [ -n "$ADMIN_PASSWORD" ] && [ -z "$DEFAULT_ADMIN_PASSWORD" ]; then
    export DEFAULT_ADMIN_PASSWORD="$ADMIN_PASSWORD"
fi

if [ -n "$ADMIN_USERNAME" ] && [ -z "$DEFAULT_ADMIN_USERNAME" ]; then
    export DEFAULT_ADMIN_USERNAME="$ADMIN_USERNAME"
fi

# Ensure data directory exists
mkdir -p "$DATA_DIR"

# Wait for database if it doesn't exist yet
if [ ! -f "$DB_PATH" ]; then
    echo "⚠️  Database not found: $DB_PATH"
    echo "    Waiting for HBBS to create database..."
    
    # Wait up to 60 seconds for the database to be created by HBBS
    for i in {1..60}; do
        if [ -f "$DB_PATH" ]; then
            echo "📂 Database detected, proceeding..."
            break
        fi
        echo "    Waiting for database... ($i/60)"
        sleep 1
    done
    
    if [ ! -f "$DB_PATH" ]; then
        echo "⚠️  Database still not found after 60 seconds"
        echo "    Starting application anyway (it will create a fresh DB if possible)"
    fi
else
    echo "📂 Database found: $DB_PATH"
fi

echo ""
echo "🌟 Starting BetterDesk Console..."
echo "   Node version: $(node -v)"
echo "   Web Interface: http://localhost:5000"
echo ""

# Handle random password generation if no password provided
if [ -z "$DEFAULT_ADMIN_PASSWORD" ] ; then
    # Generate a random password if none provided, for security
    RAND_PASS=$(node -e "console.log(require('crypto').randomBytes(12).toString('base64'))" 2>/dev/null) || RAND_PASS=""

    # Verify that password generation succeeded
    if [ -z "$RAND_PASS" ]; then
        echo "❌ Failed to generate a secure random admin password using Node.js crypto." >&2
        echo "   Please set DEFAULT_ADMIN_PASSWORD (or ADMIN_PASSWORD) environment variable explicitly." >&2
        exit 1
    fi
    export DEFAULT_ADMIN_PASSWORD="$RAND_PASS"
    
    echo "🔐 GENERATED ADMIN PASSWORD:"
    echo "========================================"
    echo "   Username: ${DEFAULT_ADMIN_USERNAME:-admin}"
    echo "   Password: $RAND_PASS"
    echo "========================================"
    echo "⚠️  IMPORTANT: Change this password after first login!"
    echo ""
    
    # Save to file as a backup
    echo "Admin credentials generated on $(date)" > "$DATA_DIR/admin_credentials.txt"
    echo "Username: ${DEFAULT_ADMIN_USERNAME:-admin}" >> "$DATA_DIR/admin_credentials.txt"
    echo "Password: $RAND_PASS" >> "$DATA_DIR/admin_credentials.txt"
fi

# Start Node.js application
exec node server.js