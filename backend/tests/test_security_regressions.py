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
    assert [tuple(r) for r in cur.fetchall()] == [(50, 55)]


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


# --------------------------------------------------------------------------- #
# Auth hardening (audit H-5, H-6, H-7, M-9, M-10)
# --------------------------------------------------------------------------- #

def test_password_policy_on_register_and_reset(db_connection):
    from main import app

    client = TestClient(app)
    r = client.post("/api/auth/register", json={"username": "weak", "email": "weak@example.com",
                                                "password": "a", "phone": "5551234567"})
    assert r.status_code == 422
    r = client.post("/api/auth/reset-password", json={"token": "x", "new_password": "short"})
    assert r.status_code == 422
    r = client.post("/api/auth/reset-password", json={"token": "x", "new_password": "é" * 40})  # 80 bytes
    assert r.status_code == 422


def test_password_reset_revokes_existing_sessions(db_connection):
    import hashlib
    from datetime import timedelta

    from main import app

    uid = _user(db_connection, "victim")
    client = TestClient(app)
    old = _h(client, "victim")
    assert client.get("/api/auth/me", headers=old).status_code == 200

    token = "reset-token-for-test-0001"
    cur = db_connection.cursor()
    cur.execute(
        "INSERT INTO password_reset_tokens (user_id, token_hash, expires_at, used, created_at) VALUES (?, ?, ?, 0, ?)",
        (uid, hashlib.sha256(token.encode()).hexdigest(),
         (datetime.now() + timedelta(hours=1)).isoformat(), datetime.now().isoformat()),
    )
    db_connection.commit()
    import time
    time.sleep(1.1)  # iat has second resolution
    r = client.post("/api/auth/reset-password", json={"token": token, "new_password": "brand-new-password-1"})
    assert r.status_code == 200, r.text

    assert client.get("/api/auth/me", headers=old).status_code == 401  # attacker's token is dead
    r = client.post("/api/auth/login", json={"username": "victim", "password": "brand-new-password-1"})
    assert r.status_code == 200
    fresh = {"Authorization": f"Bearer {r.json()['access_token']}"}
    assert client.get("/api/auth/me", headers=fresh).status_code == 200


def test_rotating_x_forwarded_for_does_not_bypass_lockout(db_connection, monkeypatch):
    import main

    monkeypatch.setattr(main, "LOGIN_EDGE_MAX_ATTEMPTS", 5)
    client = TestClient(main.app)
    codes = []
    for i in range(8):
        r = client.post(
            "/api/auth/login",
            json={"username": f"spray{i}", "password": "wrong-password"},  # new username each time
            headers={"X-Forwarded-For": f"10.0.0.{i}", "CF-Connecting-IP": "203.0.113.9"},
        )
        codes.append(r.status_code)
    assert 429 in codes, codes
    assert codes.index(429) <= 5


def test_missing_or_placeholder_secret_key_refuses_to_start(tmp_path):
    import os
    import subprocess
    import sys

    backend = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    for key in ("", "your-secret-key-change-in-production", "short"):
        env = {**os.environ, "SECRET_KEY": key}
        r = subprocess.run([sys.executable, "-c", "import auth"], cwd=backend, env=env,
                           capture_output=True, text=True)
        assert r.returncode != 0 and "SECRET_KEY" in r.stderr, key


def test_every_email_template_referenced_by_code_is_tracked_in_git():
    import os
    import re
    import subprocess

    backend = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    src = open(os.path.join(backend, "notifications", "email_service.py"), encoding="utf-8").read()
    names = set(re.findall(r'"([a-z_]+\.html)"', src))
    assert names, "no templates found in email_service.py"
    tracked = subprocess.run(["git", "ls-files", "notifications/templates"], cwd=backend,
                             capture_output=True, text=True).stdout
    missing = [n for n in names if n not in tracked]
    assert not missing, f"templates not in git (clean clones cannot send these emails): {missing}"
