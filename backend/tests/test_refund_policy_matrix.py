"""Exact credit outcomes per JOB_REFUND_POLICY for every terminal path.

Runs the real runner (run_job_by_id) and settlement with a scripted scraper.
Credit config: base 10, per_city 5, per_result 1, min_job 15.
The EXPECTED table below is the documented billing behaviour (see
AUDIT_FIX_REPORT.md section "Refund policy"); change it only deliberately.
"""
import asyncio
from datetime import datetime

import pytest

# scenario -> {policy: (charged, refunded)}
EXPECTED = {
    #                      charged, refund
    "completed_full":    {"delivered": (26, 0),  "unattempted": (26, 0),  "none": (26, 0)},
    "completed_partial": {"delivered": (34, 4),  "unattempted": (34, 0),  "none": (34, 0)},
    "cancelled":         {"delivered": (34, 15), "unattempted": (34, 16), "none": (34, 0)},
    "failed_no_leads":   {"delivered": (34, 34), "unattempted": (34, 34), "none": (34, 0)},
    "failed_with_leads": {"delivered": (34, 16), "unattempted": (34, 16), "none": (34, 0)},
    "all_cities_timeout": {"delivered": (34, 34), "unattempted": (34, 34), "none": (34, 0)},
    "retried_after_crash": {"delivered": (26, 0), "unattempted": (26, 0), "none": (26, 0)},
}


def _place(n, city):
    return {"business_name": f"Biz {n}", "phone": "1", "website": "", "email": "", "address": f"{n} St",
            "category": "x", "city": city, "state": "Q",
            "google_maps_url": f"https://www.google.com/maps/place/B{n}/data=!1s0x1:0x{n:06x}"}


class Script:
    plan = {}

    def __init__(self, *a, **k):
        pass

    async def scrape_location(self, category, city, state, max_results=10, *, on_result=None,
                              should_stop=None, exclude_keys=None):
        step = Script.plan.get(city, [])
        if step == "raise":
            raise RuntimeError("browser crashed")
        hang = isinstance(step, tuple)
        places = step[0] if hang else step
        for i, n in enumerate(places[:max_results]):
            if should_stop and await should_stop():
                return []
            if on_result:
                await on_result(i, len(places), _place(n, city))
        if hang:
            await asyncio.sleep(30)
        return []

    async def close(self):
        pass


def _setup(conn, monkeypatch, policy, cities, max_results):
    import job_service
    import main
    from auth import get_password_hash

    monkeypatch.setenv("JOB_REFUND_POLICY", policy)
    monkeypatch.setattr(main, "GoogleBusinessScraper", Script)
    monkeypatch.setattr(main, "_PER_CITY_TIMEOUT", 0.3)
    cur = conn.cursor()
    cur.execute("INSERT INTO users (username, email, password_hash, is_approved, role, created_at, credit_balance) "
                "VALUES ('p', 'p@example.com', ?, 1, 'user', ?, 1000)", (get_password_hash("pw-strong-123"),
                                                                       datetime.now().isoformat()))
    conn.commit()
    uid = cur.lastrowid
    job = job_service.create_job_atomic(user_id=uid, category="x", cities=cities,
                                        max_results_per_city=max_results, idempotency_key=None)
    return uid, job["job_id"]


def _cancel(job_id):
    from database import get_db

    c = get_db()
    c.cursor().execute("UPDATE jobs SET status='cancelled' WHERE job_id = ?", (job_id,))
    c.commit()
    c.close()


def _run(job_id, worker="w1"):
    import job_service
    import main

    assert job_service.claim_job(job_id, worker)
    asyncio.run(main.run_job_by_id(job_id, worker))


