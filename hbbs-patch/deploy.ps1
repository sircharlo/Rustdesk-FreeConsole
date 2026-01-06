# Quick HBBS Deployment Script
# Deploys pre-compiled binary to RustDesk server
# Usage: .\deploy.ps1 [binary-name]
# Example: .\deploy.ps1 hbbs-v3-patched

param(
    [Parameter(Mandatory=$false)]
    [string]$Binary = "hbbs-v3-patched",
    
    [Parameter(Mandatory=$false)]
    [string]$Server = "YOUR_SSH_USER@YOUR_SERVER_IP"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "HBBS Quick Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if binary exists
$BinaryPath = Join-Path $PSScriptRoot $Binary
if (-not (Test-Path $BinaryPath)) {
    Write-Host "[ERROR] Binary not found: $BinaryPath" -ForegroundColor Red
    exit 1
}

$FileSize = (Get-Item $BinaryPath).Length / 1MB
Write-Host "[1/4] Found binary: $Binary ($([math]::Round($FileSize, 2)) MB)" -ForegroundColor Yellow

# Upload binary
Write-Host "[2/4] Uploading to server..." -ForegroundColor Yellow
scp $BinaryPath "${Server}:/tmp/hbbs-new"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Upload failed" -ForegroundColor Red
    exit 1
}
Write-Host "      Upload complete" -ForegroundColor Green

# Deploy on server
Write-Host "[3/4] Installing on server..." -ForegroundColor Yellow
$DeployScript = @"
# Stop service
sudo systemctl stop rustdesksignal

# Backup current version
BACKUP_NAME="hbbs.backup.`$(date +%s)"
sudo cp /opt/rustdesk/hbbs /opt/rustdesk/`$BACKUP_NAME
echo "Backed up to: `$BACKUP_NAME"

# Install new version
sudo cp /tmp/hbbs-new /opt/rustdesk/hbbs
sudo chmod +x /opt/rustdesk/hbbs
sudo chown root:root /opt/rustdesk/hbbs

# Start service
sudo systemctl start rustdesksignal

# Wait for startup
sleep 2

# Check status
sudo systemctl status rustdesksignal --no-pager
"@

ssh -t $Server $DeployScript

if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Deployment failed" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[4/4] Verifying deployment..." -ForegroundColor Yellow

# Check logs for errors
$LogCheck = @"
if sudo grep -i "error\|panic" /var/log/rustdesk/signalserver.error | tail -5 | grep -q .; then
    echo "WARNING: Errors found in logs"
    exit 1
else
    echo "No errors in logs"
fi
"@

ssh $Server $LogCheck

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Deployment Successful!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "[WARNING] Service started but errors detected in logs" -ForegroundColor Yellow
    Write-Host "Check logs: ssh $Server 'sudo tail -50 /var/log/rustdesk/signalserver.error'" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Available backups:" -ForegroundColor Cyan
ssh $Server "ls -lh /opt/rustdesk/hbbs.backup.* 2>/dev/null | tail -5 || echo 'No backups found'"
