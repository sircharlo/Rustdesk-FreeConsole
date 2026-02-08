#===============================================================================
#
#   BetterDesk Console Manager v2.1.1
#   All-in-One Interactive Tool for Windows
#
#   Features:
#     - Fresh installation
#     - Update existing installation  
#     - Repair/fix issues
#     - Validate installation
#     - Backup & restore
#     - Reset admin password
#     - Build custom binaries
#     - Full diagnostics
#     - SHA256 binary verification
#     - Auto mode (non-interactive)
#
#   Usage: Run as Administrator
#          Interactive: .\betterdesk.ps1
#          Auto mode:   .\betterdesk.ps1 -Auto
#
#===============================================================================

[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$SkipVerify,
    [switch]$Help
)

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$Version = "2.1.1"

# Show help
if ($Help) {
    Write-Host "BetterDesk Console Manager v$Version"
    Write-Host ""
    Write-Host "Usage: .\betterdesk.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Auto         Run in automatic mode (non-interactive)"
    Write-Host "  -SkipVerify   Skip SHA256 verification of binaries"
    Write-Host "  -Help         Show this help message"
    exit 0
}

# Binary checksums (SHA256) - v2.1.1
$Script:HBBS_WINDOWS_SHA256 = "682AA117AEEC8A6408DB4462BD31EB9DE943D5F70F5C27F3383F1DF56028A6E3"
$Script:HBBR_WINDOWS_SHA256 = "B585D077D5512035132BBCE3CE6CBC9D034E2DAE0805A799B3196C7372D82BEA"

# API configuration
$Script:ApiPort = if ($env:API_PORT) { $env:API_PORT } else { "21114" }

# Default paths (can be overridden by environment variables)
$Script:RustdeskPath = if ($env:RUSTDESK_PATH) { $env:RUSTDESK_PATH } else { "" }
$Script:ConsolePath = if ($env:CONSOLE_PATH) { $env:CONSOLE_PATH } else { "" }
$Script:DbPath = ""
$Script:BackupDir = if ($env:BACKUP_DIR) { $env:BACKUP_DIR } else { "C:\rustdesk-backups" }
$Script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Common installation paths to search
$Script:CommonRustdeskPaths = @(
    "C:\rustdesk",
    "C:\Program Files\rustdesk",
    "C:\Program Files (x86)\rustdesk",
    "$env:ProgramData\rustdesk",
    "$env:LOCALAPPDATA\rustdesk",
    "$env:USERPROFILE\rustdesk"
)

$Script:CommonConsolePaths = @(
    "C:\BetterDeskConsole",
    "C:\Program Files\BetterDeskConsole",
    "$env:ProgramData\BetterDeskConsole",
    "$env:USERPROFILE\BetterDeskConsole"
)

# Status variables
$Script:InstallStatus = "none"
$Script:HbbsRunning = $false
$Script:HbbrRunning = $false  
$Script:ConsoleRunning = $false
$Script:BinariesOk = $false
$Script:DatabaseOk = $false

#===============================================================================
# Helper Functions
#===============================================================================

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                                                                  ║" -ForegroundColor Cyan
    Write-Host "  ║   ██████╗ ███████╗████████╗████████╗███████╗██████╗              ║" -ForegroundColor Cyan
    Write-Host "  ║   ██╔══██╗██╔════╝╚══██╔══╝╚══██╔══╝██╔════╝██╔══██╗             ║" -ForegroundColor Cyan
    Write-Host "  ║   ██████╔╝█████╗     ██║      ██║   █████╗  ██████╔╝             ║" -ForegroundColor Cyan
    Write-Host "  ║   ██╔══██╗██╔══╝     ██║      ██║   ██╔══╝  ██╔══██╗             ║" -ForegroundColor Cyan
    Write-Host "  ║   ██████╔╝███████╗   ██║      ██║   ███████╗██║  ██║             ║" -ForegroundColor Cyan
    Write-Host "  ║   ╚═════╝ ╚══════╝   ╚═╝      ╚═╝   ╚══════╝╚═╝  ╚═╝             ║" -ForegroundColor Cyan
    Write-Host "  ║                    ██████╗ ███████╗███████╗██╗  ██╗              ║" -ForegroundColor Cyan
    Write-Host "  ║                    ██╔══██╗██╔════╝██╔════╝██║ ██╔╝              ║" -ForegroundColor Cyan
    Write-Host "  ║                    ██║  ██║█████╗  ███████╗█████╔╝               ║" -ForegroundColor Cyan
    Write-Host "  ║                    ██║  ██║██╔══╝  ╚════██║██╔═██╗               ║" -ForegroundColor Cyan
    Write-Host "  ║                    ██████╔╝███████╗███████║██║  ██╗              ║" -ForegroundColor Cyan
    Write-Host "  ║                    ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝              ║" -ForegroundColor Cyan
    Write-Host "  ║                                                                  ║" -ForegroundColor Cyan
    Write-Host "  ║                  Console Manager v$Version (Windows)              ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success { param($Message) Write-Host "  ✓ $Message" -ForegroundColor Green }
function Write-Error2 { param($Message) Write-Host "  ✗ $Message" -ForegroundColor Red }
function Write-Warning2 { param($Message) Write-Host "  ! $Message" -ForegroundColor Yellow }
function Write-Info { param($Message) Write-Host "  ℹ $Message" -ForegroundColor Blue }
function Write-Step { param($Message) Write-Host "  ▶ $Message" -ForegroundColor Magenta }

function Wait-ForEnter {
    Write-Host ""
    Write-Host "  Press Enter to continue..." -ForegroundColor Cyan
    Read-Host
}

function Confirm-Action {
    param([string]$Prompt = "Continue?")
    $response = Read-Host "  $Prompt [y/N]"
    return $response -match "^[TtYy]$"
}

#===============================================================================
# Detection Functions
#===============================================================================

