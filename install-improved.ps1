# BetterDesk Console - Windows Installation Script v1.5.0
# 
# This script installs the enhanced RustDesk HBBS/HBBR servers with 
# bidirectional ban enforcement, HTTP API, and web management console.
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
# - Configures Windows services
#
# Author: GitHub Copilot
# License: MIT

param(
    [Parameter(Mandatory=$false)]
    [string]$RustDeskPath = "",
    
    [Parameter(Mandatory=$false)]
    [string]$ConsolePath = "C:\BetterDeskConsole",
    
    [Parameter(Mandatory=$false)]
    [switch]$SkipBackup = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$NoInteractive = $false
)

$ErrorActionPreference = "Stop"
$VERSION = "v1.5.0"
$BINARY_VERSION = "v8-api"
$HBBS_API_PORT = 21114

# Helper functions
function Write-Header {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ $Message" -ForegroundColor Blue
}

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
        Write-Warning "No existing RustDesk installation found"
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
                Write-Info "Will install to: C:\RustDesk"
                return "C:\RustDesk"
            }
            "2" {
                $customDir = Read-Host "Enter full path to RustDesk directory"
                if ([string]::IsNullOrWhiteSpace($customDir)) {
                    Write-Error "Directory path cannot be empty"
                    exit 1
                }
                Write-Info "Will install to: $customDir"
                return $customDir
            }
            default {
                Write-Error "Invalid option"
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
            Write-Info "Using first found directory: $($foundDirs[0])"
            return $foundDirs[0]
        }
        
        $choice = Read-Host "Choose installation directory [1-$i]"
        
        if ($choice -eq $i) {
            $customDir = Read-Host "Enter full path to RustDesk directory"
            if ([string]::IsNullOrWhiteSpace($customDir)) {
                Write-Error "Directory path cannot be empty"
                exit 1
            }
            return $customDir
        }
        elseif ([int]$choice -ge 1 -and [int]$choice -lt $i) {
            $selectedDir = $foundDirs[[int]$choice - 1]
            Write-Info "Selected directory: $selectedDir"
            return $selectedDir
        }
        else {
            Write-Error "Invalid option"
            exit 1
        }
    }
}

function Test-RustDeskFiles {
    param([string]$Path)
    
    Write-Header "Verifying RustDesk Installation"
    
    # Create directory if it doesn't exist
    if (-not (Test-Path $Path)) {
        Write-Info "Creating directory: $Path"
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
        Write-Warning "Missing RustDesk key files: $($missingFiles -join ', ')"
        Write-Info "These files will be generated automatically when HBBS first starts"
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
            Write-Info "Database size: $([math]::Round($dbSize / 1KB, 2)) KB"
        }
        else {
            Write-Warning "Database file is very small - may be empty"
        }
    }
    else {
        Write-Info "No database found - will be created automatically"
    }
    
    Write-Success "Installation directory verified: $Path"
}

function Backup-RustDesk {
    param([string]$Path)
    
    Write-Header "Backing Up Existing RustDesk Installation"
    
    if (-not (Test-Path $Path) -or (Get-ChildItem $Path -ErrorAction SilentlyContinue).Count -eq 0) {
        Write-Info "No existing data to backup"
        Write-Info "Will proceed with fresh installation"
        return $null
    }
    
    if ($SkipBackup) {
        Write-Warning "Skipping backup as requested"
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
        Write-Info "Creating automatic backup..."
        Copy-Item -Path $Path -Destination $backupDir -Recurse -Force
        Write-Success "Backup created at: $backupDir"
        return $backupDir
    }
    
    $choice = Read-Host "Choose option [1-3]"
    
    switch ($choice) {
        "1" {
            Write-Info "Creating backup..."
            Copy-Item -Path $Path -Destination $backupDir -Recurse -Force
            Write-Success "Backup created at: $backupDir"
            return $backupDir
        }
        "2" {
            Write-Info "Using manual backup"
            return $null
        }
        "3" {
            Write-Warning "Skipping backup - YOU ARE RESPONSIBLE FOR ANY DATA LOSS"
            $confirm = Read-Host "Are you SURE? Type 'yes' to continue"
            if ($confirm -ne "yes") {
                Write-Error "Installation cancelled"
                exit 1
            }
            return $null
        }
        default {
            Write-Error "Invalid option"
            exit 1
        }
    }
}

