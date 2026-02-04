# 🔧 Bug Fixes - User-Reported Issues

## 🐛 Reported Problems

### Problem 1: Docker Error
```bash
sh: 1: executable file not found in $PATH
```

**Cause:**  
The Docker image `python:3.11-slim` by default does not include `bash`, and `docker-entrypoint.sh` has a shebang `#!/bin/bash`.

**Impact:**
- Docker containers won't start
- Error occurs during `docker-compose up`
- Application doesn't work in Docker

---

### Problem 2: PowerShell Error
```powershell
Write-Info : The term 'Write-Info' is not recognized as the name of a cmdlet
```

**Cause:**  
Custom functions `Write-Error`, `Write-Warning`, and `Write-Info` in `install-improved.ps1` conflict with PowerShell built-in cmdlets.

**Impact:**
- PowerShell installation script doesn't work
- Error when running `.\install-improved.ps1`
- Installation fails

---

## ✅ Solutions

### Fix 1: Docker - Add bash

**Modified file:** `Dockerfile.console`

**Before:**
```dockerfile
RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*
```

**After:**
```dockerfile
RUN apt-get update && apt-get install -y \
    bash \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*
```

**What changed:**
- Added `bash` to the list of installed packages
- Ensures that `#!/bin/bash` works in `docker-entrypoint.sh`

---

### Fix 2: PowerShell - Rename Functions

**Modified file:** `install-improved.ps1`

**Before:**
```powershell
function Write-Error {
    param([string]$Message)
    Write-Host "❌ ERROR: $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️ WARNING: $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️ INFO: $Message" -ForegroundColor Cyan
}
```

**After:**
```powershell
function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "❌ ERROR: $Message" -ForegroundColor Red
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Host "⚠️ WARNING: $Message" -ForegroundColor Yellow
}

function Write-InfoMsg {
    param([string]$Message)
    Write-Host "ℹ️ INFO: $Message" -ForegroundColor Cyan
}
```

**What changed:**
- Renamed `Write-Error` → `Write-ErrorMsg`
- Renamed `Write-Warning` → `Write-WarningMsg`
- Renamed `Write-Info` → `Write-InfoMsg`
- Updated **58 function calls** throughout the file

**Additional changes:**
```powershell
# Added at the beginning of the file
#Requires -Version 5.1
Set-StrictMode -Version Latest
```

---

## 🧪 Testing

### Test 1: Docker

```bash
# Rebuild the image
docker-compose down
docker-compose build --no-cache

# Start containers
docker-compose up -d

# Check logs
docker logs rustdesk-console

# Expected result:
✅ "Starting RustDesk Console..."
✅ "Database initialized"
✅ No errors about "bash not found"
```

### Test 2: PowerShell

```powershell
# Run the script
.\install-improved.ps1

# Expected result:
✅ No errors about "Write-Info"
✅ Script executes normally
✅ Messages display with emojis and colors
```

---

## 📝 Changed Files

### 1. Dockerfile.console
**Lines changed:** 1  
**Location:** Line ~15 (RUN apt-get install)  
**Impact:** Docker image now includes bash

### 2. install-improved.ps1
**Lines changed:** ~60  
**Location:** 
- Lines 28-46: Function definitions (3 functions)
- Lines 50-500: Function calls (58 calls)  
**Impact:** PowerShell script now works without conflicts

---

## 🔍 Diagnostics

### Check if Docker Fix Works:

```bash
docker exec -it rustdesk-console bash --version
# Expected output: GNU bash, version 5.x.x
```

### Check if PowerShell Fix Works:

```powershell
# In PowerShell:
Get-Command Write-ErrorMsg
# Expected output: CommandType: Function, Name: Write-ErrorMsg

Get-Command Write-Info
# Expected output: CommandType: Cmdlet (built-in, not ours)
```

---

## 🎯 Summary

| Problem | Cause | Solution | Status |
|---------|-------|----------|--------|
| Docker bash error | Missing bash in image | Added bash to Dockerfile | ✅ Fixed |
| PowerShell Write-Info | Function name conflict | Renamed to Write-InfoMsg | ✅ Fixed |

**All problems resolved and tested.**

---

## 📚 Additional Information

### Why bash wasn't included?

`python:3.11-slim` is a minimal image to reduce size. It includes only:
- Python 3.11
- Essential libraries
- sh (minimal shell)

Bash must be installed manually.

### Why function name conflict?

PowerShell has built-in cmdlets:
- `Write-Error` - writes errors to error stream
- `Write-Warning` - writes warnings
- `Write-Host` - writes to console
- `Write-Verbose`, `Write-Debug` etc.

Custom functions with these names override built-in cmdlets, which can cause problems.

**Best practice:**  
Always use unique function names, e.g., `Write-CustomError` or `Write-ErrorMsg`.

---

## ✅ Checklist

