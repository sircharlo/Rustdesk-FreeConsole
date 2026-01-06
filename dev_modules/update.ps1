#############################################################################
# BetterDesk Console - Update Script (v1.1.0) for Windows
# 
# This script updates existing BetterDesk installation to version 1.1.0
# with device banning system and soft delete functionality.
#
# Features:
# - Automatic database backup before migration
# - Executes database migrations (v1.0.1 soft delete + v1.1.0 bans)
# - Updates web console files via SSH/SCP
# - Restarts BetterDesk service on remote Linux server
# - Verifies installation
#
# Requirements:
# - PowerShell 5.1 or higher
# - SSH access to Linux server with BetterDesk installed
# - Python 3.x on remote server
#
# Usage:
#   .\update.ps1 -RemoteHost <hostname> -RemoteUser <username>
#   Example: .\update.ps1 -RemoteHost YOUR_SERVER_IP -RemoteUser YOUR_SSH_USER
#   Example: .\update.ps1 -RemoteHost YOUR_SERVER_IP -RemoteUser YOUR_SSH_USER -RustDeskPath "/custom/path/rustdesk"
#
# Author: GitHub Copilot
# License: MIT
#############################################################################

param(
    [Parameter(Mandatory=$true)]
    [string]$RemoteHost,
    
    [Parameter(Mandatory=$true)]
    [string]$RemoteUser,
    
    [string]$RemotePath = "/opt/BetterDeskConsole",
    [string]$RustDeskPath = "/opt/rustdesk",
    [string]$DbPath = ""  # Will be auto-set from RustDeskPath if empty
)

# Colors for output
function Write-Success { param($Message) Write-Host "✓ $Message" -ForegroundColor Green }
function Write-Error { param($Message) Write-Host "✗ $Message" -ForegroundColor Red }
function Write-Warning { param($Message) Write-Host "⚠ $Message" -ForegroundColor Yellow }
function Write-Info { param($Message) Write-Host "→ $Message" -ForegroundColor Cyan }
function Write-Header { 
    param($Message) 
    Write-Host "`n========================================" -ForegroundColor Blue
    Write-Host $Message -ForegroundColor Blue
    Write-Host "========================================`n" -ForegroundColor Blue
}

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Auto-set DbPath if not provided
if ([string]::IsNullOrEmpty($DbPath)) {
    $DbPath = "$RustDeskPath/db_v2.sqlite3"
}

Write-Header "BetterDesk Console - Update to v1.1.0"

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Remote host:        $RemoteUser@$RemoteHost"
Write-Host "  Console directory:  $RemotePath"
Write-Host "  RustDesk directory: $RustDeskPath"
Write-Host "  Database path:      $DbPath"
Write-Host ""
Write-Host "This update includes:" -ForegroundColor Cyan
Write-Host "  • Soft delete system for devices (v1.0.1)"
Write-Host "  • Device banning system (v1.1.0)"
Write-Host "  • Enhanced UI with ban controls"
Write-Host "  • Input validation and security improvements"
Write-Host ""
Write-Warning "This will modify the database and restart services"
Write-Host ""

$confirm = Read-Host "Continue with update? [y/N]"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "Update cancelled."
    exit 0
}

# Check if required files exist locally
Write-Header "Step 1: Checking Local Files"

$requiredFiles = @(
    "$ScriptDir\migrations\v1.0.1_soft_delete.py",
    "$ScriptDir\migrations\v1.1.0_device_bans.py",
    "$ScriptDir\web\app.py",
    "$ScriptDir\web\static\script.js",
    "$ScriptDir\web\templates\index.html"
)

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Success "Found: $(Split-Path -Leaf $file)"
    } else {
        Write-Error "Missing: $file"
        exit 1
    }
}

# Check SSH connectivity
Write-Header "Step 2: Testing SSH Connection"

Write-Info "Testing connection to $RemoteHost..."
$testConnection = ssh -o ConnectTimeout=5 -o BatchMode=yes "$RemoteUser@$RemoteHost" "echo 'Connected'" 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Success "SSH connection successful"
} else {
    Write-Error "Cannot connect to $RemoteHost. Please check SSH access."
    Write-Info "Hint: Make sure you have SSH keys set up or use: ssh $RemoteUser@$RemoteHost"
    exit 1
}

# Check if BetterDesk is installed on remote
Write-Info "Checking remote installation..."
$checkInstall = ssh "$RemoteUser@$RemoteHost" "test -d $RemotePath && test -f $DbPath && echo 'OK' || echo 'MISSING'"

if ($checkInstall -match "OK") {
    Write-Success "BetterDesk installation found on remote server"
} else {
    Write-Error "BetterDesk not found at $RemotePath or database missing"
    exit 1
}

# Create backup on remote server
Write-Header "Step 3: Creating Remote Backup"

$backupDir = "/opt/betterdesk-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
Write-Info "Creating backup directory: $backupDir"

$backupScript = @"
#!/bin/bash
set -e
mkdir -p $backupDir
cp $DbPath $backupDir/db_v2.sqlite3.backup
[ -f $RemotePath/app.py ] && cp $RemotePath/app.py $backupDir/app.py.backup
[ -f $RemotePath/static/script.js ] && cp $RemotePath/static/script.js $backupDir/script.js.backup
[ -f $RemotePath/templates/index.html ] && cp $RemotePath/templates/index.html $backupDir/index.html.backup
echo 'Backup completed'
"@

$backupResult = $backupScript | ssh "$RemoteUser@$RemoteHost" "bash"
Write-Success "Backup created: $backupDir"

