# Security Placeholders - Configuration Guide

## 🔐 About Placeholders

This repository contains **placeholders** instead of actual server credentials for security reasons. Before using any scripts or following the documentation, you must replace these placeholders with your actual values.

---

## 📝 Placeholders Used

| Placeholder | Description | Example Value |
|------------|-------------|---------------|
| `YOUR_SERVER_IP` | Your RustDesk server IP address | `192.168.1.100` or `server.example.com` |
| `YOUR_SSH_USER` | SSH username for server access | `admin`, `rustdesk`, etc. |

---

## 🔄 How to Replace Placeholders

### Option 1: Manual Replacement (Recommended for beginners)

When you see a command like this:
```bash
ssh YOUR_SSH_USER@YOUR_SERVER_IP
```

Replace it with your actual values:
```bash
ssh admin@192.168.1.100
```

### Option 2: Global Find & Replace (For advanced users)

If you want to configure multiple files at once:

**Windows (PowerShell):**
```powershell
# Navigate to project directory
cd C:\path\to\BetterDeskConsole

# Replace server IP
(Get-ChildItem -Recurse -Include *.md,*.ps1,*.sh).ForEach{
    (Get-Content $_.FullName) -replace 'YOUR_SERVER_IP', '192.168.1.100' | 
    Set-Content $_.FullName
}

# Replace SSH user
(Get-ChildItem -Recurse -Include *.md,*.ps1,*.sh).ForEach{
    (Get-Content $_.FullName) -replace 'YOUR_SSH_USER', 'admin' | 
    Set-Content $_.FullName
}
```

**Linux/macOS:**
```bash
# Replace server IP
find . -type f \( -name "*.md" -o -name "*.ps1" -o -name "*.sh" \) \
  -exec sed -i 's/YOUR_SERVER_IP/192.168.1.100/g' {} +

# Replace SSH user
find . -type f \( -name "*.md" -o -name "*.ps1" -o -name "*.sh" \) \
  -exec sed -i 's/YOUR_SSH_USER/admin/g' {} +
```

### Option 3: Environment Variables (Most secure)

Set environment variables instead of hardcoding values:

**PowerShell:**
```powershell
$env:RUSTDESK_SERVER="192.168.1.100"
$env:RUSTDESK_USER="admin"

# Use in scripts
.\update.ps1 -RemoteHost $env:RUSTDESK_SERVER -RemoteUser $env:RUSTDESK_USER
```

**Bash:**
```bash
export RUSTDESK_SERVER="192.168.1.100"
export RUSTDESK_USER="admin"

# Use in scripts
ssh $RUSTDESK_USER@$RUSTDESK_SERVER
```

---

## 📂 Files Containing Placeholders

The following files contain placeholders that may need to be replaced:

### Documentation
- [README.md](README.md)
- [docs/UPDATE_GUIDE.md](docs/UPDATE_GUIDE.md)
- [docs/UPDATE_REFERENCE.md](docs/UPDATE_REFERENCE.md)
- [docs/QUICKSTART_UPDATE.md](docs/QUICKSTART_UPDATE.md)
- [hbbs-patch/QUICKSTART.md](hbbs-patch/QUICKSTART.md)
- [hbbs-patch/BAN_ENFORCEMENT.md](hbbs-patch/BAN_ENFORCEMENT.md)

### Scripts
- [hbbs-patch/deploy.ps1](hbbs-patch/deploy.ps1)
- [hbbs-patch/deploy-v6.ps1](hbbs-patch/deploy-v6.ps1)
- [hbbs-patch/deploy-v8.sh](hbbs-patch/deploy-v8.sh)
- [hbbs-patch/test_ban_enforcement.ps1](hbbs-patch/test_ban_enforcement.ps1)
- [hbbs-patch/diagnose_ban.ps1](hbbs-patch/diagnose_ban.ps1)
- [dev_modules/update.ps1](dev_modules/update.ps1)
- [dev_modules/test_ban_api.sh](dev_modules/test_ban_api.sh)

---

## ⚠️ Security Warnings

### DO NOT:
- ❌ Commit files with real credentials to public repositories
- ❌ Share screenshots containing real IP addresses or usernames
- ❌ Push configuration files with actual server details

### DO:
- ✅ Keep placeholders in version control
- ✅ Use environment variables for sensitive data
- ✅ Create a local `.env` file (add to `.gitignore`)
- ✅ Document your actual values in a secure password manager

---

## 🔒 Best Practices

### 1. Create a Local Configuration File

Create `.env` file (excluded from git):
```bash
# .env - DO NOT COMMIT THIS FILE
RUSTDESK_SERVER_IP=192.168.1.100
RUSTDESK_SSH_USER=admin
RUSTDESK_DB_PATH=/opt/rustdesk/db_v2.sqlite3
```

### 2. Add to .gitignore

```gitignore
# Sensitive configuration
.env
.env.local
config.local.ps1
*_local.sh
```

### 3. Use Configuration Templates

Create `config.template` files:
```powershell
# config.template.ps1
$ServerIP = "YOUR_SERVER_IP"
$SSHUser = "YOUR_SSH_USER"
```

Then copy and customize:
```powershell
Copy-Item config.template.ps1 config.local.ps1
# Edit config.local.ps1 with your values
```

---

## 🚀 Quick Start

1. **Clone the repository:**
   ```bash
   git clone https://github.com/UNITRONIX/Rustdesk-FreeConsole.git
   cd Rustdesk-FreeConsole
   ```

2. **Configure your credentials:**
   
   **Option A - Environment Variables (Recommended):**
   ```powershell
   # Windows
   $env:RUSTDESK_SERVER="192.168.1.100"
   $env:RUSTDESK_USER="admin"
   ```
   
   **Option B - Direct Replacement:**
   Follow "Option 2: Global Find & Replace" above

3. **Test connection:**
   ```bash
   ssh YOUR_SSH_USER@YOUR_SERVER_IP  # Replace placeholders!
   ```

4. **Run scripts:**
   ```powershell
   # After replacing placeholders
   .\update.ps1 -RemoteHost YOUR_SERVER_IP -RemoteUser YOUR_SSH_USER
   ```

---

## 📞 Support

If you have questions about configuration:
1. Check the [main README](README.md)
2. Review [UPDATE_GUIDE.md](docs/UPDATE_GUIDE.md)
3. See [Security Audit](hbbs-patch/SECURITY_AUDIT.md)

---

## ✅ Verification Checklist

Before running any script, verify:
- [ ] All `YOUR_SERVER_IP` replaced with actual IP
- [ ] All `YOUR_SSH_USER` replaced with actual username
- [ ] SSH connection works: `ssh YOUR_SSH_USER@YOUR_SERVER_IP`
- [ ] Server paths are correct: `/opt/rustdesk/`, `/opt/BetterDeskConsole/`
- [ ] No actual credentials committed to git

---

**Remember:** Security is not just about technology—it's about practice. Always think before you commit! 🔐