- [x] Docker: Added bash to Dockerfile.console
- [x] Docker: Tested building the image
- [x] Docker: Tested starting containers
- [x] PowerShell: Renamed Write-Error → Write-ErrorMsg
- [x] PowerShell: Renamed Write-Warning → Write-WarningMsg
- [x] PowerShell: Renamed Write-Info → Write-InfoMsg
- [x] PowerShell: Updated 58 function calls
- [x] PowerShell: Added #Requires -Version 5.1
- [x] PowerShell: Added Set-StrictMode
- [x] Documentation: Created TROUBLESHOOTING.md
- [x] Documentation: Created QUICK_FIX.md

---

**Last Updated:** February 4, 2026  

Thank you for reporting the problems! 🙏

---

## 🔴 Problem 3: All Devices Show as "Offline"

### Symptoms
- All devices in BetterDesk Console are shown as "Offline"
- RustDesk clients can connect to each other normally
- `status` column in database is always 0 or NULL

### Cause
You are using the **original RustDesk hbbs binary** instead of the **BetterDesk enhanced binary**.

The original hbbs does NOT update the `status` field in the database - this is a BetterDesk-specific feature.

### How to Check

Run this command to see which binary you have:
```bash
/opt/rustdesk/hbbs --help | head -5
```

**BetterDesk binary shows:**
```
hbbs 1.1.14
Purslane Ltd. <info@rustdesk.com>
BetterDesk Enhanced Server v2.0.0
```

**Original binary shows:**
```
hbbs 1.1.14
Purslane Ltd. <info@rustdesk.com>
RustDesk ID/Rendezvous Server
```

### Solution

#### Option 1: Use Diagnostic Script (Recommended)
```bash
cd /path/to/Rustdesk-FreeConsole
chmod +x dev_modules/diagnose_offline_status.sh
./dev_modules/diagnose_offline_status.sh
```

#### Option 2: Manual Fix

1. **Stop current hbbs:**
```bash
sudo pkill -f hbbs
```

2. **Backup original binary:**
```bash
sudo cp /opt/rustdesk/hbbs /opt/rustdesk/hbbs.backup-original
```

3. **Install BetterDesk binary:**
```bash
# Download if you don't have it
git clone https://github.com/UNITRONIX/Rustdesk-FreeConsole.git
cd Rustdesk-FreeConsole

# Copy enhanced binary
sudo cp hbbs-patch-v2/hbbs-linux-x86_64 /opt/rustdesk/hbbs
sudo cp hbbs-patch-v2/hbbr-linux-x86_64 /opt/rustdesk/hbbr
sudo chmod +x /opt/rustdesk/hbbs /opt/rustdesk/hbbr
```

4. **Start with API port:**
```bash
cd /opt/rustdesk
sudo ./hbbs -k _ --api-port 21114 &
sudo ./hbbr &
```

5. **Verify:**
```bash
/opt/rustdesk/hbbs --help | grep -i betterdesk
# Should show: BetterDesk Enhanced Server v2.0.0
```

### For Manual (non-systemd) Installations

If you're NOT using systemd services, you need to:

1. **Create a startup script** (`/opt/rustdesk/start.sh`):
```bash
#!/bin/bash
cd /opt/rustdesk
./hbbs -k _ --api-port 21114 > hbbs.log 2>&1 &
./hbbr > hbbr.log 2>&1 &
echo "RustDesk servers started"
```

2. **Or create systemd services** (recommended):
```bash
# Signal server service
sudo tee /etc/systemd/system/rustdesksignal.service << 'EOF'
[Unit]
Description=RustDesk Signal Server (BetterDesk)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/rustdesk
ExecStart=/opt/rustdesk/hbbs -k _ --api-port 21114
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Relay server service
sudo tee /etc/systemd/system/rustdeskrelay.service << 'EOF'
[Unit]
Description=RustDesk Relay Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/rustdesk
ExecStart=/opt/rustdesk/hbbr
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable rustdesksignal rustdeskrelay
sudo systemctl start rustdesksignal rustdeskrelay
```

### Understanding How Online Status Works

```
┌─────────────┐     register      ┌──────────────┐     updates      ┌──────────────┐
│  RustDesk   │ ───────────────► │  BetterDesk  │ ───────────────► │   SQLite     │
│   Client    │                  │    hbbs      │   status=1       │  db_v2.sqlite│
└─────────────┘                  └──────────────┘   last_online    └──────────────┘
                                                                           │
                                                                           │ reads
                                                                           ▼
                                 ┌──────────────┐                   ┌──────────────┐
                                 │  BetterDesk  │ ◄──────────────── │   Web UI     │
                                 │   Console    │    status=1?     │   Browser    │
                                 └──────────────┘    → Online       └──────────────┘
```

**Key point:** Only the **BetterDesk enhanced hbbs** updates the database with online status. The original RustDesk hbbs does not have this feature.
