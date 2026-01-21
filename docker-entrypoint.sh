#!/bin/bash
set -e

echo "🚀 BetterDesk Console - Container Startup"
echo "========================================"

DB_PATH="/opt/rustdesk/db_v2.sqlite3"
MIGRATION_MARKER="/app/data/.migration_completed"

# Funkcja do wykonania migracji
run_migration() {
    echo "📦 Running database migration..."
    
    # Get admin credentials from environment or generate random
    ADMIN_USERNAME="${ADMIN_USERNAME:-admin}"
    ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(python3 -c 'import secrets; print(secrets.token_urlsafe(12))')}"
    
    python3 -c "
import sqlite3
import bcrypt
from datetime import datetime
import os

DB_PATH = '/opt/rustdesk/db_v2.sqlite3'
DEFAULT_ADMIN_USERNAME = os.environ.get('ADMIN_USERNAME', 'admin')
DEFAULT_ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD', '$ADMIN_PASSWORD')

if not os.path.exists(DB_PATH):
    print('⚠️  Database not found, skipping migration')
    exit(0)

# Połącz się z bazą danych
conn = sqlite3.connect(DB_PATH)
cursor = conn.cursor()

# Sprawdź czy tabela users istnieje
cursor.execute(\"SELECT name FROM sqlite_master WHERE type='table' AND name='users'\")
if cursor.fetchone():
    print('ℹ️  Migration already applied')
    exit(0)

print('🔧 Creating authentication tables...')

# Utwórz tabele autoryzacji
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

print('🔧 Creating indexes...')
cursor.execute('CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id)')
cursor.execute('CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at)')
cursor.execute('CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id)')

# Sprawdź czy admin już istnieje
cursor.execute('SELECT id FROM users WHERE username = ?', (DEFAULT_ADMIN_USERNAME,))
if cursor.fetchone():
    print('ℹ️  Admin user already exists')
else:
    # Utwórz domyślnego admina
    print('👤 Creating default admin user...')
    salt = bcrypt.gensalt()
    password_hash = bcrypt.hashpw(DEFAULT_ADMIN_PASSWORD.encode('utf-8'), salt).decode('utf-8')
    
    cursor.execute('''
        INSERT INTO users (username, password_hash, role, created_at, is_active)
        VALUES (?, ?, 'admin', ?, 1)
    ''', (DEFAULT_ADMIN_USERNAME, password_hash, datetime.now()))
    
    print('✅ Created default admin user')
    print()
    print('=' * 60)
    print('🔐 DEFAULT ADMIN CREDENTIALS:')
    print('=' * 60)
    print(f'   Username: {DEFAULT_ADMIN_USERNAME}')
    print(f'   Password: {DEFAULT_ADMIN_PASSWORD}')
    print('=' * 60)
    print('⚠️  IMPORTANT: Change this password after first login!')
    print('=' * 60)
    print()
    
    # Zapisz dane do pliku
    try:
        os.makedirs('/app/data', exist_ok=True)
        with open('/app/data/admin_credentials.txt', 'w') as f:
            f.write('=' * 60 + '\n')
            f.write('BetterDesk Console - Default Admin Credentials\n')
            f.write('=' * 60 + '\n\n')
            f.write(f'Username: {DEFAULT_ADMIN_USERNAME}\n')
            f.write(f'Password: {DEFAULT_ADMIN_PASSWORD}\n\n')
            f.write('⚠️  IMPORTANT: Change this password immediately after first login!\n')
            f.write('=' * 60 + '\n')
            f.write(f'Created: {datetime.now().strftime(\"%Y-%m-%d %H:%M:%S\")}\n')
        
        print('📝 Credentials saved to: /app/data/admin_credentials.txt')
    except Exception as e:
        print(f'⚠️  Could not save credentials file: {e}')

conn.commit()
conn.close()

print('✅ Migration completed successfully')
"
    
    # Oznacz migrację jako zakończoną
    touch "$MIGRATION_MARKER"
}

# Sprawdź czy baza danych istnieje
if [ -f "$DB_PATH" ]; then
    echo "📂 Database found: $DB_PATH"
    
    # Sprawdź czy migracja była już wykonana lub czy jest wyłączona
    if [ ! -f "$MIGRATION_MARKER" ] && [ "${SKIP_AUTO_MIGRATION:-false}" != "true" ]; then
        run_migration
    else
        if [ "${SKIP_AUTO_MIGRATION:-false}" = "true" ]; then
            echo "⏭️  Auto-migration disabled by SKIP_AUTO_MIGRATION=true"
        else
            echo "✅ Database migration already completed"
        fi
    fi
else
    echo "⚠️  Database not found: $DB_PATH"
    echo "    Waiting for HBBS to create database..."
    
    # Czekaj maksymalnie 60 sekund na utworzenie bazy
    for i in {1..60}; do
        if [ -f "$DB_PATH" ]; then
            echo "📂 Database created, running migration..."
            run_migration
            break
        fi
        echo "    Waiting for database... ($i/60)"
        sleep 1
    done
    
    if [ ! -f "$DB_PATH" ]; then
        echo "⚠️  Database still not found after 60 seconds"
        echo "    Starting application anyway..."
    fi
fi

echo ""
echo "🌟 Starting BetterDesk Console..."
echo "   Web Interface: http://localhost:5000"
echo "   Default Login: admin / (see logs above for password)"
echo ""

# Uruchom aplikację Flask
exec python3 app_v14.py