# Auto-detect RustDesk installation paths
function Find-Paths {
    $found = $false
    
    # If RUSTDESK_PATH is already set (via env var), validate it
    if ($Script:RustdeskPath -ne "") {
        if ((Test-Path $Script:RustdeskPath) -and 
            ((Test-Path "$Script:RustdeskPath\hbbs.exe") -or (Test-Path "$Script:RustdeskPath\hbbs-v8-api.exe"))) {
            Write-Info "Using configured RustDesk path: $Script:RustdeskPath"
            $found = $true
        } else {
            Write-Warning2 "Configured RUSTDESK_PATH ($Script:RustdeskPath) is invalid"
            $Script:RustdeskPath = ""
        }
    }
    
    # Auto-detect if not found
    if ($Script:RustdeskPath -eq "") {
        foreach ($path in $Script:CommonRustdeskPaths) {
            if ((Test-Path $path) -and 
                ((Test-Path "$path\hbbs.exe") -or (Test-Path "$path\hbbs-v8-api.exe"))) {
                $Script:RustdeskPath = $path
                Write-Success "Detected RustDesk installation: $Script:RustdeskPath"
                $found = $true
                break
            }
        }
    }
    
    # If still not found, use default for new installations
    if ($Script:RustdeskPath -eq "") {
        $Script:RustdeskPath = "C:\rustdesk"
        Write-Info "No installation detected. Default path: $Script:RustdeskPath"
    }
    
    # Auto-detect Console path
    if ($Script:ConsolePath -ne "") {
        if ((Test-Path $Script:ConsolePath) -and (Test-Path "$Script:ConsolePath\app.py")) {
            Write-Info "Using configured Console path: $Script:ConsolePath"
        } else {
            Write-Warning2 "Configured CONSOLE_PATH ($Script:ConsolePath) is invalid"
            $Script:ConsolePath = ""
        }
    }
    
    if ($Script:ConsolePath -eq "") {
        foreach ($path in $Script:CommonConsolePaths) {
            if ((Test-Path $path) -and (Test-Path "$path\app.py")) {
                $Script:ConsolePath = $path
                Write-Success "Detected Console installation: $Script:ConsolePath"
                break
            }
        }
    }
    
    # Default Console path if not found
    if ($Script:ConsolePath -eq "") {
        $Script:ConsolePath = "C:\BetterDeskConsole"
    }
    
    # Update DB_PATH based on detected RUSTDESK_PATH
    $Script:DbPath = "$Script:RustdeskPath\db_v2.sqlite3"
}

# Interactive path configuration
function Set-Paths {
    Clear-Host
    Write-Header
    Write-Host ""
    Write-Host "  ═══ Path Configuration ═══" -ForegroundColor White
    Write-Host ""
    Write-Host "    Current RustDesk path: $Script:RustdeskPath" -ForegroundColor Cyan
    Write-Host "    Current Console path:  $Script:ConsolePath" -ForegroundColor Cyan
    Write-Host "    Database path:         $Script:DbPath" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "  Options:" -ForegroundColor Yellow
    Write-Host "    1. Auto-detect installation paths"
    Write-Host "    2. Set RustDesk server path manually"
    Write-Host "    3. Set Console path manually"
    Write-Host "    4. Reset to defaults"
    Write-Host "    0. Back to main menu"
    Write-Host ""
    $choice = Read-Host "  Select option [0-4]"
    
    switch ($choice) {
        "1" {
            $Script:RustdeskPath = ""
            $Script:ConsolePath = ""
            Find-Paths
            Wait-ForEnter
            Set-Paths
        }
        "2" {
            Write-Host ""
            $newPath = Read-Host "  Enter RustDesk server path (e.g., C:\rustdesk)"
            if ($newPath -ne "") {
                if (Test-Path $newPath) {
                    $Script:RustdeskPath = $newPath
                    $Script:DbPath = "$Script:RustdeskPath\db_v2.sqlite3"
                    Write-Success "RustDesk path set to: $Script:RustdeskPath"
                } else {
                    Write-Warning2 "Directory does not exist: $newPath"
                    if (Confirm-Action "Create this directory?") {
                        New-Item -ItemType Directory -Path $newPath -Force | Out-Null
                        $Script:RustdeskPath = $newPath
                        $Script:DbPath = "$Script:RustdeskPath\db_v2.sqlite3"
                        Write-Success "Created and set RustDesk path: $Script:RustdeskPath"
                    }
                }
            }
            Wait-ForEnter
            Set-Paths
        }
        "3" {
            Write-Host ""
            $newPath = Read-Host "  Enter Console path (e.g., C:\BetterDeskConsole)"
            if ($newPath -ne "") {
                if (Test-Path $newPath) {
                    $Script:ConsolePath = $newPath
                    Write-Success "Console path set to: $Script:ConsolePath"
                } else {
                    Write-Warning2 "Directory does not exist: $newPath"
                    if (Confirm-Action "Create this directory?") {
                        New-Item -ItemType Directory -Path $newPath -Force | Out-Null
                        $Script:ConsolePath = $newPath
                        Write-Success "Created and set Console path: $Script:ConsolePath"
                    }
                }
            }
            Wait-ForEnter
            Set-Paths
        }
        "4" {
            $Script:RustdeskPath = "C:\rustdesk"
            $Script:ConsolePath = "C:\BetterDeskConsole"
            $Script:DbPath = "$Script:RustdeskPath\db_v2.sqlite3"
            Write-Success "Paths reset to defaults"
            Wait-ForEnter
            Set-Paths
        }
        "0" {
            return
        }
        default {
            Write-Error2 "Invalid option"
            Wait-ForEnter
            Set-Paths
        }
    }
}

function Find-Installation {
    $Script:InstallStatus = "none"
    $Script:HbbsRunning = $false
    $Script:HbbrRunning = $false
    $Script:ConsoleRunning = $false
    $Script:BinariesOk = $false
    $Script:DatabaseOk = $false
    
    # Check paths
    if (Test-Path $Script:RustdeskPath) {
        $Script:InstallStatus = "partial"
        
        # Check binaries
        if ((Test-Path "$Script:RustdeskPath\hbbs.exe") -or (Test-Path "$Script:RustdeskPath\hbbs-v8-api.exe")) {
            $Script:BinariesOk = $true
        }
        
        # Check database
        if (Test-Path $Script:DbPath) {
            $Script:DatabaseOk = $true
        }
    }
    
    if ((Test-Path $Script:ConsolePath) -and (Test-Path "$Script:ConsolePath\app.py")) {
        if ($Script:BinariesOk -and $Script:DatabaseOk) {
            $Script:InstallStatus = "complete"
        }
    }
    
    # Check services/processes
    $hbbsProc = Get-Process -Name "hbbs*" -ErrorAction SilentlyContinue
    $hbbrProc = Get-Process -Name "hbbr*" -ErrorAction SilentlyContinue
    
    $Script:HbbsRunning = $null -ne $hbbsProc
    $Script:HbbrRunning = $null -ne $hbbrProc
    
    # Check if console is running (Python on port 5000)
    try {
        $conn = Get-NetTCPConnection -LocalPort 5000 -ErrorAction SilentlyContinue
        $Script:ConsoleRunning = $null -ne $conn
    } catch {
        $Script:ConsoleRunning = $false
    }
}

