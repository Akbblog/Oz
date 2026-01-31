import sqlite3, json, sys
DB='scraper.db'
job=sys.argv[1]
conn=sqlite3.connect(DB)
c=conn.cursor()
c.execute('SELECT log_message, created_at FROM job_logs WHERE job_id=? ORDER BY created_at',(job,))
rows=c.fetchall()
print(json.dumps(rows, default=str, indent=2))
conn.close()
