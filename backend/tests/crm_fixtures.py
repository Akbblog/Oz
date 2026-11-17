"""Shared helpers for the CRM tests (imported by tests/test_crm_*.py)."""
import json
import uuid
from datetime import datetime, timedelta

import pytest

from tests.test_user_ux_api import _client_and_headers, _user


def maps_url(n, name="Biz"):
    """A Google Maps place URL carrying a feature id -> stable place key."""
    return f"https://www.google.com/maps/place/{name.replace(' ', '+')}/@25.28,51.52,17z/data=!4m6!3m5!1s0x3e45c5{n:04x}:0x{n:08x}!8m2"


class CRM:
    def __init__(self, conn):
        self.conn = conn

    def user(self, username):
        uid = _user(self.conn, username)
        client, headers = _client_and_headers(username)
        return Account(self, uid, client, headers)

    def job(self, uid, status="completed", category="cafes", cities=("Doha, Qatar",), created=None):
        job_id = str(uuid.uuid4())
        created = (created or datetime(2026, 11, 1, 9, 0)).isoformat()
        self.conn.cursor().execute(
            "INSERT INTO jobs (job_id, user_id, category, cities_data, max_results_per_city, status, progress, "
            "total_cities, created_at, credit_charged, credit_refunded, completed_cities, failed_cities, settled_at) "
            "VALUES (?, ?, ?, ?, 10, ?, 0, ?, ?, 20, 0, ?, 0, ?)",
            (job_id, uid, category, json.dumps(list(cities)), status, len(cities), created, len(cities), created),
        )
        self.conn.commit()
        return job_id

    def result(self, job_id, n, **over):
        row = {
            "business_name": f"Biz {n}", "phone": f"+974 5{n:07d}", "website": f"https://biz{n}.example.com",
            "email": f"info{n}@example.com", "address": f"{n} Corniche", "category": "cafes", "city": "Doha",
            "state": "Doha", "google_maps_url": maps_url(n), "dedupe_key": f"k{job_id[:8]}{n}",
        }
        row.update(over)
        cur = self.conn.cursor()
        cur.execute(f"INSERT INTO results (job_id, {', '.join(row)}) VALUES (?, {', '.join('?' * len(row))})",
                    (job_id, *row.values()))
        self.conn.commit()
        return int(cur.lastrowid)

    def results(self, job_id, count, start=1, **over):
        return [self.result(job_id, n, **over) for n in range(start, start + count)]


class Account:
    def __init__(self, crm, uid, client, headers):
        self.crm, self.id, self.client, self.h = crm, uid, client, headers

    def get(self, path, **params):
        return self.client.get("/api/crm" + path, params=params, headers=self.h)

    def post(self, path, body=None):
        return self.client.post("/api/crm" + path, json=body, headers=self.h)

    def patch(self, path, body):
        return self.client.patch("/api/crm" + path, json=body, headers=self.h)

    def put(self, path, body):
        return self.client.put("/api/crm" + path, json=body, headers=self.h)

    def delete(self, path):
        return self.client.delete("/api/crm" + path, headers=self.h)

    def ok(self, resp, code=200):
        assert resp.status_code == code, resp.text
        return resp.json()

    def import_ids(self, job_id, ids, key=None):
        return self.ok(self.post("/import", {"job_id": job_id, "result_ids": list(ids),
                                             "idempotency_key": key or uuid.uuid4().hex}))

    def import_all(self, job_id, key=None):
        key = key or uuid.uuid4().hex
        calls = []
        while True:
            body = self.ok(self.post("/import", {"job_id": job_id, "all": True, "idempotency_key": key}))
            calls.append(body)
            if body["done"]:
                return calls
            assert len(calls) < 50

    def record(self, record_id):
        return self.ok(self.get(f"/records/{record_id}"))

    def new_record(self, title="Manual Co", **company):
        company.setdefault("name", title)
        return self.ok(self.post("/records", {"title": title, "company": company}))


@pytest.fixture
def crm(db_connection, monkeypatch):
    from crm.common import import_limiter

    monkeypatch.setenv("CRM_ENABLED", "true")
    import_limiter.reset()
    yield CRM(db_connection)
    import_limiter.reset()


def utcnow():
    from crm.common import utcnow as _now

    return _now()


def iso(dt, offset_minutes=0):
    """Naive UTC -> aware ISO string in the given offset."""
    from datetime import timezone

    tz = timezone(timedelta(minutes=offset_minutes))
    return dt.replace(tzinfo=timezone.utc).astimezone(tz).isoformat()
