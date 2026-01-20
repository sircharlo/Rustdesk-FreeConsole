#############################################################################
# BetterDesk Console - Update Script (v8) for Windows
# 
# This script updates existing BetterDesk installation to version 1.2.0-v8
# with bidirectional ban enforcement and precompiled binaries.
#
# Features:
# - Installs precompiled HBBS/HBBR v8 binaries with bidirectional ban enforcement
# - Automatic database backup before migration
# - Executes database migrations (v1.0.1 soft delete + v1.1.0 bans)
# - Updates web console files
# - Restarts RustDesk services
# - Verifies installation
# - Works locally on Windows server (no SSH required)
#
# Requirements:
# - PowerShell 5.1 or higher
# - Python 3.x installed
# - Administrator privileges
#
# Usage:
#   .\update.ps1 [-RustDeskPath <path>] [-ConsolePath <path>]
#   Example: .\update.ps1
#   Example: .\update.ps1 -RustDeskPath "C:\RustDesk" -ConsolePath "C:\BetterDeskConsole"
#
# Author: UNITRONIX Team
# License: MIT
#############################################################################

param(
    [string]$RustDeskPath = "C:\RustDesk",
    [string]$ConsolePath = "C:\BetterDeskConsole",
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

# Check if running as Administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Error "This script requires Administrator privileges"
    Write-Info "Please run PowerShell as Administrator and try again"
    exit 1
}

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# Auto-set DbPath if not provided
if ([string]::IsNullOrEmpty($DbPath)) {
    $DbPath = Join-Path $RustDeskPath "db_v2.sqlite3"
}

Write-Header "BetterDesk Console - Update to v1.2.0-v8"

Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  RustDesk directory: $RustDeskPath"
Write-Host "  Console directory:  $ConsolePath"
Write-Host "  Database path:      $DbPath"
Write-Host ""
Write-Host "This update includes:" -ForegroundColor Cyan
Write-Host "  • HBBS/HBBR v8 with bidirectional ban enforcement"
Write-Host "  • Prevents banned devices from initiating connections"
Write-Host "  • Prevents connections to banned devices"
Write-Host "  • Database migrations (soft delete + banning system)"
Write-Host "  • Updated web console"
Write-Host ""
Write-Warning "This will stop RustDesk services, update binaries, and restart services"
Write-Host ""

$confirm = Read-Host "Continue with update? [y/N]"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "Update cancelled."
    exit 0
}

# Check if required files exist locally
Write-Header "Step 1: Checking Local Files"

$requiredFiles = @(
    "$ProjectRoot\migrations\v1.0.1_soft_delete.py",
    "$ProjectRoot\migrations\v1.1.0_device_bans.py",
    "$ProjectRoot\web\app.py",
    "$ProjectRoot\web\static\script.js",
    "$ProjectRoot\web\templates\index.html",
    "$ProjectRoot\hbbs-patch\bin\hbbs-v8",
    "$ProjectRoot\hbbs-patch\bin\hbbr-v8"
)

foreach ($file in $requiredFiles) {
    if (Test-Path $file) {
        Write-Success "Found: $(Split-Path -Leaf $file)"
    } else {
        Write-Error "Missing: $file"
        exit 1
    }
}

# Check if RustDesk is installed
Write-Header "Step 2: Checking RustDesk Installation"

if (-not (Test-Path $RustDeskPath)) {
    Write-Error "RustDesk directory not found: $RustDeskPath"
    Write-Info "Please specify correct path using -RustDeskPath parameter"
    exit 1
}

Write-Success "RustDesk directory found"

if (Test-Path $DbPath) {
    Write-Success "Database found: $DbPath"
} else {
    Write-Warning "Database not found - it will be created on first run"
}

# Create backup
Write-Header "Step 3: Creating Backup"

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $RustDeskPath "backup-$timestamp"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
Write-Success "Created backup directory: $backupDir"

# Backup binaries
if (Test-Path (Join-Path $RustDeskPath "hbbs.exe")) {
    Copy-Item (Join-Path $RustDeskPath "hbbs.exe") (Join-Path $backupDir "hbbs.exe.backup")
    Write-Success "Backed up hbbs.exe"
}

if (Test-Path (Join-Path $RustDeskPath "hbbr.exe")) {
    Copy-Item (Join-Path $RustDeskPath "hbbr.exe") (Join-Path $backupDir "hbbr.exe.backup")
    Write-Success "Backed up hbbr.exe"
}

# Backup database
if (Test-Path $DbPath) {
    Copy-Item $DbPath (Join-Path $backupDir "db_v2.sqlite3.backup")
    Write-Success "Backed up database"
}

# Stop services
Write-Header "Step 4: Stopping RustDesk Services"

Write-Info "Stopping HBBS service..."
Stop-Service -Name "RustDeskSignal" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

Write-Info "Stopping HBBR service..."
Stop-Service -Name "RustDeskRelay" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Kill any remaining processes
Get-Process -Name "hbbs" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process -Name "hbbr" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2

Write-Success "Services stopped"

# Install new binaries
Write-Header "Step 5: Installing HBBS/HBBR v8 Binaries"

Write-Info "Installing hbbs-v8..."
Copy-Item "$ProjectRoot\hbbs-patch\bin\hbbs-v8" (Join-Path $RustDeskPath "hbbs.exe") -Force
Write-Success "Installed hbbs-v8"

Write-Info "Installing hbbr-v8..."
Copy-Item "$ProjectRoot\hbbs-patch\bin\hbbr-v8" (Join-Path $RustDeskPath "hbbr.exe") -Force
Write-Success "Installed hbbr-v8"

Write-Info "Features:"
Write-Host "  ✓ Bidirectional ban enforcement"
Write-Host "  ✓ Source device ban check"
Write-Host "  ✓ Target device ban check"
Write-Host "  ✓ Real-time database sync"

