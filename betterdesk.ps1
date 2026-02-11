#Requires -RunAsAdministrator
<#
.SYNOPSIS
    BetterDesk Console Manager v2.1.1 - All-in-One Interactive Tool for Windows

.DESCRIPTION
    Features:
      - Fresh installation
      - Update existing installation
      - Repair/fix issues
      - Validate installation
      - Backup & restore
      - Reset admin password
      - Build custom binaries
      - Full diagnostics
      - SHA256 binary verification
      - Auto mode (non-interactive)

.PARAMETER Auto
    Run installation in automatic mode (non-interactive)

.PARAMETER SkipVerify
    Skip SHA256 verification of binaries

.EXAMPLE
    .\betterdesk.ps1
    Interactive mode

.EXAMPLE
    .\betterdesk.ps1 -Auto
    Automatic installation without prompts

.EXAMPLE
    .\betterdesk.ps1 -SkipVerify
    Skip binary verification
#>

param(
    [switch]$Auto,
    [switch]$SkipVerify
)

#===============================================================================
# Configuration
#===============================================================================

$script:VERSION = "2.1.1"
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Auto mode flags
$script:AUTO_MODE = $Auto
$script:SKIP_VERIFY = $SkipVerify

# Binary checksums (SHA256) - v2.1.1
$script:HBBS_WINDOWS_X86_64_SHA256 = "682AA117AEEC8A6408DB4462BD31EB9DE943D5F70F5C27F3383F1DF56028A6E3"
$script:HBBR_WINDOWS_X86_64_SHA256 = "B585D077D5512035132BBCE3CE6CBC9D034E2DAE0805A799B3196C7372D82BEA"

# Default paths
$script:RUSTDESK_PATH = if ($env:RUSTDESK_PATH) { $env:RUSTDESK_PATH } else { "C:\BetterDesk" }
$script:CONSOLE_PATH = if ($env:CONSOLE_PATH) { $env:CONSOLE_PATH } else { "C:\BetterDeskConsole" }
$script:BACKUP_DIR = if ($env:BACKUP_DIR) { $env:BACKUP_DIR } else { "C:\BetterDesk-Backups" }
$script:DB_PATH = "$script:RUSTDESK_PATH\db_v2.sqlite3"

# API configuration
$script:API_PORT = if ($env:API_PORT) { $env:API_PORT } else { "21114" }

# Common installation paths to search
$script:COMMON_RUSTDESK_PATHS = @(
    "C:\BetterDesk",
    "C:\RustDesk",
    "C:\Program Files\BetterDesk",
    "C:\Program Files\RustDesk",
    "$env:LOCALAPPDATA\BetterDesk"
)

$script:COMMON_CONSOLE_PATHS = @(
    "C:\BetterDeskConsole",
    "C:\Program Files\BetterDeskConsole",
    "$env:LOCALAPPDATA\BetterDeskConsole"
)

# Service names
$script:HBBS_SERVICE = "BetterDeskSignal"
$script:HBBR_SERVICE = "BetterDeskRelay"
$script:CONSOLE_SERVICE = "BetterDeskConsole"

# Status variables
$script:INSTALL_STATUS = "none"
$script:HBBS_RUNNING = $false
$script:HBBR_RUNNING = $false
$script:CONSOLE_RUNNING = $false
$script:BINARIES_OK = $false
$script:DATABASE_OK = $false

# Logging
$script:LOG_FILE = "$env:TEMP\betterdesk_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

#===============================================================================
# Helper Functions
#===============================================================================

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "[$timestamp] $Message" | Out-File -FilePath $script:LOG_FILE -Append -Encoding UTF8
}

function Print-Header {
    Clear-Host
    Write-Host @"
╔══════════════════════════════════════════════════════════════════╗
║                                                                  ║
║   ██████╗ ███████╗████████╗████████╗███████╗██████╗              ║
║   ██╔══██╗██╔════╝╚══██╔══╝╚══██╔══╝██╔════╝██╔══██╗             ║
║   ██████╔╝█████╗     ██║      ██║   █████╗  ██████╔╝             ║
║   ██╔══██╗██╔══╝     ██║      ██║   ██╔══╝  ██╔══██╗             ║
║   ██████╔╝███████╗   ██║      ██║   ███████╗██║  ██║             ║
║   ╚═════╝ ╚══════╝   ╚═╝      ╚═╝   ╚══════╝╚═╝  ╚═╝             ║
║                    ██████╗ ███████╗███████╗██╗  ██╗              ║
║                    ██╔══██╗██╔════╝██╔════╝██║ ██╔╝              ║
║                    ██║  ██║█████╗  ███████╗█████╔╝               ║
║                    ██║  ██║██╔══╝  ╚════██║██╔═██╗               ║
║                    ██████╔╝███████╗███████║██║  ██╗              ║
║                    ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝              ║
║                                                                  ║
║                  Console Manager v$($script:VERSION)                          ║
╚══════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
}

function Print-Success {
    param([string]$Message)
    Write-Host "[OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message
    Write-Log "SUCCESS: $Message"
}

function Print-Error {
    param([string]$Message)
    Write-Host "[X] " -ForegroundColor Red -NoNewline
    Write-Host $Message
    Write-Log "ERROR: $Message"
}

function Print-Warning {
    param([string]$Message)
    Write-Host "[!] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
    Write-Log "WARNING: $Message"
}

function Print-Info {
    param([string]$Message)
    Write-Host "[i] " -ForegroundColor Blue -NoNewline
    Write-Host $Message
    Write-Log "INFO: $Message"
}

function Print-Step {
    param([string]$Message)
    Write-Host "[>] " -ForegroundColor Magenta -NoNewline
    Write-Host $Message
    Write-Log "STEP: $Message"
}

function Press-Enter {
    Write-Host ""
    Write-Host "Press Enter to continue..." -ForegroundColor Cyan
    if (-not $script:AUTO_MODE) {
        $null = Read-Host
    }
}

function Confirm-Action {
    param([string]$Prompt = "Continue?")
    if ($script:AUTO_MODE) { return $true }
    
    $response = Read-Host "$Prompt [y/N]"
    return $response -match "^[YyTt]"
}

function Get-PublicIP {
    try {
        $ip = (Invoke-WebRequest -Uri "https://ifconfig.me/ip" -UseBasicParsing -TimeoutSec 10).Content.Trim()
        return $ip
    } catch {
        try {
            $ip = (Invoke-WebRequest -Uri "https://icanhazip.com" -UseBasicParsing -TimeoutSec 10).Content.Trim()
            return $ip
        } catch {
            return "127.0.0.1"
        }
    }
}

