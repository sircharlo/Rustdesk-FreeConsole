#!/usr/bin/env python3
"""
Database Migration Script v1.4.1 - Last Online Tracking
Adds last_online column to peer table for tracking device connectivity
Required for hbbs-v8-api to properly record online/offline transitions

Supports automatic mode via BETTERDESK_AUTO=1 environment variable.
"""

import sqlite3
import sys
import os
from datetime import datetime

DB_PATH = '/opt/rustdesk/db_v2.sqlite3'
BACKUP_SUFFIX = '.backup-pre-v1.4.1'


def is_auto_mode():
    """Check if running in automatic (non-interactive) mode."""
    return os.environ.get('BETTERDESK_AUTO', '').strip() in ('1', 'true', 'yes')


def backup_database():
    """Create backup of database before migration"""
    backup_path = DB_PATH + BACKUP_SUFFIX
    
    if os.path.exists(backup_path):
        timestamp = datetime.now().strftime('%Y%m%d-%H%M%S')
        backup_path = f"{DB_PATH}.backup-v1.4.1-{timestamp}"
    
    print(f"📦 Creating backup: {backup_path}")
    
    import shutil
    shutil.copy2(DB_PATH, backup_path)
    
    print(f"✅ Backup created successfully")
    return backup_path


def check_if_migration_needed(conn):
    """Check if migration was already applied"""
    cursor = conn.cursor()
    
    # Check if last_online column exists
    cursor.execute("PRAGMA table_info(peer)")
    columns = [row[1] for row in cursor.fetchall()]
    
    if 'last_online' in columns:
        print("ℹ️  Migration already applied (last_online column exists)")
        return False
    
    return True


def apply_migration(conn):
    """Apply migration SQL"""
    cursor = conn.cursor()
    
    print("🔧 Adding last_online column to peer table...")
    cursor.execute('''
        ALTER TABLE peer 
        ADD COLUMN last_online DATETIME
    ''')
    
    print("🔧 Setting last_online for currently active peers...")
    cursor.execute('''
        UPDATE peer 
        SET last_online = datetime('now') 
        WHERE status = 1 AND is_deleted = 0
    ''')
    
    rows_updated = cursor.rowcount
    print(f"✅ Updated {rows_updated} active peer(s)")
    
    conn.commit()
    print("✅ Migration applied successfully")


def verify_migration(conn):
    """Verify migration was applied correctly"""
    cursor = conn.cursor()
    
    print("🔍 Verifying migration...")
    
    # Check column exists
    cursor.execute("PRAGMA table_info(peer)")
    columns = {row[1]: row[2] for row in cursor.fetchall()}
    
    if 'last_online' not in columns:
        print("❌ Verification failed: last_online column not found")
        return False
    
    print(f"✅ Column last_online exists (type: {columns['last_online']})")
    
    # Check data integrity
    cursor.execute('''
        SELECT COUNT(*) 
        FROM peer 
        WHERE status = 1 AND last_online IS NOT NULL AND is_deleted = 0
    ''')
    active_with_timestamp = cursor.fetchone()[0]
    
    cursor.execute('''
        SELECT COUNT(*) 
        FROM peer 
        WHERE status = 1 AND is_deleted = 0
    ''')
    total_active = cursor.fetchone()[0]
    
    print(f"✅ Active peers with timestamp: {active_with_timestamp}/{total_active}")
    
    return True


def main():
    print("=" * 60)
    print("Database Migration v1.4.1 - Last Online Tracking")
    print("=" * 60)
    print()
    
    # Check if database exists
    if not os.path.exists(DB_PATH):
        print(f"❌ Database not found: {DB_PATH}")
        sys.exit(1)
    
    try:
        # Connect to database
        print(f"🔌 Connecting to database: {DB_PATH}")
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        
        # Check if migration is needed
        if not check_if_migration_needed(conn):
            print("✅ No migration needed")
            conn.close()
            sys.exit(0)
        
        # Create backup
        backup_path = backup_database()
        
        # Confirm migration
        auto_mode = is_auto_mode()
        print()
        print("⚠️  This migration will:")
        print("   - Add last_online column to peer table")
        print("   - Set last_online timestamp for currently active peers")
        print()
        
        if auto_mode:
            print("ℹ Running in automatic mode (BETTERDESK_AUTO=1)")
            response = 'y'
        else:
            print("Press 'y' and Enter to continue, or any other key to cancel.")
            response = input("Continue with migration? [y/N]: ").strip().lower()
        
        if response != 'y':
            print("❌ Migration cancelled")
            sys.exit(1)
        
        print()
        
        # Apply migration
        apply_migration(conn)
        
        # Verify migration
        if not verify_migration(conn):
            print()
            print("❌ Migration verification failed")
            print(f"⚠️  You can restore from backup: {backup_path}")
            sys.exit(1)
        
        conn.close()
        
        print()
        print("=" * 60)
        print("✅ Migration completed successfully!")
        print("=" * 60)
        print()
        print("Next steps:")
        print("1. Restart hbbs service: systemctl restart rustdesksignal")
        print("2. Restart hbbr service: systemctl restart rustdeskrelay")
        print("3. Monitor logs for errors")
        print()
        
    except Exception as e:
        print(f"❌ Migration failed: {e}")
        backup_file = DB_PATH + BACKUP_SUFFIX if os.path.exists(DB_PATH + BACKUP_SUFFIX) else "backup not found"
        print(f"⚠️  Restore from backup if needed: {backup_file}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
