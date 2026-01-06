# Deploy HBBS v6 + HBBR with comprehensive ban enforcement
# This script deploys both signal server (hbbs) and relay server (hbbr)

param(
    [string]$Server = "YOUR_SERVER_IP",
    [string]$User = "YOUR_SSH_USER"
)

$ErrorActionPreference = "Stop"

Write-Host "`n🚀 Deploying HBBS v6 + HBBR with comprehensive ban checks...`n" -ForegroundColor Cyan

# Step 1: Wait for compilation
Write-Host "⏱️  Checking compilation status..." -ForegroundColor Yellow
$maxWait = 20
for ($i = 1; $i -le $maxWait; $i++) {
    $status = ssh "$User@$Server" "ps aux | grep -q '[c]argo build' && echo 'running' || echo 'done'"
    
    if ($status -match "done") {
        Write-Host "✅ Compilation finished!" -ForegroundColor Green
        break
    }
    
    if ($i -eq $maxWait) {
        Write-Host "❌ Compilation timeout" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "   Waiting... ($i/$maxWait)" -ForegroundColor Gray
    Start-Sleep -Seconds 30
}

# Step 2: Verify binaries exist
Write-Host "`n📦 Verifying binaries..." -ForegroundColor Yellow
$result = ssh "$User@$Server" @"
ls -lh /tmp/rustdesk-server/target/release/hbbs /tmp/rustdesk-server/target/release/hbbr 2>/dev/null | wc -l
"@

if ($result -ne "2") {
    Write-Host "❌ Binaries not found! Compilation may have failed." -ForegroundColor Red
    Write-Host "`nChecking build log for errors..." -ForegroundColor Yellow
    ssh "$User@$Server" "tail -50 /tmp/build-v6-final.log | grep -A5 'error\[' || tail -30 /tmp/build-v6-final.log"
    exit 1
}

Write-Host "✅ Both binaries found" -ForegroundColor Green

# Step 3: Stop services
Write-Host "`n🛑 Stopping RustDesk services..." -ForegroundColor Yellow
ssh -t "$User@$Server" @"
sudo systemctl stop rustdesksignal
sudo systemctl stop rustdeskrelay 2>/dev/null || true
echo 'Services stopped'
"@

# Step 4: Backup existing binaries
Write-Host "`n💾 Creating backups..." -ForegroundColor Yellow
ssh -t "$User@$Server" @"
sudo cp /opt/rustdesk/hbbs /opt/rustdesk/hbbs.v6.backup 2>/dev/null && echo 'HBBS backup created' || echo 'No existing HBBS'
sudo cp /opt/rustdesk/hbbr /opt/rustdesk/hbbr.v6.backup 2>/dev/null && echo 'HBBR backup created' || echo 'No existing HBBR'
"@

# Step 5: Deploy new binaries
Write-Host "`n📥 Deploying new binaries..." -ForegroundColor Yellow
ssh -t "$User@$Server" @"
sudo cp /tmp/rustdesk-server/target/release/hbbs /opt/rustdesk/hbbs
sudo cp /tmp/rustdesk-server/target/release/hbbr /opt/rustdesk/hbbr
sudo chmod +x /opt/rustdesk/hbbs /opt/rustdesk/hbbr
sudo chown root:root /opt/rustdesk/hbbs /opt/rustdesk/hbbr
echo 'Binaries deployed'
"@

# Step 6: Start services
Write-Host "`n▶️  Starting services..." -ForegroundColor Yellow
ssh -t "$User@$Server" @"
sudo systemctl start rustdesksignal
sudo systemctl start rustdeskrelay 2>/dev/null || sudo systemctl start hbbr 2>/dev/null || echo 'Note: Relay service may have different name'
sleep 3
echo ''
echo '=== HBBS Status ==='
sudo systemctl status rustdesksignal --no-pager | head -12
echo ''
echo '=== HBBR Status ==='
sudo systemctl status rustdeskrelay --no-pager 2>/dev/null || ps aux | grep '[h]bbr' || echo 'HBBR may not be running as service'
"@

# Step 7: Verify deployment
Write-Host "`n✅ Verifying deployment..." -ForegroundColor Green
ssh "$User@$Server" @"
echo ''
echo 'Binary sizes:'
ls -lh /opt/rustdesk/hbbs /opt/rustdesk/hbbr | awk '{print \$9, \$5}'
echo ''
echo 'Checking ban check strings in binaries:'
strings /opt/rustdesk/hbbs | grep -E 'BLOCKED|Registration REJECTED' | head -3
strings /opt/rustdesk/hbbr | grep -E 'HBBR Relay' | head -2
"@

Write-Host "`n✅ Deployment complete!`n" -ForegroundColor Green
Write-Host "📝 Next steps:" -ForegroundColor Cyan
Write-Host "   1. Monitor logs: ssh $User@$Server 'sudo tail -f /var/log/rustdesk/signalserver.log'" -ForegroundColor Gray
Write-Host "   2. Test ban enforcement with device 1253021143" -ForegroundColor Gray
Write-Host "   3. Check HBBR logs for 'HBBR Relay BLOCKED' messages`n" -ForegroundColor Gray
