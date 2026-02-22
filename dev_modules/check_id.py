import sqlite3
c = sqlite3.connect('/opt/rustdesk/db_v2.sqlite3')
rows = c.execute("SELECT id, previous_ids, id_changed_at FROM peer WHERE id LIKE 'unitronix%' OR previous_ids LIKE '%1900020112%'").fetchall()
for r in rows:
    print(f"ID: {r[0]}, previous_ids: {r[1]}, changed_at: {r[2]}")
c.close()
