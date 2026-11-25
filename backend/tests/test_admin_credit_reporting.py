"""Admin credit reporting (docs/ADMIN_CREDIT_REPORTING.md).

Covers ledger classification (free vs paid vs sandbox vs admin grants), job
charges and refunds written by the real job_service paths, reconciliation of
ledger to balance, pagination, time-windowed overview metrics with the mixed
timestamp formats production has, health/active-user data that is missing or
failing, and role protection of the new endpoints.

Runs on SQLite by default and on MariaDB with IL_TEST_MYSQL_URL (see conftest).
"""
import uuid
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

PW = "pw-strong-123"


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

def _user(conn, username, role="user", balance=0, created_at=None, approved=True):
    """Approved accounts look like auto-approval: approved_at = created_at, approved_by NULL."""
    from auth import get_password_hash

    created_at = created_at or datetime.now().isoformat()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO users (username, email, password_hash, is_approved, is_admin, role, created_at, credit_balance, "
        "approved_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (username, f"{username}@example.com", get_password_hash(PW), 1 if approved else 0,
         1 if role in ("admin", "owner") else 0, role, created_at, balance, created_at if approved else None),
    )
    conn.commit()
    return cur.lastrowid


def _ledger_row(conn, uid, amount, balance_after, ttype, reason, created_at=None, job_id=None, created_by=None):
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO credit_ledger (user_id, job_id, amount, balance_after, transaction_type, reason, created_at, "
        "created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (uid, job_id, amount, balance_after, ttype, reason, created_at or datetime.now().isoformat(), created_by),
    )
    conn.commit()
    return cur.lastrowid


def _set_balance(conn, uid, balance):
    cur = conn.cursor()
    cur.execute("UPDATE users SET credit_balance = ? WHERE id = ?", (balance, uid))
    conn.commit()


def _job(conn, uid, job_id=None, status="completed", charged=65, refunded=30, leads=20, created_at=None):
    job_id = job_id or str(uuid.uuid4())
    created_at = created_at or datetime.now().isoformat()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO jobs (job_id, user_id, category, cities_data, max_results_per_city, status, progress, "
        "total_cities, created_at, credit_charged, credit_refunded, completed_cities, failed_cities, settled_at) "
        "VALUES (?, ?, 'Restaurants', '[\"Doha, Qatar\"]', 50, ?, 100, 1, ?, ?, ?, 1, 0, ?)",
        (job_id, uid, status, created_at, charged, refunded, created_at),
    )
    for n in range(leads):
        cur.execute(
            "INSERT INTO results (job_id, business_name, city, state, category, google_maps_url) "
            "VALUES (?, ?, 'Doha', 'Qatar', 'Restaurants', ?)",
            (job_id, f"Biz {n}", f"https://www.google.com/maps/place/{job_id[:8]}-{n}"),
        )
    conn.commit()
    return job_id


def _h(client, username):
    r = client.post("/api/auth/login", json={"username": username, "password": PW})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest.fixture
def client(db_connection):
    from main import app

    return TestClient(app)


@pytest.fixture
def staff(db_connection):
    return {
        "owner": _user(db_connection, "own1", "owner"),
        "admin": _user(db_connection, "adm1", "admin"),
        "support": _user(db_connection, "sup1", "support"),
    }


def _report(client, uid, who="sup1", **params):
    r = client.get(f"/api/admin/users/{uid}/credit-report", params=params, headers=_h(client, who))
    assert r.status_code == 200, r.text
    return r.json()


# --------------------------------------------------------------------------- #
# classification (pure)
# --------------------------------------------------------------------------- #

@pytest.mark.parametrize("entry,payment,expected", [
    ({"transaction_type": "credit", "reason": "Starting credits on auto-approval", "amount": 100, "_signup": True},
     None, "starting_credits"),
    ({"transaction_type": "credit", "reason": "Starting credits on account approval", "amount": 100,
      "created_by": 1, "_signup": True}, None, "starting_credits"),
    # Same text without approval provenance: a staff grant, or unclassified if system-written.
    ({"transaction_type": "credit", "reason": "Starting credits on account approval", "amount": 100,
      "created_by": 1}, None, "admin_grant"),
    ({"transaction_type": "credit", "reason": "Starting credits on auto-approval", "amount": 100}, None,
     "other_credit"),
    ({"transaction_type": "credit", "reason": "Admin manual grant", "amount": 50, "created_by": 1}, None,
     "admin_grant"),
    ({"transaction_type": "credit", "reason": "Credit request approved", "amount": 50, "created_by": 1}, None,
     "admin_grant"),
    ({"transaction_type": "credit", "reason": "Safepay payment track_x", "amount": 500},
     {"status": "completed", "environment": "production", "provider": "safepay"}, "purchase"),
    # Safepay must say "production" explicitly; a missing environment is never paid.
    ({"transaction_type": "credit", "reason": "Safepay payment track_x", "amount": 500},
     {"status": "completed", "environment": None, "provider": "safepay"}, "sandbox_test"),
    ({"transaction_type": "credit", "reason": "Safepay payment track_x [sandbox]", "amount": 500},
     {"status": "completed", "environment": "sandbox"}, "sandbox_test"),
    ({"transaction_type": "credit", "reason": "Safepay payment track_x", "amount": 500}, None,
     "purchase_unverified"),
    ({"transaction_type": "credit", "reason": "Safepay payment track_x", "amount": 500},
     {"status": "pending", "environment": "production"}, "purchase_unverified"),
    ({"transaction_type": "credit", "reason": "Payment confirmed", "amount": 500},
     {"status": "completed", "environment": None}, "purchase"),
    ({"transaction_type": "credit", "reason": "mystery", "amount": 5}, None, "other_credit"),
    ({"transaction_type": "credit", "reason": "Safepay payment track_x", "amount": 500, "created_by": 1},
     {"status": "completed", "environment": "production"}, "admin_grant"),
    ({"transaction_type": "credit", "reason": "Payment confirmed", "amount": 500, "created_by": 1}, None,
     "admin_grant"),
    ({"transaction_type": "debit", "reason": "Job charge: x", "amount": -65, "job_id": "j"}, None, "job_charge"),
    ({"transaction_type": "debit", "reason": "x", "amount": -5}, None, "other_debit"),
    ({"transaction_type": "refund", "reason": "Refund for undelivered work", "amount": 30, "job_id": "j"}, None,
     "job_refund"),
    ({"transaction_type": "bonus", "reason": "Referral reward", "amount": 10}, None, "promo_bonus"),
    ({"transaction_type": "bonus", "reason": "Promo bonus credits (track_x) [sandbox]", "amount": 10}, None,
     "sandbox_test"),
    ({"transaction_type": "promotional", "reason": "Subscription renewal", "amount": 200}, None,
     "subscription_allocation"),
])
def test_classify_entry(entry, payment, expected):
    from admin_reporting import classify_entry

    entry = dict(entry)
    signup = entry.pop("_signup", False)
    assert classify_entry(entry, payment, signup=signup) == expected