function Write-Status {
    Find-Installation
    
    Write-Host ""
    Write-Host "  ═══ System status ═══" -ForegroundColor White
    Write-Host ""
    Write-Host "    System:       Windows $([System.Environment]::OSVersion.Version)" -ForegroundColor Cyan
    Write-Host "    Architecture: $env:PROCESSOR_ARCHITECTURE" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "  ═══ Configured Paths ═══" -ForegroundColor White
    Write-Host ""
    Write-Host "    RustDesk:     $Script:RustdeskPath" -ForegroundColor Cyan
    Write-Host "    Console:      $Script:ConsolePath" -ForegroundColor Cyan
    Write-Host "    Database:     $Script:DbPath" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "  ═══ Installation status ═══" -ForegroundColor White
    Write-Host ""
    
    switch ($Script:InstallStatus) {
        "complete" { Write-Host "    Status:       ✓ Installed" -ForegroundColor Green }
        "partial"  { Write-Host "    Status:       ! Partial installation" -ForegroundColor Yellow }
        "none"     { Write-Host "    Status:       ✗ Not installed" -ForegroundColor Red }
    }
    
    if ($Script:BinariesOk) {
        Write-Host "    Binaries:     ✓ OK" -ForegroundColor Green
    } else {
        Write-Host "    Binaries:     ✗ Not found" -ForegroundColor Red
    }
    
    if ($Script:DatabaseOk) {
        Write-Host "    Database:     ✓ OK" -ForegroundColor Green
    } else {
        Write-Host "    Database:     ✗ Not found" -ForegroundColor Red
    }
    
    if (Test-Path $Script:ConsolePath) {
        Write-Host "    Web Console:  ✓ OK" -ForegroundColor Green
    } else {
        Write-Host "    Web Console:  ✗ Not found" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "  ═══ Services Status ═══" -ForegroundColor White
    Write-Host ""
    
    if ($Script:HbbsRunning) {
        Write-Host "    HBBS (Signal): ● Active" -ForegroundColor Green
    } else {
        Write-Host "    HBBS (Signal): ○ Inactive" -ForegroundColor Red
    }
    
    if ($Script:HbbrRunning) {
        Write-Host "    HBBR (Relay):  ● Active" -ForegroundColor Green
    } else {
        Write-Host "    HBBR (Relay):  ○ Inactive" -ForegroundColor Red
    }
    
    if ($Script:ConsoleRunning) {
        Write-Host "    Web Console:   ● Active" -ForegroundColor Green
    } else {
        Write-Host "    Web Console:   ○ Inactive" -ForegroundColor Red
    }
    
    Write-Host ""
}

#===============================================================================
# Installation Functions
#===============================================================================

function Install-Dependencies {
    Write-Step "Checking dependencies..."
    
    # Check Python
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        Write-Warning2 "Python is not installed!"
        Write-Info "Downloading Python..."
        
        $pythonUrl = "https://www.python.org/ftp/python/3.11.0/python-3.11.0-amd64.exe"
        $pythonInstaller = "$env:TEMP\python_installer.exe"
        
        Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonInstaller
        Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet", "InstallAllUsers=1", "PrependPath=1" -Wait
        
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }
    
    Write-Success "Python installed"
}

#===============================================================================
# Binary Verification Functions
#===============================================================================

function Test-BinaryChecksum {
    param(
        [string]$FilePath,
        [string]$ExpectedHash
    )
    
    $fileName = Split-Path $FilePath -Leaf
    
    if (-not (Test-Path $FilePath)) {
        Write-Error2 "File not found: $FilePath"
        return $false
    }
    
    Write-Info "Verifying $fileName..."
    $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
    
    if ($actualHash -eq $ExpectedHash) {
        Write-Success "$fileName`: SHA256 OK"
        return $true
    } else {
        Write-Error2 "$fileName`: SHA256 MISMATCH!"
        Write-Error2 "  Expected: $ExpectedHash"
        Write-Error2 "  Got:      $actualHash"
        return $false
    }
}

function Test-Binaries {
    Write-Step "Verifying BetterDesk binaries..."
    
    $binSource = Join-Path $Script:ScriptDir "hbbs-patch-v2"
    $errors = 0
    
    if ($SkipVerify) {
        Write-Warning2 "Verification skipped (-SkipVerify)"
        return $true
    }
    
    # Verify Windows binaries
    $hbbsPath = Join-Path $binSource "hbbs-windows-x86_64.exe"
    $hbbrPath = Join-Path $binSource "hbbr-windows-x86_64.exe"
    
    if (Test-Path $hbbsPath) {
        if (-not (Test-BinaryChecksum -FilePath $hbbsPath -ExpectedHash $Script:HBBS_WINDOWS_SHA256)) {
            $errors++
        }
    }
    
    if (Test-Path $hbbrPath) {
        if (-not (Test-BinaryChecksum -FilePath $hbbrPath -ExpectedHash $Script:HBBR_WINDOWS_SHA256)) {
            $errors++
        }
    }
    
    if ($errors -gt 0) {
        Write-Error2 "Binary verification failed! $errors error(s)"
        Write-Warning2 "Binaries may be corrupted or outdated."
        if (-not $Auto) {
            if (-not (Confirm-Action "Continue anyway?")) {
                return $false
            }
        } else {
            return $false
        }
    } else {
        Write-Success "All binaries verified"
    }
    
    return $true
}

