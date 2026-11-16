"""
Regression tests for the scraping-job durability fixes.

Covers: atomic + idempotent job creation, no overdraft under concurrency,
exactly-once credit settlement, cancellation, stale-worker recovery/resume,
cross-city de-duplication, partial results on per-city timeout, lease
ownership, UTC timestamps and the incremental status API.

No browser or network is used: GoogleBusinessScraper.scrape_location is faked.
"""

import asyncio
import json
import threading
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

def _insert_user(conn, username="u1", balance=1000, password="pw-strong-123"):
    from auth import get_password_hash

    cur = conn.cursor()
    cur.execute(
        "INSERT INTO users (username, email, password_hash, is_approved, is_admin, role, created_at, credit_balance) "
        "VALUES (?, ?, ?, 1, 0, 'user', ?, ?)",
        (username, f"{username}@example.com", get_password_hash(password), datetime.now().isoformat(), balance),
    )
    conn.commit()
    return cur.lastrowid


def _balance(conn, user_id):
    cur = conn.cursor()
    cur.execute("SELECT credit_balance FROM users WHERE id = ?", (user_id,))
    return cur.fetchone()[0]


def _ledger(conn, user_id):
    cur = conn.cursor()
    cur.execute("SELECT amount, transaction_type, job_id FROM credit_ledger WHERE user_id = ? ORDER BY id", (user_id,))
    return [tuple(r) for r in cur.fetchall()]


def _job(conn, job_id):
    import job_service

    return job_service.fetch_job_row(conn.cursor(), job_id)


def _create(user_id, cities=("Doha, Qatar", "Al Wakrah, Qatar"), max_results=3, key=None):
    import job_service

    return job_service.create_job_atomic(
        user_id=user_id, category="ecommerce", cities=list(cities),
        max_results_per_city=max_results, idempotency_key=key,
    )


def _place(n):
    return {
        "business_name": f"Biz {n}",
        "phone": "123",
        "website": "",
        "email": "",
        "address": f"{n} Street",
        "category": "ecommerce",
        "city": "x",
        "state": "y",
        "google_maps_url": f"https://www.google.com/maps/place/Biz+{n}/data=!4m7!3m6!1s0x3e45c{n:04x}:0x{n:08x}!8m2",
    }


def _cost(cities, max_results):
    import job_service

    return job_service.estimate_cost(cities, max_results)


# --------------------------------------------------------------------------- #
# creation: atomic + idempotent
# --------------------------------------------------------------------------- #

def test_same_idempotency_key_creates_one_job_and_one_charge(db_connection):
    uid = _insert_user(db_connection, balance=1000)
    first = _create(uid, key="client-key-0001")
    second = _create(uid, key="client-key-0001")

    assert second["job_id"] == first["job_id"]
    assert second["replayed"] is True
    cost = _cost(2, 3)
    assert _balance(db_connection, uid) == 1000 - cost
    debits = [r for r in _ledger(db_connection, uid) if r[1] == "debit"]
    assert len(debits) == 1 and debits[0][0] == -cost and debits[0][2] == first["job_id"]


def test_insufficient_credits_creates_nothing(db_connection):
    import job_service

    uid = _insert_user(db_connection, balance=5)
    with pytest.raises(job_service.JobCreateError) as exc:
        _create(uid)
    assert exc.value.status_code == 402
    cur = db_connection.cursor()
    cur.execute("SELECT COUNT(*) FROM jobs WHERE user_id = ?", (uid,))
    assert cur.fetchone()[0] == 0
    assert _balance(db_connection, uid) == 5
    assert _ledger(db_connection, uid) == []