def test_free_credits_and_admin_grants_are_never_purchases():
    from admin_reporting import classify_entry

    for reason, by in (("Starting credits on auto-approval", None), ("Admin manual grant", 3),
                       ("Credit request approved (bulk)", 3)):
        assert classify_entry({"transaction_type": "credit", "reason": reason, "amount": 100, "created_by": by}) \
            not in ("purchase", "sandbox_test", "purchase_unverified")


# --------------------------------------------------------------------------- #
# synthetic replica of the reported case (amounts and order only; no real data)
# --------------------------------------------------------------------------- #

def test_replica_of_reported_case_shows_the_six_headline_figures_in_order(db_connection, client, staff):
    uid = _user(db_connection, "replica_case", balance=30, created_at="2026-01-10T09:00:00")
    j1 = _job(db_connection, uid, created_at="2026-01-10T09:05:00")
    j2 = _job(db_connection, uid, created_at="2026-01-10T09:20:00")
    _ledger_row(db_connection, uid, 100, 100, "credit", "Starting credits on auto-approval", "2026-01-10T09:00:02")
    _ledger_row(db_connection, uid, -65, 35, "debit", "Job charge: Restaurants", "2026-01-10T09:05:00", j1)
    _ledger_row(db_connection, uid, 30, 65, "refund", "Refund for undelivered work (completed, 20 leads)",
                "2026-01-10T09:07:00", j1)
    _ledger_row(db_connection, uid, -65, 0, "debit", "Job charge: Restaurants", "2026-01-10T09:20:00", j2)
    _ledger_row(db_connection, uid, 30, 30, "refund", "Refund for undelivered work (completed, 20 leads)",
                "2026-01-10T09:22:00", j2)

    rep = _report(client, uid)
    s = rep["summary"]
    headline = ["starting_credits", "paid_credits", "job_charges_gross", "job_refunds", "job_charges_net",
                "current_balance"]
    assert list(s)[:6] == headline
    assert [s[k] for k in headline] == [100, 0, 130, 60, 70, 30]
    assert s["admin_grants"] == 0 and s["sandbox_test_credits"] == 0
    assert s["leads_on_file"] == 40
    assert s["net_credits_per_lead_on_file"] == 1.75
    assert rep["reconciliation"]["status"] == "reconciled"
    assert rep["reconciliation"]["ledger_sum"] == 30
    assert [t["category"] for t in rep["transactions"]] == [
        "job_refund", "job_charge", "job_refund", "job_charge", "starting_credits"]
    assert rep["transactions"][-1]["category_label"] == "Free signup credits"
    assert [t["balance_after"] for t in rep["transactions"]] == [30, 0, 65, 35, 100]
    assert all(t["chain_ok"] for t in rep["transactions"])
    assert rep["transactions"][1]["job"]["exists"] is True

    # The legacy KPI endpoint no longer calls free credits "purchased".
    k = client.get(f"/api/admin/users/{uid}/kpis", headers=_h(client, "sup1")).json()
    assert k["credits_purchased"] == 0
    assert k["credits_used"] == 70 and k["credits_charged_gross"] == 130 and k["credits_refunded"] == 60
    assert k["cost_per_result"] == 1.75


# --------------------------------------------------------------------------- #
# real writers: charges, refunds, grants, payments
# --------------------------------------------------------------------------- #

