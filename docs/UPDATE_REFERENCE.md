# Update Scripts - Quick Reference

## 📋 Command Syntax

### Linux
```bash
sudo ./update.sh [OPTIONS]
```

### Windows
```powershell
.\update.ps1 -RemoteHost <IP> -RemoteUser <user> [OPTIONS]
```

---

## 🔧 Parameters

### Linux (update.sh)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--rustdesk-dir PATH` | RustDesk installation directory | `/opt/rustdesk` |
| `--console-dir PATH` | BetterDesk Console directory | `/opt/BetterDeskConsole` |
| `--help` | Show help message | - |

### Windows (update.ps1)

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-RemoteHost` | Server IP/hostname | **(required)** |
| `-RemoteUser` | SSH username | **(required)** |
| `-RemotePath` | BetterDesk Console directory | `/opt/BetterDeskConsole` |
| `-RustDeskPath` | RustDesk installation directory | `/opt/rustdesk` |
| `-DbPath` | Database file path | `{RustDeskPath}/db_v2.sqlite3` |

---

## 💡 Usage Examples

### Basic Update (Default Paths)

**Linux:**
```bash
sudo ./update.sh
```

**Windows:**
```powershell
.\update.ps1 -RemoteHost YOUR_SERVER_IP -RemoteUser YOUR_SSH_USER
```

---

### Custom RustDesk Directory

**Linux:**
```bash
sudo ./update.sh --rustdesk-dir /custom/rustdesk
```

**Windows:**
```powershell
.\update.ps1 -RemoteHost YOUR_SERVER_IP -RemoteUser YOUR_SSH_USER -RustDeskPath "/custom/rustdesk"
```

---

### Custom Console Directory

**Linux:**
```bash
sudo ./update.sh --console-dir /var/www/betterdesk
```

**Windows:**
```powershell
.\update.ps1 -RemoteHost YOUR_SERVER_IP -RemoteUser YOUR_SSH_USER -RemotePath "/var/www/betterdesk"
```

---

### Both Custom Directories

**Linux:**
```bash
sudo ./update.sh --rustdesk-dir /home/user/rustdesk --console-dir /home/user/console
```

**Windows:**
```powershell
.\update.ps1 -RemoteHost YOUR_SERVER_IP -RemoteUser YOUR_SSH_USER `
    -RustDeskPath "/home/user/rustdesk" `
    -RemotePath "/home/user/console"
```

---

### Custom Database Path (Windows only)

**Windows:**
```powershell
.\update.ps1 -RemoteHost YOUR_SERVER_IP -RemoteUser YOUR_SSH_USER `
    -DbPath "/custom/database/location/db.sqlite3"
```

---

## 📁 Default File Locations

### Standard Installation
```
/opt/rustdesk/
├── db_v2.sqlite3          # Database
├── hbbs                   # HBBS binary
└── id_ed25519.pub         # Public key

/opt/BetterDeskConsole/
├── app.py                 # Flask backend
├── static/
│   └── script.js         # Frontend JS
└── templates/
    └── index.html        # UI template
```

### Custom Installation Example
```
/home/admin/services/rustdesk/
└── db_v2.sqlite3

/var/www/betterdesk/
├── app.py
├── static/
└── templates/
```

---

## ✅ Quick Verification

After update, check:

```bash
# Check service
systemctl status betterdesk

# Check database columns
sqlite3 /opt/rustdesk/db_v2.sqlite3 "PRAGMA table_info(peer);" | grep -E "is_banned|is_deleted"

# Check web console
curl http://localhost:5000/api/stats
```

Expected API response:
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

---

## 🔙 Rollback

If update fails, restore from backup:

```bash
# Find backup
ls -ltr /opt/ | grep betterdesk-backup

# Restore
BACKUP_DIR="/opt/betterdesk-backup-YYYYMMDD-HHMMSS"
sudo systemctl stop betterdesk
sudo cp $BACKUP_DIR/db_v2.sqlite3.backup /opt/rustdesk/db_v2.sqlite3
sudo cp $BACKUP_DIR/*.backup /opt/BetterDeskConsole/
sudo systemctl start betterdesk
```

---

## 🆘 Troubleshooting

### Linux: Permission Denied
```bash
chmod +x update.sh
sudo ./update.sh
```

### Windows: SSH Connection Failed
```powershell
# Test connection
ssh YOUR_SSH_USER@YOUR_SERVER_IP

# Set up SSH keys
ssh-keygen
ssh-copy-id YOUR_SSH_USER@YOUR_SERVER_IP
```

### Windows: Execution Policy
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Database Migration Failed
```bash
# Check permissions
ls -l /opt/rustdesk/db_v2.sqlite3

# Run manually
sudo python3 migrations/v1.1.0_device_bans.py
```

---

## 📚 See Also

- [UPDATE_GUIDE.md](UPDATE_GUIDE.md) - Full documentation
- [QUICKSTART_UPDATE.md](QUICKSTART_UPDATE.md) - Detailed examples
- [CHANGELOG.md](CHANGELOG.md) - Version history
- [README.md](README.md) - Main documentation
