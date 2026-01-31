import sqlite3
import json
import sys

DB = 'scraper.db'
conn = sqlite3.connect(DB)
c = conn.cursor()

c.execute("SELECT id, username, email, password_hash, is_approved, is_admin, created_at, last_login FROM users ORDER BY id DESC")
rows = c.fetchall()
print(json.dumps({'users': rows}, default=str, indent=2))
conn.close()
