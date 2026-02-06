# =============================================================================
# BetterDesk Server - Interactive Build Script (Windows)
# =============================================================================
# This script automates building BetterDesk enhanced binaries from source.
# It handles downloading RustDesk sources, applying BetterDesk modifications,
# and compiling the final binaries.
#
# Usage:
#   .\build-betterdesk.ps1              # Interactive mode
#   .\build-betterdesk.ps1 -Auto        # Non-interactive (use defaults)
#   .\build-betterdesk.ps1 -Clean       # Clean build directory
#   .\build-betterdesk.ps1 -Help        # Show help
#
# Requirements:
#   - Rust toolchain (rustup)
#   - Visual Studio Build Tools with C++ support
#   - Git
# =============================================================================

param(
    [switch]$Auto,
    [switch]$Clean,
    [string]$Version = "",
    [string]$Platform = "",
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# Configuration
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildDir = Join-Path $ScriptDir "build"
$PatchesDir = Join-Path $ScriptDir "hbbs-patch-v2\src"
$OutputDir = Join-Path $ScriptDir "hbbs-patch-v2"

# Default RustDesk version
$DefaultRustDeskVersion = "1.1.14"
$RustDeskRepo = "https://github.com/rustdesk/rustdesk-server.git"

# State
$RustDeskVersion = $DefaultRustDeskVersion
$TargetPlatform = "windows-x64"

# =============================================================================
# Helper Functions
# =============================================================================

function Write-Header {
    param([string]$Message)
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║ $Message" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Success { param([string]$Msg) Write-Host "✓ $Msg" -ForegroundColor Green }
function Write-Error2 { param([string]$Msg) Write-Host "✗ $Msg" -ForegroundColor Red }
function Write-Warning2 { param([string]$Msg) Write-Host "⚠ $Msg" -ForegroundColor Yellow }
function Write-Info { param([string]$Msg) Write-Host "ℹ $Msg" -ForegroundColor Blue }
function Write-Step { param([string]$Msg) Write-Host "→ $Msg" -ForegroundColor Cyan }

function Show-Help {
    Write-Host "BetterDesk Server - Build Script (Windows)"
    Write-Host ""
    Write-Host "Usage: .\build-betterdesk.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Auto          Non-interactive mode (use default settings)"
    Write-Host "  -Clean         Clean build directory and exit"
    Write-Host "  -Version VER   Specify RustDesk version (default: $DefaultRustDeskVersion)"
    Write-Host "  -Platform PLT  Target platform: windows-x64, linux-x64"
    Write-Host "  -Help          Show this help message"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\build-betterdesk.ps1                    # Interactive build"
    Write-Host "  .\build-betterdesk.ps1 -Auto              # Build with defaults"
    Write-Host "  .\build-betterdesk.ps1 -Version 1.1.15    # Build specific version"
    Write-Host ""
}

# =============================================================================
# Dependency Checks
# =============================================================================

function Test-Dependencies {
    Write-Header "Checking Dependencies"
    
    $missing = 0
    
    # Check Rust
    $cargo = Get-Command cargo -ErrorAction SilentlyContinue
    if ($cargo) {
        $rustVersion = & rustc --version 2>&1
        Write-Success "Rust/Cargo: $rustVersion"
    } else {
        Write-Error2 "Rust/Cargo not found"
        Write-Host "  Install from: https://rustup.rs/"
        $missing++
    }
    
    # Check Git
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $gitVersion = & git --version 2>&1
        Write-Success "Git: $gitVersion"
    } else {
        Write-Error2 "Git not found"
        Write-Host "  Install from: https://git-scm.com/"
        $missing++
    }
    
    # Check Visual Studio Build Tools
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsWhere) {
        $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>&1
        if ($vsPath) {
            Write-Success "Visual Studio Build Tools found"
        } else {
            Write-Warning2 "Visual Studio C++ Build Tools may not be installed"
            Write-Host "  Install from: https://visualstudio.microsoft.com/visual-cpp-build-tools/"
        }
    } else {
        Write-Warning2 "Could not verify Visual Studio Build Tools"
    }
    
    if ($missing -gt 0) {
        Write-Host ""
        Write-Error2 "Missing dependencies. Please install them first."
        Write-Host ""
        Write-Host "Required:"
        Write-Host "  1. Rust: https://rustup.rs/"
        Write-Host "  2. Git: https://git-scm.com/"
        Write-Host "  3. Visual Studio Build Tools with C++ support"
        Write-Host ""
        exit 1
    }
    
    Write-Success "All dependencies satisfied!"
}

# =============================================================================
# Interactive Configuration
# =============================================================================

