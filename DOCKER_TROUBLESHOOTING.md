# 🚀 Docker Quick Start for BetterDesk Console

## Problem: "Pull Access Denied" for betterdesk-hbbs / betterdesk-hbbr

### Symptom
```
! Image betterdesk-hbbs:latest pull access denied for betterdesk-hbbs, repository does not exist
! Image betterdesk-hbbr:latest pull access denied for betterdesk-hbbr, repository does not exist
Error response from daemon: pull access denied for betterdesk-hbbr, repository does not exist
```

### Cause
BetterDesk images are **NOT published to Docker Hub**. They must be **built locally** from the provided Dockerfiles.

### ✅ Solution

**Option 1: Use docker compose build**
```bash
# Build images locally first
docker compose build

# Then start services
docker compose up -d
```

**Option 2: Build and start in one command**
```bash
docker compose up -d --build
```

**Option 3: Use the quick setup script**
```bash
chmod +x docker-quickstart.sh
./docker-quickstart.sh
```

This is the expected behavior - the images are built from:
- `Dockerfile.hbbs` - Signal server with BetterDesk API
- `Dockerfile.hbbr` - Relay server
- `Dockerfile.console` - Web console

---

## Problem: Missing Admin Login Credentials

If you started BetterDesk Console using Docker Compose following "Option 2" and don't see admin login credentials in the logs, it means the **database migration was not automatically executed**.

## ✅ Quick Solution

### Step 1: Check container status
```bash
docker compose ps
docker compose logs betterdesk-console | grep -i admin
```

### Step 2: Run migration manually
```bash
# Run migration directly in the console container
docker compose exec betterdesk-console python3 -c "
import sqlite3
import secrets
import bcrypt
from datetime import datetime
import os

DB_PATH = '/opt/rustdesk/db_v2.sqlite3'
DEFAULT_ADMIN_USERNAME = 'admin'
DEFAULT_ADMIN_PASSWORD = secrets.token_urlsafe(12)

print('📦 Running BetterDesk Console migration...')

# Connect to database
conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()

# Check if users table exists
cursor.execute(\"SELECT name FROM sqlite_master WHERE type='table' AND name='users'\")
if cursor.fetchone():
    print('ℹ️  Migration already applied')
    exit(0)

print('🔧 Creating authentication tables...')

# Create authentication tables
cursor.execute('''
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username VARCHAR(50) UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        role VARCHAR(20) NOT NULL DEFAULT 'viewer',
        created_at DATETIME NOT NULL,
        last_login DATETIME,
        is_active BOOLEAN NOT NULL DEFAULT 1,
        CHECK (role IN ('admin', 'operator', 'viewer'))
    )
''')

cursor.execute('''
    CREATE TABLE IF NOT EXISTS sessions (
        token VARCHAR(64) PRIMARY KEY,
        user_id INTEGER NOT NULL,
        created_at DATETIME NOT NULL,
        expires_at DATETIME NOT NULL,
        last_activity DATETIME NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    )
''')

cursor.execute('''
    CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        action VARCHAR(50) NOT NULL,
        device_id VARCHAR(100),
        details TEXT,
        ip_address VARCHAR(50),
        timestamp DATETIME NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
    )
''')

# Check if admin already exists
cursor.execute('SELECT id FROM users WHERE username = ?', (DEFAULT_ADMIN_USERNAME,))
if cursor.fetchone():
    print('ℹ️  Admin user already exists')
else:
    # Create default admin
    print('👤 Creating default admin user...')
    salt = bcrypt.gensalt()
    password_hash = bcrypt.hashpw(DEFAULT_ADMIN_PASSWORD.encode('utf-8'), salt).decode('utf-8')
    
    cursor.execute('''
        INSERT INTO users (username, password_hash, role, created_at, is_active)
        VALUES (?, ?, 'admin', ?, 1)
    ''', (DEFAULT_ADMIN_USERNAME, password_hash, datetime.now()))
    
    print('✅ Created default admin user')
    print('')
    print('=' * 60)
    print('🔐 DEFAULT ADMIN CREDENTIALS:')
    print('=' * 60)
    print(f'   Username: {DEFAULT_ADMIN_USERNAME}')
    print(f'   Password: {DEFAULT_ADMIN_PASSWORD}')
    print('=' * 60)
    print('⚠️  IMPORTANT: Change this password after first login!')
    print('=' * 60)

conn.commit()
conn.close()
print('✅ Migration completed successfully')
"
```