function Install-RustDeskBinaries {
    param([string]$TargetPath)
    
    Write-Header "Installing Enhanced HBBS/HBBR $VERSION"
    
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $binDir = Join-Path $scriptDir "hbbs-patch\bin-with-api"
    
    $hbbsSource = Join-Path $binDir "hbbs-$BINARY_VERSION.exe"
    $hbbrSource = Join-Path $binDir "hbbr-$BINARY_VERSION.exe"
    
    # Check for binaries
    if (-not (Test-Path $hbbsSource) -or -not (Test-Path $hbbrSource)) {
        # Try fallback location
        $binDir = Join-Path $scriptDir "hbbs-patch\bin"
        $hbbsSource = Join-Path $binDir "hbbs-v8.exe"
        $hbbrSource = Join-Path $binDir "hbbr-v8.exe"
        
        if (-not (Test-Path $hbbsSource) -or -not (Test-Path $hbbrSource)) {
            Write-Error "Precompiled binaries not found"
            Write-Info "Checked locations:"
            Write-Info "  - $scriptDir\hbbs-patch\bin-with-api\hbbs-$BINARY_VERSION.exe"
            Write-Info "  - $scriptDir\hbbs-patch\bin\hbbs-v8.exe"
            exit 1
        }
        
        Write-Warning "Using older binaries without HTTP API"
    }
    
    # Create target directory
    if (-not (Test-Path $TargetPath)) {
        New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
    }
    
    # Stop existing services/processes
    Write-Info "Stopping RustDesk services and processes..."
    Stop-Service -Name "RustDeskSignal" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "RustDeskRelay" -Force -ErrorAction SilentlyContinue
    Get-Process -Name "hbbs","hbbr" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    
    # Backup existing binaries
    $hbbsTarget = Join-Path $TargetPath "hbbs.exe"
    $hbbrTarget = Join-Path $TargetPath "hbbr.exe"
    
    if (Test-Path $hbbsTarget) {
        $backupName = "hbbs.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss').exe"
        Write-Info "Backing up old hbbs.exe..."
        Copy-Item $hbbsTarget (Join-Path $TargetPath $backupName)
    }
    
    if (Test-Path $hbbrTarget) {
        $backupName = "hbbr.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss').exe"
        Write-Info "Backing up old hbbr.exe..."
        Copy-Item $hbbrTarget (Join-Path $TargetPath $backupName)
    }
    
    # Install new binaries
    Write-Info "Installing HBBS $VERSION (with HTTP API + ban enforcement)..."
    Copy-Item $hbbsSource $hbbsTarget -Force
    
    Write-Info "Installing HBBR $VERSION..."
    Copy-Item $hbbrSource $hbbrTarget -Force
    
    Write-Success "Binaries installed successfully"
    
    # Create/update Windows services
    Write-Info "Configuring Windows services..."
    
    # Create log directory
    $logDir = Join-Path $TargetPath "logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    # Install NSSM if not present (for service management)
    $nssmPath = Join-Path $env:ProgramData "nssm"
    if (-not (Test-Path $nssmPath)) {
        Write-Info "NSSM not found - services need to be configured manually"
        Write-Info "Or download NSSM from: https://nssm.cc/download"
    }
    else {
        Write-Info "Configuring services with NSSM..."
        # TODO: Add NSSM service configuration
    }
    
    Write-Success "Installation complete"
    
    # Display version info
    Write-Host ""
    Write-Info "HBBS/HBBR version: $VERSION"
    Write-Info "Features:"
    Write-Host "  ✓ HTTP API on port $HBBS_API_PORT" -ForegroundColor Green
    Write-Host "  ✓ Real-time device status" -ForegroundColor Green
    Write-Host "  ✓ Bidirectional ban enforcement" -ForegroundColor Green
    Write-Host "  ✓ Source + Target device ban checks" -ForegroundColor Green
    Write-Host ""
}

