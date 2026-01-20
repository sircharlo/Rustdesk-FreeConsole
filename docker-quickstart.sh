# Quick Setup Script for Docker
#!/bin/bash

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

# Ask user about existing RustDesk data
read -p "Do you have existing RustDesk data to import? [y/N] " -n 1 -r
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

echo ""
echo "🚀 Starting BetterDesk Console..."

# Pull latest images
$COMPOSE_CMD pull

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
echo "   Update: $COMPOSE_CMD pull && $COMPOSE_CMD up -d"