#!/usr/bin/env python3
import sqlite3

conn = sqlite3.connect('/opt/rustdesk/db_v2.sqlite3')
cursor = conn.cursor()

# Check all tables
cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = [row[0] for row in cursor.fetchall()]
print('=== Database Tables ===')
for table in tables:
    print(f'  - {table}')

print('\n=== Peer Table Schema ===')
cursor.execute('PRAGMA table_info(peer)')
columns = cursor.fetchall()
for col in columns:
    print(f'  {col[1]}: {col[2]}')

# Check if ban-related tables exist
print('\n=== Ban-related Tables ===')
ban_tables = [t for t in tables if 'ban' in t.lower()]
if ban_tables:
    print('Found:', ban_tables)
else:
    print('  No ban-related tables found')

# Check if ban-related columns exist in peer table
print('\n=== Ban-related Columns in Peer ===')
ban_columns = [col[1] for col in columns if 'ban' in col[1].lower()]
if ban_columns:
    print('Found:', ban_columns)
else:
    print('  No ban-related columns found')

conn.close()
