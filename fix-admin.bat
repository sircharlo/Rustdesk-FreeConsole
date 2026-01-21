@echo off
echo 🔧 BetterDesk Console - Admin Account Fix
echo ========================================

REM Check if Docker Compose is available
where docker-compose >nul 2>nul
if %errorlevel% == 0 (
    set COMPOSE_CMD=docker-compose
    goto compose_found
)

docker compose version >nul 2>nul
if %errorlevel% == 0 (
    set COMPOSE_CMD=docker compose
    goto compose_found
)

echo ❌ Docker Compose is not available. Please install docker-compose.
pause
exit /b 1

:compose_found
echo ✅ Using: %COMPOSE_CMD%

REM Check if betterdesk-console container exists
%COMPOSE_CMD% ps | findstr "betterdesk-console" >nul
if %errorlevel% neq 0 (
    echo ❌ BetterDesk console container not found or not running.
    echo    Please start with: %COMPOSE_CMD% up -d
    pause
    exit /b 1
)

echo 🔍 Checking database and creating admin account...

REM Run the fix script in the container
%COMPOSE_CMD% exec betterdesk-console python3 -c "import sqlite3; import secrets; import bcrypt; from datetime import datetime; DB_PATH = '/opt/rustdesk/db_v2.sqlite3'; DEFAULT_ADMIN_USERNAME = 'admin'; DEFAULT_ADMIN_PASSWORD = secrets.token_urlsafe(12); print('📦 Checking BetterDesk Console database...'); conn = sqlite3.connect(DB_PATH); cursor = conn.cursor(); cursor.execute('CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY AUTOINCREMENT, username VARCHAR(50) UNIQUE NOT NULL, password_hash TEXT NOT NULL, role VARCHAR(20) NOT NULL DEFAULT \"viewer\", created_at DATETIME NOT NULL, last_login DATETIME, is_active BOOLEAN NOT NULL DEFAULT 1, CHECK (role IN (\"admin\", \"operator\", \"viewer\")))'); cursor.execute('CREATE TABLE IF NOT EXISTS sessions (token VARCHAR(64) PRIMARY KEY, user_id INTEGER NOT NULL, created_at DATETIME NOT NULL, expires_at DATETIME NOT NULL, last_activity DATETIME NOT NULL, FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE)'); cursor.execute('SELECT id, username FROM users WHERE username = ? OR role = \"admin\"', (DEFAULT_ADMIN_USERNAME,)); existing_admin = cursor.fetchone(); print(f'ℹ️  Admin user already exists: {existing_admin[1]}' if existing_admin else f'👤 Creating admin user...'); salt = bcrypt.gensalt() if not existing_admin else None; password_hash = bcrypt.hashpw(DEFAULT_ADMIN_PASSWORD.encode('utf-8'), salt).decode('utf-8') if not existing_admin else None; cursor.execute('INSERT INTO users (username, password_hash, role, created_at, is_active) VALUES (?, ?, \"admin\", ?, 1)', (DEFAULT_ADMIN_USERNAME, password_hash, datetime.now())) if not existing_admin else None; conn.commit() if not existing_admin else None; print('✅ Admin user created successfully!\n🔐 LOGIN CREDENTIALS:\n' + '='*50 + f'\n   Username: {DEFAULT_ADMIN_USERNAME}\n   Password: {DEFAULT_ADMIN_PASSWORD}\n' + '='*50 + '\n\n💡 Access your console at: http://localhost:5000\n⚠️  IMPORTANT: Change this password after login!') if not existing_admin else None; conn.close()"

echo.
echo ✅ Fix completed! You can now access the web console.
echo 🌐 Open: http://localhost:5000
pause