def test_real_charge_refund_and_grant_paths_reconcile(db_connection, client, staff):
    import job_service
    import main

    uid = _user(db_connection, "flow_user", balance=0)
    main.record_credit_transaction(uid, 100, 100, "credit", "Starting credits on auto-approval")
    _set_balance(db_connection, uid, 100)
    r = client.post(f"/api/admin/users/{uid}/credits", json={"amount": 400, "reason": "Pilot customer"},
                    headers=_h(client, "adm1"))
    assert r.status_code == 200, r.text

    job = job_service.create_job_atomic(user_id=uid, category="cafes", cities=["Doha, Qatar", "Al Wakrah, Qatar"],
                                        max_results_per_city=3, idempotency_key=None)
    cost = job["credit_cost"]
    cur = db_connection.cursor()
    cur.execute("UPDATE jobs SET status = 'failed' WHERE job_id = ?", (job["job_id"],))
    db_connection.commit()
    refunded = job_service.settle_job_credits(job["job_id"])
    assert refunded == cost  # failed with nothing delivered: full refund

    rep = _report(client, uid)
    s = rep["summary"]
    assert s["starting_credits"] == 100
    assert s["admin_grants"] == 400
    assert s["paid_credits"] == 0
    assert s["job_charges_gross"] == cost and s["job_refunds"] == cost and s["job_charges_net"] == 0
    assert s["current_balance"] == 500
    assert rep["reconciliation"]["status"] == "reconciled"
    grant = next(t for t in rep["transactions"] if t["category"] == "admin_grant")
    assert grant["granted_by"] == "adm1" and grant["reason"] == "Pilot customer"


def _safepay_payment(conn, uid, env, credits=500, status="pending"):
    tid = str(uuid.uuid4())
    tracker = "track_" + uuid.uuid4().hex[:12]
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO payment_transactions (transaction_id, user_id, payment_provider, provider_transaction_id, "
        "amount_cents, currency, credits_purchased, status, provider_environment, created_at) "
        "VALUES (?, ?, 'safepay', ?, 1000, 'USD', ?, ?, ?, ?)",
        (tid, uid, tracker, credits, status, env, datetime.now().strftime("%Y-%m-%d %H:%M:%S")),
    )
    conn.commit()
    return tid, tracker


def test_sandbox_payments_are_not_paid_credits_and_live_ones_are(db_connection, client, staff):
    from payments import safepay_checkout

    uid = _user(db_connection, "buyer1", balance=0)
    tid_s, tr_s = _safepay_payment(db_connection, uid, "sandbox")
    tid_p, tr_p = _safepay_payment(db_connection, uid, "production", credits=1000)
    safepay_checkout._fulfill_once(tid_s, tracker=tr_s, source="test", provider_status="PAID")
    safepay_checkout._fulfill_once(tid_p, tracker=tr_p, source="test", provider_status="PAID")

    rep = _report(client, uid)
    s = rep["summary"]
    assert s["sandbox_test_credits"] == 500
    assert s["paid_credits"] == 1000
    assert s["current_balance"] == 1500
    assert rep["reconciliation"]["status"] == "reconciled"
    rows = {t["category"]: t for t in rep["transactions"]}
    assert rows["purchase"]["payment"]["environment"] == "production"
    assert rows["sandbox_test"]["payment"]["environment"] == "sandbox"
    # Raw provider trackers never reach the admin UI.
    assert tr_s not in rows["sandbox_test"]["reason"] and tr_p not in rows["purchase"]["reason"]
    assert rows["purchase"]["reason"].startswith(f"Safepay payment #{rows['purchase']['payment']['id']}")


def test_payment_credit_without_completed_payment_is_flagged(db_connection, client, staff):
    uid = _user(db_connection, "ghost_buyer", balance=500)
    _ledger_row(db_connection, uid, 500, 500, "credit", "Safepay payment track_missing")
    s = _report(client, uid)["summary"]
    assert s["paid_credits"] == 0 and s["unverified_payment_credits"] == 500


# --------------------------------------------------------------------------- #
# reconciliation
# --------------------------------------------------------------------------- #

def test_balance_without_ledger_is_a_mismatch(db_connection, client, staff):
    uid = _user(db_connection, "drift", balance=0)
    _ledger_row(db_connection, uid, 100, 100, "credit", "Starting credits on auto-approval")
    _set_balance(db_connection, uid, 150)  # 50 credits nobody recorded
    rec = _report(client, uid)["reconciliation"]
    assert rec["status"] == "mismatch"
    assert rec["ledger_sum"] == 100 and rec["current_balance"] == 150 and rec["difference"] == 50
    assert rec["chain_breaks"] == 0


def test_chain_break_is_reported_even_when_sum_matches(db_connection, client, staff):
    uid = _user(db_connection, "chain", balance=70)
    _ledger_row(db_connection, uid, 100, 100, "credit", "Starting credits on auto-approval")
    bad = _ledger_row(db_connection, uid, -30, 90, "debit", "Job charge: x", job_id="j-missing")  # should be 70
    rep = _report(client, uid)
    rec = rep["reconciliation"]
    assert rec["status"] == "mismatch" and rec["difference"] == 0 and rec["chain_breaks"] == 1
    assert rec["first_chain_break"] == {"entry_id": bad, "expected_balance_after": 70, "recorded_balance_after": 90}
    row = next(t for t in rep["transactions"] if t["id"] == bad)
    assert row["chain_ok"] is False and row["job"] == {"job_id": "j-missing", "exists": False}
    assert rep["summary"]["charged_searches_since_deleted"] == 1


def test_empty_account(db_connection, client, staff):
    uid = _user(db_connection, "fresh", balance=0)
    rep = _report(client, uid)
    assert rep["reconciliation"]["status"] == "no_history"
    assert rep["transactions"] == [] and rep["pagination"] == {"page": 1, "page_size": 25, "total": 0, "pages": 1}
    assert rep["summary"]["net_credits_per_lead_on_file"] is None