#===============================================================================
# Installation Functions
#===============================================================================

function Install-Binaries {
    Write-Step "Installing BetterDesk binaries..."
    
    if (-not (Test-Path $Script:RustdeskPath)) {
        New-Item -ItemType Directory -Path $Script:RustdeskPath -Force | Out-Null
    }
    
    # Find binaries
    $binSource = $null
    
    $v2Path = Join-Path $Script:ScriptDir "hbbs-patch-v2"
    if (Test-Path "$v2Path\hbbs-windows-x86_64.exe") {
        $binSource = $v2Path
        Write-Info "Found binaries in hbbs-patch-v2/"
    }
    
    if (-not $binSource) {
        Write-Error2 "BetterDesk binaries not found!"
        Write-Info "Run 'Build binaries' option or download prebuilt files."
        return $false
    }
    
    # Verify binaries before installation
    if (-not (Test-Binaries)) {
        Write-Error2 "Aborting installation due to verification failure"
        return $false
    }
    
    # Copy binaries
    Copy-Item "$binSource\hbbs-windows-x86_64.exe" "$Script:RustdeskPath\hbbs.exe" -Force
    Write-Success "Installed hbbs.exe (signal server)"
    
    Copy-Item "$binSource\hbbr-windows-x86_64.exe" "$Script:RustdeskPath\hbbr.exe" -Force
    Write-Success "Installed hbbr.exe (relay server)"
    
    Write-Success "BetterDesk binaries v$Version installed"
    return $true
}

function Install-Console {
    Write-Step "Installing Web Console..."
    
    if (-not (Test-Path $Script:ConsolePath)) {
        New-Item -ItemType Directory -Path $Script:ConsolePath -Force | Out-Null
    }
    
    # Copy web files
    $webSource = Join-Path $Script:ScriptDir "web"
    if (Test-Path $webSource) {
        Copy-Item "$webSource\*" $Script:ConsolePath -Recurse -Force
    } else {
        Write-Error2 "web/ folder not found in project!"
        return $false
    }
    
    # Setup Python environment
    Write-Step "Configuring Python environment..."
    
    Push-Location $Script:ConsolePath
    
    python -m venv venv 2>$null
    & "$Script:ConsolePath\venv\Scripts\pip.exe" install --quiet --upgrade pip
    & "$Script:ConsolePath\venv\Scripts\pip.exe" install --quiet -r requirements.txt
    
    Pop-Location
    
    Write-Success "Web Console installed"
    return $true
}

function Initialize-WindowsServices {
    Write-Step "Configuring Windows services..."
    
    # Get server IP
    $serverIp = try {
        (Invoke-WebRequest -Uri "https://ifconfig.me" -UseBasicParsing -TimeoutSec 5).Content.Trim()
    } catch {
        "127.0.0.1"
    }
    
    Write-Info "Server IP: $serverIp"
    Write-Info "API Port: $Script:ApiPort"
    
    # Create start scripts with correct API port
    $hbbsStartScript = @"
@echo off
cd /d "$Script:RustdeskPath"
hbbs.exe -r $serverIp -k _ --api-port $Script:ApiPort
"@
    
    $hbbrStartScript = @"
@echo off
cd /d "$Script:RustdeskPath"
hbbr.exe -k _
"@
    
    $consoleStartScript = @"
@echo off
cd /d "$Script:ConsolePath"
call venv\Scripts\activate
set RUSTDESK_PATH=$Script:RustdeskPath
set API_PORT=$Script:ApiPort
python app.py
"@
    
    Set-Content -Path "$Script:RustdeskPath\start-hbbs.bat" -Value $hbbsStartScript
    Set-Content -Path "$Script:RustdeskPath\start-hbbr.bat" -Value $hbbrStartScript
    Set-Content -Path "$Script:ConsolePath\start-console.bat" -Value $consoleStartScript
    
    # Create scheduled tasks for auto-start
    $taskExists = Get-ScheduledTask -TaskName "BetterDesk-HBBS" -ErrorAction SilentlyContinue
    if ($taskExists) {
        Unregister-ScheduledTask -TaskName "BetterDesk-HBBS" -Confirm:$false
    }
    
    $action = New-ScheduledTaskAction -Execute "$Script:RustdeskPath\start-hbbs.bat"
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
    Register-ScheduledTask -TaskName "BetterDesk-HBBS" -Action $action -Trigger $trigger -Principal $principal -Description "BetterDesk Signal Server v$Version" | Out-Null
    
    $taskExists = Get-ScheduledTask -TaskName "BetterDesk-HBBR" -ErrorAction SilentlyContinue
    if ($taskExists) {
        Unregister-ScheduledTask -TaskName "BetterDesk-HBBR" -Confirm:$false
    }
    
    $action = New-ScheduledTaskAction -Execute "$Script:RustdeskPath\start-hbbr.bat"
    Register-ScheduledTask -TaskName "BetterDesk-HBBR" -Action $action -Trigger $trigger -Principal $principal -Description "BetterDesk Relay Server v$Version" | Out-Null
    
    Write-Success "Windows services configured"
    Write-Info "Tasks: BetterDesk-HBBS, BetterDesk-HBBR"
}

function Invoke-Migrations {
    Write-Step "Running database migrations..."
    
    $migrationsPath = Join-Path $Script:ScriptDir "migrations"
    if (Test-Path $migrationsPath) {
        Get-ChildItem "$migrationsPath\v*.py" | ForEach-Object {
            Write-Info "Migration: $($_.Name)"
            & python $_.FullName $Script:DbPath 2>$null
        }
    }
    
    Write-Success "Migrations completed"
}

