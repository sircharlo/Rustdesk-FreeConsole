# 🐳 Docker Support Information

## Issue: Installation Script Not Detecting Docker RustDesk

If you're running RustDesk in Docker containers, the `install-improved.sh` script will now **detect** your Docker installation and inform you.

### What Changed?

**Before:** The script searched only for native file system installations and didn't recognize Docker containers.

**Now:** The script:
- ✅ Detects running Docker containers (hbbs/hbbr)
- ⚠️ Warns you that it's designed for native installations
- 📌 Provides Docker management commands
- ❓ Asks if you want to continue anyway

### If You're Using Docker

The enhanced installer is primarily designed for **native RustDesk installations**. If you're running RustDesk in Docker, consider these options:

#### Option 1: Continue with Native Installation (Not Recommended)

You can choose to install BetterDesk Console alongside your Docker installation, but this may cause conflicts:
- Port conflicts (21115, 21116, 21117, 21120)
- Database access issues
- Service management complexity

#### Option 2: Docker-Native Management (Recommended)

Manage your Docker RustDesk directly:

```bash
# Access container
docker exec -it <container_name> /bin/sh

# View logs
docker logs <container_name>

# Restart container
docker restart <container_name>

# Check status
docker ps | grep -E "(hbbs|hbbr|rustdesk)"
```

#### Option 3: Install BetterDesk Console in Docker

If you want to use BetterDesk Console with your Docker RustDesk, consider:

1. **Mount the RustDesk database** from your Docker container to the host
2. **Install BetterDesk Console** on the host
3. **Configure it** to access the mounted database

Example Docker compose setup:
```yaml
services:
  hbbs:
    image: rustdesk/rustdesk-server
    volumes:
      - ./db:/root/.rustdesk  # Mount database
    ports:
      - "21115:21115"
      - "21116:21116/tcp"
      - "21116:21116/udp"
      - "21120:21120"  # API port
```

### Detecting Your Setup

The script now runs these checks:

```bash
# Check for Docker containers
docker ps --format "{{.Names}}" | grep -E "(hbbs|hbbr|rustdesk)"

# Check for native installation
ls -la /opt/rustdesk/hbbs 2>/dev/null
```

### Next Steps

1. **Determine your setup:** Are you using Docker or native installation?
2. **For Docker:** Use Docker management tools
3. **For native:** Run `sudo ./install-improved.sh`
4. **For hybrid:** Consider the implications carefully

## Support

If you need help deciding the best approach for your setup:
- Open an issue: https://github.com/UNITRONIX/Rustdesk-FreeConsole/issues
- Provide details about your current setup (Docker compose file, container names, etc.)

---

**Updated:** January 2026  
**Version:** v1.3.1+