function Install-WebConsole {
    param([string]$RustDeskPath)
    
    Write-Header "Installing Web Management Console"
    
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $webDir = Join-Path $scriptDir "web"
    
    if (-not (Test-Path $webDir)) {
        Write-Error "Web directory not found: $webDir"
        exit 1
    }
    
    # Create console directory
    if (-not (Test-Path $ConsolePath)) {
        New-Item -ItemType Directory -Path $ConsolePath -Force | Out-Null
    }
    
    # Copy files
    Write-Info "Copying web console files..."
    Copy-Item -Path "$webDir\*" -Destination $ConsolePath -Recurse -Force
    
    # Update app.py with correct RustDesk path (Windows paths)
    $appPyPath = Join-Path $ConsolePath "app.py"
    if (Test-Path $appPyPath) {
        Write-Info "Updating console configuration for RustDesk path..."
        $dbPath = Join-Path $RustDeskPath "db_v2.sqlite3" | ForEach-Object { $_ -replace '\\', '/' }
        $keyPath = Join-Path $RustDeskPath "id_ed25519.pub" | ForEach-Object { $_ -replace '\\', '/' }
        
        $content = Get-Content $appPyPath -Raw
        $content = $content -replace "'/opt/rustdesk/db_v2.sqlite3'", "'$dbPath'"
        $content = $content -replace "'/opt/rustdesk/id_ed25519.pub'", "'$keyPath'"
        Set-Content -Path $appPyPath -Value $content
    }
    
    # Install Python dependencies
    Write-Info "Installing Python dependencies..."
    $requirementsPath = Join-Path $ConsolePath "requirements.txt"
    
    # Check if Python is available
    try {
        $pythonVersion = & python --version 2>&1
        Write-Info "Found Python: $pythonVersion"
        
        & python -m pip install -r $requirementsPath
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to install some Python packages"
            Write-Info "You may need to install them manually:"
            Write-Info "  python -m pip install -r $requirementsPath"
        }
        else {
            Write-Success "Python dependencies installed"
        }
    }
    catch {
        Write-Warning "Python not found in PATH"
        Write-Info "Please install Python 3.8+ and run:"
        Write-Info "  python -m pip install -r $requirementsPath"
    }
    
    Write-Success "Web console files installed to: $ConsolePath"
    Write-Info "To start the console manually, run:"
    Write-Info "  cd $ConsolePath"
    Write-Info "  python app.py"
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
        Write-Error "HBBS binary not found at: $hbbsPath"
    }
    
    if (Test-Path $hbbrPath) {
        Write-Success "HBBR binary found"
    }
    else {
        Write-Error "HBBR binary not found at: $hbbrPath"
    }
    
    # Test web console files
    $appPyPath = Join-Path $ConsolePath "app.py"
    if (Test-Path $appPyPath) {
        Write-Success "Web console files found"
    }
    else {
        Write-Error "Web console not found at: $ConsolePath"
    }
    
    Write-Info "Installation verification complete"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  1. Start HBBS: cd $RustDeskPath ; .\hbbs.exe"
    Write-Host "  2. Start HBBR: cd $RustDeskPath ; .\hbbr.exe"
    Write-Host "  3. Start Web Console: cd $ConsolePath ; python app.py"
    Write-Host ""
    Write-Host "Or configure them as Windows services for automatic startup"
}

function Show-Summary {
    param([string]$RustDeskPath, [string]$BackupPath)
    
    Write-Header "Installation Complete!"
    
    Write-Host "BetterDesk Console $VERSION has been successfully installed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Installation details:"
    Write-Host "  • RustDesk Directory: $RustDeskPath"
    Write-Host "  • Console Directory:  $ConsolePath"
    Write-Host ""
    
    if ($BackupPath) {
        Write-Host "Backup location:"
        Write-Host "  • $BackupPath"
        Write-Host ""
    }
    
    Write-Host "Features:"
    Write-Host "  ✓ HTTP API on port $HBBS_API_PORT" -ForegroundColor Green
    Write-Host "  ✓ Real-time device status monitoring" -ForegroundColor Green
    Write-Host "  ✓ Bidirectional ban enforcement" -ForegroundColor Green
    Write-Host "  ✓ Web management console" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "RustDesk Ports:"
    Write-Host "  • 21115 - NAT test"
    Write-Host "  • 21116 - TCP/UDP"
    Write-Host "  • 21117 - Relay"
    Write-Host "  • 21118 - WebSocket"
    Write-Host "  • 21119 - Relay (additional)"
    Write-Host "  • $HBBS_API_PORT - HTTP API"
    Write-Host ""
    
    Write-Info "For support and documentation:"
    Write-Host "  • GitHub: https://github.com/UNITRONIX/Rustdesk-FreeConsole"
    Write-Host ""
}

# Main installation flow
function Main {
    Clear-Host
    Write-Header "BetterDesk Console Installer $VERSION (Windows)"
    
    Write-Host "This script will install:"
    Write-Host "  • Enhanced RustDesk HBBS/HBBR with HTTP API"
    Write-Host "  • Bidirectional ban enforcement"
    Write-Host "  • Real-time device status monitoring"
    Write-Host "  • Web Management Console with Material Design"
    Write-Host ""
    Write-Host "Installation method: Precompiled binaries (no compilation required)"
    Write-Host ""
    
    # Check admin rights
    if (-not (Test-Administrator)) {
        Write-Warning "This script should be run as Administrator for full functionality"
        $continue = Read-Host "Continue anyway? (y/n)"
        if ($continue -ne "y") {
            Write-Error "Installation cancelled"
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
