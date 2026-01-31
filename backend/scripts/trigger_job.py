import requests
import json

BASE = 'http://127.0.0.1:8001'

# login
r = requests.post(f'{BASE}/api/auth/login', json={'username':'akb@tool.com','password':'tool.com'})
print('login status', r.status_code, r.text)
if r.status_code != 200:
    raise SystemExit('Login failed')

token = r.json()['access_token']
headers = {'Authorization': f'Bearer {token}'}

# create job
job_payload = {'category':'coffee','cities_data':['San Francisco, CA'],'max_results_per_city':5}
r = requests.post(f'{BASE}/api/jobs', json=job_payload, headers=headers)
print('create job status', r.status_code)
print(r.text)