def test_large_ledger_pagination_is_newest_first_and_totals_are_page_independent(db_connection, client, staff):
    uid = _user(db_connection, "bulk", balance=0)
    _ledger_row(db_connection, uid, 1000, 1000, "credit", "Starting credits on auto-approval")
    bal = 1000
    for i in range(130):
        bal -= 5
        _ledger_row(db_connection, uid, -5, bal, "debit", f"Job charge: {i}", job_id=f"j{i}")
    _set_balance(db_connection, uid, bal)
    p1 = _report(client, uid, page=1, page_size=50)
    p3 = _report(client, uid, page=3, page_size=50)
    assert p1["pagination"] == {"page": 1, "page_size": 50, "total": 131, "pages": 3}
    assert len(p1["transactions"]) == 50 and len(p3["transactions"]) == 31
    assert p1["transactions"][0]["balance_after"] == bal  # newest first
    assert p3["transactions"][-1]["category"] == "starting_credits"  # oldest last
    assert p1["summary"] == p3["summary"] and p1["summary"]["job_charges_gross"] == 650
    assert p1["reconciliation"]["status"] == "reconciled"
    big = _report(client, uid, page=99, page_size=1000)  # clamped
    assert big["pagination"]["page_size"] == 200 and big["pagination"]["page"] == 1


# --------------------------------------------------------------------------- #
# overview time windows
# --------------------------------------------------------------------------- #

def _ts(dt, sep="T"):
    return dt.isoformat(sep=sep)


def test_overview_windows_use_real_time_ranges_and_mixed_timestamp_formats(db_connection, client, staff):
    import admin_reporting

    now = datetime.now()
    u_recent = _user(db_connection, "recent", balance=0, created_at=_ts(now - timedelta(hours=2)))
    u_old = _user(db_connection, "older", balance=0, created_at=_ts(now - timedelta(days=3)))
    _user(db_connection, "ancient", balance=0, created_at=_ts(now - timedelta(days=40)))

    _ledger_row(db_connection, u_recent, 100, 100, "credit", "Starting credits on auto-approval",
                _ts(now - timedelta(hours=2)))
    # Same hour, space-separated (the format MySQL-side writers use): must still count.
    _ledger_row(db_connection, u_recent, -65, 35, "debit", "Job charge: x", _ts(now - timedelta(hours=1), " "),
                job_id="jr")
    _ledger_row(db_connection, u_recent, 30, 65, "refund", "Refund", _ts(now - timedelta(minutes=30), " "),
                job_id="jr")
    _ledger_row(db_connection, u_old, 100, 100, "credit", "Starting credits on auto-approval",
                _ts(now - timedelta(days=3)))
    _ledger_row(db_connection, u_old, 250, 350, "credit", "Admin manual grant", _ts(now - timedelta(days=3)),
                created_by=staff["admin"])
    _ledger_row(db_connection, u_old, -40, 310, "debit", "Job charge: y", _ts(now - timedelta(days=20)), job_id="jo")
    _job(db_connection, u_recent, created_at=_ts(now - timedelta(hours=1)), leads=3)
    _job(db_connection, u_old, created_at=_ts(now - timedelta(days=20)), status="failed", leads=0)

    def get(rng):
        r = client.get("/api/admin/overview", params={"range": rng}, headers=_h(client, "sup1"))
        assert r.status_code == 200, r.text
        return r.json()

    d24, d7, d30, dall = get("24h"), get("7d"), get("30d"), get("all")
    # staff users are created "now" by the fixture (3 of them)
    assert d24["metrics"]["new_users"] == 1 + 3
    assert d7["metrics"]["new_users"] == 2 + 3
    assert dall["metrics"]["new_users"] == 3 + 3
    assert d24["metrics"]["credits_charged_gross"] == 65
    assert d24["metrics"]["credits_refunded"] == 30 and d24["metrics"]["credits_charged_net"] == 35
    assert d24["metrics"]["starting_credits"] == 100 and d24["metrics"]["admin_grants"] == 0
    assert d7["metrics"]["starting_credits"] == 200 and d7["metrics"]["admin_grants"] == 250
    assert d7["metrics"]["credits_charged_gross"] == 65 and d30["metrics"]["credits_charged_gross"] == 105
    assert d24["metrics"]["paid_credits"] == 0
    assert d24["metrics"]["searches_started"] == 1 and d30["metrics"]["searches_started"] == 2
    assert d30["metrics"]["searches_by_status"] == {"completed": 1, "failed": 1}
    assert d24["metrics"]["leads_delivered"] == 3
    # snapshot is independent of the range
    assert d24["snapshot"] == dall["snapshot"]
    assert d24["snapshot"]["total_users"] == 6
    assert d24["window"]["label"] == "Last 24 hours" and dall["window"]["start"] is None
    assert d24["unavailable"] == []
    assert set(admin_reporting.OVERVIEW_DEFINITIONS) >= {"active_users", "credits_charged_net", "snapshot"}


def test_window_boundary_on_the_cutoff_date_with_both_timestamp_formats(db_connection, staff):
    """A plain string compare gets both rows wrong: ' ' sorts before 'T'."""
    import admin_reporting

    now = datetime(2026, 11, 25, 12, 0, 0)  # 24h cutoff = "2026-11-24 12:00:00"
    uid = _user(db_connection, "edge", balance=0)
    _ledger_row(db_connection, uid, -7, 0, "debit", "Job charge: in", "2026-11-24 13:00:00", job_id="in")
    _ledger_row(db_connection, uid, -11, 0, "debit", "Job charge: out", "2026-11-24T11:00:00.5", job_id="out")
    _ledger_row(db_connection, uid, -13, 0, "debit", "Job charge: in2", "2026-11-24T12:00:01", job_id="in2")
    _ledger_row(db_connection, uid, -17, 0, "debit", "Job charge: end", "2026-11-25 12:00:00", job_id="end")
    # After the window end: excluded, in both formats, for "all" as well.
    _ledger_row(db_connection, uid, -19, 0, "debit", "Job charge: late", "2026-11-25T12:00:01", job_id="late")
    _ledger_row(db_connection, uid, -23, 0, "debit", "Job charge: late2", "2026-11-26 08:00:00", job_id="late2")
    m = admin_reporting.get_overview_metrics("24h", now=now)["metrics"]
    assert m["credits_charged_gross"] == 7 + 13 + 17
    m_all = admin_reporting.get_overview_metrics("all", now=now)["metrics"]
    assert m_all["credits_charged_gross"] == 7 + 11 + 13 + 17