function Generate-RandomPassword {
    param([int]$Length = 16)
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $password = -join ((1..$Length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return $password
}

#===============================================================================
# Detection Functions
#===============================================================================

function Detect-Installation {
    $script:INSTALL_STATUS = "none"
    $script:HBBS_RUNNING = $false
    $script:HBBR_RUNNING = $false
    $script:CONSOLE_RUNNING = $false
    $script:BINARIES_OK = $false
    $script:DATABASE_OK = $false
    
    # Check paths
    if (Test-Path $script:RUSTDESK_PATH) {
        if ((Test-Path "$script:RUSTDESK_PATH\hbbs.exe") -or (Test-Path "$script:RUSTDESK_PATH\hbbs-v8-api.exe")) {
            $script:BINARIES_OK = $true
            $script:INSTALL_STATUS = "partial"
        }
    }
    
    if (Test-Path "$script:RUSTDESK_PATH\db_v2.sqlite3") {
        $script:DATABASE_OK = $true
    }
    
    if ((Test-Path $script:CONSOLE_PATH) -and (Test-Path "$script:CONSOLE_PATH\app.py")) {
        if ($script:BINARIES_OK) {
            $script:INSTALL_STATUS = "complete"
        }
    }
    
    # Check services
    $hbbsService = Get-Service -Name $script:HBBS_SERVICE -ErrorAction SilentlyContinue
    if ($hbbsService -and $hbbsService.Status -eq 'Running') {
        $script:HBBS_RUNNING = $true
    }
    
    $hbbrService = Get-Service -Name $script:HBBR_SERVICE -ErrorAction SilentlyContinue
    if ($hbbrService -and $hbbrService.Status -eq 'Running') {
        $script:HBBR_RUNNING = $true
    }
    
    $consoleService = Get-Service -Name $script:CONSOLE_SERVICE -ErrorAction SilentlyContinue
    if ($consoleService -and $consoleService.Status -eq 'Running') {
        $script:CONSOLE_RUNNING = $true
    }
}

function Auto-DetectPaths {
    $found = $false
    
    # Check configured path first
    if ($script:RUSTDESK_PATH -and (Test-Path $script:RUSTDESK_PATH)) {
        if ((Test-Path "$script:RUSTDESK_PATH\hbbs.exe") -or (Test-Path "$script:RUSTDESK_PATH\hbbs-v8-api.exe")) {
            Print-Info "Using configured RustDesk path: $script:RUSTDESK_PATH"
            $found = $true
        }
    }
    
    # Auto-detect if not found
    if (-not $found) {
        foreach ($path in $script:COMMON_RUSTDESK_PATHS) {
            if ((Test-Path $path) -and ((Test-Path "$path\hbbs.exe") -or (Test-Path "$path\hbbs-v8-api.exe"))) {
                $script:RUSTDESK_PATH = $path
                Print-Success "Detected RustDesk installation: $script:RUSTDESK_PATH"
                $found = $true
                break
            }
        }
    }
    
    # Default path for new installations
    if (-not $found) {
        $script:RUSTDESK_PATH = "C:\BetterDesk"
        Print-Info "No installation detected. Default path: $script:RUSTDESK_PATH"
    }
    
    # Auto-detect Console path
    $consoleFound = $false
    foreach ($path in $script:COMMON_CONSOLE_PATHS) {
        if ((Test-Path $path) -and (Test-Path "$path\app.py")) {
            $script:CONSOLE_PATH = $path
            Print-Success "Detected Console installation: $script:CONSOLE_PATH"
            $consoleFound = $true
            break
        }
    }
    
    if (-not $consoleFound) {
        $script:CONSOLE_PATH = "C:\BetterDeskConsole"
    }
    
    # Update DB_PATH
    $script:DB_PATH = "$script:RUSTDESK_PATH\db_v2.sqlite3"
}

function Print-Status {
    Detect-Installation
    
    Write-Host ""
    Write-Host "=== System Status ===" -ForegroundColor White
    Write-Host ""
    Write-Host "  System:       " -NoNewline; Write-Host "Windows $([System.Environment]::OSVersion.Version)" -ForegroundColor Cyan
    Write-Host "  Architecture: " -NoNewline; Write-Host $env:PROCESSOR_ARCHITECTURE -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "=== Configured Paths ===" -ForegroundColor White
    Write-Host ""
    Write-Host "  RustDesk:     " -NoNewline; Write-Host $script:RUSTDESK_PATH -ForegroundColor Cyan
    Write-Host "  Console:      " -NoNewline; Write-Host $script:CONSOLE_PATH -ForegroundColor Cyan
    Write-Host "  Database:     " -NoNewline; Write-Host $script:DB_PATH -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "=== Installation Status ===" -ForegroundColor White
    Write-Host ""
    
    switch ($script:INSTALL_STATUS) {
        "complete" { Write-Host "  Status:       " -NoNewline; Write-Host "[OK] Installed" -ForegroundColor Green }
        "partial"  { Write-Host "  Status:       " -NoNewline; Write-Host "[!] Partial installation" -ForegroundColor Yellow }
        "none"     { Write-Host "  Status:       " -NoNewline; Write-Host "[X] Not installed" -ForegroundColor Red }
    }
    
    if ($script:BINARIES_OK) {
        Write-Host "  Binaries:     " -NoNewline; Write-Host "[OK]" -ForegroundColor Green
    } else {
        Write-Host "  Binaries:     " -NoNewline; Write-Host "[X] Not found" -ForegroundColor Red
    }
    
    if ($script:DATABASE_OK) {
        Write-Host "  Database:     " -NoNewline; Write-Host "[OK]" -ForegroundColor Green
    } else {
        Write-Host "  Database:     " -NoNewline; Write-Host "[X] Not found" -ForegroundColor Red
    }
    
    if (Test-Path $script:CONSOLE_PATH) {
        Write-Host "  Web Console:  " -NoNewline; Write-Host "[OK]" -ForegroundColor Green
    } else {
        Write-Host "  Web Console:  " -NoNewline; Write-Host "[X] Not found" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "=== Services Status ===" -ForegroundColor White
    Write-Host ""
    
    if ($script:HBBS_RUNNING) {
        Write-Host "  HBBS (Signal): " -NoNewline; Write-Host "* Active" -ForegroundColor Green
    } else {
        Write-Host "  HBBS (Signal): " -NoNewline; Write-Host "o Inactive" -ForegroundColor Red
    }
    
    if ($script:HBBR_RUNNING) {
        Write-Host "  HBBR (Relay):  " -NoNewline; Write-Host "* Active" -ForegroundColor Green
    } else {
        Write-Host "  HBBR (Relay):  " -NoNewline; Write-Host "o Inactive" -ForegroundColor Red
    }
    
    if ($script:CONSOLE_RUNNING) {
        Write-Host "  Web Console:   " -NoNewline; Write-Host "* Active" -ForegroundColor Green
    } else {
        Write-Host "  Web Console:   " -NoNewline; Write-Host "o Inactive" -ForegroundColor Red
    }
    
    Write-Host ""
}

#===============================================================================
# Binary Verification Functions
#===============================================================================

function Verify-BinaryChecksum {
    param(
        [string]$FilePath,
        [string]$ExpectedHash
    )
    
    $fileName = Split-Path -Leaf $FilePath
    
    if (-not (Test-Path $FilePath)) {
        Print-Error "File not found: $FilePath"
        return $false
    }
    
    Print-Info "Verifying $fileName..."
    $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToUpper()
    
    if ($actualHash -eq $ExpectedHash.ToUpper()) {
        Print-Success "$fileName`: SHA256 OK"
        return $true
    } else {
        Print-Error "$fileName`: SHA256 MISMATCH!"
        Print-Error "  Expected: $ExpectedHash"
        Print-Error "  Got:      $actualHash"
        return $false
    }
}

function Verify-Binaries {
    Print-Step "Verifying BetterDesk binaries..."
    
    $binSource = Join-Path $script:ScriptDir "hbbs-patch-v2"
    $errors = 0
    
    if ($script:SKIP_VERIFY) {
        Print-Warning "Verification skipped (-SkipVerify)"
        return $true
    }
    
    # Verify Windows binaries
    $hbbsPath = Join-Path $binSource "hbbs-windows-x86_64.exe"
    $hbbrPath = Join-Path $binSource "hbbr-windows-x86_64.exe"
    
    if (Test-Path $hbbsPath) {
        if (-not (Verify-BinaryChecksum -FilePath $hbbsPath -ExpectedHash $script:HBBS_WINDOWS_X86_64_SHA256)) {
            $errors++
        }
    }
    
    if (Test-Path $hbbrPath) {
        if (-not (Verify-BinaryChecksum -FilePath $hbbrPath -ExpectedHash $script:HBBR_WINDOWS_X86_64_SHA256)) {
            $errors++
        }
    }
    
    if ($errors -gt 0) {
        Print-Error "Binary verification failed! $errors error(s)"
        Print-Warning "Binaries may be corrupted or outdated."
        if (-not $script:AUTO_MODE) {
            if (-not (Confirm-Action "Continue anyway?")) {
                return $false
            }
        } else {
            return $false
        }
    } else {
        Print-Success "All binaries verified"
    }
    
    return $true
}

#===============================================================================
# Installation Functions
#===============================================================================

function Install-Dependencies {
    Print-Step "Checking dependencies..."
    
    # Check Python
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        Print-Warning "Python not found! Please install Python 3.8+ from python.org"
        Print-Info "Download: https://www.python.org/downloads/"
        if (-not $script:AUTO_MODE) {
            Press-Enter
        }
        return $false
    }
    
    $pythonVersion = python --version 2>&1
    Print-Info "Python: $pythonVersion"
    
    # Check pip
    try {
        $null = python -m pip --version 2>&1
        Print-Success "pip is available"
    } catch {
        Print-Warning "pip not found, attempting to install..."
        python -m ensurepip --upgrade
    }
    
    # Install bcrypt for password hashing
    Print-Step "Installing Python packages..."
    python -m pip install --quiet --upgrade pip
    python -m pip install --quiet bcrypt flask flask-wtf flask-limiter requests markupsafe
    
    Print-Success "Dependencies installed"
    return $true
}

function Install-Binaries {
    Print-Step "Installing BetterDesk binaries..."
    
    # Create directory
    if (-not (Test-Path $script:RUSTDESK_PATH)) {
        New-Item -ItemType Directory -Path $script:RUSTDESK_PATH -Force | Out-Null
    }
    
    # Check for pre-compiled binaries
    $binSource = $null
    
    $hbbsPatchPath = Join-Path $script:ScriptDir "hbbs-patch-v2\hbbs-windows-x86_64.exe"
    if (Test-Path $hbbsPatchPath) {
        $binSource = Join-Path $script:ScriptDir "hbbs-patch-v2"
        Print-Info "Found binaries in hbbs-patch-v2/"
    } else {
        Print-Error "BetterDesk binaries not found!"
        Print-Info "Expected: $hbbsPatchPath"
        Print-Info "Run 'Build binaries' option or download prebuilt files."
        return $false
    }
    
    # Verify binaries before installation
    if (-not (Verify-Binaries)) {
        Print-Error "Aborting installation due to verification failure"
        return $false
    }
    
    # Stop services if running
    Stop-Service -Name $script:HBBS_SERVICE -ErrorAction SilentlyContinue -Force
    Stop-Service -Name $script:HBBR_SERVICE -ErrorAction SilentlyContinue -Force
    Start-Sleep -Seconds 2
    
    # Copy binaries
    Copy-Item -Path (Join-Path $binSource "hbbs-windows-x86_64.exe") -Destination (Join-Path $script:RUSTDESK_PATH "hbbs.exe") -Force
    Print-Success "Installed hbbs.exe (signal server)"
    
    Copy-Item -Path (Join-Path $binSource "hbbr-windows-x86_64.exe") -Destination (Join-Path $script:RUSTDESK_PATH "hbbr.exe") -Force
    Print-Success "Installed hbbr.exe (relay server)"
    
    Print-Success "BetterDesk binaries v$script:VERSION installed"
    return $true
}

function Install-Console {
    Print-Step "Installing Web Console..."
    
    # Create directory
    if (-not (Test-Path $script:CONSOLE_PATH)) {
        New-Item -ItemType Directory -Path $script:CONSOLE_PATH -Force | Out-Null
    }
    
    # Copy web files
    $webSource = Join-Path $script:ScriptDir "web"
    if (Test-Path $webSource) {
        Copy-Item -Path "$webSource\*" -Destination $script:CONSOLE_PATH -Recurse -Force
    } else {
        Print-Error "web/ folder not found in project!"
        return $false
    }
    
    # Setup Python virtual environment
    Print-Step "Configuring Python environment..."
    
    Push-Location $script:CONSOLE_PATH
    try {
        python -m venv venv
        
        # Install requirements
        & "$script:CONSOLE_PATH\venv\Scripts\pip.exe" install --quiet --upgrade pip
        & "$script:CONSOLE_PATH\venv\Scripts\pip.exe" install --quiet -r requirements.txt
        
        Print-Success "Web Console installed"
    } catch {
        Print-Error "Failed to setup Python environment: $_"
        return $false
    } finally {
        Pop-Location
    }
    
    return $true
}

function Setup-Services {
    Print-Step "Configuring Windows services..."
    
    $serverIP = Get-PublicIP
    Print-Info "Server IP: $serverIP"
    Print-Info "API Port: $script:API_PORT"
    
    # Check for NSSM (Non-Sucking Service Manager)
    $nssmPath = Get-Command nssm -ErrorAction SilentlyContinue
    
    if (-not $nssmPath) {
        # Try to find NSSM in the project directory
        $nssmLocalPath = Join-Path $script:ScriptDir "tools\nssm.exe"
        if (Test-Path $nssmLocalPath) {
            $nssmPath = $nssmLocalPath
        } else {
            Print-Warning "NSSM not found. Services will be created as scheduled tasks."
            Print-Info "For proper Windows services, install NSSM from https://nssm.cc"
            
            # Create scheduled tasks as fallback
            Setup-ScheduledTasks -ServerIP $serverIP
            return
        }
    }
    
    $nssm = if ($nssmPath -is [System.Management.Automation.ApplicationInfo]) { $nssmPath.Source } else { $nssmPath }
    
    # Remove existing services
    & $nssm stop $script:HBBS_SERVICE 2>$null
    & $nssm remove $script:HBBS_SERVICE confirm 2>$null
    & $nssm stop $script:HBBR_SERVICE 2>$null
    & $nssm remove $script:HBBR_SERVICE confirm 2>$null
    & $nssm stop $script:CONSOLE_SERVICE 2>$null
    & $nssm remove $script:CONSOLE_SERVICE confirm 2>$null
    
    Start-Sleep -Seconds 2
    
    # HBBS Service (Signal Server with HTTP API)
    $hbbsExe = Join-Path $script:RUSTDESK_PATH "hbbs.exe"
    $hbbsArgs = "-r $serverIP -k _ --api-port $script:API_PORT"
    
    & $nssm install $script:HBBS_SERVICE $hbbsExe $hbbsArgs
    & $nssm set $script:HBBS_SERVICE AppDirectory $script:RUSTDESK_PATH
    & $nssm set $script:HBBS_SERVICE DisplayName "BetterDesk Signal Server v$script:VERSION"
    & $nssm set $script:HBBS_SERVICE Description "BetterDesk/RustDesk Signal Server with HTTP API"
    & $nssm set $script:HBBS_SERVICE Start SERVICE_AUTO_START
    & $nssm set $script:HBBS_SERVICE AppStdout "$script:RUSTDESK_PATH\logs\hbbs.log"
    & $nssm set $script:HBBS_SERVICE AppStderr "$script:RUSTDESK_PATH\logs\hbbs_error.log"
    
    # HBBR Service (Relay Server)
    $hbbrExe = Join-Path $script:RUSTDESK_PATH "hbbr.exe"
    $hbbrArgs = "-k _"
    
    & $nssm install $script:HBBR_SERVICE $hbbrExe $hbbrArgs
    & $nssm set $script:HBBR_SERVICE AppDirectory $script:RUSTDESK_PATH
    & $nssm set $script:HBBR_SERVICE DisplayName "BetterDesk Relay Server v$script:VERSION"
    & $nssm set $script:HBBR_SERVICE Description "BetterDesk/RustDesk Relay Server"
    & $nssm set $script:HBBR_SERVICE Start SERVICE_AUTO_START
    & $nssm set $script:HBBR_SERVICE AppStdout "$script:RUSTDESK_PATH\logs\hbbr.log"
    & $nssm set $script:HBBR_SERVICE AppStderr "$script:RUSTDESK_PATH\logs\hbbr_error.log"
    
    # Console Service (Web Interface)
    $pythonExe = Join-Path $script:CONSOLE_PATH "venv\Scripts\python.exe"
    $appPy = Join-Path $script:CONSOLE_PATH "app.py"
    
    & $nssm install $script:CONSOLE_SERVICE $pythonExe $appPy
    & $nssm set $script:CONSOLE_SERVICE AppDirectory $script:CONSOLE_PATH
    & $nssm set $script:CONSOLE_SERVICE DisplayName "BetterDesk Web Console"
    & $nssm set $script:CONSOLE_SERVICE Description "BetterDesk Web Management Console"
    & $nssm set $script:CONSOLE_SERVICE Start SERVICE_AUTO_START
    & $nssm set $script:CONSOLE_SERVICE AppEnvironmentExtra "FLASK_ENV=production" "RUSTDESK_PATH=$script:RUSTDESK_PATH" "API_PORT=$script:API_PORT"
    & $nssm set $script:CONSOLE_SERVICE AppStdout "$script:CONSOLE_PATH\logs\console.log"
    & $nssm set $script:CONSOLE_SERVICE AppStderr "$script:CONSOLE_PATH\logs\console_error.log"
    
    # Create logs directories
    New-Item -ItemType Directory -Path "$script:RUSTDESK_PATH\logs" -Force | Out-Null
    New-Item -ItemType Directory -Path "$script:CONSOLE_PATH\logs" -Force | Out-Null
    
    Print-Success "Windows services configured"
    Print-Info "Services: $script:HBBS_SERVICE, $script:HBBR_SERVICE, $script:CONSOLE_SERVICE"
}

function Setup-ScheduledTasks {
    param([string]$ServerIP)
    
    Print-Step "Creating scheduled tasks as service alternative..."
    
    # Remove existing tasks
    Unregister-ScheduledTask -TaskName $script:HBBS_SERVICE -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $script:HBBR_SERVICE -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $script:CONSOLE_SERVICE -Confirm:$false -ErrorAction SilentlyContinue
    
    # HBBS Task
    $hbbsExe = Join-Path $script:RUSTDESK_PATH "hbbs.exe"
    $hbbsAction = New-ScheduledTaskAction -Execute $hbbsExe -Argument "-r $ServerIP -k _ --api-port $script:API_PORT" -WorkingDirectory $script:RUSTDESK_PATH
    $hbbsTrigger = New-ScheduledTaskTrigger -AtStartup
    $hbbsPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $hbbsSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $script:HBBS_SERVICE -Action $hbbsAction -Trigger $hbbsTrigger -Principal $hbbsPrincipal -Settings $hbbsSettings -Description "BetterDesk Signal Server" | Out-Null
    
    # HBBR Task
    $hbbrExe = Join-Path $script:RUSTDESK_PATH "hbbr.exe"
    $hbbrAction = New-ScheduledTaskAction -Execute $hbbrExe -Argument "-k _" -WorkingDirectory $script:RUSTDESK_PATH
    $hbbrTrigger = New-ScheduledTaskTrigger -AtStartup
    $hbbrPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $hbbrSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $script:HBBR_SERVICE -Action $hbbrAction -Trigger $hbbrTrigger -Principal $hbbrPrincipal -Settings $hbbrSettings -Description "BetterDesk Relay Server" | Out-Null
    
    # Console Task
    $pythonExe = Join-Path $script:CONSOLE_PATH "venv\Scripts\python.exe"
    $appPy = Join-Path $script:CONSOLE_PATH "app.py"
    $consoleAction = New-ScheduledTaskAction -Execute $pythonExe -Argument $appPy -WorkingDirectory $script:CONSOLE_PATH
    $consoleTrigger = New-ScheduledTaskTrigger -AtStartup
    $consolePrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $consoleSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $script:CONSOLE_SERVICE -Action $consoleAction -Trigger $consoleTrigger -Principal $consolePrincipal -Settings $consoleSettings -Description "BetterDesk Web Console" | Out-Null
    
    Print-Success "Scheduled tasks created"
}

function Run-Migrations {
    Print-Step "Running database migrations..."
    
    # Ensure database directory exists
    $dbDir = Split-Path -Parent $script:DB_PATH
    if (-not (Test-Path $dbDir)) {
        New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
    }
    
    # Create database schema and add missing columns
    $pythonScript = @"
import sqlite3
import os
from datetime import datetime

db_path = r'$($script:DB_PATH)'

# Ensure db directory exists
os.makedirs(os.path.dirname(db_path), exist_ok=True)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Create peer table if not exists
cursor.execute('''
    CREATE TABLE IF NOT EXISTS peer (
        guid BLOB PRIMARY KEY NOT NULL,
        id VARCHAR(100) NOT NULL,
        uuid BLOB NOT NULL,
        pk BLOB NOT NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        user BLOB,
        status INTEGER DEFAULT 0,
        note VARCHAR(300),
        info TEXT NOT NULL,
        last_online TEXT,
        is_deleted INTEGER DEFAULT 0,
        deleted_at TEXT,
        updated_at TEXT,
        previous_ids TEXT,
        id_changed_at TEXT,
        is_banned INTEGER DEFAULT 0
    )
''')

# Create indexes
cursor.execute('CREATE UNIQUE INDEX IF NOT EXISTS index_peer_id ON peer (id)')
cursor.execute('CREATE INDEX IF NOT EXISTS index_peer_user ON peer (user)')
cursor.execute('CREATE INDEX IF NOT EXISTS index_peer_created_at ON peer (created_at)')
cursor.execute('CREATE INDEX IF NOT EXISTS index_peer_status ON peer (status)')

# Create users table
cursor.execute('''
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username VARCHAR(50) UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        role VARCHAR(20) NOT NULL DEFAULT 'viewer',
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_login DATETIME,
        is_active INTEGER NOT NULL DEFAULT 1,
        CHECK (role IN ('admin', 'operator', 'viewer'))
    )
''')

# Create sessions table
cursor.execute('''
    CREATE TABLE IF NOT EXISTS sessions (
        token VARCHAR(64) PRIMARY KEY,
        user_id INTEGER NOT NULL,
        created_at DATETIME NOT NULL,
        expires_at DATETIME NOT NULL,
        last_activity DATETIME NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    )
''')

# Create audit_log table
cursor.execute('''
    CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        action VARCHAR(50) NOT NULL,
        device_id VARCHAR(100),
        details TEXT,
        ip_address VARCHAR(50),
        timestamp DATETIME NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
    )
''')

# Create indexes for auth tables
cursor.execute('CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id)')
cursor.execute('CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at)')
cursor.execute('CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id)')
cursor.execute('CREATE INDEX IF NOT EXISTS idx_audit_device ON audit_log(device_id)')
cursor.execute('CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp)')

# Add missing columns to peer table
columns_to_add = [
    ('status', 'INTEGER DEFAULT 0'),
    ('last_online', 'TEXT'),
    ('is_deleted', 'INTEGER DEFAULT 0'),
    ('deleted_at', 'TEXT'),
    ('updated_at', 'TEXT'),
    ('note', 'TEXT'),
    ('previous_ids', 'TEXT'),
    ('id_changed_at', 'TEXT'),
    ('is_banned', 'INTEGER DEFAULT 0'),
]

cursor.execute("PRAGMA table_info(peer)")
existing_columns = [col[1] for col in cursor.fetchall()]

for col_name, col_def in columns_to_add:
    if col_name not in existing_columns:
        try:
            cursor.execute(f"ALTER TABLE peer ADD COLUMN {col_name} {col_def}")
            print(f"  Added column: {col_name}")
        except Exception as e:
            pass

conn.commit()
conn.close()
print("Database migrations completed")
"@
    
    $pythonScript | python
    
    Print-Success "Migrations completed"
}

function Create-AdminUser {
    Print-Step "Creating admin user..."
    
    $adminPassword = Generate-RandomPassword
    
    $pythonScript = @"
import sqlite3
import bcrypt
from datetime import datetime

db_path = r'$($script:DB_PATH)'
admin_password = '$adminPassword'

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

# Check if admin exists
cursor.execute("SELECT id FROM users WHERE username='admin'")
if cursor.fetchone():
    print("Admin already exists")
else:
    password_hash = bcrypt.hashpw(admin_password.encode(), bcrypt.gensalt()).decode()
    cursor.execute('''INSERT INTO users (username, password_hash, role, is_active, created_at)
                      VALUES ('admin', ?, 'admin', 1, ?)''', (password_hash, datetime.now().isoformat()))
    conn.commit()
    print("Admin created")

conn.close()
"@
    
    $pythonScript | python
    
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "             PANEL LOGIN CREDENTIALS                        " -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  Login:    " -NoNewline; Write-Host "admin" -ForegroundColor White
    Write-Host "  Password: " -NoNewline; Write-Host $adminPassword -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    
    # Save credentials
    $credentialsFile = Join-Path $script:RUSTDESK_PATH ".admin_credentials"
    "admin:$adminPassword" | Out-File -FilePath $credentialsFile -Encoding UTF8
    
    Print-Info "Credentials saved in: $credentialsFile"
    
    return $adminPassword
}

function Start-Services {
    Print-Step "Starting services..."
    
    # Try to start as Windows services first
    $serviceExists = Get-Service -Name $script:HBBS_SERVICE -ErrorAction SilentlyContinue
    
    if ($serviceExists) {
        Start-Service -Name $script:HBBS_SERVICE -ErrorAction SilentlyContinue
        Start-Service -Name $script:HBBR_SERVICE -ErrorAction SilentlyContinue
        Start-Service -Name $script:CONSOLE_SERVICE -ErrorAction SilentlyContinue
    } else {
        # Start scheduled tasks
        Start-ScheduledTask -TaskName $script:HBBS_SERVICE -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskName $script:HBBR_SERVICE -ErrorAction SilentlyContinue
        Start-ScheduledTask -TaskName $script:CONSOLE_SERVICE -ErrorAction SilentlyContinue
    }
    
    Start-Sleep -Seconds 3
    
    Detect-Installation
    
    if ($script:HBBS_RUNNING -and $script:HBBR_RUNNING) {
        Print-Success "All services started"
    } else {
        Print-Warning "Some services may not be working properly"
        Print-Info "Check logs in: $script:RUSTDESK_PATH\logs\"
    }
}

function Stop-AllServices {
    Print-Step "Stopping services..."
    
    # Stop Windows services
    Stop-Service -Name $script:HBBS_SERVICE -ErrorAction SilentlyContinue -Force
    Stop-Service -Name $script:HBBR_SERVICE -ErrorAction SilentlyContinue -Force
    Stop-Service -Name $script:CONSOLE_SERVICE -ErrorAction SilentlyContinue -Force
    
    # Stop scheduled tasks
    Stop-ScheduledTask -TaskName $script:HBBS_SERVICE -ErrorAction SilentlyContinue
    Stop-ScheduledTask -TaskName $script:HBBR_SERVICE -ErrorAction SilentlyContinue
    Stop-ScheduledTask -TaskName $script:CONSOLE_SERVICE -ErrorAction SilentlyContinue
    
    # Kill processes directly
    Get-Process -Name "hbbs" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Process -Name "hbbr" -ErrorAction SilentlyContinue | Stop-Process -Force
    
    Start-Sleep -Seconds 2
}

#===============================================================================
# Main Installation Function
#===============================================================================

function Do-Install {
    Print-Header
    Write-Host "========== FRESH INSTALLATION ==========" -ForegroundColor White
    Write-Host ""
    
    Detect-Installation
    
    if ($script:INSTALL_STATUS -eq "complete") {
        Print-Warning "BetterDesk is already installed!"
        if (-not $script:AUTO_MODE) {
            if (-not (Confirm-Action "Do you want to reinstall?")) {
                return
            }
        }
        Do-BackupSilent
    }
    
    Write-Host ""
    Print-Info "Starting BetterDesk Console v$script:VERSION installation..."
    Write-Host ""
    
    if (-not (Install-Dependencies)) { return }
    if (-not (Install-Binaries)) { Print-Error "Binary installation failed"; return }
    if (-not (Install-Console)) { Print-Error "Console installation failed"; return }
    Setup-Services
    Run-Migrations
    $adminPassword = Create-AdminUser
    Start-Services
    
    Write-Host ""
    Print-Success "Installation completed successfully!"
    Write-Host ""
    
    $serverIP = Get-PublicIP
    $publicKey = ""
    $pubKeyPath = Join-Path $script:RUSTDESK_PATH "id_ed25519.pub"
    if (Test-Path $pubKeyPath) {
        $publicKey = (Get-Content $pubKeyPath -Raw).Trim()
    }
    
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "              INSTALLATION INFO                             " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Panel Web:     " -NoNewline; Write-Host "http://${serverIP}:5000" -ForegroundColor White
    Write-Host "  API Port:      " -NoNewline; Write-Host $script:API_PORT -ForegroundColor White
    Write-Host "  Server ID:     " -NoNewline; Write-Host $serverIP -ForegroundColor White
    if ($publicKey) {
        Write-Host "  Key:           " -NoNewline; Write-Host "$($publicKey.Substring(0, [Math]::Min(20, $publicKey.Length)))..." -ForegroundColor White
    }
    Write-Host "============================================================" -ForegroundColor Cyan
    
    if (-not $script:AUTO_MODE) {
        Press-Enter
    }
}

#===============================================================================
# Update Functions
#===============================================================================

function Do-Update {
    Print-Header
    Write-Host "========== UPDATE ==========" -ForegroundColor White
    Write-Host ""
    
    Detect-Installation
    
    if ($script:INSTALL_STATUS -eq "none") {
        Print-Error "BetterDesk is not installed!"
        Print-Info "Use 'FRESH INSTALLATION' option"
        Press-Enter
        return
    }
    
    Print-Info "Creating backup before update..."
    Do-BackupSilent
    
    Stop-AllServices
    
    if (-not (Install-Binaries)) { Print-Error "Binary update failed"; return }
    if (-not (Install-Console)) { Print-Error "Console update failed"; return }
    Run-Migrations
    
    Start-Services
    
    Print-Success "Update completed!"
    Press-Enter
}

#===============================================================================
# Repair Functions
#===============================================================================

function Do-Repair {
    Print-Header
    Write-Host "========== REPAIR INSTALLATION ==========" -ForegroundColor White
    Write-Host ""
    
    Detect-Installation
    Print-Status
    
    Write-Host ""
    Write-Host "What do you want to repair?" -ForegroundColor White
    Write-Host ""
    Write-Host "  1. Repair binaries (replace with BetterDesk)"
    Write-Host "  2. Repair database (add missing columns)"
    Write-Host "  3. Repair Windows services"
    Write-Host "  4. Full repair (all of the above)"
    Write-Host "  0. Back"
    Write-Host ""
    
    $choice = Read-Host "Select option"
    
    switch ($choice) {
        "1" { Repair-Binaries }
        "2" { Repair-Database }
        "3" { Repair-Services }
        "4" { 
            Repair-Binaries
            Repair-Database
            Repair-Services
            Print-Success "Full repair completed!"
        }
        "0" { return }
    }
    
    Press-Enter
}

function Repair-Binaries {
    Print-Step "Repairing binaries..."
    
    Stop-AllServices
    Install-Binaries | Out-Null
    Start-Services
    
    Print-Success "Binaries repaired"
}

function Repair-Database {
    Print-Step "Repairing database..."
    
    Run-Migrations
    
    Print-Success "Database repaired"
}

function Repair-Services {
    Print-Step "Repairing Windows services..."
    
    Setup-Services
    Start-Services
    
    Print-Success "Services repaired"
}

#===============================================================================
# Validation Functions
#===============================================================================

function Do-Validate {
    Print-Header
    Write-Host "========== INSTALLATION VALIDATION ==========" -ForegroundColor White
    Write-Host ""
    
    $errors = 0
    $warnings = 0
    
    Detect-Installation
    
    Write-Host "Checking components..." -ForegroundColor White
    Write-Host ""
    
    # Check directories
    Write-Host "  RustDesk directory ($script:RUSTDESK_PATH): " -NoNewline
    if (Test-Path $script:RUSTDESK_PATH) {
        Write-Host "[OK]" -ForegroundColor Green
    } else {
        Write-Host "[X] Not found" -ForegroundColor Red
        $errors++
    }
    
    Write-Host "  Console directory ($script:CONSOLE_PATH): " -NoNewline
    if (Test-Path $script:CONSOLE_PATH) {
        Write-Host "[OK]" -ForegroundColor Green
    } else {
        Write-Host "[X] Not found" -ForegroundColor Red
        $errors++
    }
    
    # Check binaries
    Write-Host "  HBBS binary: " -NoNewline
    if (Test-Path (Join-Path $script:RUSTDESK_PATH "hbbs.exe")) {
        Write-Host "[OK]" -ForegroundColor Green
    } else {
        Write-Host "[X] Not found" -ForegroundColor Red
        $errors++
    }
    
    Write-Host "  HBBR binary: " -NoNewline
    if (Test-Path (Join-Path $script:RUSTDESK_PATH "hbbr.exe")) {
        Write-Host "[OK]" -ForegroundColor Green
    } else {
        Write-Host "[X] Not found" -ForegroundColor Red
        $errors++
    }
    
    # Check database
    Write-Host "  Database: " -NoNewline
    if (Test-Path $script:DB_PATH) {
        Write-Host "[OK]" -ForegroundColor Green
    } else {
        Write-Host "[X] Not found" -ForegroundColor Red
        $errors++
    }
    
    # Check keys
    Write-Host "  Public key: " -NoNewline
    $pubKeyPath = Join-Path $script:RUSTDESK_PATH "id_ed25519.pub"
    if (Test-Path $pubKeyPath) {
        Write-Host "[OK]" -ForegroundColor Green
    } else {
        Write-Host "[!] Will be generated on first start" -ForegroundColor Yellow
        $warnings++
    }
    
    # Check services
    Write-Host ""
    Write-Host "Checking services..." -ForegroundColor White
    Write-Host ""
    
    $services = @($script:HBBS_SERVICE, $script:HBBR_SERVICE, $script:CONSOLE_SERVICE)
    foreach ($service in $services) {
        Write-Host "  ${service}: " -NoNewline
        $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.Status -eq 'Running') {
                Write-Host "[OK] Running" -ForegroundColor Green
            } else {
                Write-Host "[!] Not running ($($svc.Status))" -ForegroundColor Yellow
                $warnings++
            }
        } else {
            $task = Get-ScheduledTask -TaskName $service -ErrorAction SilentlyContinue
            if ($task) {
                if ($task.State -eq 'Running') {
                    Write-Host "[OK] Running (task)" -ForegroundColor Green
                } else {
                    Write-Host "[!] Task exists but not running" -ForegroundColor Yellow
                    $warnings++
                }
            } else {
                Write-Host "[X] Not found" -ForegroundColor Red
                $errors++
            }
        }
    }
    
    # Check ports
    Write-Host ""
    Write-Host "Checking ports..." -ForegroundColor White
    Write-Host ""
    
    $ports = @(21114, 21115, 21116, 21117, 5000)
    foreach ($port in $ports) {
        Write-Host "  Port ${port}: " -NoNewline
        $connection = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($connection) {
            Write-Host "[OK] Listening" -ForegroundColor Green
        } else {
            Write-Host "[!] Not listening" -ForegroundColor Yellow
            $warnings++
        }
    }
    
    # Summary
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor White
    
    if ($errors -eq 0 -and $warnings -eq 0) {
        Write-Host "[OK] Installation correct - no problems found" -ForegroundColor Green
    } elseif ($errors -eq 0) {
        Write-Host "[!] Found $warnings warning(s)" -ForegroundColor Yellow
    } else {
        Write-Host "[X] Found $errors error(s) and $warnings warning(s)" -ForegroundColor Red
        Write-Host "Use 'REPAIR INSTALLATION' option to fix problems" -ForegroundColor Cyan
    }
    
    Press-Enter
}