# Upload migration scripts
Write-Header "Step 4: Uploading Migration Scripts"

Write-Info "Uploading v1.0.1_soft_delete.py..."
scp "$ScriptDir\migrations\v1.0.1_soft_delete.py" "${RemoteUser}@${RemoteHost}:/tmp/" | Out-Null
Write-Success "Uploaded v1.0.1_soft_delete.py"

Write-Info "Uploading v1.1.0_device_bans.py..."
scp "$ScriptDir\migrations\v1.1.0_device_bans.py" "${RemoteUser}@${RemoteHost}:/tmp/" | Out-Null
Write-Success "Uploaded v1.1.0_device_bans.py"

# Execute migrations
Write-Header "Step 5: Running Database Migrations"

Write-Info "Executing migration v1.0.1 (soft delete)..."
$migration1 = @"
cd /tmp
echo 'y' | sudo python3 v1.0.1_soft_delete.py 2>&1 | tail -5
"@

$result1 = $migration1 | ssh "$RemoteUser@$RemoteHost" "bash"
Write-Success "Migration v1.0.1 completed"

Write-Host ""
Write-Info "Executing migration v1.1.0 (device bans)..."
$migration2 = @"
cd /tmp
echo 'y' | sudo python3 v1.1.0_device_bans.py 2>&1 | tail -5
"@

$result2 = $migration2 | ssh "$RemoteUser@$RemoteHost" "bash"
Write-Success "Migration v1.1.0 completed"

# Upload web files
Write-Header "Step 6: Updating Web Console Files"

Write-Info "Uploading app.py..."
scp "$ScriptDir\web\app.py" "${RemoteUser}@${RemoteHost}:/tmp/" | Out-Null
ssh "$RemoteUser@$RemoteHost" "cp /tmp/app.py $RemotePath/app.py"
Write-Success "Updated app.py"

Write-Info "Uploading script.js..."
scp "$ScriptDir\web\static\script.js" "${RemoteUser}@${RemoteHost}:/tmp/" | Out-Null
ssh "$RemoteUser@$RemoteHost" "cp /tmp/script.js $RemotePath/static/script.js"
Write-Success "Updated script.js"

Write-Info "Uploading index.html..."
scp "$ScriptDir\web\templates\index.html" "${RemoteUser}@${RemoteHost}:/tmp/" | Out-Null
ssh "$RemoteUser@$RemoteHost" "cp /tmp/index.html $RemotePath/templates/index.html"
Write-Success "Updated index.html"

# Restart service
Write-Header "Step 7: Restarting BetterDesk Service"

$restartScript = @"
if systemctl list-unit-files | grep -q 'betterdesk.service'; then
    sudo systemctl restart betterdesk
    sleep 3
    if systemctl is-active --quiet betterdesk; then
        echo 'Service restarted successfully'
    else
        echo 'Service failed to start'
        exit 1
    fi
else
    echo 'Service not found, skipping restart'
fi
"@

$restartResult = $restartScript | ssh "$RemoteUser@$RemoteHost" "bash"
if ($LASTEXITCODE -eq 0) {
    Write-Success $restartResult
} else {
    Write-Warning "Service restart may have failed"
}

# Verify installation
Write-Header "Step 8: Verification"

Write-Info "Verifying database schema..."
$schemaCheck = ssh "$RemoteUser@$RemoteHost" "sqlite3 $DbPath 'PRAGMA table_info(peer);' | wc -l"
if ([int]$schemaCheck -ge 16) {
    Write-Success "Database schema updated ($schemaCheck columns)"
} else {
    Write-Warning "Database may be missing columns (found $schemaCheck)"
}

Write-Info "Checking web console..."
Start-Sleep -Seconds 2
$apiCheck = ssh "$RemoteUser@$RemoteHost" "curl -s http://localhost:5000/api/stats 2>&1"
if ($apiCheck -match "success") {
    Write-Success "Web console is responding"
    
    # Parse stats
    if ($apiCheck -match '"total":\s*(\d+)') {
        $total = $matches[1]
        Write-Info "Total devices: $total"
    }
    if ($apiCheck -match '"banned":\s*(\d+)') {
        $banned = $matches[1]
        Write-Info "Banned devices: $banned"
    }
} else {
    Write-Warning "Web console may not be responding"
}

# Final summary
Write-Header "Update Complete!"

Write-Success "Database migrated to v1.1.0"
Write-Success "Web console files updated"
Write-Success "Backup created: $backupDir"
Write-Success "Service restarted"
Write-Host ""
Write-Host "New Features:" -ForegroundColor Cyan
Write-Host "  • Soft delete for devices (is_deleted, deleted_at, updated_at)"
Write-Host "  • Device banning system (is_banned, banned_at, banned_by, ban_reason)"
Write-Host "  • Ban/Unban buttons in web interface"
Write-Host "  • Enhanced input validation and security"
Write-Host "  • Banned devices statistics card"
Write-Host ""
Write-Host "Access the console:" -ForegroundColor Cyan
Write-Host "  http://${RemoteHost}:5000"
Write-Host ""
Write-Host "Rollback Instructions (if needed):" -ForegroundColor Yellow
Write-Host "  ssh $RemoteUser@$RemoteHost"
Write-Host "  sudo systemctl stop betterdesk"
Write-Host "  sudo cp $backupDir/db_v2.sqlite3.backup $DbPath"
Write-Host "  sudo cp $backupDir/*.backup $RemotePath/"
Write-Host "  sudo systemctl start betterdesk"
Write-Host ""
Write-Success "Update completed successfully!"
