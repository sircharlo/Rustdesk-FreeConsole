# BetterDesk Console - Windows Installation Script v1.5.1
# 
# This script installs the enhanced RustDesk HBBS/HBBR servers with 
# bidirectional ban enforcement, HTTP API, and web management console.
#
# NEW in v1.5.1:
# - Support for hbbs-patch-v2 Windows binaries (v2.0.0)
# - Added --Fix parameter to repair existing installations
# - Added --Diagnose parameter to check for common issues
# - Automatic detection of original vs BetterDesk binaries
#
# NEW in v1.5.0:
# - Authentication system with bcrypt password hashing
# - Role-based access control (Admin, Operator, Viewer)
# - Sidebar navigation with multiple sections
# - Password-protected public key access
# - User management panel (admin only)
# - Support for custom RustDesk installation directories
# - Automatic verification of required RustDesk files
# - Improved error handling and validation
# - Windows-specific path handling
#
# Features:
# - Automatic backup of existing RustDesk installation
# - Precompiled HBBS/HBBR binaries with ban enforcement + HTTP API
# - Bidirectional ban checking (source + target devices)
# - Real-time device status via HTTP API (port 21114)
# - Installs Flask web console with glassmorphism UI
# - Manual server startup (no Windows services)
#
# Author: UNITRONIX Team
# License: MIT

#Requires -Version 5.1

param(
    [Parameter(Mandatory=$false)]
    [string]$RustDeskPath = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ConsolePath = "C:\BetterDeskConsole",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBackup = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$NoInteractive = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Fix = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Diagnose = $false
)

# Set strict mode for better error detection
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$VERSION = "v1.5.1"
$BINARY_VERSION = "v8-api"
$HBBS_API_PORT = 21114

#region Helper Functions
# Helper functions - must be defined before use