def test_window_bounds_carry_an_explicit_utc_offset():
    """Stored timestamps are naive server-local; the UI must not guess the zone."""
    import re
    import admin_reporting

    now = datetime(2026, 11, 25, 12, 0, 0)
    w = admin_reporting.window_bounds("24h", now)
    offset = re.compile(r"[+-]\d\d:\d\d$")
    assert offset.search(w["start"]) and offset.search(w["end"])
    assert datetime.fromisoformat(w["end"]).replace(tzinfo=None) == now
    assert w["_start"] == "2026-11-24 12:00:00" and w["_end"] == "2026-11-25 12:00:00"
    assert admin_reporting.window_bounds("all", now)["start"] is None


def test_overview_rejects_unknown_range(db_connection, client, staff):
    r = client.get("/api/admin/overview", params={"range": "1y"}, headers=_h(client, "sup1"))
    assert r.status_code == 422


def test_active_users_counts_distinct_audited_actors_in_window(db_connection, client, staff):
    now = datetime.now()
    cur = db_connection.cursor()
    rows = [(staff["admin"], now - timedelta(hours=1)), (staff["admin"], now - timedelta(hours=2)),
            (staff["owner"], now - timedelta(days=2)), (None, now)]
    for actor, ts in rows:
        cur.execute("INSERT INTO audit_events (request_id, actor_user_id, action, status, created_at, record_hash) "
                    "VALUES (?, ?, 'auth.login', 'success', ?, ?)",
                    (str(uuid.uuid4()), actor, ts.isoformat(), uuid.uuid4().hex))
    db_connection.commit()
    hdr = _h(client, "sup1")  # this login is itself an audited action by sup1, right now
    d24 = client.get("/api/admin/overview", params={"range": "24h"}, headers=hdr).json()
    d7 = client.get("/api/admin/overview", params={"range": "7d"}, headers=hdr).json()
    assert d24["metrics"]["active_users"] == 2  # adm1 + sup1
    assert d7["metrics"]["active_users"] == 3   # + own1


def test_failing_metric_is_reported_unavailable_not_zero(db_connection, client, staff, monkeypatch):
    import admin_reporting

    real_get_db = admin_reporting.get_db

    class _Cur:
        def __init__(self, cur):
            self._c = cur

        def execute(self, sql, params=()):
            if "audit_events" in sql:
                raise RuntimeError("audit table unavailable")
            return self._c.execute(sql, params)

        def __getattr__(self, name):
            return getattr(self._c, name)

    class _Conn:
        def __init__(self):
            self._c = real_get_db()

        def cursor(self):
            return _Cur(self._c.cursor())

        def __getattr__(self, name):
            return getattr(self._c, name)

    monkeypatch.setattr(admin_reporting, "get_db", lambda: _Conn())
    out = admin_reporting.get_overview_metrics("24h")
    assert out["metrics"]["active_users"] is None
    assert "active_users" in out["unavailable"]
    assert out["metrics"]["new_users"] is not None  # other metrics still computed


# --------------------------------------------------------------------------- #
# health
# --------------------------------------------------------------------------- #

class _Runner:
    poll_seconds = 3
    active_job_ids = ["a"]

    def __init__(self, last_ok, ok=True, error=None):
        self.last_ok_pass_at = last_ok
        self.last_pass_ok = None if last_ok is None and ok else ok
        self.last_pass_error = error


def test_health_checks_real_dependencies(db_connection):
    import time
    import admin_reporting

    h = admin_reporting.get_internal_health(_Runner(time.time()), mode="inprocess")
    assert h["checks"]["database"]["status"] == "ok"
    assert h["checks"]["migrations"]["status"] == "ok"
    assert h["checks"]["job_runner"]["status"] == "ok"
    assert h["checks"]["tunnel_connector"]["status"] == "unknown"  # never claimed without a probe
    assert h["status"] == "ok"


def test_health_reports_stale_missing_and_external_runner(db_connection):
    import time
    import admin_reporting

    stale = admin_reporting.get_internal_health(_Runner(time.time() - 600), mode="inprocess")
    assert stale["checks"]["job_runner"]["status"] == "stale" and stale["status"] == "degraded"
    missing = admin_reporting.get_internal_health(None, mode="inprocess")
    assert missing["checks"]["job_runner"]["status"] == "down" and missing["status"] == "degraded"
    never = admin_reporting.get_internal_health(_Runner(None), mode="inprocess")
    assert never["checks"]["job_runner"]["status"] == "unknown" and never["status"] == "unknown"
    ext = admin_reporting.get_internal_health(None, mode="external")
    assert ext["checks"]["job_runner"]["status"] == "unknown" and ext["status"] == "unknown"


def test_failed_scheduling_pass_prevents_ok(db_connection):
    import time
    import admin_reporting

    # A recent successful pass followed by a failed one is not OK.
    h = admin_reporting.get_internal_health(
        _Runner(time.time() - 5, ok=False, error="list pending: OperationalError"), mode="inprocess")
    assert h["checks"]["job_runner"]["status"] == "failing"
    assert "OperationalError" in h["checks"]["job_runner"]["detail"]
    assert h["status"] == "degraded"


