# HBBS Ban Enforcement - Diagnostic Script
# Tests both directions and verifies database access

param(
    [string]$Server = "YOUR_SSH_USER@YOUR_SERVER_IP",
    [string]$BannedDevice = "1253021143"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "HBBS Ban Diagnostic v4" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# 1. Check database location and permissions
Write-Host "[1/5] Database Configuration" -ForegroundColor Yellow
$dbInfo = ssh $Server "ls -lh /opt/rustdesk/db_v2.sqlite* && echo '' && file /opt/rustdesk/db_v2.sqlite3"
Write-Host $dbInfo -ForegroundColor Gray

# 2. Check HBBS process
Write-Host "`n[2/5] HBBS Process Status" -ForegroundColor Yellow
$processInfo = ssh $Server "ps aux | grep '/opt/rustdesk/hbbs' | grep -v grep && echo '' && sudo readlink /proc/`$(pgrep -f '/opt/rustdesk/hbbs')/cwd"
Write-Host $processInfo -ForegroundColor Gray

# 3. Check device ban status in database (via API)
Write-Host "`n[3/5] Device Ban Status (API)" -ForegroundColor Yellow
$apiCheck = ssh $Server "curl -s http://localhost:5000/api/devices 2>/dev/null | grep -A10 '$BannedDevice' | head -15"
Write-Host $apiCheck -ForegroundColor Gray

# 4. Check recent logs for ban enforcement
Write-Host "`n[4/5] Recent Ban Logs" -ForegroundColor Yellow
$banLogs = ssh $Server "grep -E 'REJECTED|ban.*$BannedDevice|$BannedDevice.*ban' /var/log/rustdesk/signalserver.log | tail -10"
if ($banLogs) {
    Write-Host $banLogs -ForegroundColor Gray
} else {
    Write-Host "No ban enforcement logs found" -ForegroundColor Yellow
}

# 5. Check for registration attempts
Write-Host "`n[5/5] Registration Attempts" -ForegroundColor Yellow
$regLogs = ssh $Server "grep 'update_pk $BannedDevice' /var/log/rustdesk/signalserver.log | tail -5"
if ($regLogs) {
    Write-Host "Device is still registering (should be blocked):" -ForegroundColor Red
    Write-Host $regLogs -ForegroundColor Gray
} else {
    Write-Host "No recent registration attempts" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Diagnostic Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nExpected behavior after v4 deployment:" -ForegroundColor Yellow
Write-Host "1. Device $BannedDevice should NOT appear in 'update_pk' logs" -ForegroundColor Gray
Write-Host "2. Should see 'Registration REJECTED' messages" -ForegroundColor Gray
Write-Host "3. Should see 'Relay REJECTED - initiator is banned' OR 'target is banned'" -ForegroundColor Gray
Write-Host "4. Device should NOT be 'online' in API response" -ForegroundColor Gray

Write-Host "`nIf device still registers:" -ForegroundColor Yellow
Write-Host "- Check if v4 binary is deployed" -ForegroundColor Gray
Write-Host "- Restart HBBS service" -ForegroundColor Gray
Write-Host "- Check error logs for database access issues" -ForegroundColor Gray
