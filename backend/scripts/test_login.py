import json
import sys
try:
    import requests
except Exception:
    requests=None

url='http://127.0.0.1:8001/api/auth/login'
cred={'username':'akb@tool.com','password':'tool.com'}

if requests:
    r=requests.post(url,json=cred,timeout=10)
    print('status',r.status_code)
    try:
        print(json.dumps(r.json(),indent=2))
    except Exception:
        print(r.text)
else:
    import http.client
    from urllib.parse import urlparse
    p=urlparse(url)
    conn=http.client.HTTPConnection(p.hostname,p.port,timeout=10)
    body=json.dumps(cred)
    headers={'Content-Type':'application/json'}
    conn.request('POST',p.path,body,headers)
    res=conn.getresponse()
    print('status',res.status)
    data=res.read().decode()
    try:
        print(json.dumps(json.loads(data),indent=2))
    except Exception:
        print(data)