#===============================================================================
# Backup Functions
#===============================================================================

function Do-Backup {
    Print-Header
    Write-Host "========== BACKUP ==========" -ForegroundColor White
    Write-Host ""
    
    Do-BackupSilent
    
    Print-Success "Backup completed!"
    Press-Enter
}

function Do-BackupSilent {
    $backupName = "betterdesk_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $backupPath = Join-Path $script:BACKUP_DIR $backupName
    
    if (-not (Test-Path $script:BACKUP_DIR)) {
        New-Item -ItemType Directory -Path $script:BACKUP_DIR -Force | Out-Null
    }
    
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    
    Print-Step "Creating backup: $backupName"
    
    # Backup database
    if (Test-Path $script:DB_PATH) {
        Copy-Item -Path $script:DB_PATH -Destination $backupPath
        Print-Info "  - Database"
    }
    
    # Backup keys
    $keyPath = Join-Path $script:RUSTDESK_PATH "id_ed25519"
    if (Test-Path $keyPath) {
        Copy-Item -Path $keyPath -Destination $backupPath
        Copy-Item -Path "$keyPath.pub" -Destination $backupPath -ErrorAction SilentlyContinue
        Print-Info "  - Keys"
    }
    
    # Backup API key
    $apiKeyPath = Join-Path $script:RUSTDESK_PATH ".api_key"
    if (Test-Path $apiKeyPath) {
        Copy-Item -Path $apiKeyPath -Destination $backupPath
        Print-Info "  - API key"
    }
    
    # Backup credentials
    $credPath = Join-Path $script:RUSTDESK_PATH ".admin_credentials"
    if (Test-Path $credPath) {
        Copy-Item -Path $credPath -Destination $backupPath
        Print-Info "  - Login credentials"
    }
    
    # Create zip archive
    $zipPath = "$backupPath.zip"
    Compress-Archive -Path $backupPath -DestinationPath $zipPath -Force
    Remove-Item -Path $backupPath -Recurse -Force
    
    Print-Success "Backup saved: $zipPath"
}