function Get-Configuration {
    Write-Header "Build Configuration"
    
    # Select RustDesk version
    Write-Host "Available RustDesk versions:" -ForegroundColor White
    Write-Host "  1) 1.1.14 (stable, recommended)"
    Write-Host "  2) 1.1.13 (older stable)"
    Write-Host "  3) Custom (enter version)"
    Write-Host ""
    
    if ($Auto) {
        $script:RustDeskVersion = $DefaultRustDeskVersion
        Write-Info "Auto mode: Using version $RustDeskVersion"
    } elseif ($Version) {
        $script:RustDeskVersion = $Version
    } else {
        $choice = Read-Host "Select version [1]"
        switch ($choice) {
            "2" { $script:RustDeskVersion = "1.1.13" }
            "3" { $script:RustDeskVersion = Read-Host "Enter version (e.g., 1.1.15)" }
            default { $script:RustDeskVersion = $DefaultRustDeskVersion }
        }
    }
    
    Write-Success "Selected RustDesk version: $RustDeskVersion"
    Write-Host ""
    
    # Select target platform
    Write-Host "Target platform:" -ForegroundColor White
    Write-Host "  1) Windows x86_64 (native)"
    Write-Host "  2) Linux x86_64 (cross-compile, requires WSL)"
    Write-Host ""
    
    if ($Auto) {
        $script:TargetPlatform = "windows-x64"
        Write-Info "Auto mode: Building for $TargetPlatform"
    } elseif ($Platform) {
        $script:TargetPlatform = $Platform
    } else {
        $choice = Read-Host "Select platform [1]"
        switch ($choice) {
            "2" { $script:TargetPlatform = "linux-x64" }
            default { $script:TargetPlatform = "windows-x64" }
        }
    }
    
    Write-Success "Target platform: $TargetPlatform"
    Write-Host ""
    
    # Confirm
    if (-not $Auto) {
        Write-Host "Build Summary:" -ForegroundColor White
        Write-Host "  RustDesk Version: $RustDeskVersion"
        Write-Host "  Target Platform:  $TargetPlatform"
        Write-Host "  Build Directory:  $BuildDir"
        Write-Host "  Output Directory: $OutputDir"
        Write-Host ""
        $confirm = Read-Host "Continue with build? [Y/n]"
        if ($confirm -match "^[Nn]$") {
            Write-Host "Build cancelled."
            exit 0
        }
    }
}

# =============================================================================
# Download RustDesk Sources
# =============================================================================

