"""Regression tests for deep-audit fixes on the admin / payment path."""

from datetime import datetime

from fastapi.testclient import TestClient


def _user(conn, username, role="user", is_admin=0, balance=0):
    from auth import get_password_hash

    cur = conn.cursor()
    cur.execute(
        "INSERT INTO users (username, email, password_hash, is_approved, is_admin, role, created_at, credit_balance) "
        "VALUES (?, ?, ?, 1, ?, ?, ?, ?)",
        (username, f"{username}@example.com", get_password_hash("pw-strong-123"), is_admin, role,
         datetime.now().isoformat(), balance),
    )
    conn.commit()
    return cur.lastrowid


def _h(client, username):
    r = client.post("/api/auth/login", json={"username": username, "password": "pw-strong-123"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def test_support_role_cannot_grant_credits_or_mutate(db_connection):
    from main import app

    _user(db_connection, "helpdesk", role="support", is_admin=1)  # legacy rows had is_admin=1
    target = _user(db_connection, "customer")
    client = TestClient(app)
    h = _h(client, "helpdesk")

    r = client.post(f"/api/admin/users/{target}/credits", json={"amount": 100000, "reason": "x"}, headers=h)
    assert r.status_code == 403
    assert client.delete(f"/api/admin/users/{target}", headers=h).status_code == 403
    assert client.put("/api/admin/settings/enable_live_payments", json={"value": "true"}, headers=h).status_code == 403
    cur = db_connection.cursor()
    cur.execute("SELECT credit_balance FROM users WHERE id = ?", (target,))
    assert cur.fetchone()[0] == 0
    # read access is kept
    assert client.get("/api/admin/users", headers=h).status_code == 200


def test_admin_grant_is_atomic_and_ledgered(db_connection):
    from main import app

    _user(db_connection, "boss", role="admin", is_admin=1)
    target = _user(db_connection, "customer2", balance=5)
    client = TestClient(app)
    r = client.post(f"/api/admin/users/{target}/credits", json={"amount": 50, "reason": "goodwill"},
                    headers=_h(client, "boss"))
    assert r.status_code == 200, r.text
    cur = db_connection.cursor()
    cur.execute("SELECT credit_balance FROM users WHERE id = ?", (target,))
    assert cur.fetchone()[0] == 55
    cur.execute("SELECT amount, balance_after FROM credit_ledger WHERE user_id = ?", (target,))
    assert cur.fetchall() == [(50, 55)]


def test_debug_user_dump_and_public_docs_are_gone(db_connection):
    from main import app

    client = TestClient(app)
    assert client.get("/internal/debug_users").status_code == 404
    assert client.get("/openapi.json").status_code == 404
    assert client.get("/docs").status_code == 404


def test_default_admin_bootstrap_never_promotes_or_uses_builtin_password(db_connection, monkeypatch):
    import database

    _user(db_connection, "admin")  # self-registered account that happens to be called "admin"
    monkeypatch.setenv("DISABLE_DEFAULT_ADMIN", "false")
    monkeypatch.delenv("DEFAULT_ADMIN_PASSWORD", raising=False)
    monkeypatch.setenv("DEFAULT_ADMIN_EMAIL", "admin@example.com")
    database._ensure_default_admin_user()
    monkeypatch.setenv("DEFAULT_ADMIN_PASSWORD", "a-long-enough-password")
    database._ensure_default_admin_user()

    cur = db_connection.cursor()
    cur.execute("SELECT is_admin FROM users WHERE username = 'admin'")
    assert cur.fetchone()[0] == 0
    cur.execute("SELECT COUNT(*) FROM users WHERE is_admin = 1")
    assert cur.fetchone()[0] == 0


def test_default_admin_bootstrap_creates_owner_only_when_configured(db_connection, monkeypatch):
    import database

    monkeypatch.setenv("DISABLE_DEFAULT_ADMIN", "false")
    monkeypatch.setenv("DEFAULT_ADMIN_EMAIL", "first@example.com")
    monkeypatch.setenv("DEFAULT_ADMIN_USERNAME", "firstadmin")
    monkeypatch.setenv("DEFAULT_ADMIN_PASSWORD", "short")
    database._ensure_default_admin_user()
    cur = db_connection.cursor()
    cur.execute("SELECT COUNT(*) FROM users")
    assert cur.fetchone()[0] == 0
    monkeypatch.setenv("DEFAULT_ADMIN_PASSWORD", "a-long-enough-password")
    database._ensure_default_admin_user()
    cur.execute("SELECT role, is_admin FROM users WHERE username = 'firstadmin'")
    assert cur.fetchone() == ("owner", 1)


def test_webhook_redelivery_is_idempotent(db_connection):
    from db.payment_crud import begin_webhook_event, mark_webhook_failed, mark_webhook_processed

    wid, done = begin_webhook_event("evt_1", "coinbase", "charge:confirmed", "{}")
    assert done is False
    mark_webhook_failed(wid, "transient db error")
    wid2, done2 = begin_webhook_event("evt_1", "coinbase", "charge:confirmed", "{}")
    assert (wid2, done2) == (wid, False)  # retry reuses the row instead of crashing on UNIQUE
    mark_webhook_processed(wid2)
    assert begin_webhook_event("evt_1", "coinbase", "charge:confirmed", "{}") == (wid, True)


def test_monthly_purchase_query_is_portable(db_connection, sample_user):
    from payments.pricing_engine import PricingEngine

    # Used to call SQLite-only datetime('now', ...); must run and return an int.
    assert PricingEngine()._get_monthly_credits_purchased(sample_user) == 0