function New-AdminUser {
    Write-Step "Creating admin user..."
    
    # Generate password
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $adminPassword = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    
    # Create admin via Python
    $pythonScript = @"
import sqlite3
import sys
sys.path.insert(0, '$($Script:ConsolePath -replace '\\', '\\\\')\\venv\\Lib\\site-packages')
import bcrypt
from datetime import datetime

conn = sqlite3.connect('$($Script:DbPath -replace '\\', '\\\\')')
cursor = conn.cursor()

cursor.execute('''CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    role TEXT DEFAULT 'viewer',
    is_active INTEGER DEFAULT 1,
    created_at TEXT,
    last_login TEXT
)''')

cursor.execute("SELECT id FROM users WHERE username='admin'")
if cursor.fetchone():
    print("Admin already exists")
else:
    password_hash = bcrypt.hashpw('$adminPassword'.encode(), bcrypt.gensalt()).decode()
    cursor.execute('''INSERT INTO users (username, password_hash, role, is_active, created_at)
                      VALUES ('admin', ?, 'admin', 1, ?)''', (password_hash, datetime.now().isoformat()))
    conn.commit()
    print("Admin created")

conn.close()
"@
    
    $pythonScript | & "$Script:ConsolePath\venv\Scripts\python.exe" 2>$null
    
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║            PANEL LOGIN CREDENTIALS                    ║" -ForegroundColor Green
    Write-Host "  ╠════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "  ║  Login:    admin                                       ║" -ForegroundColor Green
    Write-Host "  ║  Password: $adminPassword                         ║" -ForegroundColor Green
    Write-Host "  ╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    
    # Save credentials
    "admin:$adminPassword" | Set-Content "$Script:RustdeskPath\.admin_credentials"
    
    Write-Info "Credentials saved in: $Script:RustdeskPath\.admin_credentials"
}

function Start-Services {
    Write-Step "Starting services..."
    
    # Start HBBS
    Start-Process -FilePath "$Script:RustdeskPath\start-hbbs.bat" -WindowStyle Hidden
    Start-Sleep -Seconds 2
    
    # Start HBBR
    Start-Process -FilePath "$Script:RustdeskPath\start-hbbr.bat" -WindowStyle Hidden
    Start-Sleep -Seconds 2
    
    # Start Console
    Start-Process -FilePath "$Script:ConsolePath\start-console.bat" -WindowStyle Hidden
    Start-Sleep -Seconds 3
    
    Find-Installation
    
    if ($Script:HbbsRunning -and $Script:HbbrRunning) {
        Write-Success "Services started"
    } else {
        Write-Warning2 "Some services might not be working properly"
    }
}

function Stop-Services {
    Write-Step "Stopping services..."
    
    Get-Process -Name "hbbs*" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process -Name "hbbr*" -ErrorAction SilentlyContinue | Stop-Process -Force
    
    # Find and stop Python console process
    $pythonProcesses = Get-Process -Name "python*" -ErrorAction SilentlyContinue
    foreach ($proc in $pythonProcesses) {
        try {
            $cmdLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
            if ($cmdLine -like "*app.py*") {
                $proc | Stop-Process -Force
            }
        } catch {}
    }
    
    Write-Success "Services stopped"
}

function Invoke-Install {
    Write-Header
    Write-Host "  ══════════ FRESH INSTALLATION ═════════=" -ForegroundColor White
    Write-Host ""
    
    Find-Installation
    
    if ($Script:InstallStatus -eq "complete") {
        Write-Warning2 "BetterDesk is already installed!"
        if (-not $Auto) {
            if (-not (Confirm-Action "Do you want to reinstall?")) {
                return
            }
        }
        Invoke-BackupSilent
    }
    
    Write-Host ""
    Write-Info "Starting BetterDesk Console v$Version installation..."
    Write-Host ""
    
    Install-Dependencies
    if (-not (Install-Binaries)) { 
        Write-Error2 "Binary installation failed"
        if (-not $Auto) { Wait-ForEnter }
        return $false 
    }
    if (-not (Install-Console)) { 
        if (-not $Auto) { Wait-ForEnter }
        return $false 
    }
    Initialize-WindowsServices
    Invoke-Migrations
    New-AdminUser
    Start-Services
    
    Write-Host ""
    Write-Success "Installation completed successfully!"
    Write-Host ""
    
    $serverIp = try {
        (Invoke-WebRequest -Uri "https://ifconfig.me" -UseBasicParsing -TimeoutSec 5).Content.Trim()
    } catch { "YOUR_IP" }
    
    $publicKey = ""
    if (Test-Path "$Script:RustdeskPath\id_ed25519.pub") {
        $publicKey = Get-Content "$Script:RustdeskPath\id_ed25519.pub" -First 1
    }
    
    Write-Host "  ╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║              INSTALLATION INFO                             ║" -ForegroundColor Cyan
    Write-Host "  ╠════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "  ║  Web Panel:     http://${serverIp}:5000                         ║" -ForegroundColor Cyan
    Write-Host "  ║  API Port:      $Script:ApiPort                                      ║" -ForegroundColor Cyan
    Write-Host "  ║  Server ID:     $serverIp                                       ║" -ForegroundColor Cyan
    if ($publicKey) {
        Write-Host "  ║  Key:           $($publicKey.Substring(0, [Math]::Min(20, $publicKey.Length)))...                               ║" -ForegroundColor Cyan
    }
    Write-Host "  ╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    if (-not $Auto) {
        Wait-ForEnter
    }
    
    return $true
}

#===============================================================================
# Update Functions
#===============================================================================

function Invoke-Update {
    Write-Header
    Write-Host "  ══════════ UPDATE ═════════=" -ForegroundColor White
    Write-Host ""
    
    Find-Installation
    
    if ($Script:InstallStatus -eq "none") {
        Write-Error2 "BetterDesk is not installed!"
        Write-Info "Use 'FRESH INSTALLATION' option"
        Wait-ForEnter
        return
    }
    
    Write-Info "Creating backup before update..."
    Invoke-BackupSilent
    
    Stop-Services
    Install-Binaries
    Install-Console
    Run-Migrations
    Start-Services
    
    Write-Success "UPDATE completed!"
    Wait-ForEnter
}

#===============================================================================
# Repair Functions
#===============================================================================