def test_missing_migration_prevents_ok(db_connection, monkeypatch):
    import time
    import admin_reporting

    expected = admin_reporting._expected_migration_versions()
    assert admin_reporting._check_migrations(expected, expected)["status"] == "ok"
    # A gap in the middle is missing even though the newest version is applied.
    gap = [v for v in expected if v != "017"]
    chk = admin_reporting._check_migrations(gap, expected)
    assert chk["status"] == "missing" and chk["missing"] == ["017"]
    assert admin_reporting._check_migrations(None, expected)["status"] == "unknown"
    monkeypatch.setattr(admin_reporting, "_expected_migration_versions", lambda: expected + ["999"])
    h = admin_reporting.get_internal_health(_Runner(time.time()), mode="inprocess")
    assert h["checks"]["migrations"]["status"] == "missing" and h["status"] == "degraded"


def test_health_database_down_is_down_not_ok(db_connection, monkeypatch):
    import time
    import admin_reporting

    def boom():
        raise ConnectionError("db unreachable")

    monkeypatch.setattr(admin_reporting, "get_db", boom)
    h = admin_reporting.get_internal_health(_Runner(time.time()), mode="inprocess")
    assert h["status"] == "down"
    assert h["checks"]["database"]["status"] == "down"
    assert h["checks"]["migrations"]["status"] == "unknown"


def test_health_tunnel_probe_failure_is_down(db_connection, monkeypatch):
    import admin_reporting

    monkeypatch.setenv("TUNNEL_METRICS_URL", "http://127.0.0.1:9")  # nothing listens on the discard port
    t = admin_reporting._check_tunnel()
    assert t["status"] == "down"


def test_runner_records_failed_and_successful_passes(db_connection, monkeypatch):
    import asyncio
    import job_service
    from job_runner import JobRunner

    async def noop(job_id, worker_id):
        return None

    runner = JobRunner(noop, concurrency=1, poll_seconds=1)
    assert runner.last_pass_ok is None and runner.last_ok_pass_at is None
    asyncio.run(runner.run_once())
    assert runner.last_pass_ok is True and runner.last_ok_pass_at is not None
    ok_at = runner.last_ok_pass_at

    def broken(*a, **k):
        raise RuntimeError("db gone")

    monkeypatch.setattr(job_service, "list_claimable_job_ids", broken)
    asyncio.run(runner.run_once())
    assert runner.last_pass_ok is False and "list pending" in runner.last_pass_error
    assert runner.last_ok_pass_at == ok_at  # a failed pass never refreshes the OK timestamp


# --------------------------------------------------------------------------- #
# consistent snapshot
# --------------------------------------------------------------------------- #

def _wrap_db_with_hook(monkeypatch, admin_reporting, on_sql):
    real_get_db = admin_reporting.get_db

    class _Cur:
        def __init__(self, cur):
            self._c = cur

        def execute(self, sql, params=()):
            on_sql("before", sql)
            out = self._c.execute(sql, params)
            on_sql("after", sql)
            return out

        def __getattr__(self, name):
            return getattr(self._c, name)

    class _Conn:
        def __init__(self):
            self._c = real_get_db()

        def cursor(self):
            return _Cur(self._c.cursor())

        def __getattr__(self, name):
            return getattr(self._c, name)

    monkeypatch.setattr(admin_reporting, "get_db", lambda: _Conn())
    return real_get_db


@pytest.mark.parametrize("kind", ["charge", "refund"])
def test_report_stays_reconciled_when_a_write_commits_between_reads(db_connection, monkeypatch, kind):
    """Balance and ledger must come from one snapshot.

    A charge/refund is committed on another connection right after the report
    has read the balance and before it reads the ledger. On MariaDB (READ
    COMMITTED in production) the commit really lands in between; without the
    snapshot the ledger would include it and the balance would not.
    """
    import threading
    import admin_reporting
    import job_service
    import main

    uid = _user(db_connection, f"snap_{kind}", balance=0)
    main.record_credit_transaction(uid, 500, 500, "credit", "Starting credits on auto-approval")
    _set_balance(db_connection, uid, 500)
    job_id = None
    if kind == "refund":
        job_id = job_service.create_job_atomic(user_id=uid, category="cafes", cities=["Doha, Qatar"],
                                               max_results_per_city=3, idempotency_key=None)["job_id"]
        cur = db_connection.cursor()
        cur.execute("UPDATE jobs SET status = 'failed' WHERE job_id = ?", (job_id,))
        db_connection.commit()
    before = admin_reporting.get_user_credit_report(uid)
    assert before["reconciliation"]["status"] == "reconciled"

    done = threading.Event()
    errors = []
    state = {"started": False, "committed_before_ledger_read": None}

    def writer():
        try:
            if kind == "charge":
                main.deduct_credits(uid, 25, job_id="snap-job", reason="Job charge: snapshot")
            else:
                assert job_service.settle_job_credits(job_id) > 0
        except Exception as exc:  # pragma: no cover - reported below
            errors.append(exc)
        finally:
            done.set()

    thread = threading.Thread(target=writer)
    mysql = admin_reporting._is_mysql()

    def on_sql(phase, sql):
        if phase == "after" and "FROM users WHERE id" in sql and not state["started"]:
            state["started"] = True
            thread.start()
            done.wait(timeout=10 if mysql else 0.5)
        if phase == "before" and "FROM credit_ledger WHERE user_id" in sql:
            state["committed_before_ledger_read"] = done.is_set()

    real_get_db = _wrap_db_with_hook(monkeypatch, admin_reporting, on_sql)
    during = admin_reporting.get_user_credit_report(uid)
    thread.join(timeout=30)
    monkeypatch.setattr(admin_reporting, "get_db", real_get_db)
    assert not errors, errors
    if mysql:
        # The write really committed between the two reads ...
        assert state["committed_before_ledger_read"] is True
    # ... yet the report is one coherent picture (the pre-write state).
    assert during["reconciliation"]["status"] == "reconciled", during["reconciliation"]
    assert during["summary"]["current_balance"] == before["summary"]["current_balance"]
    assert during["pagination"]["total"] == before["pagination"]["total"]

    after = admin_reporting.get_user_credit_report(uid)
    assert after["reconciliation"]["status"] == "reconciled"
    assert after["pagination"]["total"] == before["pagination"]["total"] + 1


