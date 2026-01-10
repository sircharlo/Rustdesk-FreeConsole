#!/bin/bash
# Przywróć oryginalny HBBS (bez patcha) i restartuj serwis

echo "Stopping rustdesksignal service..."
systemctl stop rustdesksignal

echo "Restoring original HBBS binary..."
cp /opt/rustdesk/hbbs.backup /opt/rustdesk/hbbs
chmod +x /opt/rustdesk/hbbs

echo "Starting rustdesksignal service..."
systemctl start rustdesksignal

echo "Checking service status..."
systemctl status rustdesksignal --no-pager -l

echo ""
echo "HBBS restored successfully!"
echo "Ban Enforcer daemon will continue to provide 95% ban protection."