function Invoke-Repair {
    Write-Header
    Write-Host "  ══════════ REPAIR INSTALLATION ═════════=" -ForegroundColor White
    Write-Host ""
    
    Find-Installation
    Write-Status
    
    Write-Host ""
    Write-Host "  What do you want to repair?" -ForegroundColor White
    Write-Host ""
    Write-Host "    1. 🔧 Repair binaries (replace with BetterDesk)"
    Write-Host "    2. 🗃️  Repair database"
    Write-Host "    3. ⚙️  Repair Windows services"
    Write-Host "    4. 🔄 Full repair (everything)"
    Write-Host "    0. ↩️  Back"
    Write-Host ""
    
    $choice = Read-Host "  Select option"
    
    switch ($choice) {
        "1" { Repair-Binaries }
        "2" { Repair-Database }
        "3" { Setup-WindowsServices }
        "4" { 
            Repair-Binaries
            Repair-Database
            Setup-WindowsServices
            Write-Success "Full repair completed!"
        }
        "0" { return }
    }
    
    Wait-ForEnter
}

function Repair-Binaries {
    Write-Step "Repair binaries..."
    Stop-Services
    Install-Binaries
    Start-Services
    Write-Success "Binaries repaired"
}

function Repair-Database {
    Write-Step "Repair database..."
    
    if (-not (Test-Path $Script:DbPath)) {
        Write-Warning2 "Database does not exist, creating new one..."
        New-Item -ItemType File -Path $Script:DbPath -Force | Out-Null
    }
    
    $pythonScript = @"
import sqlite3

conn = sqlite3.connect('$($Script:DbPath -replace '\\', '\\\\')')
cursor = conn.cursor()

columns_to_add = [
    ('status', 'INTEGER DEFAULT 0'),
    ('last_online', 'TEXT'),
    ('is_deleted', 'INTEGER DEFAULT 0'),
    ('deleted_at', 'TEXT'),
    ('updated_at', 'TEXT'),
    ('note', 'TEXT'),
    ('previous_ids', 'TEXT'),
    ('id_changed_at', 'TEXT'),
]

cursor.execute("PRAGMA table_info(peer)")
existing_columns = [col[1] for col in cursor.fetchall()]

for col_name, col_def in columns_to_add:
    if col_name not in existing_columns:
        try:
            cursor.execute(f"ALTER TABLE peer ADD COLUMN {col_name} {col_def}")
            print(f"  Added column: {col_name}")
        except:
            pass

conn.commit()
conn.close()
print("Database repaired")
"@
    
    $pythonScript | python 2>$null
    
    Write-Success "Database repaired"
}

#===============================================================================
# Validation Functions
#===============================================================================

