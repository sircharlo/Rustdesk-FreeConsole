#!/usr/bin/env python3
"""
BetterDesk Console - Database Migration v1.5.0
Fixes online status detection by adding required columns.

This migration adds:
- last_online column to peer table (for accurate online/offline detection)
- is_deleted column to peer table (for soft delete functionality)
- Ensures all ban-related columns exist

Run this script if devices show as "offline" even when they are online.

Supports automatic mode via BETTERDESK_AUTO=1 environment variable.

Usage:
    python3 v1.5.0_fix_online_status.py [database_path]
    
Default database path: /opt/rustdesk/db_v2.sqlite3
"""

import sqlite3
import sys
import os
from datetime import datetime

# Default database paths to try
DEFAULT_PATHS = [
    "/opt/rustdesk/db_v2.sqlite3",
    "/opt/rustdesk/db.sqlite3",
    "/var/lib/rustdesk/db_v2.sqlite3",
    os.path.expanduser("~/.rustdesk/db_v2.sqlite3"),
]


def is_auto_mode():
    """Check if running in automatic (non-interactive) mode."""
    return os.environ.get('BETTERDESK_AUTO', '').strip() in ('1', 'true', 'yes')


def get_database_path():
    """Get database path from argument or find it automatically."""
    if len(sys.argv) > 1:
        path = sys.argv[1]
        if os.path.exists(path):
            return path
        else:
            print(f"❌ Database not found: {path}")
            sys.exit(1)
    
    # Try default paths
    for path in DEFAULT_PATHS:
        if os.path.exists(path):
            return path
    
    print("❌ Could not find database. Please specify path:")
    print(f"   python3 {sys.argv[0]} /path/to/db_v2.sqlite3")
    sys.exit(1)


def backup_database(db_path):
    """Create a backup of the database before migration."""
    backup_path = f"{db_path}.backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    
    try:
        import shutil
        shutil.copy2(db_path, backup_path)
        print(f"✓ Backup created: {backup_path}")
        return backup_path
    except Exception as e:
        print(f"⚠ Could not create backup: {e}")
        auto_mode = is_auto_mode()
        if auto_mode:
            print("ℹ Auto mode: Continuing without backup...")
            return None
        else:
            print("Press 'y' and Enter to continue without backup, or any other key to cancel.")
            response = input("Continue without backup? [y/N] ").strip().lower()
            if response != 'y':
                sys.exit(1)
            return None


def get_existing_columns(cursor, table_name):
    """Get list of existing columns in a table."""
    cursor.execute(f"PRAGMA table_info({table_name})")
    return [row[1] for row in cursor.fetchall()]


def add_column_if_missing(cursor, table, column, column_type, default=None):
    """Add a column to a table if it doesn't exist."""
    existing = get_existing_columns(cursor, table)
    
    if column in existing:
        print(f"  ✓ Column '{column}' already exists")
        return False
    
    default_clause = f" DEFAULT {default}" if default is not None else ""
    sql = f"ALTER TABLE {table} ADD COLUMN {column} {column_type}{default_clause}"
    
    try:
        cursor.execute(sql)
        print(f"  ✓ Added column '{column}'")
        return True
    except Exception as e:
        print(f"  ❌ Failed to add column '{column}': {e}")
        return False


def create_table_if_missing(cursor, table_name, create_sql, description):
    """Create a table if it doesn't exist."""
    cursor.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        (table_name,)
    )
    
    if cursor.fetchone():
        print(f"  ✓ Table '{table_name}' already exists")
        return False
    
    try:
        cursor.execute(create_sql)
        print(f"  ✓ Created table '{table_name}' ({description})")
        return True
    except Exception as e:
        print(f"  ❌ Failed to create table '{table_name}': {e}")
        return False


def run_migration(db_path):
    """Run the database migration."""
    print(f"\n📂 Database: {db_path}")
    print("=" * 50)
    
    # Create backup
    backup_database(db_path)
    
    # Connect to database
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    changes_made = 0
    
    # ==========================================================================
    # PEER TABLE MIGRATIONS
    # ==========================================================================
    print("\n📋 Migrating 'peer' table...")
    
    # Add last_online column (critical for online status detection)
    if add_column_if_missing(cursor, "peer", "last_online", "TEXT"):
        changes_made += 1
    
    # Add is_deleted column (for soft delete)
    if add_column_if_missing(cursor, "peer", "is_deleted", "INTEGER", 0):
        changes_made += 1
    
    # Add ban-related columns
    if add_column_if_missing(cursor, "peer", "is_banned", "INTEGER", 0):
        changes_made += 1
    
    if add_column_if_missing(cursor, "peer", "banned_at", "TEXT"):
        changes_made += 1
    
    if add_column_if_missing(cursor, "peer", "banned_by", "TEXT"):
        changes_made += 1
    
    if add_column_if_missing(cursor, "peer", "ban_reason", "TEXT"):
        changes_made += 1
    
    # ==========================================================================
    # AUTH SYSTEM TABLES
    # ==========================================================================
    print("\n📋 Checking authentication tables...")
    
    # Users table
    if create_table_if_missing(cursor, "users", """
        CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            role TEXT DEFAULT 'viewer',
            is_active INTEGER DEFAULT 1,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            last_login TEXT
        )
    """, "user authentication"):
        changes_made += 1
    
    # Sessions table
    if create_table_if_missing(cursor, "sessions", """
        CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            token TEXT UNIQUE NOT NULL,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            expires_at TEXT NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id)
        )
    """, "session management"):
        changes_made += 1
    
    # Audit log table
    if create_table_if_missing(cursor, "audit_log", """
        CREATE TABLE audit_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER,
            username TEXT,
            action TEXT NOT NULL,
            target TEXT,
            details TEXT,
            ip_address TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """, "audit logging"):
        changes_made += 1
    
    # ==========================================================================
    # INDEXES
    # ==========================================================================
    print("\n📋 Checking indexes...")
    
    indexes = [
        ("idx_peer_last_online", "peer", "last_online"),
        ("idx_peer_is_deleted", "peer", "is_deleted"),
        ("idx_peer_is_banned", "peer", "is_banned"),
        ("idx_sessions_token", "sessions", "token"),
        ("idx_sessions_expires", "sessions", "expires_at"),
        ("idx_audit_created", "audit_log", "created_at"),
    ]
    
    for idx_name, table, column in indexes:
        try:
            cursor.execute(f"CREATE INDEX IF NOT EXISTS {idx_name} ON {table}({column})")
            print(f"  ✓ Index '{idx_name}' ensured")
        except Exception as e:
            print(f"  ⚠ Index '{idx_name}': {e}")
    
    # ==========================================================================
    # FINALIZE
    # ==========================================================================
    conn.commit()
    conn.close()
    
    print("\n" + "=" * 50)
    if changes_made > 0:
        print(f"✅ Migration complete! {changes_made} changes made.")
    else:
        print("✅ Database is already up to date. No changes needed.")
    
    print("\n💡 Next steps:")
    print("   1. Restart HBBS service: sudo systemctl restart hbbs")
    print("   2. Restart BetterDesk: sudo systemctl restart betterdesk")
    print("   3. Wait 15-30 seconds for devices to register")
    print("   4. Check the web console - devices should show correct status")
    
    return changes_made


def main():
    print("╔════════════════════════════════════════════════╗")
    print("║   BetterDesk Console - Database Migration      ║")
    print("║              Version 1.5.0                     ║")
    print("╚════════════════════════════════════════════════╝")
    
    db_path = get_database_path()
    run_migration(db_path)


if __name__ == "__main__":
    main()
