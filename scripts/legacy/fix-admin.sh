#!/bin/bash
set -e

echo "🔧 BetterDesk Console - Admin Account Fix"
echo "========================================"

# Check if docker compose is available
if command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
else
    echo "❌ Docker Compose is not available. Please install docker-compose."
    exit 1
fi

echo "✅ Using: $COMPOSE_CMD"

# Check if betterdesk-console container exists and is running
if ! $COMPOSE_CMD ps | grep -q "betterdesk-console"; then
    echo "❌ BetterDesk console container not found or not running."
    echo "   Please start with: $COMPOSE_CMD up -d"
    exit 1
fi

echo "🔍 Checking database and creating admin account..."

# Run the fix script in the container
$COMPOSE_CMD exec betterdesk-console python3 -c "
import sqlite3
import secrets
import bcrypt
from datetime import datetime

DB_PATH = '/opt/rustdesk/db_v2.sqlite3'
DEFAULT_ADMIN_USERNAME = 'admin'
DEFAULT_ADMIN_PASSWORD = secrets.token_urlsafe(12)

print('📦 Checking BetterDesk Console database...')

try:
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Create tables if they don't exist
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
    
    # Check if admin user exists
    cursor.execute('SELECT id, username FROM users WHERE username = ? OR role = \"admin\"', (DEFAULT_ADMIN_USERNAME,))
    existing_admin = cursor.fetchone()
    
    if existing_admin:
        print(f'ℹ️  Admin user already exists: {existing_admin[1]}')
        print('   If you forgot the password, you can reset it from the database.')
    else:
        print('👤 Creating admin user...')
        
        # Create admin user
        salt = bcrypt.gensalt()
        password_hash = bcrypt.hashpw(DEFAULT_ADMIN_PASSWORD.encode('utf-8'), salt).decode('utf-8')
        
        cursor.execute('''
            INSERT INTO users (username, password_hash, role, created_at, is_active)
            VALUES (?, ?, 'admin', ?, 1)
        ''', (DEFAULT_ADMIN_USERNAME, password_hash, datetime.now()))
        
        conn.commit()
        
        print('✅ Admin user created successfully!')
        print('')
        print('🔐 LOGIN CREDENTIALS:')
        print('=' * 50)
        print(f'   Username: {DEFAULT_ADMIN_USERNAME}')
        print(f'   Password: {DEFAULT_ADMIN_PASSWORD}')
        print('=' * 50)
        print('')
        print('💡 Access your console at: http://localhost:5000')
        print('⚠️  IMPORTANT: Change this password after login!')
        
        # Save to file for backup
        try:
            with open('/app/data/admin_credentials.txt', 'w') as f:
                f.write(f'Username: {DEFAULT_ADMIN_USERNAME}\n')
                f.write(f'Password: {DEFAULT_ADMIN_PASSWORD}\n')
                f.write(f'Created: {datetime.now()}\n')
            print('📝 Credentials also saved to container:/app/data/admin_credentials.txt')
        except:
            pass
    
    conn.close()
    
except sqlite3.Error as e:
    print(f'❌ Database error: {e}')
    exit(1)
except Exception as e:
    print(f'❌ Error: {e}')
    exit(1)
"

echo ""
echo "✅ Fix completed! You can now access the web console."
echo "🌐 Open: http://localhost:5000"