#!/usr/bin/env python3
"""
Database Migration Script v1.4.0 - Authentication System
Adds user management, sessions, and audit logging to BetterDesk Console
"""

import sqlite3
import sys
import os
import secrets
import bcrypt
from datetime import datetime

DB_PATH = '/opt/rustdesk/db_v2.sqlite3'
BACKUP_SUFFIX = '.backup-pre-v1.4.0'

# Default admin credentials
DEFAULT_ADMIN_USERNAME = 'admin'
DEFAULT_ADMIN_PASSWORD = secrets.token_urlsafe(12)  # Random password


def backup_database():
    """Create backup of database before migration"""
    backup_path = DB_PATH + BACKUP_SUFFIX
    
    if os.path.exists(backup_path):
        print(f"⚠️  Backup already exists: {backup_path}")
        response = input("Overwrite? [y/N]: ").strip().lower()
        if response != 'y':
            print("❌ Migration cancelled")
            sys.exit(1)
    
    print(f"📦 Creating backup: {backup_path}")
    
    # Copy database file
    import shutil
    shutil.copy2(DB_PATH, backup_path)
    
    print(f"✅ Backup created successfully")
    return backup_path


def check_if_migration_needed(conn):
    """Check if migration was already applied"""
    cursor = conn.cursor()
    
    # Check if users table exists
    cursor.execute("""
        SELECT name FROM sqlite_master 
        WHERE type='table' AND name='users'
    """)
    
    if cursor.fetchone():
        print("ℹ️  Migration already applied (users table exists)")
        return False
    
    return True


def apply_migration(conn):
    """Apply migration SQL"""
    cursor = conn.cursor()
    
    print("🔧 Creating users table...")
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
    
    print("🔧 Creating sessions table...")
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
    
    print("🔧 Creating audit_log table...")
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
    
    print("🔧 Creating indexes...")
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_sessions_expires ON sessions(expires_at)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_log(user_id)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_audit_device ON audit_log(device_id)')
    cursor.execute('CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp)')
    
    conn.commit()
    print("✅ Database schema updated")


def create_default_admin(conn):
    """Create default admin user"""
    cursor = conn.cursor()
    
    # Check if admin already exists
    cursor.execute("SELECT id FROM users WHERE username = ?", (DEFAULT_ADMIN_USERNAME,))
    if cursor.fetchone():
        print(f"ℹ️  Admin user '{DEFAULT_ADMIN_USERNAME}' already exists")
        return None
    
    print(f"👤 Creating default admin user...")
    
    # Hash password
    salt = bcrypt.gensalt()
    password_hash = bcrypt.hashpw(DEFAULT_ADMIN_PASSWORD.encode('utf-8'), salt).decode('utf-8')
    
    # Insert admin user
    cursor.execute('''
        INSERT INTO users (username, password_hash, role, created_at, is_active)
        VALUES (?, ?, 'admin', ?, 1)
    ''', (DEFAULT_ADMIN_USERNAME, password_hash, datetime.now()))
    
    conn.commit()
    
    print(f"✅ Default admin user created")
    return DEFAULT_ADMIN_PASSWORD


def save_credentials(password):
    """Save admin credentials to file"""
    creds_file = '/opt/BetterDeskConsole/admin_credentials.txt'
    
    try:
        os.makedirs(os.path.dirname(creds_file), exist_ok=True)
        
        with open(creds_file, 'w') as f:
            f.write("=" * 60 + "\n")
            f.write("BetterDesk Console - Default Admin Credentials\n")
            f.write("=" * 60 + "\n\n")
            f.write(f"Username: {DEFAULT_ADMIN_USERNAME}\n")
            f.write(f"Password: {password}\n\n")
            f.write("⚠️  IMPORTANT: Change this password immediately after first login!\n")
            f.write("=" * 60 + "\n")
            f.write(f"Created: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        
        os.chmod(creds_file, 0o600)  # Read/write for owner only
        
        print(f"📝 Credentials saved to: {creds_file}")
        
    except Exception as e:
        print(f"⚠️  Could not save credentials file: {e}")


def main():
    print("=" * 60)
    print("BetterDesk Console - Database Migration v1.4.0")
    print("Adding Authentication System")
    print("=" * 60)
    print()
    
    # Check if database exists
    if not os.path.exists(DB_PATH):
        print(f"❌ Database not found: {DB_PATH}")
        print("   Please run the installer first")
        sys.exit(1)
    
    # Create backup
    backup_path = backup_database()
    
    try:
        # Connect to database
        print(f"🔌 Connecting to database: {DB_PATH}")
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        
        # Check if migration needed
        if not check_if_migration_needed(conn):
            conn.close()
            print("\n✅ Database is already up to date")
            sys.exit(0)
        
        # Apply migration
        print("\n🚀 Starting migration...")
        apply_migration(conn)
        
        # Create default admin
        admin_password = create_default_admin(conn)
        
        conn.close()
        
        print("\n" + "=" * 60)
        print("✅ Migration completed successfully!")
        print("=" * 60)
        
        if admin_password:
            print("\n🔐 DEFAULT ADMIN CREDENTIALS:")
            print("=" * 60)
            print(f"   Username: {DEFAULT_ADMIN_USERNAME}")
            print(f"   Password: {admin_password}")
            print("=" * 60)
            print("\n⚠️  IMPORTANT:")
            print("   1. Save these credentials in a secure location")
            print("   2. Change the password immediately after first login")
            print("   3. Delete /opt/BetterDeskConsole/admin_credentials.txt after saving")
            print()
            
            save_credentials(admin_password)
        
        print(f"\n📦 Backup location: {backup_path}")
        print("   Keep this backup until you verify everything works correctly")
        print()
        
    except Exception as e:
        print(f"\n❌ Migration failed: {e}")
        print(f"\n🔄 Restoring from backup...")
        
        try:
            conn.close()
        except:
            pass
        
        # Restore backup
        import shutil
        shutil.copy2(backup_path, DB_PATH)
        
        print(f"✅ Database restored from backup")
        print(f"   Original backup preserved at: {backup_path}")
        sys.exit(1)


if __name__ == '__main__':
    main()