#===============================================================================
# Password Reset Function
#===============================================================================

function Do-ResetPassword {
    Print-Header
    Write-Host "========== ADMIN PASSWORD RESET ==========" -ForegroundColor White
    Write-Host ""
    
    if (-not (Test-Path $script:DB_PATH)) {
        Print-Error "Database not found: $script:DB_PATH"
        Print-Info "Run installation first"
        Press-Enter
        return
    }
    
    Write-Host "Select option:"
    Write-Host ""
    Write-Host "  1. Generate new random password"
    Write-Host "  2. Set custom password"
    Write-Host "  0. Back"
    Write-Host ""
    
    $choice = Read-Host "Choice"
    
    $newPassword = $null
    
    switch ($choice) {
        "1" { $newPassword = Generate-RandomPassword }
        "2" { 
            $newPassword = Read-Host "Enter new password (min 8 chars)"
            if ($newPassword.Length -lt 8) {
                Print-Error "Password too short!"
                Press-Enter
                return
            }
        }
        "0" { return }
        default { return }
    }
    
    if (-not $newPassword) { return }
    
    $pythonScript = @"
import sqlite3
import bcrypt

db_path = r'$($script:DB_PATH)'
new_password = '$newPassword'

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

password_hash = bcrypt.hashpw(new_password.encode(), bcrypt.gensalt()).decode()
cursor.execute("UPDATE users SET password_hash = ? WHERE username = 'admin'", (password_hash,))

if cursor.rowcount == 0:
    cursor.execute('''INSERT INTO users (username, password_hash, role, is_active)
                      VALUES ('admin', ?, 'admin', 1)''', (password_hash,))

conn.commit()
conn.close()
print("Password updated")
"@
    
    $pythonScript | python
    
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "              NEW LOGIN CREDENTIALS                         " -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  Login:    " -NoNewline; Write-Host "admin" -ForegroundColor White
    Write-Host "  Password: " -NoNewline; Write-Host $newPassword -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Green
    
    # Save credentials
    $credentialsFile = Join-Path $script:RUSTDESK_PATH ".admin_credentials"
    "admin:$newPassword" | Out-File -FilePath $credentialsFile -Encoding UTF8
    
    Press-Enter
}