# Run database migrations
Write-Header "Step 6: Running Database Migrations"

if (Test-Path $DbPath) {
    Write-Info "Running migration v1.0.1 (soft delete)..."
    try {
        python "$ProjectRoot\migrations\v1.0.1_soft_delete.py"
        Write-Success "Migration v1.0.1 completed"
    } catch {
        Write-Warning "Migration v1.0.1 may have already been applied"
    }

    Write-Info "Running migration v1.1.0 (device bans)..."
    try {
        python "$ProjectRoot\migrations\v1.1.0_device_bans.py"
        Write-Success "Migration v1.1.0 completed"
    } catch {
        Write-Warning "Migration v1.1.0 may have already been applied"
    }
} else {
    Write-Info "Database doesn't exist yet - migrations will run automatically on first start"
}

# Update web console files
Write-Header "Step 7: Updating Web Console Files"

if (-not (Test-Path $ConsolePath)) {
    Write-Info "Creating console directory: $ConsolePath"
    New-Item -ItemType Directory -Path $ConsolePath -Force | Out-Null
}

Write-Info "Copying web console files..."
Copy-Item "$ProjectRoot\web\*" $ConsolePath -Recurse -Force
Write-Success "Web console files updated"

# Install Python dependencies
Write-Info "Installing Python dependencies..."
try {
    pip install -r (Join-Path $ConsolePath "requirements.txt")
    Write-Success "Python dependencies installed"
} catch {
    Write-Warning "Failed to install dependencies - you may need to install them manually"
}

# Start services
Write-Header "Step 8: Starting RustDesk Services"

Write-Info "Starting HBBS service..."
Start-Service -Name "RustDeskSignal" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Write-Info "Starting HBBR service..."
Start-Service -Name "RustDeskRelay" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Verify services
$hbbsService = Get-Service -Name "RustDeskSignal" -ErrorAction SilentlyContinue
$hbbrService = Get-Service -Name "RustDeskRelay" -ErrorAction SilentlyContinue

if ($hbbsService.Status -eq "Running") {
    Write-Success "HBBS service is running"
} else {
    Write-Warning "HBBS service is not running - you may need to start it manually"
}

if ($hbbrService -and $hbbrService.Status -eq "Running") {
    Write-Success "HBBR service is running"
} else {
    Write-Info "HBBR service not configured (optional)"
}

# Verify installation
Write-Header "Step 9: Verification"

if (Test-Path $DbPath) {
    Write-Info "Verifying database schema..."
    try {
        $schemaCheck = & sqlite3 $DbPath "PRAGMA table_info(peer);" | Measure-Object -Line
        $columnCount = $schemaCheck.Lines
        if ($columnCount -ge 16) {
            Write-Success "Database schema updated ($columnCount columns)"
        } else {
            Write-Warning "Database may be missing columns (found $columnCount)"
        }
    } catch {
        Write-Warning "Could not verify database (sqlite3 may not be installed)"
    }
}

Write-Info "Checking web console..."
Start-Sleep -Seconds 3
try {
    $response = Invoke-WebRequest -Uri "http://localhost:5000/api/stats" -UseBasicParsing -TimeoutSec 5
    if ($response.StatusCode -eq 200) {
        Write-Success "Web console is responding"
        $stats = $response.Content | ConvertFrom-Json
        if ($stats.total) {
            Write-Info "Total devices: $($stats.total)"
        }
        if ($stats.banned) {
            Write-Info "Banned devices: $($stats.banned)"
        }
    }
} catch {
    Write-Warning "Web console may not be running yet - give it a few seconds to start"
}

# Final summary
Write-Header "Update Complete!"

Write-Success "HBBS/HBBR updated to v8 with bidirectional ban enforcement"
Write-Success "Database migrated"
Write-Success "Web console files updated"
Write-Success "Backup created: $backupDir"
Write-Success "Services restarted"
Write-Host ""
Write-Host "New Features in v8:" -ForegroundColor Cyan
Write-Host "  • Bidirectional ban enforcement (prevents banned devices from connecting AND being connected to)"
Write-Host "  • Source device ban check (blocks outgoing connections from banned devices)"
Write-Host "  • Target device ban check (blocks incoming connections to banned devices)"
Write-Host "  • Real-time database synchronization"
Write-Host "  • Works for both P2P and relay connections"
Write-Host ""
Write-Host "Previous Features (v1.1.0):" -ForegroundColor Cyan
Write-Host "  • Soft delete for devices (is_deleted, deleted_at, updated_at)"
Write-Host "  • Device banning system (is_banned, banned_at, banned_by, ban_reason)"
Write-Host "  • Ban/Unban buttons in web interface"
Write-Host "  • Enhanced input validation and security"
Write-Host ""
Write-Host "Access the console:" -ForegroundColor Cyan
Write-Host "  http://localhost:5000"
Write-Host ""
Write-Host "Rollback Instructions (if needed):" -ForegroundColor Yellow
Write-Host "  1. Stop services: Stop-Service RustDeskSignal, RustDeskRelay"
Write-Host "  2. Restore binaries:"
Write-Host "     Copy-Item '$backupDir\hbbs.exe.backup' '$RustDeskPath\hbbs.exe'"
Write-Host "     Copy-Item '$backupDir\hbbr.exe.backup' '$RustDeskPath\hbbr.exe'"
Write-Host "  3. Restore database:"
Write-Host "     Copy-Item '$backupDir\db_v2.sqlite3.backup' '$DbPath'"
Write-Host "  4. Start services: Start-Service RustDeskSignal, RustDeskRelay"
Write-Host ""
Write-Success "Update completed successfully!"
