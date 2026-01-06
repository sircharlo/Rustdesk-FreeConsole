# Quick Start - Update Scripts

## For Linux Users (Direct Access)

```bash
# 1. Download/clone the repository
git clone https://github.com/UNITRONIX/Rustdesk-FreeConsole.git
cd Rustdesk-FreeConsole

# 2. Make script executable
chmod +x update.sh

# 3. Run the update (default paths)
sudo ./update.sh

# OR with custom paths:
sudo ./update.sh --rustdesk-dir /custom/path/rustdesk
sudo ./update.sh --console-dir /var/www/betterdesk
sudo ./update.sh --rustdesk-dir /custom/rustdesk --console-dir /custom/console
```

**Available options:**
- `--rustdesk-dir PATH` - Custom RustDesk installation path
- `--console-dir PATH` - Custom BetterDesk Console path
- `--help` - Show usage information

**Example Output:**
```
========================================
BetterDesk Console - Update to v1.1.0
========================================

This update includes:
  • Soft delete system for devices (v1.0.1)
  • Device banning system (v1.1.0)
  • Enhanced UI with ban controls
  • Input validation and security improvements

⚠ WARNING: This will modify the database and restart services

Continue with update? [y/N]: y

========================================
Step 1: Checking Installation
========================================

✓ Found BetterDesk Console
✓ Found database
✓ Found BetterDesk service

========================================
Step 2: Creating Backup
========================================

→ Backup directory: /opt/betterdesk-backup-20260105-083000
→ Backing up database...
✓ Database backed up
→ Backing up web console files...
✓ Web files backed up

✓ Backup completed: /opt/betterdesk-backup-20260105-083000

========================================
Step 3: Database Migration
========================================

→ Running migration v1.0.1 (soft delete)...
✓ Migration v1.0.1 completed

→ Running migration v1.1.0 (device bans)...
✓ Migration v1.1.0 completed

========================================
Update Complete!
========================================

✓ Database migrated to v1.1.0
✓ Web console files updated
✓ Backup created: /opt/betterdesk-backup-20260105-083000
✓ Service restarted

Access the console:
  http://localhost:5000
```

---

## For Windows Users (Remote Update)

```powershell
# 1. Open PowerShell as Administrator
# 2. Navigate to project directory
cd C:\Path\To\BetterDeskConsole

# 3. Run update script with your server details (default paths)
.\update.ps1 -RemoteHost YOUR_SERVER_IP -RemoteUser YOUR_SSH_USER

# Optional: Custom RustDesk directory
.\update.ps1 -RemoteHost YOUR_SERVER_IP -RemoteUser YOUR_SSH_USER -RustDeskPath "/custom/path/rustdesk"

# Optional: Custom console directory
.\update.ps1 -RemoteHost YOUR_SERVER_IP -RemoteUser YOUR_SSH_USER -RemotePath "/var/www/betterdesk"

# Optional: All custom paths
.\update.ps1 -RemoteHost YOUR_SERVER_IP -RemoteUser YOUR_SSH_USER -RemotePath "/var/www/betterdesk" -RustDeskPath "/custom/rustdesk"
```

**Parameters:**
- `-RemoteHost` - Server IP or hostname (required)
- `-RemoteUser` - SSH username (required)
- `-RemotePath` - Console directory (default: `/opt/BetterDeskConsole`)
- `-RustDeskPath` - RustDesk directory (default: `/opt/rustdesk`)
- `-DbPath` - Database path (auto-set from RustDeskPath)