function Invoke-Validate {
    Write-Header
    Write-Host "  ══════════ INSTALLATION VALIDATION ═════════=" -ForegroundColor White
    Write-Host ""
    
    $errors = 0
    $warnings = 0
    
    Find-Installation
    
    Write-Host "  Checking components..." -ForegroundColor White
    Write-Host ""
    
    # Check directories
    Write-Host -NoNewline "    RustDesk directory ($Script:RustdeskPath): "
    if (Test-Path $Script:RustdeskPath) {
        Write-Host "✓" -ForegroundColor Green
    } else {
        Write-Host "✗ Not found" -ForegroundColor Red
        $errors++
    }
    
    Write-Host -NoNewline "    Console directory ($Script:ConsolePath): "
    if (Test-Path $Script:ConsolePath) {
        Write-Host "✓" -ForegroundColor Green
    } else {
        Write-Host "✗ Not found" -ForegroundColor Red
        $errors++
    }
    
    # Check binaries
    Write-Host -NoNewline "    HBBS binary: "
    if (Test-Path "$Script:RustdeskPath\hbbs.exe") {
        Write-Host "✓" -ForegroundColor Green
    } else {
        Write-Host "✗ Not found" -ForegroundColor Red
        $errors++
    }
    
    Write-Host -NoNewline "    HBBR binary: "
    if (Test-Path "$Script:RustdeskPath\hbbr.exe") {
        Write-Host "✓" -ForegroundColor Green
    } else {
        Write-Host "✗ Not found" -ForegroundColor Red
        $errors++
    }
    
    # Check database
    Write-Host -NoNewline "    Database: "
    if (Test-Path $Script:DbPath) {
        Write-Host "✓" -ForegroundColor Green
    } else {
        Write-Host "✗ Not found" -ForegroundColor Red
        $errors++
    }
    
    # Check keys
    Write-Host -NoNewline "    Public key: "
    if (Test-Path "$Script:RustdeskPath\id_ed25519.pub") {
        Write-Host "✓" -ForegroundColor Green
    } else {
        Write-Host "! Will be generated on first start" -ForegroundColor Yellow
        $warnings++
    }
    
    Write-Host ""
    Write-Host "  Checking processes..." -ForegroundColor White
    Write-Host ""
    
    Write-Host -NoNewline "    HBBS (Signal): "
    if ($Script:HbbsRunning) {
        Write-Host "● Active" -ForegroundColor Green
    } else {
        Write-Host "○ Inactive" -ForegroundColor Red
        $errors++
    }
    
    Write-Host -NoNewline "    HBBR (Relay):  "
    if ($Script:HbbrRunning) {
        Write-Host "● Active" -ForegroundColor Green
    } else {
        Write-Host "○ Inactive" -ForegroundColor Red
        $errors++
    }
    
    Write-Host -NoNewline "    Web Console:   "
    if ($Script:ConsoleRunning) {
        Write-Host "● Active" -ForegroundColor Green
    } else {
        Write-Host "○ Inactive" -ForegroundColor Red
        $errors++
    }
    
    # Check ports
    Write-Host ""
    Write-Host "  Checking ports..." -ForegroundColor White
    Write-Host ""
    
    foreach ($port in @(21114, 21115, 21116, 21117, 5000)) {
        Write-Host -NoNewline "    Port ${port}: "
        $conn = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($conn) {
            Write-Host "● Listening" -ForegroundColor Green
        } else {
            Write-Host "○ Free" -ForegroundColor Yellow
            $warnings++
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "  ═══════════════════════════════════════" -ForegroundColor White
    
    if ($errors -eq 0 -and $warnings -eq 0) {
        Write-Host "  ✓ Installation correct - no problems found" -ForegroundColor Green
    } elseif ($errors -eq 0) {
        Write-Host "  ! Found $warnings warnings" -ForegroundColor Yellow
    } else {
        Write-Host "  ✗ Found $errors errors and $warnings warnings" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Use 'REPAIR INSTALLATION' option to fix problems" -ForegroundColor Cyan
    }
    
    Wait-ForEnter
}

#===============================================================================
# Backup Functions
#===============================================================================

function Invoke-Backup {
    Write-Header
    Write-Host "  ══════════ BACKUP ═════════=" -ForegroundColor White
    Write-Host ""
    
    Invoke-BackupSilent
    
    Write-Success "Backup completed!"
    Wait-ForEnter
}

function Invoke-BackupSilent {
    $backupName = "betterdesk_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $backupPath = Join-Path $Script:BackupDir $backupName
    
    if (-not (Test-Path $Script:BackupDir)) {
        New-Item -ItemType Directory -Path $Script:BackupDir -Force | Out-Null
    }
    
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    
    Write-Step "Creating backup: $backupName"
    
    # Backup database
    if (Test-Path $Script:DbPath) {
        Copy-Item $Script:DbPath $backupPath
        Write-Info "  - Database"
    }
    
    # Backup keys
    if (Test-Path "$Script:RustdeskPath\id_ed25519") {
        Copy-Item "$Script:RustdeskPath\id_ed25519*" $backupPath
        Write-Info "  - Keys"
    }
    
    # Backup API key
    if (Test-Path "$Script:RustdeskPath\.api_key") {
        Copy-Item "$Script:RustdeskPath\.api_key" $backupPath
        Write-Info "  - API key"
    }
    
    # Backup credentials
    if (Test-Path "$Script:RustdeskPath\.admin_credentials") {
        Copy-Item "$Script:RustdeskPath\.admin_credentials" $backupPath
        Write-Info "  - Login credentials"
    }
    
    # Create archive
    Compress-Archive -Path $backupPath -DestinationPath "$Script:BackupDir\$backupName.zip" -Force
    Remove-Item $backupPath -Recurse -Force
    
    Write-Success "Backup saved: $Script:BackupDir\$backupName.zip"
}

#===============================================================================
# Password Reset Functions
#===============================================================================

function Reset-AdminPassword {
    Write-Header
    Write-Host "  ══════════ ADMIN PASSWORD RESET ═════════=" -ForegroundColor White
    Write-Host ""
    
    if (-not (Test-Path $Script:DbPath)) {
        Write-Error2 "Database does not exist!"
        Wait-ForEnter
        return
    }
    
    Write-Host "  Select option:"
    Write-Host ""
    Write-Host "    1. Generate new random password"
    Write-Host "    2. Set custom password"
    Write-Host "    0. Back"
    Write-Host ""
    
    $choice = Read-Host "  Choice"
    
    $newPassword = ""
    
    switch ($choice) {
        "1" {
            $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            $newPassword = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
        }
        "2" {
            Write-Host ""
            $newPassword = Read-Host "  Enter new password (min. 8 characters)"
            if ($newPassword.Length -lt 8) {
                Write-Error2 "Password must be at least 8 characters!"
                Wait-ForEnter
                return
            }
        }
        "0" { return }
        default { return }
    }
    
    $pythonScript = @"
import sqlite3
import sys
sys.path.insert(0, '$($Script:ConsolePath -replace '\\', '\\\\')\\venv\\Lib\\site-packages')
import bcrypt

conn = sqlite3.connect('$($Script:DbPath -replace '\\', '\\\\')')
cursor = conn.cursor()

password_hash = bcrypt.hashpw('$newPassword'.encode(), bcrypt.gensalt()).decode()
cursor.execute("UPDATE users SET password_hash = ? WHERE username = 'admin'", (password_hash,))

if cursor.rowcount == 0:
    cursor.execute('''INSERT INTO users (username, password_hash, role, is_active)
                      VALUES ('admin', ?, 'admin', 1)''', (password_hash,))

conn.commit()
conn.close()
"@
    
    $pythonScript | & "$Script:ConsolePath\venv\Scripts\python.exe" 2>$null
    
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║              NEW LOGIN CREDENTIALS                       ║" -ForegroundColor Green
    Write-Host "  ╠════════════════════════════════════════════════════════╣" -ForegroundColor Green
    Write-Host "  ║  Login:    admin                                       ║" -ForegroundColor Green
    Write-Host "  ║  Password: $newPassword                         ║" -ForegroundColor Green
    Write-Host "  ╚════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    "admin:$newPassword" | Set-Content "$Script:RustdeskPath\.admin_credentials"
    
    Wait-ForEnter
}

#===============================================================================
# Build Functions
#===============================================================================

function Invoke-Build {
    Write-Header
    Write-Host "  ══════════ Build binaries ═════════=" -ForegroundColor White
    Write-Host ""
    
    # Check Rust
    $cargo = Get-Command cargo -ErrorAction SilentlyContinue
    if (-not $cargo) {
        Write-Warning2 "Rust is not installed!"
        Write-Host ""
        if (Confirm-Action "Do you want to install Rust?") {
            Write-Info "Downloading Rust..."
            $rustupUrl = "https://win.rustup.rs/x86_64"
            $rustupInstaller = "$env:TEMP\rustup-init.exe"
            Invoke-WebRequest -Uri $rustupUrl -OutFile $rustupInstaller
            Start-Process -FilePath $rustupInstaller -ArgumentList "-y" -Wait
            
            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        } else {
            Wait-ForEnter
            return
        }
    }
    
    Write-Info "Rust: $(cargo --version)"
    Write-Host ""
    
    $buildDir = "$env:TEMP\betterdesk_build_$(Get-Random)"
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
    
    Push-Location $buildDir
    
    Write-Step "Downloading RustDesk Server sources..."
    git clone --depth 1 --branch 1.1.14 https://github.com/rustdesk/rustdesk-server.git
    Set-Location rustdesk-server
    git submodule update --init --recursive
    
    Write-Step "Applying BetterDesk modifications..."
    
    $srcPath = Join-Path $Script:ScriptDir "hbbs-patch-v2\src"
    if (Test-Path $srcPath) {
        Copy-Item "$srcPath\main.rs" "src\" -Force -ErrorAction SilentlyContinue
        Copy-Item "$srcPath\http_api.rs" "src\" -Force -ErrorAction SilentlyContinue
        Copy-Item "$srcPath\database.rs" "src\" -Force -ErrorAction SilentlyContinue
        Copy-Item "$srcPath\peer.rs" "src\" -Force -ErrorAction SilentlyContinue
        Copy-Item "$srcPath\rendezvous_server.rs" "src\" -Force -ErrorAction SilentlyContinue
    } else {
        Write-Error2 "Modified sources not found in hbbs-patch-v2\src\"
        Pop-Location
        Remove-Item $buildDir -Recurse -Force
        Wait-ForEnter
        return
    }
    
    Write-Step "Compiling (may take several minutes)..."
    cargo build --release
    
    Write-Step "Copying binaries..."
    
    $destPath = Join-Path $Script:ScriptDir "hbbs-patch-v2"
    Copy-Item "target\release\hbbs.exe" "$destPath\hbbs-windows-x86_64.exe" -Force
    Copy-Item "target\release\hbbr.exe" "$destPath\hbbr-windows-x86_64.exe" -Force
    
    Pop-Location
    Remove-Item $buildDir -Recurse -Force
    
    Write-Success "Compilation completed!"
    Write-Info "Binaries saved in: $destPath"
    
    Write-Host ""
    if (Confirm-Action "Do you want to install the new binaries?") {
        Stop-Services
        Install-Binaries
        Start-Services
    }
    
    Wait-ForEnter
}

#===============================================================================
# Diagnostics Functions
#===============================================================================

function Invoke-Diagnostics {
    Write-Header
    Write-Host "  ══════════ DIAGNOSTICS ═════════=" -ForegroundColor White
    Write-Host ""
    
    Write-Status
    
    Write-Host ""
    Write-Host "  ═══ Database statistics ═══" -ForegroundColor White
    Write-Host ""
    
    if (Test-Path $Script:DbPath) {
        $pythonScript = @"
import sqlite3
conn = sqlite3.connect('$($Script:DbPath -replace '\\', '\\\\')')
cursor = conn.cursor()
try:
    cursor.execute("SELECT COUNT(*) FROM peer WHERE is_deleted = 0")
    devices = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM peer WHERE status = 1 AND is_deleted = 0")
    online = cursor.fetchone()[0]
    cursor.execute("SELECT COUNT(*) FROM users")
    users = cursor.fetchone()[0]
    print(f"    Devices:           {devices}")
    print(f"    Online:            {online}")
    print(f"    Users:             {users}")
except:
    print("    Database read error")
conn.close()
"@
        $pythonScript | python 2>$null
    } else {
        Write-Host "    Database does not exist"
    }
    
    Write-Host ""
    Write-Host "  ═══ Network connections ═══" -ForegroundColor White
    Write-Host ""
    
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | 
        Where-Object { $_.LocalPort -in @(21114, 21115, 21116, 21117, 5000) } |
        Format-Table LocalPort, State, OwningProcess -AutoSize
    
    Wait-ForEnter
}

#===============================================================================
# Uninstall Functions
#===============================================================================

function Invoke-Uninstall {
    Write-Header
    Write-Host "  ══════════ UNINSTALL ═════════=" -ForegroundColor Red
    Write-Host ""
    
    Write-Warning2 "This operation will remove BetterDesk Console!"
    Write-Host ""
    
    if (-not (Confirm-Action "Are you sure you want to continue?")) {
        return
    }
    
    if (Confirm-Action "Create backup before uninstall?") {
        Invoke-BackupSilent
    }
    
    Stop-Services
    
    Write-Step "Removing scheduled tasks..."
    Unregister-ScheduledTask -TaskName "BetterDesk-HBBS" -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "BetterDesk-HBBR" -Confirm:$false -ErrorAction SilentlyContinue
    
    if (Confirm-Action "Remove installation files ($Script:RustdeskPath)?") {
        Remove-Item $Script:RustdeskPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Info "Removed: $Script:RustdeskPath"
    }
    
    if (Confirm-Action "Remove Web Console ($Script:ConsolePath)?") {
        Remove-Item $Script:ConsolePath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Info "Removed: $Script:ConsolePath"
    }
    
    Write-Success "BetterDesk has been uninstalled"
    Wait-ForEnter
}

#===============================================================================
# Main Menu
#===============================================================================

function Show-Menu {
    Write-Header
    Write-Status
    
    Write-Host "  ══════════ MAIN MENU ═════════=" -ForegroundColor White
    Write-Host ""
    Write-Host "    1. 🚀 FRESH INSTALLATION"
    Write-Host "    2. ⬆️  UPDATE"
    Write-Host "    3. 🔧 REPAIR INSTALLATION"
    Write-Host "    4. ✅ INSTALLATION VALIDATION"
    Write-Host "    5. 💾 Backup"
    Write-Host "    6. 🔐 Reset admin password"
    Write-Host "    7. 🔨 Build binaries"
    Write-Host "    8. 📊 DIAGNOSTICS"
    Write-Host "    9. 🗑️  UNINSTALL"
    Write-Host ""
    Write-Host "    S. ⚙️  Settings (paths)"
    Write-Host "    0. ❌ Exit"
    Write-Host ""
}

# Auto-detect paths on startup
Write-Host "  Detecting installation..." -ForegroundColor Cyan
Find-Paths
Write-Host ""
Start-Sleep -Seconds 1

# Auto mode - run installation directly
if ($Auto) {
    Write-Info "Running in AUTO mode..."
    $result = Invoke-Install
    if ($result) {
        exit 0
    } else {
        exit 1
    }
}

# Interactive Main Menu
while ($true) {
    Show-Menu
    $choice = Read-Host "  Select option"
    
    switch ($choice) {
        "1" { Invoke-Install }
        "2" { Invoke-Update }
        "3" { Invoke-Repair }
        "4" { Invoke-Validate }
        "5" { Invoke-Backup }
        "6" { Reset-AdminPassword }
        "7" { Invoke-Build }
        "8" { Invoke-Diagnostics }
        "9" { Invoke-Uninstall }
        "S" { Set-Paths }
        "s" { Set-Paths }
        "0" { 
            Write-Host ""
            Write-Info "Goodbye!"
            exit
        }
        default {
            Write-Warning2 "Invalid option"
            Start-Sleep -Seconds 1
        }
    }
}
