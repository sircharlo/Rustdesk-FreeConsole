#!/usr/bin/env python3
"""
BetterDesk Console - Database Migration v1.1.0
Device Banning System

Adds columns to peer table for device banning functionality:
- is_banned: Flag indicating if device is banned (0=active, 1=banned)
- banned_at: Timestamp when device was banned
- banned_by: Administrator who banned the device
- ban_reason: Reason for banning the device
"""

import sqlite3
import sys
from datetime import datetime

# Database configuration
DB_PATH = '/opt/rustdesk/db_v2.sqlite3'

# ANSI color codes for terminal output
GREEN = '\033[92m'
RED = '\033[91m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
RESET = '\033[0m'

def print_header():
    """Print migration header."""
    print("=" * 60)
    print("BetterDesk Console - Database Migration v1.1.0")
    print("Device Banning System")
    print("=" * 60)
    print()

def print_success(message):
    """Print success message."""
    print(f"{GREEN}✓{RESET} {message}")

def print_error(message):
    """Print error message."""
    print(f"{RED}✗{RESET} {message}")

def print_info(message):
    """Print info message."""
    print(f"{BLUE}→{RESET} {message}")

def print_warning(message):
    """Print warning message."""
    print(f"{YELLOW}⚠{RESET} {message}")

def get_table_columns(cursor):
    """Get current columns of peer table."""
    cursor.execute("PRAGMA table_info(peer)")
    return [row[1] for row in cursor.fetchall()]

def add_column_if_not_exists(cursor, column_name, column_def):
    """Add column to peer table if it doesn't exist."""
    columns = get_table_columns(cursor)
    
    if column_name in columns:
        print(f"  • Column '{column_name}' already exists, skipping")
        return False
    
    print_info(f"Adding '{column_name}' column...")
    try:
        cursor.execute(f"ALTER TABLE peer ADD COLUMN {column_name} {column_def}")
        print_success(f"Added {column_name} column")
        return True
    except sqlite3.OperationalError as e:
        print_error(f"Failed to add {column_name}: {e}")
        return False

def main():
    """Execute database migration."""
    print_warning("This script will modify the RustDesk database")
    print(f"Database: {DB_PATH}")
    print()
    
    # Confirmation prompt
    response = input("Continue? [y/N]: ").strip().lower()
    if response != 'y':
        print("Migration cancelled.")
        sys.exit(0)
    
    print_header()
    
    try:
        # Connect to database
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        print_success(f"Connected to database: {DB_PATH}")
        
        # Check current schema
        columns_before = get_table_columns(cursor)
        print_success(f"Current columns: {', '.join(columns_before)}")
        print()
        
        # Track applied migrations
        migrations_applied = []
        
        # Add is_banned column (0=active, 1=banned)
        if add_column_if_not_exists(cursor, 'is_banned', 'INTEGER DEFAULT 0'):
            migrations_applied.append('is_banned')
        print()
        
        # Add banned_at column (timestamp)
        if add_column_if_not_exists(cursor, 'banned_at', 'INTEGER'):
            migrations_applied.append('banned_at')
        print()
        
        # Add banned_by column (who banned the device)
        if add_column_if_not_exists(cursor, 'banned_by', 'VARCHAR(100)'):
            migrations_applied.append('banned_by')
        print()
        
        # Add ban_reason column (why was it banned)
        if add_column_if_not_exists(cursor, 'ban_reason', 'TEXT'):
            migrations_applied.append('ban_reason')
        print()
        
        # Create index for performance
        print_info("Creating indexes...")
        try:
            cursor.execute("CREATE INDEX IF NOT EXISTS idx_peer_is_banned ON peer(is_banned)")
            print_success("Created index on is_banned")
            migrations_applied.append('index_is_banned')
        except sqlite3.OperationalError as e:
            print_error(f"Failed to create index: {e}")
        
        print()
        
        # Commit changes
        conn.commit()
        
        # Verify changes
        columns_after = get_table_columns(cursor)
        
        print("=" * 60)
        print("Migration Completed Successfully!")
        print("=" * 60)
        print()
        
        if migrations_applied:
            print_success(f"Applied migrations: {', '.join(migrations_applied)}")
        else:
            print_info("No new migrations applied (all columns already exist)")
        
        print()
        print_success(f"New schema: {', '.join(columns_after)}")
        
        # Close connection
        conn.close()
        
        # Additional info
        print()
        print("=" * 60)
        print("Next Steps:")
        print("=" * 60)
        print("1. Update Flask app.py with ban/unban endpoints")
        print("2. Update web UI with ban/unban buttons")
        print("3. Restart betterdesk service:")
        print("   sudo systemctl restart betterdesk")
        print()
        
    except sqlite3.Error as e:
        print_error(f"Database error: {e}")
        sys.exit(1)
    except Exception as e:
        print_error(f"Unexpected error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
