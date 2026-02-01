#!/bin/bash
# ==============================================
# BetterDesk Console v1.5 - Complete Clean Deployment
# Date: 2026-02-01
# ==============================================

set -e

echo "========================================"
echo "   BetterDesk Console v1.5 Deployment"
echo "========================================"
echo ""

WEB_DIR="/opt/BetterDeskConsole/web"
BACKUP_DIR="/opt/BetterDeskConsole/backups/pre_v15_$(date +%Y%m%d_%H%M%S)"

# Create backup
echo "[1/5] Creating backup..."
sudo mkdir -p "$BACKUP_DIR"
sudo cp -r "$WEB_DIR" "$BACKUP_DIR/"
echo "     Backup created: $BACKUP_DIR"

# Clean old files from templates
echo ""
echo "[2/5] Cleaning old template files..."
sudo rm -f "$WEB_DIR/templates/base.html"
sudo rm -f "$WEB_DIR/templates/clients.html"
sudo rm -f "$WEB_DIR/templates/dashboard.html"
sudo rm -f "$WEB_DIR/templates/minimal_client.html"
sudo rm -f "$WEB_DIR/templates/minimal_client.html.backup"
sudo rm -f "$WEB_DIR/templates/settings.html"
sudo rm -f "$WEB_DIR/templates/updates.html"
sudo rm -f "$WEB_DIR/templates/index_v14.html"
echo "     Old templates removed"

# Clean old files from static
echo ""
echo "[3/5] Cleaning old static files..."
sudo rm -f "$WEB_DIR/static/clients.css"
sudo rm -f "$WEB_DIR/static/clients.js"
sudo rm -f "$WEB_DIR/static/dashboard.css"
sudo rm -f "$WEB_DIR/static/dashboard.js"
sudo rm -f "$WEB_DIR/static/minimal_client.css"
sudo rm -f "$WEB_DIR/static/minimal_client.css.backup"
sudo rm -f "$WEB_DIR/static/minimal_client.js"
sudo rm -f "$WEB_DIR/static/minimal_client.js.backup2"
sudo rm -f "$WEB_DIR/static/settings.css"
sudo rm -f "$WEB_DIR/static/sidebar.js"
sudo rm -f "$WEB_DIR/static/sidebar.css"
sudo rm -f "$WEB_DIR/static/updates.css"
sudo rm -f "$WEB_DIR/static/updates.js"
sudo rm -f "$WEB_DIR/static/performance-config.css"
sudo rm -f "$WEB_DIR/static/script_v14.js"
sudo rm -f "$WEB_DIR/static/script.js"
echo "     Old static files removed"

# Clean old Python files
echo ""
echo "[4/5] Cleaning old Python files..."
sudo rm -f "$WEB_DIR/app.py"
sudo rm -f "$WEB_DIR/app.py.backup-"
echo "     Old Python files removed"

# Deploy new files from /tmp/
echo ""
echo "[5/5] Deploying new files..."
if [ -f /tmp/deploy_v15/app_v14.py ]; then
    # Templates
    sudo cp /tmp/deploy_v15/index_v15.html "$WEB_DIR/templates/"
    sudo cp /tmp/deploy_v15/login.html "$WEB_DIR/templates/"
    sudo cp /tmp/deploy_v15/client_generator.html "$WEB_DIR/templates/"
    
    # Static files
    sudo cp /tmp/deploy_v15/style.css "$WEB_DIR/static/"
    sudo cp /tmp/deploy_v15/script_v15.js "$WEB_DIR/static/"
    sudo cp /tmp/deploy_v15/client_generator.css "$WEB_DIR/static/"
    sudo cp /tmp/deploy_v15/client_generator.js "$WEB_DIR/static/"
    
    # Python app
    sudo cp /tmp/deploy_v15/app_v14.py "$WEB_DIR/"
    sudo cp /tmp/deploy_v15/auth.py "$WEB_DIR/"
    sudo cp /tmp/deploy_v15/client_generator_module.py "$WEB_DIR/"
    
    echo "     New files deployed"
else
    echo "     ERROR: Deploy files not found in /tmp/deploy_v15/"
    echo "     Please upload files first"
    exit 1
fi

# Set permissions
echo ""
echo "Setting permissions..."
# Use current user as owner (parameterized for different environments)
DEPLOY_USER="${DEPLOY_USER:-$(whoami)}"
sudo chown -R "$DEPLOY_USER:$DEPLOY_USER" "$WEB_DIR"
sudo chmod -R 755 "$WEB_DIR"

# Restart service
echo ""
echo "Restarting BetterDesk service..."
sudo systemctl restart betterdesk
sleep 2

# Show status
echo ""
echo "========================================"
echo "   Deployment Complete!"
echo "========================================"
echo ""
echo "Files deployed:"
ls -la "$WEB_DIR/templates/" 2>/dev/null | grep -E "\.html$" | awk '{print "  • " $NF}'
echo ""
ls -la "$WEB_DIR/static/" 2>/dev/null | grep -E "\.(css|js)$" | awk '{print "  • " $NF}'
echo ""
echo "Service status:"
sudo systemctl status betterdesk --no-pager | head -5
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