# --------------------------------------------------------------------------- #
# paid-credit provenance
# --------------------------------------------------------------------------- #

def _purchased_link(conn, uid, ledger_id, credits):
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO credit_expiry (user_id, credit_ledger_id, credits_granted, credits_remaining, expiry_type, "
        "expires_at, created_at, updated_at) VALUES (?, ?, ?, ?, 'purchased', NULL, ?, ?)",
        (uid, ledger_id, credits, credits, datetime.now().isoformat(), datetime.now().isoformat()),
    )
    conn.commit()


def test_staff_grant_with_payment_like_text_cannot_inflate_paid_credits(db_connection, client, staff):
    from payments import safepay_checkout

    uid = _user(db_connection, "live_buyer", balance=0)
    tid, tracker = _safepay_payment(db_connection, uid, "production", credits=1000)
    safepay_checkout._fulfill_once(tid, tracker=tracker, source="test", provider_status="PAID")
    hdr = _h(client, "adm1")
    for reason in (f"Safepay payment {tracker}", "Payment confirmed"):
        r = client.post(f"/api/admin/users/{uid}/credits", json={"amount": 1000, "reason": reason}, headers=hdr)
        assert r.status_code == 200, r.text

    rep = _report(client, uid)
    s = rep["summary"]
    assert s["paid_credits"] == 1000 and s["confirmed_paid_payments"] == 1
    assert s["admin_grants"] == 2000
    assert s["unverified_payment_credits"] == 0
    assert s["current_balance"] == 3000 and rep["reconciliation"]["status"] == "reconciled"
    ov = client.get("/api/admin/overview", params={"range": "24h"}, headers=_h(client, "sup1")).json()["metrics"]
    assert ov["paid_credits"] == 1000 and ov["admin_grants"] == 2000


def test_paid_credits_require_matching_amount_link_and_count_each_payment_once(db_connection, client, staff):
    from payments import safepay_checkout

    uid = _user(db_connection, "edge_buyer", balance=0)
    tid, tracker = _safepay_payment(db_connection, uid, "production", credits=500)
    safepay_checkout._fulfill_once(tid, tracker=tracker, source="test", provider_status="PAID")  # real: 500
    bal = 500
    # Same tracker claimed twice by a system-looking row (with link): counted once.
    bal += 500
    dup = _ledger_row(db_connection, uid, 500, bal, "credit", f"Safepay payment {tracker}")
    _purchased_link(db_connection, uid, dup, 500)
    # Completed live payment of 300 credits, but the ledger row says 999: amount mismatch.
    _, tr_wrong = _safepay_payment(db_connection, uid, "production", credits=300, status="completed")
    bal += 999
    wrong = _ledger_row(db_connection, uid, 999, bal, "credit", f"Safepay payment {tr_wrong}")
    _purchased_link(db_connection, uid, wrong, 999)
    # Completed live payment of 200 with a matching row but no payment-path link.
    _, tr_nolink = _safepay_payment(db_connection, uid, "production", credits=200, status="completed")
    bal += 200
    _ledger_row(db_connection, uid, 200, bal, "credit", f"Safepay payment {tr_nolink}")
    # Live payment whose ledger row claims to be sandbox: environment mismatch.
    _, tr_env = _safepay_payment(db_connection, uid, "production", credits=50, status="completed")
    bal += 50
    env_row = _ledger_row(db_connection, uid, 50, bal, "credit", f"Safepay payment {tr_env} [sandbox]")
    _purchased_link(db_connection, uid, env_row, 50)
    _set_balance(db_connection, uid, bal)

    rep = _report(client, uid)
    s = rep["summary"]
    assert s["paid_credits"] == 500 and s["confirmed_paid_payments"] == 1
    assert s["unverified_payment_credits"] == 500 + 999 + 200 + 50
    assert s["admin_grants"] == 0 and s["sandbox_test_credits"] == 0
    assert rep["reconciliation"]["status"] == "reconciled"
    unmatched = [t for t in rep["transactions"] if t["category"] == "purchase_unverified"]
    assert len(unmatched) == 4 and all(t["payment"] is None for t in unmatched)
    assert all(tr not in t["reason"] for t in rep["transactions"] for tr in (tracker, tr_wrong, tr_nolink, tr_env))


# --------------------------------------------------------------------------- #
# permissions
# --------------------------------------------------------------------------- #

