# RustDesk HBBS/HBBR Windows Build Script (Local)
#
# This script builds RustDesk HBBS and HBBR for Windows locally
# with HTTP API and ban enforcement features.
#
# Requirements:
# - Windows 10/11
# - Rust toolchain (cargo, rustc)
# - Git
#
# Usage:
#   .\build-windows-local.ps1
#
# Output:
#   - hbbs-ban-check-package/hbbs.exe
#   - hbbs-ban-check-package/hbbr.exe
#   - bin-with-api/hbbs-v8-api.exe
#   - bin-with-api/hbbr-v8-api.exe

param(
    [Parameter(Mandatory=$false)]
    [switch]$SkipClone = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$Clean = $false
)

$ErrorActionPreference = "Stop"

# Configuration
$RUSTDESK_VERSION = "1.1.14"
$GITHUB_REPO = "https://github.com/rustdesk/rustdesk-server.git"
$OUTPUT_DIR = "hbbs-ban-check-package"
$BIN_API_DIR = "bin-with-api"

function Write-Header {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host "[$Step] " -NoNewline -ForegroundColor Blue
    Write-Host $Message -ForegroundColor White
}

function Write-Success {
    param([string]$Message)
    Write-Host "? $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "? $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "? $Message" -ForegroundColor Yellow
}

Write-Header "RustDesk Windows Build Script (Local)"

# Step 1: Check Rust installation
Write-Step "1/9" "Checking Rust installation..."
try {
    $cargoVersion = cargo --version
    $rustcVersion = rustc --version
    Write-Host "  Cargo: $cargoVersion"
    Write-Host "  Rustc: $rustcVersion"
    Write-Success "Rust toolchain ready"
}
catch {
    Write-Error "Rust not found. Please install from https://rustup.rs/"
    exit 1
}

# Step 2: Check Git
Write-Step "2/9" "Checking Git..."
try {
    $gitVersion = git --version
    Write-Host "  $gitVersion"
    Write-Success "Git ready"
}
catch {
    Write-Error "Git not found. Please install Git for Windows"
    exit 1
}

# Step 3: Clone or use existing source
Write-Step "3/9" "Preparing RustDesk source..."

$sourceDir = "rustdesk-server-$RUSTDESK_VERSION"

if ($Clean -and (Test-Path $sourceDir)) {
    Write-Host "  Cleaning old source directory..."
    Remove-Item -Path $sourceDir -Recurse -Force
}

if (-not (Test-Path $sourceDir) -and -not $SkipClone) {
    Write-Host "  Downloading RustDesk Server v$RUSTDESK_VERSION..."
    
    $archiveFile = "rustdesk-server-$RUSTDESK_VERSION.zip"
    if (-not (Test-Path $archiveFile)) {
        $downloadUrl = "https://github.com/rustdesk/rustdesk-server/archive/refs/tags/$RUSTDESK_VERSION.zip"
        Write-Host "  Downloading from GitHub..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $archiveFile -UseBasicParsing
        Write-Success "Download complete"
    }
    
    Write-Host "  Extracting archive..."
    Expand-Archive -Path $archiveFile -DestinationPath . -Force
    Write-Success "Source extracted"
}
elseif (Test-Path $sourceDir) {
    Write-Success "Source directory exists"
}
else {
    Write-Error "Source directory not found and -SkipClone specified"
    exit 1
}

# Step 4: Initialize submodules
Write-Step "4/9" "Initializing git submodules..."
Push-Location $sourceDir

if (Test-Path ".git") {
    Write-Host "  Updating submodules..."
    git submodule update --init --recursive 2>$null
}

# Check if hbb_common is present
if (-not (Test-Path "libs\hbb_common\Cargo.toml")) {
    Write-Warning "hbb_common not found, cloning directly..."
    
    if (Test-Path "libs\hbb_common") {
        Remove-Item -Path "libs\hbb_common" -Recurse -Force
    }
    
    Write-Host "  Cloning hbb_common..."
    git clone --depth 1 https://github.com/rustdesk/hbb_common.git libs\hbb_common
    
    if (Test-Path "libs\hbb_common\Cargo.toml") {
        Write-Success "hbb_common ready"
    }
    else {
        Write-Error "Failed to get hbb_common"
        Pop-Location
        exit 1
    }
}
else {
    Write-Success "hbb_common present"
}

# Step 5: Copy custom source files
Write-Step "5/9" "Applying custom modifications..."

$srcDir = "..\src"

if (Test-Path "$srcDir\http_api.rs") {
    Write-Host "  Copying http_api.rs..."
    Copy-Item "$srcDir\http_api.rs" "src\http_api.rs" -Force
}
else {
    Write-Error "http_api.rs not found in $srcDir"
    Pop-Location
    exit 1
}

if (Test-Path "$srcDir\main.rs") {
    Write-Host "  Copying main.rs..."
    Copy-Item "$srcDir\main.rs" "src\main.rs" -Force
}

if (Test-Path "$srcDir\peer.rs") {
    Write-Host "  Copying peer.rs..."
    Copy-Item "$srcDir\peer.rs" "src\peer.rs" -Force
}

