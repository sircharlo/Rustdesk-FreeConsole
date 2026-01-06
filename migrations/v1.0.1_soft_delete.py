#!/usr/bin/env python3
"""
Database Migration Script for BetterDesk Console v1.0.1
Adds soft delete and enhanced tracking columns
"""

import sqlite3
import sys
from datetime import datetime

DB_PATH = '/opt/rustdesk/db_v2.sqlite3'

def migrate_database():
    """Add new columns for enhanced functionality"""
    
    print("=" * 60)
    print("BetterDesk Console - Database Migration v1.0.1")
    print("=" * 60)
    
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # Check current schema
        cursor.execute("PRAGMA table_info(peer)")
        columns = [col[1] for col in cursor.fetchall()]
        
        print(f"\n✓ Connected to database: {DB_PATH}")
        print(f"✓ Current columns: {', '.join(columns)}")
        
        migrations_applied = []
        
        # Migration 1: Add is_deleted column
        if 'is_deleted' not in columns:
            print("\n→ Adding 'is_deleted' column...")
            cursor.execute("""
                ALTER TABLE peer ADD COLUMN is_deleted INTEGER DEFAULT 0
            """)
            migrations_applied.append("is_deleted")
            print("  ✓ Added is_deleted column")
        else:
            print("\n  ℹ Column 'is_deleted' already exists")
        
        # Migration 2: Add deleted_at column
        if 'deleted_at' not in columns:
            print("\n→ Adding 'deleted_at' column...")
            cursor.execute("""
                ALTER TABLE peer ADD COLUMN deleted_at INTEGER
            """)
            migrations_applied.append("deleted_at")
            print("  ✓ Added deleted_at column")
        else:
            print("\n  ℹ Column 'deleted_at' already exists")
        
        # Migration 3: Add updated_at column
        if 'updated_at' not in columns:
            print("\n→ Adding 'updated_at' column...")
            cursor.execute("""
                ALTER TABLE peer ADD COLUMN updated_at INTEGER
            """)
            migrations_applied.append("updated_at")
            print("  ✓ Added updated_at column")
        else:
            print("\n  ℹ Column 'updated_at' already exists")
        
        # Create index for soft delete queries
        print("\n→ Creating indexes...")
        try:
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_peer_is_deleted 
                ON peer(is_deleted)
            """)
            print("  ✓ Created index on is_deleted")
        except sqlite3.OperationalError:
            print("  ℹ Index already exists")
        
        # Commit changes
        conn.commit()
        
        print("\n" + "=" * 60)
        print("Migration Completed Successfully!")
        print("=" * 60)
        
        if migrations_applied:
            print(f"\n✓ Applied migrations: {', '.join(migrations_applied)}")
        else:
            print("\n✓ Database already up to date")
        
        # Verify changes
        cursor.execute("PRAGMA table_info(peer)")
        new_columns = [col[1] for col in cursor.fetchall()]
        print(f"\n✓ New schema: {', '.join(new_columns)}")
        
        conn.close()
        return True
        
    except sqlite3.Error as e:
        print(f"\n✗ Database error: {e}")
        return False
    except Exception as e:
        print(f"\n✗ Unexpected error: {e}")
        return False

def rollback_migration():
    """Rollback migration (not supported by SQLite ALTER TABLE)"""
    print("\n⚠ WARNING: SQLite does not support DROP COLUMN")
    print("To rollback, restore from backup:")
    print(f"  sudo systemctl stop rustdesksignal")
    print(f"  sudo cp /opt/rustdesk-backup-*/db_v2.sqlite3 {DB_PATH}")
    print(f"  sudo systemctl start rustdesksignal")

if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == '--rollback':
        rollback_migration()
        sys.exit(0)
    
    print("\n⚠ This script will modify the RustDesk database")
    print(f"Database: {DB_PATH}")
    
    response = input("\nContinue? [y/N]: ")
    if response.lower() != 'y':
        print("Migration cancelled")
        sys.exit(0)
    
    success = migrate_database()
    sys.exit(0 if success else 1)