#===============================================================================
# Diagnostics Function
#===============================================================================

function Do-Diagnostics {
    Print-Header
    Write-Host "========== DIAGNOSTICS ==========" -ForegroundColor White
    Write-Host ""
    
    Detect-Installation
    Print-Status
    
    Write-Host ""
    Write-Host "=== Process Information ===" -ForegroundColor White
    Write-Host ""
    
    $hbbsProc = Get-Process -Name "hbbs" -ErrorAction SilentlyContinue
    if ($hbbsProc) {
        Write-Host "  HBBS: PID $($hbbsProc.Id), Memory $('{0:N0}' -f ($hbbsProc.WorkingSet64/1MB)) MB" -ForegroundColor Green
    } else {
        Write-Host "  HBBS: Not running" -ForegroundColor Red
    }
    
    $hbbrProc = Get-Process -Name "hbbr" -ErrorAction SilentlyContinue
    if ($hbbrProc) {
        Write-Host "  HBBR: PID $($hbbrProc.Id), Memory $('{0:N0}' -f ($hbbrProc.WorkingSet64/1MB)) MB" -ForegroundColor Green
    } else {
        Write-Host "  HBBR: Not running" -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "=== Database Statistics ===" -ForegroundColor White
    Write-Host ""
    
    if (Test-Path $script:DB_PATH) {
        $fileInfo = Get-Item $script:DB_PATH
        Write-Host "  Size: $('{0:N2}' -f ($fileInfo.Length/1KB)) KB"
        Write-Host "  Modified: $($fileInfo.LastWriteTime)"
        
        # Get database counts
        $pythonScript = @"
import sqlite3
db_path = r'$($script:DB_PATH)'
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

try:
    cursor.execute("SELECT COUNT(*) FROM peer WHERE is_deleted = 0")
    devices = cursor.fetchone()[0]
    print(f"  Devices: {devices}")
except:
    print("  Devices: Unable to query")

try:
    cursor.execute("SELECT COUNT(*) FROM peer WHERE status = 1 AND is_deleted = 0")
    online = cursor.fetchone()[0]
    print(f"  Online:  {online}")
except:
    pass

try:
    cursor.execute("SELECT COUNT(*) FROM users")
    users = cursor.fetchone()[0]
    print(f"  Users:   {users}")
except:
    pass

conn.close()
"@
        $pythonScript | python
    } else {
        Write-Host "  Database does not exist"
    }
    
    Write-Host ""
    Write-Host "=== Network Connections ===" -ForegroundColor White
    Write-Host ""
    
    $portsToCheck = @(21114, 21115, 21116, 21117, 5000)
    foreach ($port in $portsToCheck) {
        $conn = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($conn) {
            Write-Host "  Port ${port}: Listening (PID: $($conn[0].OwningProcess))" -ForegroundColor Green
        }
    }
    
    Write-Host ""
    Write-Host "Diagnostics log saved: $script:LOG_FILE" -ForegroundColor Cyan
    
    Press-Enter
}

#===============================================================================
# Uninstall Function
#===============================================================================

function Do-Uninstall {
    Print-Header
    Write-Host "========== UNINSTALL ==========" -ForegroundColor Red
    Write-Host ""
    
    Print-Warning "This operation will remove BetterDesk Console!"
    Write-Host ""
    
    if (-not (Confirm-Action "Are you sure you want to continue?")) {
        return
    }
    
    if (Confirm-Action "Create backup before uninstall?") {
        Do-BackupSilent
    }
    
    Print-Step "Stopping services..."
    Stop-AllServices
    
    Print-Step "Removing services..."
    
    # Remove Windows services (NSSM)
    $nssmPath = Get-Command nssm -ErrorAction SilentlyContinue
    if ($nssmPath) {
        $nssm = if ($nssmPath -is [System.Management.Automation.ApplicationInfo]) { $nssmPath.Source } else { $nssmPath }
        & $nssm remove $script:HBBS_SERVICE confirm 2>$null
        & $nssm remove $script:HBBR_SERVICE confirm 2>$null
        & $nssm remove $script:CONSOLE_SERVICE confirm 2>$null
    }
    
    # Remove scheduled tasks
    Unregister-ScheduledTask -TaskName $script:HBBS_SERVICE -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $script:HBBR_SERVICE -Confirm:$false -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $script:CONSOLE_SERVICE -Confirm:$false -ErrorAction SilentlyContinue
    
    if (Confirm-Action "Remove installation files ($script:RUSTDESK_PATH)?") {
        Remove-Item -Path $script:RUSTDESK_PATH -Recurse -Force -ErrorAction SilentlyContinue
        Print-Info "Removed: $script:RUSTDESK_PATH"
    }
    
    if (Confirm-Action "Remove Web Console ($script:CONSOLE_PATH)?") {
        Remove-Item -Path $script:CONSOLE_PATH -Recurse -Force -ErrorAction SilentlyContinue
        Print-Info "Removed: $script:CONSOLE_PATH"
    }
    
    Print-Success "BetterDesk has been uninstalled"
    Press-Enter
}

#===============================================================================
# Path Configuration
#===============================================================================

function Configure-Paths {
    Print-Header
    Write-Host ""
    Write-Host "=== Path Configuration ===" -ForegroundColor White
    Write-Host ""
    Write-Host "  Current RustDesk path: " -NoNewline; Write-Host $script:RUSTDESK_PATH -ForegroundColor Cyan
    Write-Host "  Current Console path:  " -NoNewline; Write-Host $script:CONSOLE_PATH -ForegroundColor Cyan
    Write-Host "  Database path:         " -NoNewline; Write-Host $script:DB_PATH -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  1. Auto-detect installation paths"
    Write-Host "  2. Set RustDesk server path manually"
    Write-Host "  3. Set Console path manually"
    Write-Host "  4. Reset to defaults"
    Write-Host "  0. Back to main menu"
    Write-Host ""
    
    $choice = Read-Host "Select option [0-4]"
    
    switch ($choice) {
        "1" {
            $script:RUSTDESK_PATH = ""
            $script:CONSOLE_PATH = ""
            Auto-DetectPaths
            Press-Enter
            Configure-Paths
        }
        "2" {
            Write-Host ""
            $newPath = Read-Host "Enter RustDesk server path (e.g., C:\BetterDesk)"
            if ($newPath) {
                if (Test-Path $newPath) {
                    $script:RUSTDESK_PATH = $newPath
                    $script:DB_PATH = "$script:RUSTDESK_PATH\db_v2.sqlite3"
                    Print-Success "RustDesk path set to: $script:RUSTDESK_PATH"
                } else {
                    Print-Warning "Directory does not exist: $newPath"
                    if (Confirm-Action "Create this directory?") {
                        New-Item -ItemType Directory -Path $newPath -Force | Out-Null
                        $script:RUSTDESK_PATH = $newPath
                        $script:DB_PATH = "$script:RUSTDESK_PATH\db_v2.sqlite3"
                        Print-Success "Created and set RustDesk path: $script:RUSTDESK_PATH"
                    }
                }
            }
            Press-Enter
            Configure-Paths
        }
        "3" {
            Write-Host ""
            $newPath = Read-Host "Enter Console path (e.g., C:\BetterDeskConsole)"
            if ($newPath) {
                if (Test-Path $newPath) {
                    $script:CONSOLE_PATH = $newPath
                    Print-Success "Console path set to: $script:CONSOLE_PATH"
                } else {
                    Print-Warning "Directory does not exist: $newPath"
                    if (Confirm-Action "Create this directory?") {
                        New-Item -ItemType Directory -Path $newPath -Force | Out-Null
                        $script:CONSOLE_PATH = $newPath
                        Print-Success "Created and set Console path: $script:CONSOLE_PATH"
                    }
                }
            }
            Press-Enter
            Configure-Paths
        }
        "4" {
            $script:RUSTDESK_PATH = "C:\BetterDesk"
            $script:CONSOLE_PATH = "C:\BetterDeskConsole"
            $script:DB_PATH = "$script:RUSTDESK_PATH\db_v2.sqlite3"
            Print-Success "Paths reset to defaults"
            Press-Enter
            Configure-Paths
        }
        "0" { return }
        default {
            Print-Error "Invalid option"
            Start-Sleep -Seconds 1
            Configure-Paths
        }
    }
}

#===============================================================================
# Build Functions
#===============================================================================

function Do-Build {
    Print-Header
    Write-Host "========== BUILD BINARIES ==========" -ForegroundColor White
    Write-Host ""
    
    # Check Rust
    $cargoCmd = Get-Command cargo -ErrorAction SilentlyContinue
    if (-not $cargoCmd) {
        Print-Error "Rust is not installed!"
        Print-Info "Install from: https://rustup.rs"
        if (Confirm-Action "Open Rust installation page?") {
            Start-Process "https://rustup.rs"
        }
        Press-Enter
        return
    }
    
    $rustVersion = rustc --version
    Print-Info "Rust: $rustVersion"
    Write-Host ""
    
    $buildDir = Join-Path $env:TEMP "betterdesk_build_$((Get-Date).Ticks)"
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
    
    Push-Location $buildDir
    
    try {
        Print-Step "Downloading RustDesk Server sources..."
        git clone --depth 1 --branch 1.1.14 https://github.com/rustdesk/rustdesk-server.git
        Set-Location "rustdesk-server"
        git submodule update --init --recursive
        
        Print-Step "Applying BetterDesk modifications..."
        
        $srcDir = Join-Path $script:ScriptDir "hbbs-patch-v2\src"
        if (Test-Path $srcDir) {
            Copy-Item -Path "$srcDir\main.rs" -Destination "src\main.rs" -Force
            Copy-Item -Path "$srcDir\http_api.rs" -Destination "src\http_api.rs" -Force
            Copy-Item -Path "$srcDir\database.rs" -Destination "src\database.rs" -Force
            Copy-Item -Path "$srcDir\peer.rs" -Destination "src\peer.rs" -Force -ErrorAction SilentlyContinue
            Copy-Item -Path "$srcDir\rendezvous_server.rs" -Destination "src\rendezvous_server.rs" -Force -ErrorAction SilentlyContinue
        } else {
            Print-Error "Source modifications not found: $srcDir"
            return
        }
        
        Print-Step "Compiling (may take several minutes)..."
        cargo build --release
        
        Print-Step "Copying binaries..."
        
        $outputDir = Join-Path $script:ScriptDir "hbbs-patch-v2"
        Copy-Item -Path "target\release\hbbs.exe" -Destination "$outputDir\hbbs-windows-x86_64.exe" -Force
        Copy-Item -Path "target\release\hbbr.exe" -Destination "$outputDir\hbbr-windows-x86_64.exe" -Force
        
        Print-Success "Compilation completed!"
        Print-Info "Binaries saved in: $outputDir"
        
    } finally {
        Pop-Location
        Remove-Item -Path $buildDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host ""
    if (Confirm-Action "Install newly compiled binaries?") {
        Do-Update
    }
    
    Press-Enter
}

#===============================================================================
# Main Menu
#===============================================================================

function Show-Menu {
    Print-Header
    Print-Status
    
    Write-Host "========== MAIN MENU ==========" -ForegroundColor White
    Write-Host ""
    Write-Host "  1. FRESH INSTALLATION"
    Write-Host "  2. UPDATE"
    Write-Host "  3. REPAIR INSTALLATION"
    Write-Host "  4. INSTALLATION VALIDATION"
    Write-Host "  5. Backup"
    Write-Host "  6. Reset admin password"
    Write-Host "  7. Build binaries"
    Write-Host "  8. DIAGNOSTICS"
    Write-Host "  9. UNINSTALL"
    Write-Host ""
    Write-Host "  S. Settings (paths)"
    Write-Host "  0. Exit"
    Write-Host ""
}

function Main {
    # Auto-detect paths on startup
    Write-Host "Detecting installation..." -ForegroundColor Cyan
    Auto-DetectPaths
    Write-Host ""
    Start-Sleep -Seconds 1
    
    # Auto mode - run installation directly
    if ($script:AUTO_MODE) {
        Print-Info "Running in AUTO mode..."
        Do-Install
        exit 0
    }
    
    while ($true) {
        Show-Menu
        $choice = Read-Host "Select option"
        
        switch ($choice) {
            "1" { Do-Install }
            "2" { Do-Update }
            "3" { Do-Repair }
            "4" { Do-Validate }
            "5" { Do-Backup }
            "6" { Do-ResetPassword }
            "7" { Do-Build }
            "8" { Do-Diagnostics }
            "9" { Do-Uninstall }
            "S" { Configure-Paths }
            "s" { Configure-Paths }
            "0" {
                Write-Host ""
                Print-Info "Goodbye!"
                exit 0
            }
            default {
                Print-Warning "Invalid option"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Run
Main