@pytest.mark.parametrize("policy", ["delivered", "unattempted", "none"])
@pytest.mark.parametrize("scenario", list(EXPECTED))
def test_refund_outcome(db_connection, monkeypatch, scenario, policy):
    import job_service

    three = ["A, Q", "B, Q", "C, Q"]
    if scenario == "completed_full":
        uid, jid = _setup(db_connection, monkeypatch, policy, ["A, Q", "B, Q"], 3)
        Script.plan = {"A": [1, 2, 3], "B": [4, 5, 6]}
        _run(jid)
    elif scenario == "completed_partial":
        # B finds only 1; C times out after 1 lead -> 5 leads, 1 failed city
        uid, jid = _setup(db_connection, monkeypatch, policy, three, 3)
        Script.plan = {"A": [1, 2, 3], "B": [4], "C": ([5], "hang")}
        _run(jid)
    elif scenario == "cancelled":
        # cancelled during B after its first lead -> 4 leads saved, 1 city fully done
        uid, jid = _setup(db_connection, monkeypatch, policy, three, 3)

        async def on_b(self, category, city, state_, max_results=10, *, on_result=None, should_stop=None,
                       exclude_keys=None):
            if city == "A":
                for i, n in enumerate([1, 2, 3]):
                    await on_result(i, 3, _place(n, city))
                return []
            await on_result(0, 3, _place(4, city))
            _cancel(jid)
            for i, n in enumerate([5, 6], start=1):
                if await should_stop():
                    return []
                await on_result(i, 3, _place(n, city))
            return []
        monkeypatch.setattr(Script, "scrape_location", on_b)
        _run(jid)
    elif scenario == "failed_no_leads":
        uid, jid = _setup(db_connection, monkeypatch, policy, three, 3)
        Script.plan = {"A": "raise"}
        _run(jid)
    elif scenario == "failed_with_leads":
        uid, jid = _setup(db_connection, monkeypatch, policy, three, 3)
        Script.plan = {"A": [1, 2, 3], "B": "raise"}
        _run(jid)
    elif scenario == "all_cities_timeout":
        uid, jid = _setup(db_connection, monkeypatch, policy, three, 3)
        Script.plan = {"A": ([], "hang"), "B": ([], "hang"), "C": ([], "hang")}
        _run(jid)
    elif scenario == "retried_after_crash":
        # worker 1 finished city A then died; worker 2 resumes and finishes B
        uid, jid = _setup(db_connection, monkeypatch, policy, ["A, Q", "B, Q"], 3)
        cur = db_connection.cursor()
        for n in (1, 2, 3):
            p = _place(n, "A")
            cur.execute("INSERT INTO results (job_id, business_name, city, google_maps_url, dedupe_key) "
                        "VALUES (?, ?, 'A', ?, ?)", (jid, p["business_name"], p["google_maps_url"],
                                                      job_service.dedupe_key_for(p)))
        cur.execute("UPDATE jobs SET completed_cities = 1, attempts = 1 WHERE job_id = ?", (jid,))
        db_connection.commit()
        Script.plan = {"A": [1, 2, 3], "B": [4, 5, 6]}
        _run(jid, "w2")

    row = job_service.fetch_job_row(db_connection.cursor(), jid)
    charged, refunded = int(row["credit_charged"]), int(row["credit_refunded"])
    assert row["settled_at"], "job must be settled"
    assert (charged, refunded) == EXPECTED[scenario][policy], (scenario, policy, row["status"], charged, refunded)

    # Invariants for every policy / path
    cur = db_connection.cursor()
    cur.execute("SELECT credit_balance FROM users WHERE id = ?", (uid,))
    balance = cur.fetchone()[0]
    cur.execute("SELECT COALESCE(SUM(amount), 0) FROM credit_ledger WHERE user_id = ?", (uid,))
    assert balance == 1000 + cur.fetchone()[0] == 1000 - charged + refunded
    assert job_service.settle_job_credits(jid) == 0  # exactly once


def test_refund_policy_default_is_none(monkeypatch):
    """Refunds must be an explicit operator choice, never a deployment accident."""
    import job_service

    monkeypatch.delenv("JOB_REFUND_POLICY", raising=False)
    assert job_service.refund_policy() == "none"
    assert "not set" in job_service.refund_policy_warning()
    monkeypatch.setenv("JOB_REFUND_POLICY", "Delivered ")
    assert job_service.refund_policy() == "delivered" and job_service.refund_policy_warning() is None
    monkeypatch.setenv("JOB_REFUND_POLICY", "refund-everything")
    assert job_service.refund_policy() == "none" and "invalid" in job_service.refund_policy_warning()
