import sqlite3

conn = sqlite3.connect('scraper.db')
c = conn.cursor()

print('Jobs (last 10):')
for row in c.execute('SELECT id, job_id, status, progress, current_city, error, created_at FROM jobs ORDER BY id DESC LIMIT 10'):
    print(row)

print('\nResults count by job:')
for row in c.execute('SELECT job_id, COUNT(*) FROM results GROUP BY job_id ORDER BY COUNT(*) DESC'):
    print(row)

print('\nJob logs (last 20):')
for row in c.execute('SELECT id, job_id, log_message, created_at FROM job_logs ORDER BY id DESC LIMIT 20'):
    print(row)

conn.close()