**Example Output:**
```
========================================
BetterDesk Console - Update to v1.1.0
========================================

Configuration:
  Remote host:        YOUR_SSH_USER@YOUR_SERVER_IP
  Console directory:  /opt/BetterDeskConsole
  RustDesk directory: /opt/rustdesk
  Database path:      /opt/rustdesk/db_v2.sqlite3

This update includes:
  • Soft delete system for devices (v1.0.1)
  • Device banning system (v1.1.0)
  • Enhanced UI with ban controls
  • Input validation and security improvements

⚠ This will modify the database and restart services

Continue with update? [y/N]: y

========================================
Step 1: Checking Local Files
========================================

✓ Found: v1.0.1_soft_delete.py
✓ Found: v1.1.0_device_bans.py
✓ Found: app.py
✓ Found: script.js
✓ Found: index.html

========================================
Step 2: Testing SSH Connection
========================================

→ Testing connection to YOUR_SERVER_IP...
✓ SSH connection successful
→ Checking remote installation...
✓ BetterDesk installation found on remote server

========================================
Step 3: Creating Remote Backup
========================================

→ Creating backup directory: /opt/betterdesk-backup-20260105-083500
✓ Backup created: /opt/betterdesk-backup-20260105-083500

========================================
Step 4: Uploading Migration Scripts
========================================

→ Uploading v1.0.1_soft_delete.py...
✓ Uploaded v1.0.1_soft_delete.py
→ Uploading v1.1.0_device_bans.py...
✓ Uploaded v1.1.0_device_bans.py

========================================
Step 5: Running Database Migrations
========================================

→ Executing migration v1.0.1 (soft delete)...
✓ Migration v1.0.1 completed

→ Executing migration v1.1.0 (device bans)...
✓ Migration v1.1.0 completed

========================================
Step 6: Updating Web Console Files
========================================

→ Uploading app.py...
✓ Updated app.py
→ Uploading script.js...
✓ Updated script.js
→ Uploading index.html...
✓ Updated index.html

========================================
Step 7: Restarting BetterDesk Service
========================================

✓ Service restarted successfully

========================================
Step 8: Verification
========================================

→ Verifying database schema...
✓ Database schema updated (16 columns)
→ Checking web console...
✓ Web console is responding
→ Total devices: 51
→ Banned devices: 0

========================================
Update Complete!
========================================

✓ Database migrated to v1.1.0
✓ Web console files updated
✓ Backup created: /opt/betterdesk-backup-20260105-083500
✓ Service restarted

New Features:
  • Soft delete for devices
  • Device banning system
  • Ban/Unban buttons in web interface
  • Enhanced input validation and security
  • Banned devices statistics card

Access the console:
  http://YOUR_SERVER_IP:5000
```

---

## Verification

After update, verify the installation:

### Check Web Console
Open in browser:
```
http://YOUR_SERVER_IP:5000
```

You should see:
- New "Banned" statistics card (5th card)
- Ban/Unban buttons in device list
- Visual indicators for banned devices

### Check API
```bash
curl http://localhost:5000/api/stats
```

Expected response:
```json
{
  "success": true,
  "stats": {
    "total": 51,
    "active": 14,
    "inactive": 37,
    "banned": 0,
    "with_notes": 21
  }
}
```

### Check Database Schema
```bash
sqlite3 /opt/rustdesk/db_v2.sqlite3 "PRAGMA table_info(peer);" | grep -E "is_banned|is_deleted"
```

Should show:
```
9|is_deleted|INTEGER|0||0
10|deleted_at|INTEGER|0||0
11|updated_at|INTEGER|0||0
12|is_banned|INTEGER|0||0
13|banned_at|INTEGER|0||0
14|banned_by|VARCHAR(100)|0||0
15|ban_reason|TEXT|0||0
```

---

## Rollback (If Needed)

Both scripts create automatic backups. To rollback:

```bash
# 1. Stop service
sudo systemctl stop betterdesk

# 2. Find your backup directory
ls -ltr /opt/ | grep betterdesk-backup

# 3. Restore database
sudo cp /opt/betterdesk-backup-YYYYMMDD-HHMMSS/db_v2.sqlite3.backup /opt/rustdesk/db_v2.sqlite3

# 4. Restore web files
sudo cp /opt/betterdesk-backup-YYYYMMDD-HHMMSS/app.py.backup /opt/BetterDeskConsole/app.py
sudo cp /opt/betterdesk-backup-YYYYMMDD-HHMMSS/script.js.backup /opt/BetterDeskConsole/static/script.js
sudo cp /opt/betterdesk-backup-YYYYMMDD-HHMMSS/index.html.backup /opt/BetterDeskConsole/templates/index.html

# 5. Start service
sudo systemctl start betterdesk
```

---

## Common Issues

### Permission Denied (Linux)
```bash
chmod +x update.sh
sudo ./update.sh
```

### SSH Connection Failed (Windows)
```powershell
# Test SSH manually first
ssh YOUR_SSH_USER@YOUR_SERVER_IP

# If prompted for password, set up SSH keys:
ssh-keygen
ssh-copy-id YOUR_SSH_USER@YOUR_SERVER_IP
```

### PowerShell Execution Policy
```powershell
# Allow script execution
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or run with bypass
powershell -ExecutionPolicy Bypass -File update.ps1 -RemoteHost YOUR_SERVER_IP -RemoteUser YOUR_SSH_USER
```

### Service Won't Start
```bash
# Check logs
journalctl -u betterdesk -n 50 --no-pager

# Check if port 5000 is already in use
sudo netstat -tlnp | grep 5000

# Try manual start
cd /opt/BetterDeskConsole
python3 app.py
```

---

For more help, see [UPDATE_GUIDE.md](UPDATE_GUIDE.md)
