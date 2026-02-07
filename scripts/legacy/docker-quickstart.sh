#!/bin/bash
# Quick Setup Script for Docker

set -e

echo "🐳 BetterDesk Console Docker Quick Setup"
echo "========================================"

# Check if Docker is installed
if ! command -v docker &>/dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if docker-compose is available
if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
else
    echo "❌ Docker Compose is not available. Please install docker-compose."
    exit 1
fi

echo "✅ Using: $COMPOSE_CMD"

# Set up environment
export FLASK_SECRET_KEY=$(openssl rand -hex 32 2>/dev/null || echo "change-this-secret-key")
export RUSTDESK_DATA_PATH="./data"

# Create data directory
mkdir -p ./data

echo ""
echo "📁 Data directory: $(pwd)/data"
echo "🔑 Flask secret: ${FLASK_SECRET_KEY:0:16}..."
echo ""

# Auto-detect existing RustDesk installation
RUSTDESK_FOUND=false
RUSTDESK_PATHS=(
    "/opt/rustdesk"
    "/var/lib/rustdesk"
    "/root/.rustdesk"
    "$HOME/.rustdesk"
)

echo "🔍 Searching for existing RustDesk installation..."
for path in "${RUSTDESK_PATHS[@]}"; do
    if [ -d "$path" ]; then
        # Check for RustDesk files
        if [ -f "$path/hbbs" ] || [ -f "$path/hbbs-v8-api" ] || ls "$path"/*.sqlite3 &>/dev/null 2>&1; then
            echo "✅ Found RustDesk installation at: $path"
            RUSTDESK_FOUND=true
            EXISTING_RUSTDESK_PATH="$path"
            break
        fi
    fi
done

if [ "$RUSTDESK_FOUND" = true ]; then
    echo ""
    echo "🎯 Existing RustDesk installation detected!"
    read -p "Do you want to import data from existing installation? [Y/n] " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        echo "📦 Importing data from: $EXISTING_RUSTDESK_PATH"
        
        # Copy database files
        for db in "db_v2.sqlite3" "db.sqlite3" "rustdesk.db"; do
            if [ -f "$EXISTING_RUSTDESK_PATH/$db" ]; then
                cp "$EXISTING_RUSTDESK_PATH/$db" "./data/"
                echo "✅ Copied $db"
            fi
        done
        
        # Copy key files
        for key in "id_ed25519" "id_ed25519.pub" "key.pem"; do
            if [ -f "$EXISTING_RUSTDESK_PATH/$key" ]; then
                cp "$EXISTING_RUSTDESK_PATH/$key" "./data/"
                echo "✅ Copied $key"
            fi
        done
        
        echo "✅ Data import completed"
    else
        echo "⏭️  Skipping data import"
    fi
else
    echo "ℹ️  No existing RustDesk installation found"
    echo ""
    # Ask user about existing RustDesk data from other source
    read -p "Do you have RustDesk data from another source to import? [y/N] " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Please copy your existing RustDesk data to: $(pwd)/data"
        echo "Required files:"
        echo "  - id_ed25519 (private key)"
        echo "  - id_ed25519.pub (public key)"
        echo "  - db_v2.sqlite3 (database)"
        echo ""
        read -p "Press Enter when ready to continue..."
    fi
fi

echo ""
echo "🚀 Starting BetterDesk Console..."

# Build images locally (required - images are not published to Docker Hub)
echo "🔨 Building Docker images locally..."
$COMPOSE_CMD build

# Run install-docker.sh if it exists
if [ -f "./install-docker.sh" ]; then
    echo "📦 Running BetterDesk installation..."
    chmod +x ./install-docker.sh
    sudo ./install-docker.sh
fi

# Start services
$COMPOSE_CMD up -d hbbs hbbr

# Wait for services to be ready
echo "⏳ Waiting for RustDesk services to start..."
sleep 5

# Start console
$COMPOSE_CMD up -d betterdesk-console

# Show status
echo ""
echo "📊 Service Status:"
$COMPOSE_CMD ps

echo ""
echo "🎉 BetterDesk Console is starting up!"
echo ""
echo "📱 Access Points:"
echo "   Web Console: http://localhost:5000"
echo "   RustDesk ID Server: localhost:21115"
echo "   Relay Server: localhost:21117"
echo ""

# Wait for console to be ready and show logs
echo "📋 Console logs (Ctrl+C to exit):"
$COMPOSE_CMD logs -f betterdesk-console

echo ""
echo "🔧 Management Commands:"
echo "   View logs: $COMPOSE_CMD logs -f"
echo "   Stop all: $COMPOSE_CMD down"
echo "   Restart: $COMPOSE_CMD restart"
echo "   Rebuild: $COMPOSE_CMD build && $COMPOSE_CMD up -d"