def test_concurrent_creates_never_overdraw(db_connection):
    import job_service

    cost = _cost(2, 3)
    uid = _insert_user(db_connection, balance=cost + cost // 2)  # enough for exactly one job
    outcomes = []

    def worker(i):
        try:
            outcomes.append(_create(uid, key=f"concurrent-key-{i:04d}"))
        except job_service.JobCreateError as e:
            outcomes.append(e.status_code)

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(6)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    created = [o for o in outcomes if isinstance(o, dict)]
    assert len(created) == 1
    assert all(o in (402, 429) for o in outcomes if not isinstance(o, dict))
    assert _balance(db_connection, uid) == cost // 2
    # ledger and balance agree
    assert sum(r[0] for r in _ledger(db_connection, uid)) == -cost


def test_concurrent_job_cap_is_enforced_atomically(db_connection, monkeypatch):
    import job_service

    uid = _insert_user(db_connection, balance=100000)
    results = []

    def worker(i):
        try:
            results.append(_create(uid, key=f"cap-key-{i:05d}"))
        except job_service.JobCreateError as e:
            results.append(e.status_code)

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(5)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    from database import get_credit_config

    cap = get_credit_config()["max_concurrent_jobs"]
    assert len([r for r in results if isinstance(r, dict)]) == cap


def test_bad_idempotency_key_rejected():
    import job_service

    with pytest.raises(job_service.JobCreateError):
        job_service.normalize_idempotency_key("short")
    assert job_service.normalize_idempotency_key("  ") is None


# --------------------------------------------------------------------------- #
# refunds / settlement
# --------------------------------------------------------------------------- #

def test_refund_policy_math():
    import job_service

    cfg = {"base": 10, "per_city": 5, "per_result": 1, "min_job": 15}
    # delivered: zero leads -> full refund
    assert job_service.compute_refund(charged=460, final_status="failed", total_cities=30, attempted_cities=3,
                                      leads_delivered=0, max_results_per_city=10, cfg=cfg, policy="delivered") == 460
    # delivered: 38 leads over 4 attempted cities -> pay 10 + 20 + 38
    assert job_service.compute_refund(charged=460, final_status="cancelled", total_cities=30, attempted_cities=4,
                                      leads_delivered=38, max_results_per_city=10, cfg=cfg, policy="delivered") == 460 - 68
    # never refunds more than charged / never negative
    assert job_service.compute_refund(charged=20, final_status="completed", total_cities=1, attempted_cities=1,
                                      leads_delivered=100, max_results_per_city=10, cfg=cfg, policy="delivered") == 0
    # unattempted: 26 untouched cities x (5 + 10)
    assert job_service.compute_refund(charged=460, final_status="cancelled", total_cities=30, attempted_cities=4,
                                      leads_delivered=38, max_results_per_city=10, cfg=cfg, policy="unattempted") == 390
    assert job_service.compute_refund(charged=460, final_status="failed", total_cities=30, attempted_cities=30,
                                      leads_delivered=5, max_results_per_city=10, cfg=cfg, policy="none") == 0


def test_settlement_is_exactly_once(db_connection):
    import job_service

    uid = _insert_user(db_connection, balance=1000)
    job_id = _create(uid)["job_id"]
    cur = db_connection.cursor()
    cur.execute("UPDATE jobs SET status = 'failed' WHERE job_id = ?", (job_id,))
    db_connection.commit()

    first = job_service.settle_job_credits(job_id)
    second = job_service.settle_job_credits(job_id)
    assert first == _cost(2, 3) and second == 0
    assert _balance(db_connection, uid) == 1000
    refunds = [r for r in _ledger(db_connection, uid) if r[1] == "refund"]
    assert len(refunds) == 1


def test_settlement_ignores_active_jobs(db_connection):
    import job_service

    uid = _insert_user(db_connection)
    job_id = _create(uid)["job_id"]
    assert job_service.settle_job_credits(job_id) == 0
    assert _job(db_connection, job_id)["settled_at"] is None


# --------------------------------------------------------------------------- #
# worker ownership & recovery
# --------------------------------------------------------------------------- #

def test_claim_is_exclusive(db_connection):
    import job_service

    uid = _insert_user(db_connection)
    job_id = _create(uid)["job_id"]
    assert job_service.claim_job(job_id, "w1") is True
    assert job_service.claim_job(job_id, "w2") is False
    assert _job(db_connection, job_id)["worker_id"] == "w1"


def test_stale_running_job_is_requeued_not_failed(db_connection):
    import job_service

    uid = _insert_user(db_connection)
    job_id = _create(uid, cities=["A, X", "B, X", "C, X"])["job_id"]
    job_service.claim_job(job_id, "dead-worker")
    old = (datetime.now() - timedelta(minutes=10)).isoformat()
    cur = db_connection.cursor()
    cur.execute("UPDATE jobs SET heartbeat_at = ?, completed_cities = 2 WHERE job_id = ?", (old, job_id))
    db_connection.commit()

    requeued, failed = job_service.requeue_stale_jobs()
    assert (requeued, failed) == (1, 0)
    job = _job(db_connection, job_id)
    assert job["status"] == "pending" and job["worker_id"] is None and job["completed_cities"] == 2


def test_legacy_running_job_resume_point_comes_from_logs(db_connection):
    """Jobs started by the old code have no heartbeat/completed_cities."""
    import job_service

    uid = _insert_user(db_connection)
    job_id = _create(uid, cities=["A, X", "B, X", "C, X"])["job_id"]
    cur = db_connection.cursor()
    cur.execute("UPDATE jobs SET status = 'running', heartbeat_at = NULL, attempts = 0 WHERE job_id = ?", (job_id,))
    for city in ("A, X", "B, X"):
        cur.execute("INSERT INTO job_logs (job_id, log_message, created_at) VALUES (?, ?, ?)",
                    (job_id, f"Found 3 businesses in {city}", datetime.now().isoformat()))
    db_connection.commit()

    job_service.requeue_stale_jobs()
    assert _job(db_connection, job_id)["completed_cities"] == 2


def test_job_exceeding_attempts_is_failed_then_refunded(db_connection, monkeypatch):
    import job_service

    monkeypatch.setenv("JOB_MAX_ATTEMPTS", "2")
    uid = _insert_user(db_connection, balance=1000)
    job_id = _create(uid)["job_id"]
    cur = db_connection.cursor()
    cur.execute("UPDATE jobs SET status='running', attempts=2, heartbeat_at=? WHERE job_id=?",
                ((datetime.now() - timedelta(hours=1)).isoformat(), job_id))
    db_connection.commit()

    assert job_service.requeue_stale_jobs() == (0, 1)
    assert _job(db_connection, job_id)["status"] == "failed"
    job_service.settle_unsettled_terminal_jobs()
    assert _balance(db_connection, uid) == 1000


# --------------------------------------------------------------------------- #
# the runner itself (fake scraper)
# --------------------------------------------------------------------------- #

class FakeScraper:
    plan = {}       # city -> list of place numbers, or "hang"
    calls = []

    def __init__(self, *a, **k):
        pass

    async def scrape_location(self, category, city, state, max_results=10, *, on_result=None,
                              should_stop=None, exclude_keys=None):
        import job_service

        FakeScraper.calls.append(city)
        plan = FakeScraper.plan.get(city, [])
        hang = plan == "hang" or (isinstance(plan, tuple) and plan[1] == "hang")
        places = plan[0] if isinstance(plan, tuple) else ([] if plan == "hang" else plan)
        out = []
        for i, n in enumerate(places[:max_results]):
            if should_stop and await should_stop():
                break
            data = _place(n)
            if exclude_keys and job_service.dedupe_key_for(data) in exclude_keys:
                continue
            out.append(data)
            if on_result:
                await on_result(i, len(places), data)
        if hang:
            await asyncio.sleep(60)
        return out

    async def close(self):
        pass


@pytest.fixture
def fake_scraper(monkeypatch):
    import main

    FakeScraper.plan = {}
    FakeScraper.calls = []
    monkeypatch.setattr(main, "GoogleBusinessScraper", FakeScraper)
    monkeypatch.setattr(main, "_PER_CITY_TIMEOUT", 3.0)  # > a few DB round-trips on MySQL-in-Docker
    monkeypatch.setattr(main, "_HEARTBEAT_SECONDS", 0.05)

    async def _no_sleep(*_a, **_k):
        return None

    return FakeScraper


def _run(job_id, worker="w1"):
    import main

    asyncio.run(main.run_job_by_id(job_id, worker))


def _results(conn, job_id):
    cur = conn.cursor()
    cur.execute("SELECT business_name, city FROM results WHERE job_id = ? ORDER BY id", (job_id,))
    return cur.fetchall()


def test_runner_dedupes_across_cities_and_keeps_timeout_partials(db_connection, fake_scraper, monkeypatch):
    import job_service

    monkeypatch.setenv("JOB_REFUND_POLICY", "delivered")
    uid = _insert_user(db_connection, balance=1000)
    cities = ["Doha, Qatar", "Lusail, Qatar", "Al Khor, Qatar"]
    job_id = _create(uid, cities=cities, max_results=3)["job_id"]
    fake_scraper.plan = {
        "Doha": [1, 2, 3],
        "Lusail": [2, 3, 4],               # 2 and 3 are the same businesses as in Doha
        "Al Khor": ([5], "hang"),          # finds one lead, then the city times out
    }
    assert job_service.claim_job(job_id, "w1")
    _run(job_id)

    job = _job(db_connection, job_id)
    names = [r[0] for r in _results(db_connection, job_id)]
    assert names == ["Biz 1", "Biz 2", "Biz 3", "Biz 4", "Biz 5"]   # no duplicates, partial city kept
    assert job["status"] == "completed"
    assert job["completed_cities"] == 3 and job["failed_cities"] == 1
    assert job["settled_at"] is not None
    expected_refund = job_service.compute_refund(
        charged=_cost(3, 3), final_status="completed", total_cities=3, attempted_cities=3,
        leads_delivered=5, max_results_per_city=3)
    assert job["credit_refunded"] == expected_refund
    assert _balance(db_connection, uid) == 1000 - _cost(3, 3) + expected_refund

    cur = db_connection.cursor()
    cur.execute("SELECT log_message FROM job_logs WHERE job_id = ? ORDER BY id", (job_id,))
    logs = [r[0] for r in cur.fetchall()]
    assert any(l.startswith("Lead 1/3 in Doha") for l in logs)          # per-business activity
    assert any("Timeout scraping Al Khor" in l for l in logs)


def test_resumed_job_skips_completed_cities_and_keeps_results(db_connection, fake_scraper):
    import job_service

    uid = _insert_user(db_connection)
    cities = ["Doha, Qatar", "Lusail, Qatar"]
    job_id = _create(uid, cities=cities)["job_id"]
    fake_scraper.plan = {"Doha": [1, 2], "Lusail": [2, 7]}

    # Simulate a first worker that finished Doha and then died.
    cur = db_connection.cursor()
    cur.execute(
        "INSERT INTO results (job_id, business_name, google_maps_url, city) VALUES (?, 'Biz 1', ?, 'Doha')",
        (job_id, _place(1)["google_maps_url"]),
    )  # legacy row without dedupe_key
    cur.execute(
        "INSERT INTO results (job_id, business_name, google_maps_url, city, dedupe_key) VALUES (?, 'Biz 2', ?, 'Doha', ?)",
        (job_id, _place(2)["google_maps_url"], job_service.dedupe_key_for(_place(2))),
    )
    cur.execute("UPDATE jobs SET completed_cities = 1, attempts = 1 WHERE job_id = ?", (job_id,))
    db_connection.commit()

    assert job_service.claim_job(job_id, "w2")
    _run(job_id, "w2")

    assert fake_scraper.calls == ["Lusail"]
    assert [r[0] for r in _results(db_connection, job_id)] == ["Biz 1", "Biz 2", "Biz 7"]
    assert _job(db_connection, job_id)["status"] == "completed"


def test_worker_that_lost_its_lease_does_not_complete_the_job(db_connection, fake_scraper, monkeypatch):
    import job_service
    import main

    uid = _insert_user(db_connection)
    job_id = _create(uid, cities=["Doha, Qatar", "Lusail, Qatar"])["job_id"]
    assert job_service.claim_job(job_id, "w1")
    fake_scraper.plan = {"Doha": [1], "Lusail": [2]}

    original = FakeScraper.scrape_location

    async def steal_then_scrape(self, category, city, *a, **k):
        if city == "Lusail":
            from database import get_db

            c = get_db()
            c.cursor().execute("UPDATE jobs SET worker_id = 'w2' WHERE job_id = ?", (job_id,))
            c.commit()
            c.close()
        return await original(self, category, city, *a, **k)

    monkeypatch.setattr(FakeScraper, "scrape_location", steal_then_scrape)
    _run(job_id, "w1")

    job = _job(db_connection, job_id)
    assert job["status"] == "running" and job["worker_id"] == "w2"
    assert job["settled_at"] is None


def test_cancel_mid_run_stops_and_refunds(db_connection, fake_scraper):
    import job_service

    uid = _insert_user(db_connection, balance=1000)
    job_id = _create(uid, cities=["Doha, Qatar", "Lusail, Qatar", "Al Khor, Qatar"])["job_id"]
    fake_scraper.plan = {"Doha": [1], "Lusail": [2], "Al Khor": [3]}

    original = FakeScraper.scrape_location

    async def cancel_on_second_city(self, category, city, *a, **k):
        if city == "Lusail":
            from database import get_db

            c = get_db()
            c.cursor().execute("UPDATE jobs SET status = 'cancelled' WHERE job_id = ?", (job_id,))
            c.commit()
            c.close()
        return await original(self, category, city, *a, **k)

    FakeScraper.scrape_location = cancel_on_second_city
    try:
        assert job_service.claim_job(job_id, "w1")
        _run(job_id)
    finally:
        FakeScraper.scrape_location = original

    job = _job(db_connection, job_id)
    assert job["status"] == "cancelled"
    assert "Al Khor" not in fake_scraper.calls
    assert [r[0] for r in _results(db_connection, job_id)] == ["Biz 1"]
    assert job["settled_at"] is not None and job["credit_refunded"] > 0


def test_browser_failure_fails_job_and_refunds_in_full(db_connection, fake_scraper):
    import job_service

    uid = _insert_user(db_connection, balance=1000)
    job_id = _create(uid)["job_id"]

    async def boom(self, *a, **k):
        raise RuntimeError("chromium missing")

    original = FakeScraper.scrape_location
    FakeScraper.scrape_location = boom
    try:
        assert job_service.claim_job(job_id, "w1")
        _run(job_id)
    finally:
        FakeScraper.scrape_location = original

    job = _job(db_connection, job_id)
    assert job["status"] == "failed" and "chromium missing" in job["error"]
    assert _balance(db_connection, uid) == 1000


def test_job_runner_claims_and_runs_pending_job(db_connection, fake_scraper):
    import main
    from job_runner import JobRunner

    uid = _insert_user(db_connection)
    job_id = _create(uid, cities=["Doha, Qatar"])["job_id"]
    fake_scraper.plan = {"Doha": [1, 2]}

    async def go():
        runner = JobRunner(main.run_job_by_id, concurrency=1, worker_id="runner-1")
        started = await runner.run_once()
        assert started == 1
        while runner.active_job_ids:
            await asyncio.sleep(0.01)

    asyncio.run(go())
    assert _job(db_connection, job_id)["status"] == "completed"


# --------------------------------------------------------------------------- #
# API surface
# --------------------------------------------------------------------------- #

def _headers(client, username):
    r = client.post("/api/auth/login", json={"username": username, "password": "pw-strong-123"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_api_create_is_idempotent_and_status_is_incremental(db_connection):
    from main import app

    uid = _insert_user(db_connection, username="api_user", balance=1000)
    client = TestClient(app)
    h = _headers(client, "api_user")
    body = {"category": "ecommerce", "cities_data": ["Doha, Qatar", "Lusail, Qatar"], "max_results_per_city": 3}

    r1 = client.post("/api/jobs", json=body, headers={**h, "Idempotency-Key": "browser-retry-0001"})
    r2 = client.post("/api/jobs", json=body, headers={**h, "Idempotency-Key": "browser-retry-0001"})
    assert r1.status_code == 200 and r2.status_code == 200, (r1.text, r2.text)
    j1, j2 = r1.json(), r2.json()
    assert j1["job_id"] == j2["job_id"] and j2["idempotent_replay"] is True
    assert j1["credit_balance"] == 1000 - _cost(2, 3) == _balance(db_connection, uid)
    assert j1["logs"][:2] == ["Job created for category: ecommerce",
                              f"Credits charged: {_cost(2, 3)} (2 cities x 3 results)"]
    assert j1["created_at"].endswith("Z") and j1["server_time"].endswith("Z")
    assert j1["category"] == "ecommerce" and j1["cities"] == body["cities_data"]

    cursor = j1["next_log_cursor"]
    s = client.get(f"/api/jobs/{j1['job_id']}?include_results=false&logs_after={cursor}", headers=h).json()
    assert s["logs"] == [] and s["results"] == [] and s["result_count"] == 0
    assert s["status"] == "pending" and s["progress"] == 0

    active = client.get("/api/jobs/active", headers=h).json()["jobs"]
    assert [j["job_id"] for j in active] == [j1["job_id"]]

    listed = client.get("/api/jobs", headers=h).json()["jobs"]
    assert listed[0]["created_at"].endswith("Z")


def test_api_rejects_bad_inputs_and_insufficient_credit(db_connection):
    from main import app

    _insert_user(db_connection, username="poor", balance=1)
    client = TestClient(app)
    h = _headers(client, "poor")
    bad = client.post("/api/jobs", json={"category": "x", "cities_data": ["a, b"], "max_results_per_city": -10},
                      headers=h)
    assert bad.status_code == 422
    blank = client.post("/api/jobs", json={"category": "x", "cities_data": ["  "]}, headers=h)
    assert blank.status_code == 422
    poor = client.post("/api/jobs", json={"category": "x", "cities_data": ["a, b"]}, headers=h)
    assert poor.status_code == 402


def test_api_cancel_pending_job_refunds_immediately(db_connection):
    from main import app

    uid = _insert_user(db_connection, username="canceller", balance=1000)
    client = TestClient(app)
    h = _headers(client, "canceller")
    job = client.post("/api/jobs", json={"category": "x", "cities_data": ["a, b"]}, headers=h).json()
    r = client.post(f"/api/jobs/{job['job_id']}/cancel", headers=h)
    assert r.status_code == 200 and r.json()["status"] == "cancelled"
    assert _balance(db_connection, uid) == 1000
    again = client.post(f"/api/jobs/{job['job_id']}/cancel", headers=h).json()
    assert again["status"] == "cancelled" and _balance(db_connection, uid) == 1000


def test_users_cannot_see_or_cancel_each_others_jobs(db_connection):
    from main import app

    _insert_user(db_connection, username="alice", balance=1000)
    _insert_user(db_connection, username="mallory", balance=1000)
    client = TestClient(app)
    ha, hm = _headers(client, "alice"), _headers(client, "mallory")
    job = client.post("/api/jobs", json={"category": "x", "cities_data": ["a, b"]}, headers=ha).json()
    assert client.get(f"/api/jobs/{job['job_id']}", headers=hm).status_code == 404
    assert client.post(f"/api/jobs/{job['job_id']}/cancel", headers=hm).status_code == 404


# --------------------------------------------------------------------------- #
# small units
# --------------------------------------------------------------------------- #

def test_dedupe_key_ignores_tracking_params():
    import job_service

    a = "https://www.google.com/maps/place/Cafe/data=!4m7!3m6!1s0x3e45:0xabc!8m2!3d25.2!4d51.5?authuser=0&hl=en"
    b = "https://www.google.com/maps/place/Cafe/data=!4m7!3m6!1s0x3e45:0xabc!8m2!3d25.2!4d51.5?entry=ttu&g_ep=1"
    c = "https://www.google.com/maps/place/Other/data=!4m7!3m6!1s0x3e45:0xdef!8m2"
    k = job_service.dedupe_key_for
    assert k({"google_maps_url": a}) == k({"google_maps_url": b}) != k({"google_maps_url": c})


def test_api_timestamps_are_explicit_utc():
    import job_service

    naive_local = datetime(2026, 11, 16, 10, 0, 0)
    out = job_service.to_api_ts(naive_local.isoformat())
    assert out.endswith("Z")
    parsed = datetime.fromisoformat(out.replace("Z", "+00:00"))
    assert parsed == naive_local.astimezone()  # same instant, no offset drift
    assert job_service.to_api_ts(None) is None


def test_migration_runner_treats_duplicate_ddl_as_applied():
    from db.migration_runner import _is_already_applied_error

    class E(Exception):
        pass

    assert _is_already_applied_error(E(1060, "Duplicate column name 'x'"))
    assert _is_already_applied_error(Exception("duplicate column name: attempts"))
    assert not _is_already_applied_error(Exception("no such table: jobs"))


def test_migration_014_does_not_refund_historical_jobs(db_connection):
    """Pre-014 terminal jobs must never be swept into retroactive refunds."""
    import os
    import job_service

    uid = _insert_user(db_connection, balance=1000)
    cur = db_connection.cursor()
    for status in ("completed", "failed", "cancelled", "running"):
        cur.execute(
            "INSERT INTO jobs (job_id, user_id, category, cities_data, status, total_cities, credit_charged, "
            "created_at, settled_at) VALUES (?, ?, 'x', '[\"a, b\"]', ?, 1, 50, ?, NULL)",
            (f"legacy-{status}", uid, status, datetime.now().isoformat()),
        )
    db_connection.commit()

    # Run the data step of migration 014 exactly as shipped.
    path = os.path.join(os.path.dirname(__file__), "..", "migrations", "014_job_durability_sqlite.sql")
    update = [l for l in open(path, encoding="utf-8").read().splitlines() if l.startswith("UPDATE jobs SET settled_at")]
    assert len(update) == 1
    cur.execute(update[0])
    db_connection.commit()

    job_service.settle_unsettled_terminal_jobs()
    assert _balance(db_connection, uid) == 1000
    cur.execute("SELECT job_id, settled_at FROM jobs WHERE job_id LIKE 'legacy-%' ORDER BY job_id")
    rows = dict(cur.fetchall())
    assert rows["legacy-running"] is None          # still settles normally when it finishes
    assert all(rows[f"legacy-{s}"] == "pre-014" for s in ("completed", "failed", "cancelled"))


def test_heartbeat_with_identical_timestamp_keeps_ownership(db_connection, monkeypatch):
    """MySQL/MariaDB report 0 'changed' rows when an UPDATE rewrites the same
    value; two heartbeats inside one clock tick made a healthy worker think it
    had lost its job. Connections must count MATCHED rows (CLIENT.FOUND_ROWS)."""
    import job_service

    uid = _insert_user(db_connection)
    job_id = _create(uid)["job_id"]
    monkeypatch.setattr(job_service, "now_iso", lambda: "2026-11-16T10:00:00.000000")
    assert job_service.claim_job(job_id, "w1")
    assert job_service.heartbeat(job_id, "w1") is True
    assert job_service.heartbeat(job_id, "w1") is True  # same value again


def test_sweep_never_refunds_jobs_finished_by_old_code(db_connection):
    """Rollback then roll-forward: jobs the old code completed have
    settled_at NULL and attempts 0. The sweep must leave them alone."""
    import job_service

    uid = _insert_user(db_connection, balance=1000)
    cur = db_connection.cursor()
    cur.execute(
        "INSERT INTO jobs (job_id, user_id, category, cities_data, status, total_cities, credit_charged, created_at) "
        "VALUES ('old-code-job', ?, 'x', '[\"a, b\"]', 'completed', 1, 50, ?)",
        (uid, datetime.now().isoformat()),
    )
    db_connection.commit()
    job_service.settle_unsettled_terminal_jobs()
    assert _balance(db_connection, uid) == 1000
    assert _job(db_connection, "old-code-job")["settled_at"] is None


def test_job_row_update_after_concurrent_heartbeat_does_not_conflict(db_connection):
    """MariaDB with REPEATABLE READ + innodb_snapshot_isolation (its default)
    raised 1020 'Record has changed since last read' when a worker read the job
    row, the heartbeat thread updated it, and the worker then updated it.
    Connections must use READ COMMITTED (as production does)."""
    import job_service
    from database import get_db

    uid = _insert_user(db_connection)
    job_id = _create(uid)["job_id"]
    assert job_service.claim_job(job_id, "w1")

    a = get_db()
    try:
        ca = a.cursor()
        ca.execute("SELECT status FROM jobs WHERE job_id = ?", (job_id,))  # opens the snapshot
        assert ca.fetchone()[0] == "running"
        assert job_service.heartbeat(job_id, "w1")  # another connection changes the row
        ca.execute("UPDATE jobs SET progress = 50 WHERE job_id = ? AND worker_id = 'w1'", (job_id,))
        assert ca.rowcount == 1
        a.commit()
    finally:
        a.close()