def test_new_endpoints_require_staff_roles(db_connection, client, staff):
    uid = _user(db_connection, "plain", balance=0)
    paths = [f"/api/admin/users/{uid}/credit-report", "/api/admin/overview", "/api/admin/health"]
    for p in paths:
        assert client.get(p).status_code in (401, 403)
        assert client.get(p, headers=_h(client, "plain")).status_code == 403
        for who in ("sup1", "adm1", "own1"):
            assert client.get(p, headers=_h(client, who)).status_code == 200, (p, who)
    assert client.get("/api/admin/users/999999/credit-report", headers=_h(client, "sup1")).status_code == 404


# --------------------------------------------------------------------------- #
# signup provenance
# --------------------------------------------------------------------------- #

def test_signup_credits_need_approval_provenance(db_connection, client, staff):
    """Real approval -> Free signup credits; a staff grant starting with "Starting credits" -> Staff grant."""
    uid = _user(db_connection, "pending_person", approved=False)
    hdr = _h(client, "adm1")
    r = client.post(f"/api/admin/users/{uid}/approve", headers=hdr)
    assert r.status_code == 200, r.text
    cur = db_connection.cursor()
    cur.execute("SELECT credit_balance, approved_by FROM users WHERE id = ?", (uid,))
    granted, approver = cur.fetchone()
    assert granted > 0 and approver == staff["admin"]

    # Two manual grants imitating the approval text: one by the approving admin, one by the owner.
    for who, reason in (("adm1", "Starting credits on account approval"),
                        ("own1", "Starting credits on auto-approval")):
        r = client.post(f"/api/admin/users/{uid}/credits", json={"amount": 100, "reason": reason},
                        headers=_h(client, who))
        assert r.status_code == 200, r.text

    rep = _report(client, uid)
    s = rep["summary"]
    assert s["starting_credits"] == granted
    assert s["admin_grants"] == 200
    assert s["current_balance"] == granted + 200
    assert rep["reconciliation"]["status"] == "reconciled"
    cats = [t["category"] for t in rep["transactions"]]
    assert cats.count("starting_credits") == 1 and cats.count("admin_grant") == 2
    ov = client.get("/api/admin/overview", params={"range": "24h"}, headers=_h(client, "sup1")).json()["metrics"]
    assert ov["starting_credits"] == granted and ov["admin_grants"] == 200


def test_auto_approval_signup_and_late_or_repeated_rows(db_connection, client, staff):
    import main

    uid = _user(db_connection, "auto_person", balance=0)
    main.record_credit_transaction(uid, 100, 100, "credit", "Starting credits on auto-approval")
    # A second system row with the same text is not a second signup grant.
    main.record_credit_transaction(uid, 100, 200, "credit", "Starting credits on auto-approval")
    _set_balance(db_connection, uid, 200)
    s = _report(client, uid)["summary"]
    assert s["starting_credits"] == 100 and s["other_credits"] == 100 and s["admin_grants"] == 0

    late = _user(db_connection, "late_person", balance=100,
                 created_at=(datetime.now() - timedelta(days=2)).isoformat())
    _ledger_row(db_connection, late, 100, 100, "credit", "Starting credits on auto-approval")  # written 2 days later
    s = _report(client, late)["summary"]
    assert s["starting_credits"] == 0 and s["other_credits"] == 100


# --------------------------------------------------------------------------- #
# overview: payment matching uses the account's full ledger
# --------------------------------------------------------------------------- #

def test_overview_duplicate_in_range_whose_original_is_outside_is_not_paid(db_connection, client, staff):
    from payments import safepay_checkout

    uid = _user(db_connection, "old_buyer", balance=0, created_at=(datetime.now() - timedelta(days=41)).isoformat())
    tid, tracker = _safepay_payment(db_connection, uid, "production", credits=500)
    safepay_checkout._fulfill_once(tid, tracker=tracker, source="test", provider_status="PAID")
    old = (datetime.now() - timedelta(days=40)).isoformat()
    cur = db_connection.cursor()
    cur.execute("UPDATE credit_ledger SET created_at = ? WHERE user_id = ?", (old, uid))  # original: 40 days ago
    db_connection.commit()
    dup = _ledger_row(db_connection, uid, 500, 1000, "credit", f"Safepay payment {tracker}")  # duplicate: now
    _purchased_link(db_connection, uid, dup, 500)
    _set_balance(db_connection, uid, 1000)

    hdr = _h(client, "sup1")
    d24 = client.get("/api/admin/overview", params={"range": "24h"}, headers=hdr).json()["metrics"]
    d7 = client.get("/api/admin/overview", params={"range": "7d"}, headers=hdr).json()["metrics"]
    dall = client.get("/api/admin/overview", params={"range": "all"}, headers=hdr).json()["metrics"]
    assert d24["paid_credits"] == 0 and d7["paid_credits"] == 0
    assert dall["paid_credits"] == 500
    s = _report(client, uid)["summary"]
    assert s["paid_credits"] == 500 and s["unverified_payment_credits"] == 500 and s["confirmed_paid_payments"] == 1


def test_safepay_payment_without_environment_is_never_paid(db_connection, client, staff):
    uid = _user(db_connection, "no_env_buyer", balance=0)
    _, tracker = _safepay_payment(db_connection, uid, None, credits=400, status="completed")
    row = _ledger_row(db_connection, uid, 400, 400, "credit", f"Safepay payment {tracker}")
    _purchased_link(db_connection, uid, row, 400)
    _set_balance(db_connection, uid, 400)
    s = _report(client, uid)["summary"]
    assert s["paid_credits"] == 0 and s["unverified_payment_credits"] == 400
    ov = client.get("/api/admin/overview", params={"range": "24h"}, headers=_h(client, "sup1")).json()["metrics"]
    assert ov["paid_credits"] == 0