function Get-RustDeskSources {
    Write-Header "Downloading RustDesk Server Sources"
    
    $sourceDir = Join-Path $BuildDir "rustdesk-server-$RustDeskVersion"
    
    if (Test-Path $sourceDir) {
        Write-Info "Source directory exists: $sourceDir"
        
        if (-not $Auto) {
            $redownload = Read-Host "Re-download sources? [y/N]"
            if ($redownload -notmatch "^[Yy]$") {
                Write-Success "Using existing sources"
                return
            }
        } else {
            Write-Info "Auto mode: Using existing sources"
            return
        }
        
        Remove-Item $sourceDir -Recurse -Force
    }
    
    if (-not (Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir | Out-Null
    }
    
    Push-Location $BuildDir
    
    Write-Step "Cloning rustdesk-server repository..."
    & git clone --depth 1 --branch $RustDeskVersion $RustDeskRepo "rustdesk-server-$RustDeskVersion"
    
    Set-Location "rustdesk-server-$RustDeskVersion"
    
    Write-Step "Initializing submodules..."
    & git submodule update --init --recursive
    
    Pop-Location
    
    Write-Success "RustDesk sources downloaded successfully"
}

# =============================================================================
# Apply BetterDesk Modifications
# =============================================================================

function Apply-Modifications {
    Write-Header "Applying BetterDesk Modifications"
    
    $sourceDir = Join-Path $BuildDir "rustdesk-server-$RustDeskVersion"
    
    if (-not (Test-Path $sourceDir)) {
        Write-Error2 "Source directory not found: $sourceDir"
        exit 1
    }
    
    Push-Location $sourceDir
    
    # List of files to copy from patches
    $patchFiles = @(
        "main.rs",
        "http_api.rs",
        "database.rs",
        "database_fixed.rs",
        "peer.rs",
        "peer_fixed.rs",
        "rendezvous_server_core.rs"
    )
    
    Write-Step "Copying BetterDesk modifications..."
    
    foreach ($file in $patchFiles) {
        $patchPath = Join-Path $PatchesDir $file
        if (Test-Path $patchPath) {
            $targetPath = Join-Path "src" $file
            Copy-Item $patchPath $targetPath -Force
            Write-Success "Applied: $file"
        } else {
            Write-Warning2 "Patch file not found: $file"
        }
    }
    
    Pop-Location
    
    Write-Success "BetterDesk modifications applied successfully"
}

# =============================================================================
# Build Binaries
# =============================================================================

function Build-Binaries {
    Write-Header "Building BetterDesk Binaries"
    
    $sourceDir = Join-Path $BuildDir "rustdesk-server-$RustDeskVersion"
    Push-Location $sourceDir
    
    $targetFlag = ""
    $binarySuffix = "-windows-x86_64.exe"
    
    if ($TargetPlatform -eq "linux-x64") {
        Write-Step "Setting up Linux cross-compilation..."
        & rustup target add x86_64-unknown-linux-gnu
        $targetFlag = "--target x86_64-unknown-linux-gnu"
        $binarySuffix = "-linux-x86_64"
    }
    
    Write-Step "Building HBBS (Signal Server)..."
    if ($targetFlag) {
        & cargo build --release $targetFlag -p hbbs
    } else {
        & cargo build --release -p hbbs
    }
    
    Write-Step "Building HBBR (Relay Server)..."
    if ($targetFlag) {
        & cargo build --release $targetFlag -p hbbr
    } else {
        & cargo build --release -p hbbr
    }
    
    # Find binaries
    $targetDir = "target\release"
    if ($targetFlag) {
        $targetDir = "target\$($targetFlag -replace '--target ','')\release"
    }
    
    $hbbsBinary = Join-Path $targetDir "hbbs.exe"
    $hbbrBinary = Join-Path $targetDir "hbbr.exe"
    
    if ($TargetPlatform -eq "linux-x64") {
        $hbbsBinary = Join-Path $targetDir "hbbs"
        $hbbrBinary = Join-Path $targetDir "hbbr"
    }
    
    if (-not (Test-Path $hbbsBinary) -or -not (Test-Path $hbbrBinary)) {
        Write-Error2 "Build failed - binaries not found"
        Pop-Location
        exit 1
    }
    
    Write-Success "Build completed successfully!"
    
    # Copy to output directory
    Write-Step "Copying binaries to output directory..."
    
    $hbbsOutput = Join-Path $OutputDir "hbbs$binarySuffix"
    $hbbrOutput = Join-Path $OutputDir "hbbr$binarySuffix"
    
    Copy-Item $hbbsBinary $hbbsOutput -Force
    Copy-Item $hbbrBinary $hbbrOutput -Force
    
    Pop-Location
    
    Write-Success "Binaries saved to:"
    Write-Host "  - $hbbsOutput"
    Write-Host "  - $hbbrOutput"
}

# =============================================================================
# Generate Checksums
# =============================================================================

function New-Checksums {
    Write-Header "Generating Checksums"
    
    $checksumsFile = Join-Path $OutputDir "CHECKSUMS.md"
    $dateNow = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    $content = @"
# BetterDesk Server - Binary Checksums

Generated: $dateNow
RustDesk Base Version: $RustDeskVersion
BetterDesk Version: 2.0.0

## SHA256 Checksums

``````
"@
    
    Get-ChildItem $OutputDir -Filter "hbbs-*" | ForEach-Object {
        $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
        $content += "$hash  $($_.Name)`n"
    }
    
    Get-ChildItem $OutputDir -Filter "hbbr-*" | ForEach-Object {
        $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash
        $content += "$hash  $($_.Name)`n"
    }
    
    $content += "``````"
    
    $content | Out-File $checksumsFile -Encoding UTF8
    
    Write-Success "Checksums saved to: $checksumsFile"
}

# =============================================================================
# Clean Build
# =============================================================================

function Clear-Build {
    Write-Header "Cleaning Build Directory"
    
    if (Test-Path $BuildDir) {
        Write-Step "Removing: $BuildDir"
        Remove-Item $BuildDir -Recurse -Force
        Write-Success "Build directory cleaned"
    } else {
        Write-Info "Build directory does not exist"
    }
}

# =============================================================================
# Main
# =============================================================================

function Main {
    # Handle help
    if ($Help) {
        Show-Help
        exit 0
    }
    
    # Handle clean mode
    if ($Clean) {
        Clear-Build
        exit 0
    }
    
    # Banner
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     BetterDesk Server - Build from Source (Windows)      ║" -ForegroundColor Cyan
    Write-Host "║     Enhanced RustDesk with HTTP API & Management         ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    # Run build steps
    Test-Dependencies
    Get-Configuration
    Get-RustDeskSources
    Apply-Modifications
    Build-Binaries
    New-Checksums
    
    # Final message
    Write-Header "Build Complete!"
    
    Write-Host "BetterDesk binaries have been built successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Output location: $OutputDir"
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. Test the binaries:"
    Write-Host "     cd $OutputDir"
    Write-Host "     .\hbbs-windows-x86_64.exe --help"
    Write-Host ""
    Write-Host "  2. Run the installer to deploy:"
    Write-Host "     .\install-improved.ps1"
    Write-Host ""
    Write-Host "  3. Or manually start the servers:"
    Write-Host "     .\hbbs-windows-x86_64.exe -k _ --api-port 21114"
    Write-Host "     .\hbbr-windows-x86_64.exe"
    Write-Host ""
}

Main
