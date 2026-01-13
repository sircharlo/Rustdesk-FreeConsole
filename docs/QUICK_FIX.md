# 🔧 Quick Reference: Key Problems & Solutions

## 🚨 Most Common Issues

### Issue #1: "The keys do not match"

**Quick Fix:**
```bash
sudo bash repair-keys.sh
# Select option 5: Restore from backup
```

**If no backup exists:**
```bash
sudo bash repair-keys.sh
# Select option 4: Regenerate keys
# Then reconfigure ALL clients with new key
```

---

### Issue #2: BetterDesk Shows Wrong Key

**Cause**: Multiple `.pub` files exist, or wrong file name

**Quick Fix** (automatic with v9+):
```bash
cd /path/to/Rustdesk-FreeConsole
git pull
sudo bash install-improved.sh
# Select option to keep existing keys
```

**Manual Fix**:
```bash
# Find all .pub files
ls -lah /opt/rustdesk/*.pub

# Remove wrong ones (BACKUP FIRST!)
sudo cp -r /opt/rustdesk /opt/rustdesk-backup-manual
sudo rm /opt/rustdesk/wrong_key.pub

# Restart web console
sudo systemctl restart betterdesk
```

---

### Issue #3: Installation Broke My Working Setup

**Immediate Recovery:**
```bash
# Find most recent backup
BACKUP=$(ls -d /opt/rustdesk-backup-* | sort | tail -1)
echo "Using backup: $BACKUP"

# Stop services
sudo systemctl stop rustdesksignal rustdeskrelay betterdesk

# Restore everything
sudo cp -r $BACKUP/* /opt/rustdesk/

# Fix permissions
sudo chmod 600 /opt/rustdesk/id_ed25519
sudo chmod 644 /opt/rustdesk/*.pub

# Start services
sudo systemctl start rustdesksignal rustdeskrelay betterdesk

# Verify
cat /opt/rustdesk/id_ed25519.pub
```

---

## 📋 Pre-Installation Checklist

**Before running `install-improved.sh`:**

- [ ] Create manual backup: `sudo cp -r /opt/rustdesk /opt/rustdesk-backup-$(date +%Y%m%d)`
- [ ] Save current public key: `cat /opt/rustdesk/id_ed25519.pub > ~/rustdesk_key_backup.txt`
- [ ] Note your RustDesk directory location
- [ ] Check for multiple `.pub` files: `ls /opt/rustdesk/*.pub`
- [ ] Verify services are running: `systemctl status rustdesksignal`

**During installation:**

- ✅ Choose **automatic backup** when prompted
- ✅ Select **keep existing keys** when asked
- ❌ Don't skip backups
- ❌ Don't regenerate keys unless necessary

---

## 🐳 Docker-Specific Issues

### Docker Installation Detected

**Problem**: Script warns about Docker but you want web console only

**Solution**:
```bash
sudo bash install-improved.sh
# Select option 2: "Install ONLY Web Console for existing Docker RustDesk"
```

**Finding Docker volume path:**
```bash
# Find your RustDesk container
docker ps | grep rustdesk

# Inspect volume mounts
docker inspect <container_name> | grep -A 10 Mounts

# Typical locations:
# - /var/lib/docker/volumes/rustdesk_data/_data
# - /data (inside container)
# - Custom bind mount specified in docker-compose.yml
```

**Accessing keys in Docker:**
```bash
# Option 1: Exec into container
docker exec -it <container_name> sh
cat /data/id_ed25519.pub

# Option 2: Copy from container
docker cp <container_name>:/data/id_ed25519.pub ~/rustdesk_key.txt
cat ~/rustdesk_key.txt

# Option 3: Check volume on host
sudo cat /var/lib/docker/volumes/rustdesk_data/_data/id_ed25519.pub
```

---

## 🔧 Using repair-keys.sh

**Location**: `/path/to/Rustdesk-FreeConsole/repair-keys.sh`

**Features:**

1. **Show Info** - Display all keys and their locations
2. **Fix Permissions** - Automatically correct file permissions
3. **Export Key** - Save public key to file for distribution
4. **Regenerate** - Create new keys (last resort)
5. **Restore** - Recover from backup

**Usage:**
```bash
cd /path/to/Rustdesk-FreeConsole
sudo bash repair-keys.sh
```

---

## 📞 Emergency Contacts

**Can't Fix It? Need Help?**

1. Collect diagnostics:
```bash
sudo journalctl -u rustdesksignal -n 50 > ~/rustdesk_logs.txt
ls -lah /opt/rustdesk/*.pub >> ~/rustdesk_logs.txt
cat /opt/rustdesk/id_ed25519.pub >> ~/rustdesk_logs.txt
```

2. Create GitHub issue:
   - https://github.com/UNITRONIX/Rustdesk-FreeConsole/issues/new
   - Include output from above
   - Describe what you tried
   - Mention if this is Docker or native installation

3. Check existing issues:
   - Search for "key mismatch" or "keys do not match"
   - https://github.com/UNITRONIX/Rustdesk-FreeConsole/issues

---

## ✅ Verification After Fix

**Check everything works:**

```bash
# 1. Services running
systemctl status rustdesksignal rustdeskrelay betterdesk

# 2. Correct key displayed
cat /opt/rustdesk/id_ed25519.pub

# 3. Web console shows same key
curl -s http://localhost:5000 | grep -oP 'public-key.*?</div>' | head -1

# 4. API responding
curl -s http://localhost:21114/api/health | jq .

# 5. Test client connection
# (configure client with public key and try to connect)
```

**Expected Results:**
- ✅ All services show "active (running)"
- ✅ Public key file readable and contains valid key
- ✅ Web console shows same key as file
- ✅ API returns success
- ✅ Client connects without errors

---

## 📚 Full Documentation

For complete troubleshooting guide, see:
- [KEY_TROUBLESHOOTING.md](KEY_TROUBLESHOOTING.md) - Detailed solutions
- [INSTALLATION_V8.md](INSTALLATION_V8.md) - Installation guide
- [UPDATE_GUIDE.md](UPDATE_GUIDE.md) - Updating existing installation

---

**Last Updated**: 2026-01-13  
**Version**: BetterDesk v9+