if (Test-Path "$srcDir\rendezvous_server.rs") {
    Write-Host "  Copying rendezvous_server.rs..."
    Copy-Item "$srcDir\rendezvous_server.rs" "src\rendezvous_server.rs" -Force
}

Write-Success "Custom files applied"

# Step 6: Patch lib.rs
Write-Step "6/9" "Patching lib.rs..."

$librsContent = Get-Content "src\lib.rs" -Raw

if ($librsContent -notmatch "pub mod http_api;") {
    Write-Host "  Adding http_api module to lib.rs..."
    
    # Find the last 'pub mod' line and add after it
    $lines = Get-Content "src\lib.rs"
    $newLines = @()
    $added = $false
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $newLines += $lines[$i]
        
        if (-not $added -and $lines[$i] -match "^pub mod " -and ($i + 1 -lt $lines.Count) -and $lines[$i + 1] -notmatch "^pub mod ") {
            $newLines += "pub mod http_api;"
            $added = $true
        }
    }
    
    $newLines | Set-Content "src\lib.rs"
    Write-Success "lib.rs patched"
}
else {
    Write-Success "lib.rs already patched"
}

# Step 7: Update Cargo.toml
Write-Step "7/9" "Updating Cargo.toml dependencies..."

$cargoContent = Get-Content "Cargo.toml" -Raw

$modified = $false

if ($cargoContent -notmatch 'axum = ') {
    Write-Host "  Adding axum dependency..."
    $cargoContent = $cargoContent -replace '(\[dependencies\])', "`$1`naxum = `"0.5`""
    $modified = $true
}

if ($cargoContent -notmatch 'sqlx = ') {
    Write-Host "  Adding sqlx dependency..."
    $cargoContent = $cargoContent -replace '(\[dependencies\])', "`$1`nsqlx = { version = `"0.6`", features = [`"sqlite`", `"runtime-tokio-native-tls`"] }"
    $modified = $true
}

if ($modified) {
    $cargoContent | Set-Content "Cargo.toml"
    Write-Success "Dependencies updated"
}
else {
    Write-Success "Dependencies already present"
}

# Step 8: Build
Write-Step "8/9" "Building for Windows (this may take several minutes)..."
Write-Host ""

$env:RUSTFLAGS = "-C target-feature=+crt-static"

cargo build --release 2>&1 | ForEach-Object {
    if ($_ -match "Compiling|Finished|error|warning") {
        Write-Host $_
    }
}

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Error "Build failed with exit code $LASTEXITCODE"
    Pop-Location
    exit 1
}

Write-Host ""
Write-Success "Build complete!"

# Step 9: Package binaries
Write-Step "9/9" "Packaging binaries..."

Pop-Location  # Back to hbbs-patch directory

# Create output directories
if (-not (Test-Path $OUTPUT_DIR)) {
    New-Item -ItemType Directory -Path $OUTPUT_DIR | Out-Null
}

if (-not (Test-Path $BIN_API_DIR)) {
    New-Item -ItemType Directory -Path $BIN_API_DIR | Out-Null
}

# Copy executables
$hbbsPath = "$sourceDir\target\release\hbbs.exe"
$hbbrPath = "$sourceDir\target\release\hbbr.exe"

if (Test-Path $hbbsPath) {
    Copy-Item $hbbsPath "$OUTPUT_DIR\hbbs.exe" -Force
    Copy-Item $hbbsPath "$BIN_API_DIR\hbbs-v8-api.exe" -Force
    
    $hbbsSize = (Get-Item $hbbsPath).Length
    Write-Host "  ? hbbs.exe ($([math]::Round($hbbsSize / 1MB, 2)) MB)"
}
else {
    Write-Error "hbbs.exe not found"
}

if (Test-Path $hbbrPath) {
    Copy-Item $hbbrPath "$OUTPUT_DIR\hbbr.exe" -Force
    Copy-Item $hbbrPath "$BIN_API_DIR\hbbr-v8-api.exe" -Force
    
    $hbbrSize = (Get-Item $hbbrPath).Length
    Write-Host "  ? hbbr.exe ($([math]::Round($hbbrSize / 1MB, 2)) MB)"
}
else {
    Write-Error "hbbr.exe not found"
}

Write-Success "Binaries packaged"

# Summary
Write-Header "Build Complete!"

Write-Host "Windows binaries created:" -ForegroundColor Green
Write-Host "  ? $OUTPUT_DIR\hbbs.exe"
Write-Host "  ? $OUTPUT_DIR\hbbr.exe"
Write-Host ""
Write-Host "Also copied to installer directory:" -ForegroundColor Green
Write-Host "  ? $BIN_API_DIR\hbbs-v8-api.exe"
Write-Host "  ? $BIN_API_DIR\hbbr-v8-api.exe"
Write-Host ""
Write-Host "Features included:" -ForegroundColor Cyan
Write-Host "  ? HTTP API on port 21114"
Write-Host "  ? Real-time device status"
Write-Host "  ? Bidirectional ban enforcement"
Write-Host "  ? 20-second timeout synchronization"
Write-Host ""
Write-Host "Ready to use with install-improved.ps1!" -ForegroundColor Yellow
Write-Host ""