function Write-Header {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-InfoMsg {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

#endregion

function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Find-RustDeskInstallation {
    Write-Header "Detecting RustDesk Installation"
    
    # Common installation directories
    $commonDirs = @(
        "C:\Program Files\RustDesk",
        "C:\Program Files (x86)\RustDesk",
        "C:\RustDesk",
        "$env:LOCALAPPDATA\RustDesk",
        "$env:ProgramData\RustDesk"
    )
    
    $foundDirs = @()
    
    # Check common directories
    foreach ($dir in $commonDirs) {
        if (Test-Path $dir) {
            $foundDirs += $dir
        }
    }
    
    # Search for hbbs.exe in common locations
    $searchPaths = @("C:\Program Files", "C:\Program Files (x86)", "C:\RustDesk", "C:\")
    foreach ($searchPath in $searchPaths) {
        if (Test-Path $searchPath) {
            $hbbsFiles = Get-ChildItem -Path $searchPath -Filter "hbbs.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 5
            foreach ($file in $hbbsFiles) {
                $dir = $file.Directory.FullName
                if ($foundDirs -notcontains $dir) {
                    $foundDirs += $dir
                }
            }
        }
    }
    
    if ($foundDirs.Count -eq 0) {
        Write-WarningMsg "No existing RustDesk installation found"
        Write-Host ""
        Write-Host "Options:"
        Write-Host "  1) Install to default location: C:\RustDesk"
        Write-Host "  2) Specify custom installation directory"
        Write-Host ""
        
        if ($NoInteractive) {
            return "C:\RustDesk"
        }
        
        $choice = Read-Host "Choose option [1-2]"
        
        switch ($choice) {
            "1" {
                Write-InfoMsg "Will install to: C:\RustDesk"
                return "C:\RustDesk"
            }
            "2" {
                $customDir = Read-Host "Enter full path to RustDesk directory"
                if ([string]::IsNullOrWhiteSpace($customDir)) {
                    Write-ErrorMsg "Directory path cannot be empty"
                    exit 1
                }
                Write-InfoMsg "Will install to: $customDir"
                return $customDir
            }
            default {
                Write-ErrorMsg "Invalid option"
                exit 1
            }
        }
    }
    elseif ($foundDirs.Count -eq 1) {
        $dir = $foundDirs[0]
        Write-Success "Found RustDesk installation at: $dir"
        return $dir
    }
    else {
        Write-Host "Multiple RustDesk installations found:"
        Write-Host ""
        $i = 1
        foreach ($dir in $foundDirs) {
            Write-Host "  $i) $dir"
            $i++
        }
        Write-Host "  $i) Specify custom directory"
        Write-Host ""
        
        if ($NoInteractive) {
            Write-InfoMsg "Using first found directory: $($foundDirs[0])"
            return $foundDirs[0]
        }
        
        $choice = Read-Host "Choose installation directory [1-$i]"
        
        if ($choice -eq $i) {
            $customDir = Read-Host "Enter full path to RustDesk directory"
            if ([string]::IsNullOrWhiteSpace($customDir)) {
                Write-ErrorMsg "Directory path cannot be empty"
                exit 1
            }
            return $customDir
        }
        elseif ([int]$choice -ge 1 -and [int]$choice -lt $i) {
            $selectedDir = $foundDirs[[int]$choice - 1]
            Write-InfoMsg "Selected directory: $selectedDir"
            return $selectedDir
        }
        else {
            Write-ErrorMsg "Invalid option"
            exit 1
        }
    }
}

function Test-RustDeskFiles {
    param([string]$Path)
    
    Write-Header "Verifying RustDesk Installation"
    
    # Create directory if it doesn't exist
    if (-not (Test-Path $Path)) {
        Write-InfoMsg "Creating directory: $Path"
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    
    # Check for required files
    $requiredFiles = @("id_ed25519", "id_ed25519.pub")
    $missingFiles = @()
    
    foreach ($file in $requiredFiles) {
        $filePath = Join-Path $Path $file
        if (-not (Test-Path $filePath)) {
            $missingFiles += $file
        }
    }
    
    if ($missingFiles.Count -gt 0) {
        Write-WarningMsg "Missing RustDesk key files: $($missingFiles -join ', ')"
        Write-InfoMsg "These files will be generated automatically when HBBS first starts"
    }
    else {
        Write-Success "RustDesk key files found"
    }
    
    # Check for database
    $dbPath = Join-Path $Path "db_v2.sqlite3"
    if (Test-Path $dbPath) {
        Write-Success "RustDesk database found"
        
        $dbSize = (Get-Item $dbPath).Length
        if ($dbSize -gt 1000) {
            Write-InfoMsg "Database size: $([math]::Round($dbSize / 1KB, 2)) KB"
        }
        else {
            Write-WarningMsg "Database file is very small - may be empty"
        }
    }
    else {
        Write-InfoMsg "No database found - will be created automatically"
    }
    
    Write-Success "Installation directory verified: $Path"
}

function Backup-RustDesk {
    param([string]$Path)
    
    Write-Header "Backing Up Existing RustDesk Installation"
    
    if (-not (Test-Path $Path) -or (Get-ChildItem $Path -ErrorAction SilentlyContinue).Count -eq 0) {
        Write-InfoMsg "No existing data to backup"
        Write-InfoMsg "Will proceed with fresh installation"
        return $null
    }
    
    if ($SkipBackup) {
        Write-WarningMsg "Skipping backup as requested"
        return $null
    }
    
    $backupDir = "C:\RustDesk-Backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    Write-Host "Found existing RustDesk installation" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  1) Create automatic backup to $backupDir"
    Write-Host "  2) I have already created a manual backup"
    Write-Host "  3) Skip backup (not recommended)"
    Write-Host ""
    
    if ($NoInteractive) {
        Write-InfoMsg "Creating automatic backup..."
        Copy-Item -Path $Path -Destination $backupDir -Recurse -Force
        Write-Success "Backup created at: $backupDir"
        return $backupDir
    }
    
    $choice = Read-Host "Choose option [1-3]"
    
    switch ($choice) {
        "1" {
            Write-InfoMsg "Creating backup..."
            Copy-Item -Path $Path -Destination $backupDir -Recurse -Force
            Write-Success "Backup created at: $backupDir"
            return $backupDir
        }
        "2" {
            Write-InfoMsg "Using manual backup"
            return $null
        }
        "3" {
            Write-WarningMsg "Skipping backup - YOU ARE RESPONSIBLE FOR ANY DATA LOSS"
            $confirm = Read-Host "Are you SURE? Type 'yes' to continue"
            if ($confirm -ne "yes") {
                Write-ErrorMsg "Installation cancelled"
                exit 1
            }
            return $null
        }
        default {
            Write-ErrorMsg "Invalid option"
            exit 1
        }
    }
}

function Install-RustDeskBinaries {
    param([string]$TargetPath)
    
    Write-Header "Installing Enhanced HBBS/HBBR $VERSION"
    
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $hbbsSource = $null
    $hbbrSource = $null
    $binaryVersion = "v2.0.0"
    
    # Priority 1: hbbs-patch-v2 pre-compiled Windows binaries (RECOMMENDED)
    $v2BinDir = Join-Path $scriptDir "hbbs-patch-v2"
    $v2Hbbs = Join-Path $v2BinDir "hbbs-windows-x86_64.exe"
    $v2Hbbr = Join-Path $v2BinDir "hbbr-windows-x86_64.exe"
    
    if ((Test-Path $v2Hbbs) -and (Test-Path $v2Hbbr)) {
        Write-Success "Found hbbs-patch-v2 Windows binaries (v2.0.0, port 21114)"
        $hbbsSource = $v2Hbbs
        $hbbrSource = $v2Hbbr
        $binaryVersion = "v2.0.0"
    }
    else {
        # Priority 2: Old hbbs-patch binaries (DEPRECATED)
        $oldBinDir = Join-Path $scriptDir "hbbs-patch\bin-with-api"
        $oldHbbs = Join-Path $oldBinDir "hbbs-$BINARY_VERSION.exe"
        $oldHbbr = Join-Path $oldBinDir "hbbr-$BINARY_VERSION.exe"
        
        if ((Test-Path $oldHbbs) -and (Test-Path $oldHbbr)) {
            Write-WarningMsg "Found OLD hbbs-patch binaries (v1, DEPRECATED)"
            Write-InfoMsg "These binaries have known issues. Recommended: use v2 from hbbs-patch-v2/"
            $hbbsSource = $oldHbbs
            $hbbrSource = $oldHbbr
            $binaryVersion = "v1-old"
        }
        else {
            # Priority 3: Fallback old location
            $fallbackBinDir = Join-Path $scriptDir "hbbs-patch\bin"
            $fallbackHbbs = Join-Path $fallbackBinDir "hbbs-v8.exe"
            $fallbackHbbr = Join-Path $fallbackBinDir "hbbr-v8.exe"
            
            if ((Test-Path $fallbackHbbs) -and (Test-Path $fallbackHbbr)) {
                Write-WarningMsg "Using legacy binaries without full HTTP API"
                $hbbsSource = $fallbackHbbs
                $hbbrSource = $fallbackHbbr
                $binaryVersion = "legacy"
            }
        }
    }
    
    # Check if we found any binaries
    if (-not $hbbsSource -or -not $hbbrSource) {
        Write-ErrorMsg "Precompiled binaries not found!"
        Write-Host ""
        Write-InfoMsg "Checked locations (in priority order):"
        Write-InfoMsg "  1. $v2BinDir\hbbs-windows-x86_64.exe (RECOMMENDED)"
        Write-InfoMsg "  2. $scriptDir\hbbs-patch\bin-with-api\hbbs-$BINARY_VERSION.exe"
        Write-InfoMsg "  3. $scriptDir\hbbs-patch\bin\hbbs-v8.exe"
        Write-Host ""
        Write-InfoMsg "Please ensure you have the BetterDesk binaries."
        Write-InfoMsg "Download from: https://github.com/UNITRONIX/Rustdesk-FreeConsole"
        exit 1
    }
    
    Write-InfoMsg "Using binaries version: $binaryVersion"
    
    # Create target directory
    if (-not (Test-Path $TargetPath)) {
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
    }
    
    # Stop existing services/processes
    Write-InfoMsg "Stopping RustDesk services and processes..."
    Stop-Service -Name "RustDeskSignal" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "RustDeskRelay" -Force -ErrorAction SilentlyContinue
    Get-Process -Name "hbbs","hbbr" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    
    # Backup existing binaries
    $hbbsTarget = Join-Path $TargetPath "hbbs.exe"
    $hbbrTarget = Join-Path $TargetPath "hbbr.exe"
    
    if (Test-Path $hbbsTarget) {
        $backupName = "hbbs.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss').exe"
        Write-InfoMsg "Backing up old hbbs.exe..."
        Copy-Item $hbbsTarget (Join-Path $TargetPath $backupName)
    }
    
    if (Test-Path $hbbrTarget) {
        $backupName = "hbbr.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss').exe"
        Write-InfoMsg "Backing up old hbbr.exe..."
        Copy-Item $hbbrTarget (Join-Path $TargetPath $backupName)
    }
    
    # Install new binaries
    Write-InfoMsg "Installing HBBS $VERSION (with HTTP API + ban enforcement)..."
    Copy-Item $hbbsSource $hbbsTarget -Force
    
    Write-InfoMsg "Installing HBBR $VERSION..."
    Copy-Item $hbbrSource $hbbrTarget -Force
    
    Write-Success "Binaries installed successfully"
    
    # Create/update Windows services
    Write-InfoMsg "RustDesk servers will run as standard executables"
    
    # Create log directory
    $logDir = Join-Path $TargetPath "logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Write-Success "Binaries ready for manual startup"
    
    Write-Success "Installation complete"
    
    # Display version info
    Write-Host ""
    Write-InfoMsg "HBBS/HBBR version: $VERSION"
    Write-InfoMsg "Features:"
    Write-Host "  [+] HTTP API on port $HBBS_API_PORT" -ForegroundColor Green
    Write-Host "  [+] Real-time device status" -ForegroundColor Green
    Write-Host "  [+] Bidirectional ban enforcement" -ForegroundColor Green
    Write-Host "  [+] Source + Target device ban checks" -ForegroundColor Green
    Write-Host ""
}

function Install-WebConsole {
    param([string]$RustDeskPath)
    
    Write-Header "Installing Web Management Console"
    
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $webDir = Join-Path $scriptDir "web"
    
    if (-not (Test-Path $webDir)) {
        Write-ErrorMsg "Web directory not found: $webDir"
        exit 1
    }
    
    # Create console directory
    if (-not (Test-Path $ConsolePath)) {
        New-Item -ItemType Directory -Path $ConsolePath -Force | Out-Null
    }
    
    # Copy files
    Write-InfoMsg "Copying web console files..."
    Copy-Item -Path "$webDir\*" -Destination $ConsolePath -Recurse -Force
    
    # Update app.py with correct RustDesk path (Windows paths)
    $appPyPath = Join-Path $ConsolePath "app.py"
    if (Test-Path $appPyPath) {
        Write-InfoMsg "Updating console configuration for RustDesk path..."
        $dbPath = Join-Path $RustDeskPath "db_v2.sqlite3" | ForEach-Object { $_ -replace '\\', '/' }
        $keyPath = Join-Path $RustDeskPath "id_ed25519.pub" | ForEach-Object { $_ -replace '\\', '/' }
        
        $content = Get-Content $appPyPath -Raw
        $content = $content -replace "'/opt/rustdesk/db_v2.sqlite3'", "'$dbPath'"
        $content = $content -replace "'/opt/rustdesk/id_ed25519.pub'", "'$keyPath'"
        Set-Content -Path $appPyPath -Value $content
    }
    
    # Install Python dependencies
    Write-InfoMsg "Installing Python dependencies..."
    $requirementsPath = Join-Path $ConsolePath "requirements.txt"
    
    # Check if Python is available
    try {
        $pythonVersion = & python --version 2>&1
        Write-InfoMsg "Found Python: $pythonVersion"
        
        & python -m pip install -r $requirementsPath
        
        if ($LASTEXITCODE -ne 0) {
            Write-WarningMsg "Failed to install some Python packages"
            Write-InfoMsg "You may need to install them manually:"
            Write-InfoMsg "  python -m pip install -r $requirementsPath"
        }
        else {
            Write-Success "Python dependencies installed"
        }
    }
    catch {
        Write-WarningMsg "Python not found in PATH"
        Write-InfoMsg "Please install Python 3.8+ and run:"
        Write-InfoMsg "  python -m pip install -r $requirementsPath"
    }
    
    Write-Success "Web console files installed to: $ConsolePath"
    Write-InfoMsg "To start the console manually, run:"
    Write-InfoMsg "  cd $ConsolePath"
    Write-InfoMsg "  python app.py"
}

function Test-Installation {
    param([string]$RustDeskPath)
    
    Write-Header "Testing Installation"
    
    # Test if binaries exist
    $hbbsPath = Join-Path $RustDeskPath "hbbs.exe"
    $hbbrPath = Join-Path $RustDeskPath "hbbr.exe"
    
    if (Test-Path $hbbsPath) {
        Write-Success "HBBS binary found"
    }
    else {
        Write-ErrorMsg "HBBS binary not found at: $hbbsPath"
    }
    
    if (Test-Path $hbbrPath) {
        Write-Success "HBBR binary found"
    }
    else {
        Write-ErrorMsg "HBBR binary not found at: $hbbrPath"
    }
    
    # Test web console files
    $appPyPath = Join-Path $ConsolePath "app.py"
    if (Test-Path $appPyPath) {
        Write-Success "Web console files found"
    }
    else {
        Write-ErrorMsg "Web console not found at: $ConsolePath"
    }
    
    Write-InfoMsg "Installation verification complete"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Start HBBS: cd $RustDeskPath ; .\hbbs.exe"
    Write-Host "  2. Start HBBR: cd $RustDeskPath ; .\hbbr.exe"
    Write-Host "  3. Start Web Console: cd $ConsolePath ; python app.py"
    Write-Host ""
    Write-Host "Web Console will be available at: http://localhost:5000" -ForegroundColor Cyan
    Write-Host "Run servers in separate PowerShell windows for best results" -ForegroundColor Yellow
}

function Show-Summary {
    param([string]$RustDeskPath, [string]$BackupPath)
    
    Write-Header "Installation Complete!"
    
    Write-Host "BetterDesk Console $VERSION has been successfully installed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Installation details:"
    Write-Host "  - RustDesk Directory: $RustDeskPath"
    Write-Host "  - Console Directory:  $ConsolePath"
    Write-Host ""
    
    if ($BackupPath) {
        Write-Host "Backup location:"
        Write-Host "  - $BackupPath"
        Write-Host ""
    }
    
    Write-Host "Features:"
    Write-Host "  [+] HTTP API on port $HBBS_API_PORT" -ForegroundColor Green
    Write-Host "  [+] Real-time device status monitoring" -ForegroundColor Green
    Write-Host "  [+] Bidirectional ban enforcement" -ForegroundColor Green
    Write-Host "  [+] Web management console" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "RustDesk Ports:"
    Write-Host "  - 21115 - NAT test"
    Write-Host "  - 21116 - TCP/UDP"
    Write-Host "  - 21117 - Relay"
    Write-Host "  - 21118 - WebSocket"
    Write-Host "  - 21119 - Relay (additional)"
    Write-Host "  - $HBBS_API_PORT - HTTP API"
    Write-Host ""
    
    Write-Host "Usage Instructions:" -ForegroundColor Yellow
    Write-Host "  1. Open PowerShell as Administrator"
    Write-Host "  2. Navigate to: cd $RustDeskPath"
    Write-Host "  3. Start HBBS: .\hbbs.exe"
    Write-Host "  4. Open second PowerShell window"
    Write-Host "  5. Start HBBR: .\hbbr.exe"
    Write-Host "  6. Open third PowerShell window"
    Write-Host "  7. Start Console: cd $ConsolePath ; python app.py"
    Write-Host ""
    Write-Host "Access Points:" -ForegroundColor Cyan
    Write-Host "  - Web Console: http://localhost:5000"
    Write-Host "  - HTTP API: http://localhost:$HBBS_API_PORT"
    Write-Host ""
    
    Write-InfoMsg "For support and documentation:"
    Write-Host "  - GitHub: https://github.com/UNITRONIX/Rustdesk-FreeConsole"
    Write-Host ""
}

function Test-BetterDeskBinary {
    param([string]$BinaryPath)
    
    if (-not (Test-Path $BinaryPath)) {
        return $false
    }
    
    try {
        # Run hbbs --help and check for BetterDesk signature
        $output = & $BinaryPath --help 2>&1 | Out-String
        return $output -match "BetterDesk|api-port"
    }
    catch {
        return $false
    }
}

function Invoke-Diagnose {
    param([string]$RustDeskPath)
    
    Write-Header "BetterDesk Diagnostic Tool"
    
    $issuesFound = 0
    
    # Check 1: RustDesk installation
    Write-InfoMsg "Checking RustDesk installation..."
    if (-not (Test-Path $RustDeskPath)) {
        Write-ErrorMsg "RustDesk directory not found: $RustDeskPath"
        $issuesFound++
    }
    else {
        Write-Success "RustDesk directory found: $RustDeskPath"
    }
    
    # Check 2: HBBS binary
    $hbbsPath = Join-Path $RustDeskPath "hbbs.exe"
    Write-InfoMsg "Checking HBBS binary..."
    if (Test-Path $hbbsPath) {
        Write-Success "HBBS binary found"
        
        # Check if it's BetterDesk version
        if (Test-BetterDeskBinary -BinaryPath $hbbsPath) {
            Write-Success "HBBS is BetterDesk Enhanced version"
        }
        else {
            Write-ErrorMsg "HBBS is ORIGINAL RustDesk (not BetterDesk)"
            Write-Host ""
            Write-Host "  ┌─────────────────────────────────────────────────────┐" -ForegroundColor Red
            Write-Host "  │  THIS IS THE CAUSE OF YOUR OFFLINE STATUS PROBLEM  │" -ForegroundColor Red
            Write-Host "  └─────────────────────────────────────────────────────┘" -ForegroundColor Red
            Write-Host ""
            Write-Host "  The original hbbs does NOT update the 'status' field in the database."
            Write-Host "  Run this script with -Fix parameter to replace binaries:"
            Write-Host "    .\install-improved.ps1 -Fix" -ForegroundColor Yellow
            Write-Host ""
            $issuesFound++
        }
    }
    else {
        Write-ErrorMsg "HBBS binary not found at: $hbbsPath"
        $issuesFound++
    }
    
    # Check 3: HBBR binary
    $hbbrPath = Join-Path $RustDeskPath "hbbr.exe"
    Write-InfoMsg "Checking HBBR binary..."
    if (Test-Path $hbbrPath) {
        Write-Success "HBBR binary found"
    }
    else {
        Write-WarningMsg "HBBR binary not found at: $hbbrPath"
    }
    
    # Check 4: Database
    Write-InfoMsg "Checking database..."
    $dbPath = Join-Path $RustDeskPath "db_v2.sqlite3"
    if (Test-Path $dbPath) {
        Write-Success "Database found: $dbPath"
        $dbSize = (Get-Item $dbPath).Length / 1KB
        Write-InfoMsg "Database size: $([math]::Round($dbSize, 2)) KB"
    }
    else {
        Write-WarningMsg "Database not found (will be created on first run)"
    }
    
    # Check 5: Running processes
    Write-InfoMsg "Checking running processes..."
    $hbbsProcess = Get-Process -Name "hbbs" -ErrorAction SilentlyContinue
    $hbbrProcess = Get-Process -Name "hbbr" -ErrorAction SilentlyContinue
    
    if ($hbbsProcess) {
        Write-Success "HBBS is running (PID: $($hbbsProcess.Id))"
    }
    else {
        Write-WarningMsg "HBBS is NOT running"
    }
    
    if ($hbbrProcess) {
        Write-Success "HBBR is running (PID: $($hbbrProcess.Id))"
    }
    else {
        Write-WarningMsg "HBBR is NOT running"
    }
    
    # Check 6: Ports
    Write-InfoMsg "Checking ports..."
    $ports = @(
        @{Port = 21114; Name = "HTTP API"},
        @{Port = 21115; Name = "NAT test"},
        @{Port = 21116; Name = "ID Server"},
        @{Port = 21117; Name = "Relay"}
    )
    
    foreach ($p in $ports) {
        $connection = Get-NetTCPConnection -LocalPort $p.Port -ErrorAction SilentlyContinue
        if ($connection) {
            Write-Success "Port $($p.Port) ($($p.Name)) is listening"
        }
        else {
            Write-WarningMsg "Port $($p.Port) ($($p.Name)) is NOT listening"
        }
    }
    
    # Summary
    Write-Host ""
    Write-Header "Diagnostic Summary"
    
    if ($issuesFound -eq 0) {
        Write-Host "No critical issues found!" -ForegroundColor Green
    }
    else {
        Write-Host "Found $issuesFound issue(s)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Most common cause: Using original RustDesk hbbs instead of BetterDesk." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Quick fix:" -ForegroundColor Cyan
        Write-Host "  .\install-improved.ps1 -Fix"
    }
}

function Invoke-Fix {
    param([string]$RustDeskPath)
    
    Write-Header "BetterDesk Binary Fix Tool"
    
    Write-InfoMsg "This will replace your RustDesk binaries with BetterDesk enhanced versions."
    Write-Host ""
    
    # Find BetterDesk binaries
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $v2BinDir = Join-Path $scriptDir "hbbs-patch-v2"
    $v2Hbbs = Join-Path $v2BinDir "hbbs-windows-x86_64.exe"
    $v2Hbbr = Join-Path $v2BinDir "hbbr-windows-x86_64.exe"
    
    if (-not (Test-Path $v2Hbbs) -or -not (Test-Path $v2Hbbr)) {
        Write-ErrorMsg "BetterDesk binaries not found!"
        Write-InfoMsg "Expected location: $v2BinDir"
        Write-InfoMsg "Please download from: https://github.com/UNITRONIX/Rustdesk-FreeConsole"
        return
    }
    
    Write-Success "Found BetterDesk v2.0.0 binaries"
    
    # Stop running processes
    Write-InfoMsg "Stopping RustDesk processes..."
    Get-Process -Name "hbbs","hbbr" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    
    # Backup existing binaries
    $hbbsPath = Join-Path $RustDeskPath "hbbs.exe"
    $hbbrPath = Join-Path $RustDeskPath "hbbr.exe"
    
    if (Test-Path $hbbsPath) {
        $backupName = "hbbs.backup-original.$(Get-Date -Format 'yyyyMMdd-HHmmss').exe"
        Write-InfoMsg "Backing up original hbbs.exe..."
        Copy-Item $hbbsPath (Join-Path $RustDeskPath $backupName)
        Write-Success "Backup created: $backupName"
    }
    
    if (Test-Path $hbbrPath) {
        $backupName = "hbbr.backup-original.$(Get-Date -Format 'yyyyMMdd-HHmmss').exe"
        Write-InfoMsg "Backing up original hbbr.exe..."
        Copy-Item $hbbrPath (Join-Path $RustDeskPath $backupName)
        Write-Success "Backup created: $backupName"
    }
    
    # Copy new binaries
    Write-InfoMsg "Installing BetterDesk binaries..."
    Copy-Item $v2Hbbs $hbbsPath -Force
    Copy-Item $v2Hbbr $hbbrPath -Force
    
    Write-Success "BetterDesk binaries installed!"
    
    # Verify
    Write-InfoMsg "Verifying installation..."
    if (Test-BetterDeskBinary -BinaryPath $hbbsPath) {
        Write-Success "HBBS is now BetterDesk Enhanced version"
    }
    else {
        Write-WarningMsg "Could not verify HBBS version"
    }
    
    Write-Host ""
    Write-Header "Fix Complete!"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Start HBBS with API port:" -ForegroundColor Cyan
    Write-Host "     cd $RustDeskPath" 
    Write-Host "     .\hbbs.exe -k _ --api-port 21114"
    Write-Host ""
    Write-Host "  2. Start HBBR:" -ForegroundColor Cyan
    Write-Host "     .\hbbr.exe"
    Write-Host ""
    Write-Host "  3. Restart your RustDesk clients to see online status" -ForegroundColor Cyan
}

# Main installation flow
function Main {
    Clear-Host
    Write-Header "BetterDesk Console Installer $VERSION (Windows)"
    
    # Handle -Diagnose mode
    if ($Diagnose) {
        if ([string]::IsNullOrWhiteSpace($RustDeskPath)) {
            $RustDeskPath = Find-RustDeskInstallation
        }
        if ($RustDeskPath) {
            Invoke-Diagnose -RustDeskPath $RustDeskPath
        }
        return
    }
    
    # Handle -Fix mode
    if ($Fix) {
        if ([string]::IsNullOrWhiteSpace($RustDeskPath)) {
            $RustDeskPath = Find-RustDeskInstallation
        }
        if ($RustDeskPath) {
            Invoke-Fix -RustDeskPath $RustDeskPath
        }
        return
    }
    
    Write-Host "This script will install:"
    Write-Host "  - Enhanced RustDesk HBBS/HBBR with HTTP API"
    Write-Host "  - Bidirectional ban enforcement"
    Write-Host "  - Real-time device status monitoring"
    Write-Host "  - Web Management Console with Material Design"
    Write-Host ""
    Write-Host "Installation method: Precompiled binaries (no compilation required)"
    Write-Host ""
    Write-Host "Additional options:" -ForegroundColor Yellow
    Write-Host "  -Diagnose  : Check for common issues (offline status, etc.)"
    Write-Host "  -Fix       : Replace original RustDesk binaries with BetterDesk"
    Write-Host ""
    
    # Check admin rights
    if (-not (Test-Administrator)) {
        Write-WarningMsg "This script should be run as Administrator for full functionality"
        $continue = Read-Host "Continue anyway? (y/n)"
        if ($continue -ne "y") {
            Write-ErrorMsg "Installation cancelled"
            exit 1
        }
    }
    
    # Determine RustDesk directory
    if ([string]::IsNullOrWhiteSpace($RustDeskPath)) {
        $RustDeskPath = Find-RustDeskInstallation
    }
    
    # Verify installation
    Test-RustDeskFiles -Path $RustDeskPath
    
    # Backup
    $backupPath = Backup-RustDesk -Path $RustDeskPath
    
    # Install binaries
    Install-RustDeskBinaries -TargetPath $RustDeskPath
    
    # Install web console
    Install-WebConsole -RustDeskPath $RustDeskPath
    
    # Test installation
    Test-Installation -RustDeskPath $RustDeskPath
    
    # Show summary
    Show-Summary -RustDeskPath $RustDeskPath -BackupPath $backupPath
}

# Run main function
Main
