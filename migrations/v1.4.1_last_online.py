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

# Default database paths to try
DEFAULT_PATHS = [
    "/opt/rustdesk/db_v2.sqlite3",
    "/opt/rustdesk/db.sqlite3",
    "/var/lib/rustdesk/db_v2.sqlite3",
    os.path.expanduser("~/.rustdesk/db_v2.sqlite3"),
]

BACKUP_SUFFIX = ".backup-pre-v1.4.1"


def is_auto_mode():
    """Check if running in automatic (non-interactive) mode."""
    return os.environ.get("BETTERDESK_AUTO", "").strip() in ("1", "true", "yes")


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
    """Create backup of database before migration"""
    backup_path = db_path + BACKUP_SUFFIX

    if os.path.exists(backup_path):
        timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_path = f"{db_path}.backup-v1.4.1-{timestamp}"

    print(f"📦 Creating backup: {backup_path}")

    import shutil

    shutil.copy2(db_path, backup_path)

    print("✅ Backup created successfully")
    return backup_path


def get_column_info(cursor, table_name):
    """Get dictionary of existing columns and their types."""
    cursor.execute(f"PRAGMA table_info({table_name})")
    return {row[1]: row[2].upper() for row in cursor.fetchall()}


def add_or_fix_column(cursor, table, column, column_type, default=None):
    """Add a column or fix its type if it already exists but is wrong."""
    columns = get_column_info(cursor, table)

    if column in columns:
        current_type = columns[column]
        if current_type == column_type.upper():
            print(
                f"  ✓ Column '{column}' already exists with correct type '{column_type}'"
            )
            return False

        print(
            f"  ⚠ Column '{column}' has wrong type '{current_type}' (expected '{column_type}')"
        )
        print(f"  🔧 Dropping and recreating column '{column}'...")
        try:
            cursor.execute(f"ALTER TABLE {table} DROP COLUMN {column}")
        except sqlite3.OperationalError as e:
            print(f"  ❌ SQLite does not support DROP COLUMN: {e}")
            print(f"     Please manually fix the column type or update SQLite.")
            return False

    # Add the column (either fresh or after dropping)
    default_clause = f" DEFAULT {default}" if default is not None else ""
    sql = f"ALTER TABLE {table} ADD COLUMN {column} {column_type}{default_clause}"

    try:
        cursor.execute(sql)
        print(f"  ✓ Added/Fixed column '{column}' as {column_type}")
        return True
    except Exception as e:
        print(f"  ❌ Failed to add/fix column '{column}': {e}")
        return False


def check_if_migration_needed(conn):
    """Check if migration was already applied and is correct."""
    cursor = conn.cursor()
    columns = get_column_info(cursor, "peer")

    if "last_online" not in columns:
        return True

    # If it exists, check type
    if columns["last_online"] != "DATETIME":
        print(
            f"ℹ️  Column 'last_online' exists but has wrong type '{columns['last_online']}'"
        )
        return True

    print("✅ Migration already applied and verified (last_online is DATETIME)")
    return False


def apply_migration(conn):
    """Apply migration SQL"""
    cursor = conn.cursor()

    print("🔧 Ensuring last_online column in peer table...")
    if add_or_fix_column(cursor, "peer", "last_online", "DATETIME"):
        print("🔧 Setting last_online for currently active peers...")
        cursor.execute("""
            UPDATE peer 
            SET last_online = datetime('now') 
            WHERE status = 1 AND (is_deleted = 0 OR is_deleted IS NULL)
        """)
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

    if "last_online" not in columns:
        print("❌ Verification failed: last_online column not found")
        return False

    print(f"✅ Column last_online exists (type: {columns['last_online']})")

    # Check data integrity
    cursor.execute("""
        SELECT COUNT(*) 
        FROM peer 
        WHERE status = 1 AND last_online IS NOT NULL AND is_deleted = 0
    """)
    active_with_timestamp = cursor.fetchone()[0]

    cursor.execute("""
        SELECT COUNT(*) 
        FROM peer 
        WHERE status = 1 AND is_deleted = 0
    """)
    total_active = cursor.fetchone()[0]

    print(f"✅ Active peers with timestamp: {active_with_timestamp}/{total_active}")

    return True


def main():
    print("=" * 60)
    print("Database Migration v1.4.1 - Last Online Tracking")
    print("=" * 60)
    print()

    # Get database path
    db_path = get_database_path()

    try:
        # Connect to database
        print(f"🔌 Connecting to database: {db_path}")
        conn = sqlite3.connect(db_path)
        conn.row_factory = sqlite3.Row

        # Check if migration is needed
        if not check_if_migration_needed(conn):
            print("✅ No migration needed")
            conn.close()
            sys.exit(0)

        # Create backup
        backup_path = backup_database(db_path)

        # Confirm migration
        auto_mode = is_auto_mode()
        print()
        print("⚠️  This migration will:")
        print("   - Add last_online column to peer table")
        print("   - Set last_online timestamp for currently active peers")
        print()

        if auto_mode:
            print("ℹ Running in automatic mode (BETTERDESK_AUTO=1)")
            response = "y"
        else:
            print("Press 'y' and Enter to continue, or any other key to cancel.")
            response = input("Continue with migration? [y/N]: ").strip().lower()

        if response != "y":
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
        backup_file = (
            db_path + BACKUP_SUFFIX
            if "db_path" in locals() and os.path.exists(db_path + BACKUP_SUFFIX)
            else "backup not found"
        )
        print(f"⚠️  Restore from backup if needed: {backup_file}")
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
