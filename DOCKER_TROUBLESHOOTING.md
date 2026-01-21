# 🚀 Docker Quick Start for BetterDesk Console

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

---

**⚠️ IMPORTANT**: After first login, always change the default administrator password in the console settings!