### Step 3: Check the result
After running the above script you should see:
```
🔐 DEFAULT ADMIN CREDENTIALS:
============================================================
   Username: admin
   Password: XyZ1aB2cD3eF4g
============================================================
```

### Step 4: Login
1. Open browser: http://localhost:5000
2. Use credentials: `admin` / `generated-password`
3. **Immediately change password** in settings!

## 🐳 Automatic Solution (improved configuration)

To prevent this issue in the future, you can use the improved configuration:

### 1. Get improved files
Replace your current `Dockerfile.console` with the improved version that automatically runs migration.

### 2. Rebuild container
```bash
docker compose down
docker compose build betterdesk-console
docker compose up -d
```

The improved version automatically:
✅ Detects if database exists  
✅ Runs migration on first startup  
✅ Displays login credentials in container logs  
✅ Saves credentials to `/app/data/admin_credentials.txt` file

## 📋 Troubleshooting

### Problem: "Database not found"
```bash
# Check volumes
docker compose exec betterdesk-console ls -la /opt/rustdesk/

# Check if HBBS created database
docker compose exec hbbs ls -la /root/
```

### Problem: "bcrypt not available"
```bash
# Install bcrypt in container
docker compose exec betterdesk-console pip install bcrypt
```

### Problem: Container won't start
```bash
# Check logs of all containers
docker compose logs

# Check status
docker compose ps
```

## 🔧 Useful commands

```bash
# Check console container logs
docker compose logs -f betterdesk-console

# Access container
docker compose exec betterdesk-console bash

# Restart entire stack
docker compose restart

# Check database status
docker compose exec betterdesk-console sqlite3 /opt/rustdesk/db_v2.sqlite3 ".tables"

# Check users in database
docker compose exec betterdesk-console sqlite3 /opt/rustdesk/db_v2.sqlite3 "SELECT username, role FROM users;"
```

## 🔒 Security & Updates

### ⚠️ Watchtower Removed

**Important**: Watchtower has been removed from docker-compose.yml as it's **no longer maintained** and poses a security risk.

### ✅ Safe Update Methods

```bash
# Method 1: Manual updates (recommended)
docker-compose pull && docker-compose down && docker-compose up -d

# Method 2: Update specific services
docker-compose pull betterdesk-console
docker-compose up -d betterdesk-console

# Method 3: Check for updates first
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}\t{{.Size}}"
```

### 🤖 Automated Alternatives

Instead of Watchtower, consider modern secure alternatives:

1. **GitHub Dependabot** - Automatic dependency updates via PR
2. **Renovate Bot** - Advanced dependency management 
3. **Custom scripts** with notifications
4. **Kubernetes operators** (for K8s environments)

### 📅 Update Schedule

```bash
# Weekly security check (add to cron)
#!/bin/bash
cd /path/to/BetterDesk-Console
docker-compose pull --quiet
if [ $? -eq 0 ]; then
    echo "Updates available - review and apply manually"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.CreatedAt}}"
fi
```

---

**⚠️ IMPORTANT**: After first login, always change the default administrator password in the console settings!

---

## Problem: Shell Not Available in HBBS/HBBR Containers

### Symptom
When trying to exec into the hbbs or hbbr containers, you get errors like:
```
OCI runtime exec failed: exec failed: unable to start container process: exec: "sh": executable file not found in $PATH
```

### Cause
The official `rustdesk/rustdesk-server:latest` image is based on `FROM scratch` which contains only the binaries without any shell or utilities.

### Solution
BetterDesk Console now uses custom Dockerfiles (`Dockerfile.hbbs` and `Dockerfile.hbbr`) that:
1. Copy binaries from the official RustDesk image
2. Use `busybox:musl` as base for shell support
3. Provide essential tools: `sh`, `nc`, `wget`, `cat`, `ls`, `echo`, etc.

If you're upgrading from an older version, rebuild the images:
```bash
docker-compose build --no-cache hbbs hbbr
docker-compose up -d
```