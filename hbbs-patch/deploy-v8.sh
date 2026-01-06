#!/bin/bash
set -e

echo "=== Deploying HBBS + HBBR v8 (bidirectional ban check) ==="

# Backup
echo "Creating backups..."
cp /opt/rustdesk/hbbs /opt/rustdesk/hbbs.v7.backup 2>/dev/null || true
cp /opt/rustdesk/hbbr /opt/rustdesk/hbbr.v7.backup 2>/dev/null || true

# Stop
echo "Stopping old processes..."
pkill -9 hbbs || true
pkill -9 hbbr || true
sleep 2

# Copy
echo "Copying v8 binaries..."
cp /tmp/hbbs-ban-check-package/hbbs /opt/rustdesk/hbbs
cp /tmp/hbbs-ban-check-package/hbbr /opt/rustdesk/hbbr
chmod +x /opt/rustdesk/hbbs /opt/rustdesk/hbbr

# Clear logs
echo "Clearing logs..."
echo "" > /var/log/rustdesk/signalserver.log
echo "" > /var/log/rustdesk/hbbr.log

# Start HBBS
echo "Starting HBBS v8..."
cd /opt/rustdesk
nohup ./hbbs -k _ -r YOUR_SERVER_IP:21117 >> /var/log/rustdesk/signalserver.log 2>&1 &
sleep 2

# Start HBBR  
echo "Starting HBBR v8..."
nohup ./hbbr -k _ >> /var/log/rustdesk/hbbr.log 2>&1 &
sleep 2

# Verify
echo ""
echo "Processes:"
ps aux | grep -E "hbbs|hbbr" | grep -v grep

echo ""
echo "Ports:"
netstat -tlnp 2>/dev/null | grep -E "21116|21117" || ss -tlnp | grep -E "21116|21117"

echo ""
echo "=== Deployment v8 complete ==="
echo "New features:"
echo "- SOURCE device ban check (device initiating connection)"
echo "- TARGET device ban check (device being connected to)"
echo "- Bidirectional blocking"
