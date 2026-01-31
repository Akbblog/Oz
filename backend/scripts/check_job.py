import requests, time
BASE='http://127.0.0.1:8001'
# Use admin login to get token
r = requests.post(f'{BASE}/api/auth/login', json={'username':'akb@tool.com','password':'tool.com'})
if r.status_code!=200:
    print('login failed', r.status_code, r.text); raise SystemExit
token=r.json()['access_token']
headers={'Authorization':f'Bearer {token}'}

# Create job
job_payload={'category':'coffee','cities_data':['San Francisco, CA'],'max_results_per_city':5}
r = requests.post(f'{BASE}/api/jobs', json=job_payload, headers=headers)
job = r.json()
job_id = job['job_id']
print('job created', job_id)

# Poll
for i in range(15):
    r = requests.get(f'{BASE}/api/jobs/{job_id}', headers=headers)
    data = r.json()
    print(i, 'status', data['status'], 'progress', data['progress'], 'logs', data['logs'][-1] if data['logs'] else '')
    if data['status'] in ('completed','failed'):
        print('final results count', len(data.get('results', [])))
        print('results', data.get('results', []))
        break
    time.sleep(1)
else:
    print('timed out, last status', data['status'])
