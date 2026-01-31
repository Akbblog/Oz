import time
import json
try:
    import requests
except Exception:
    requests=None

BASE='http://127.0.0.1:8000'
cred={'username':'akb@tool.com','password':'tool.com'}

print('Logging in...')
if requests:
    s=requests.Session()
    r=s.post(f'{BASE}/api/auth/login',json=cred,timeout=10)
    print('login status',r.status_code)
    print(r.json())
    token=r.json().get('access_token')
    headers={'Authorization':f'Bearer {token}','Content-Type':'application/json'}
    payload={'category':'coffee','cities_data':['San Francisco, CA'],'max_results_per_city':5}
    print('creating job',payload)
    r2=s.post(f'{BASE}/api/jobs',json=payload,headers=headers,timeout=10)
    print('create job status',r2.status_code)
    job=r2.json().get('job_id')
    print('job id',job)
    # poll
    for i in range(60):
        r3=s.get(f'{BASE}/api/jobs/{job}',headers=headers,timeout=10)
        data=r3.json()
        print(i, data.get('status'), 'progress', data.get('progress'))
        if data.get('status') in ('completed','failed'):
            print('final logs:')
            for l in data.get('logs',[]):
                print(' -',l)
            print('results count:', len(data.get('results',[])))
            break
        time.sleep(2)
    # list debug files
    import os
    files=os.listdir('results')
    print('results dir files:', files)
else:
    print('requests not available')
