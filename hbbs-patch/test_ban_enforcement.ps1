# Test Ban Enforcement - Comprehensive Testing Script
# Tests bidirectional ban enforcement (initiator + target)

param(
    [Parameter(Mandatory=$false)]
    [string]$BannedDeviceId = "58457133",
    
    [Parameter(Mandatory=$false)]
    [string]$NormalDeviceId = "1253021143",
    
    [Parameter(Mandatory=$false)]
    [string]$ApiUrl = "http://YOUR_SERVER_IP:5000",
    
    [Parameter(Mandatory=$false)]
    [string]$Server = "YOUR_SSH_USER@YOUR_SERVER_IP"
)

$ErrorActionPreference = "Continue"

function Write-TestHeader {
    param([string]$Title)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host $Title -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-TestResult {
    param([string]$Test, [bool]$Passed, [string]$Details = "")
    if ($Passed) {
        Write-Host "[✓] $Test" -ForegroundColor Green
    } else {
        Write-Host "[✗] $Test" -ForegroundColor Red
    }
    if ($Details) {
        Write-Host "    $Details" -ForegroundColor Gray
    }
}

Write-TestHeader "HBBS Ban Enforcement Tests"
Write-Host "Banned Device: $BannedDeviceId" -ForegroundColor Yellow
Write-Host "Normal Device: $NormalDeviceId" -ForegroundColor Yellow
Write-Host "API URL: $ApiUrl`n" -ForegroundColor Yellow

# Test 1: Check service status
Write-TestHeader "[1/6] Service Status Check"
$serviceStatus = ssh $Server "sudo systemctl is-active rustdesksignal" 2>$null
$serviceRunning = $serviceStatus -eq "active"
Write-TestResult "Service rustdesksignal is running" $serviceRunning $serviceStatus

if (-not $serviceRunning) {
    Write-Host "`nERROR: Service is not running. Starting service..." -ForegroundColor Red
    ssh -t $Server "sudo systemctl start rustdesksignal"
    Start-Sleep -Seconds 3
}

# Test 2: Check HBBS version and binary
Write-TestHeader "[2/6] Binary Version Check"
$hbbsVersion = ssh $Server "ls -lh /opt/rustdesk/hbbs | awk '{print `$5, `$9}'" 2>$null
Write-Host "Binary: $hbbsVersion" -ForegroundColor Gray

$backupCount = ssh $Server "ls -1 /opt/rustdesk/hbbs.backup.* 2>/dev/null | wc -l" 2>$null
Write-Host "Backups available: $backupCount" -ForegroundColor Gray

# Test 3: Check API connectivity
Write-TestHeader "[3/6] API Connectivity Check"
try {
    $devices = Invoke-RestMethod -Uri "$ApiUrl/api/devices" -Method Get -TimeoutSec 5
    $deviceCount = $devices.Count
    Write-TestResult "API responding" $true "$deviceCount devices returned"
} catch {
    Write-TestResult "API responding" $false $_.Exception.Message
    Write-Host "`nERROR: Cannot connect to API. Exiting..." -ForegroundColor Red
    exit 1
}

# Test 4: Check ban status of test device
Write-TestHeader "[4/6] Device Ban Status Check"
$bannedDevice = $devices | Where-Object { $_.id -eq $BannedDeviceId }
if ($bannedDevice) {
    $isBanned = $bannedDevice.is_banned -eq $true
    Write-TestResult "Device $BannedDeviceId found in API" $true
    Write-TestResult "Device $BannedDeviceId is banned" $isBanned "is_banned: $($bannedDevice.is_banned)"
    
    if (-not $isBanned) {
        Write-Host "`nWARNING: Test device is not banned. Ban it first via console:" -ForegroundColor Yellow
        Write-Host "  $ApiUrl" -ForegroundColor Yellow
    }
} else {
    Write-TestResult "Device $BannedDeviceId found in API" $false "Device not in database"
}

# Test 5: Check logs for ban enforcement
Write-TestHeader "[5/6] Log Analysis - Ban Enforcement"
Write-Host "Checking last 50 ban-related log entries..." -ForegroundColor Gray

$banLogs = ssh $Server "grep -i 'ban\|reject' /var/log/rustdesk/signalserver.log 2>/dev/null | tail -50"
if ($banLogs) {
    $recentBans = ($banLogs -split "`n" | Select-Object -Last 10) -join "`n"
    Write-Host "`nRecent ban activity:" -ForegroundColor Yellow
    Write-Host $recentBans -ForegroundColor Gray
    
    # Count different types of rejections
    $registrationRejections = ($banLogs | Select-String "Registration REJECTED").Count
    $relayRejections = ($banLogs | Select-String "Relay.*REJECTED").Count
    $punchHoleRejections = ($banLogs | Select-String "Punch hole.*REJECTED").Count
    $initiatorBlocks = ($banLogs | Select-String "initiator.*banned").Count
    $targetBlocks = ($banLogs | Select-String "target.*banned").Count
    
    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "  Registration rejections: $registrationRejections" -ForegroundColor Gray
    Write-Host "  Relay rejections: $relayRejections" -ForegroundColor Gray
    Write-Host "  Punch hole rejections: $punchHoleRejections" -ForegroundColor Gray
    Write-Host "  Initiator blocks: $initiatorBlocks" -ForegroundColor Gray
    Write-Host "  Target blocks: $targetBlocks" -ForegroundColor Gray
    
    $bidirectionalWorks = ($initiatorBlocks -gt 0) -and ($targetBlocks -gt 0)
    Write-TestResult "Bidirectional ban enforcement active" $bidirectionalWorks
} else {
    Write-TestResult "Log file accessible" $false "No ban logs found"
}

# Test 6: Check for errors
Write-TestHeader "[6/6] Error Log Check"
$errorLogs = ssh $Server "grep -i 'error\|panic' /var/log/rustdesk/signalserver.error 2>/dev/null | tail -20"
if ($errorLogs) {
    $recentErrors = ($errorLogs -split "`n" | Select-Object -Last 5) -join "`n"
    Write-Host "Recent errors found:" -ForegroundColor Red
    Write-Host $recentErrors -ForegroundColor Gray
    Write-TestResult "No critical errors" $false "Errors detected in logs"
} else {
    Write-TestResult "No critical errors" $true "Error log is clean"
}

# Test 7: Performance check
Write-TestHeader "Performance Metrics"
$cpuUsage = ssh $Server "ps -p `$(pgrep -f '/opt/rustdesk/hbbs') -o %cpu --no-headers | awk '{print `$1}'" 2>$null
$memUsage = ssh $Server "ps -p `$(pgrep -f '/opt/rustdesk/hbbs') -o %mem --no-headers | awk '{print `$1}'" 2>$null

if ($cpuUsage) {
    Write-Host "  CPU Usage: $cpuUsage%" -ForegroundColor Gray
    Write-Host "  Memory Usage: $memUsage%" -ForegroundColor Gray
} else {
    Write-Host "  Process metrics unavailable" -ForegroundColor Yellow
}

# Final Summary
Write-TestHeader "Test Summary"
Write-Host "1. Service Status: " -NoNewline
Write-Host $(if ($serviceRunning) { "PASS" } else { "FAIL" }) -ForegroundColor $(if ($serviceRunning) { "Green" } else { "Red" })

Write-Host "2. API Connectivity: " -NoNewline
Write-Host $(if ($devices) { "PASS" } else { "FAIL" }) -ForegroundColor $(if ($devices) { "Green" } else { "Red" })

Write-Host "3. Ban Status Correct: " -NoNewline
if ($bannedDevice) {
    $banCorrect = $bannedDevice.is_banned -eq $true
    Write-Host $(if ($banCorrect) { "PASS" } else { "WARN" }) -ForegroundColor $(if ($banCorrect) { "Green" } else { "Yellow" })
} else {
    Write-Host "N/A" -ForegroundColor Gray
}

Write-Host "4. Log Analysis: " -NoNewline
Write-Host $(if ($banLogs) { "PASS" } else { "WARN" }) -ForegroundColor $(if ($banLogs) { "Green" } else { "Yellow" })

Write-Host "5. Error Check: " -NoNewline
Write-Host $(if (-not $errorLogs) { "PASS" } else { "WARN" }) -ForegroundColor $(if (-not $errorLogs) { "Green" } else { "Yellow" })

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Testing Complete!" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. If device $BannedDeviceId is not banned, ban it via console: $ApiUrl" -ForegroundColor Gray
Write-Host "2. Try connecting FROM banned device to normal device" -ForegroundColor Gray
Write-Host "3. Try connecting FROM normal device TO banned device" -ForegroundColor Gray
Write-Host "4. Check logs for 'initiator banned' and 'target banned' messages:" -ForegroundColor Gray
Write-Host "   ssh $Server 'tail -f /var/log/rustdesk/signalserver.log | grep -i reject'" -ForegroundColor Gray
