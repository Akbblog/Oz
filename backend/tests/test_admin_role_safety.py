"""Role-based regression tests for the two admin permission bugs (ADMIN_UX_PLAN.md A1, A2).

A1: saving a profile must never change a role; only the explicit owner-only
    role action may, and it can't touch the actor or another owner.
A2: staff may only suspend / unsuspend / deny / restore / delete / edit
    accounts ranked strictly below their own role.
"""

from datetime import datetime

import pytest
from fastapi.testclient import TestClient

PW = "pw-strong-123"


def _user(conn, username, role="user", is_admin=None, approved=1, suspended=0):
    from auth import get_password_hash

    if is_admin is None:
        is_admin = 1 if role in ("admin", "owner") else 0
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO users (username, email, password_hash, is_approved, is_admin, role, created_at, "
        "credit_balance, is_suspended) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)",
        (username, f"{username}@example.com", get_password_hash(PW), approved, is_admin, role,
         datetime.now().isoformat(), suspended),
    )
    conn.commit()
    return cur.lastrowid


def _h(client, username):
    r = client.post("/api/auth/login", json={"username": username, "password": PW})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


def _row(conn, uid):
    cur = conn.cursor()
    cur.execute("SELECT role, is_admin, phone, is_suspended FROM users WHERE id = ?", (uid,))
    r = cur.fetchone()
    return None if r is None else {"role": r[0], "is_admin": int(r[1] or 0), "phone": r[2], "susp": int(r[3] or 0)}


@pytest.fixture
def staff(db_connection):
    from main import app

    ids = {
        "owner": _user(db_connection, "own1", "owner"),
        "owner2": _user(db_connection, "own2", "owner"),
        "admin": _user(db_connection, "adm1", "admin"),
        "admin2": _user(db_connection, "adm2", "admin"),
        "support": _user(db_connection, "sup1", "support"),
        "user": _user(db_connection, "usr1", "user"),
    }
    client = TestClient(app)
    return client, ids


def _profile_body(conn, uid, **extra):
    cur = conn.cursor()
    cur.execute("SELECT username, email, is_admin FROM users WHERE id = ?", (uid,))
    u = cur.fetchone()
    # Exactly what the old Manage Profile dialog sent: all fields + is_admin.
    body = {"username": u[0], "email": u[1], "phone": "+1 555 0100", "is_admin": bool(u[2])}
    body.update(extra)
    return body


# ---------------------------------------------------------------- A1 -------

@pytest.mark.parametrize("target", ["owner2", "admin2", "support", "user"])
def test_owner_profile_save_never_changes_role(db_connection, staff, target):
    client, ids = staff
    before = _row(db_connection, ids[target])["role"]
    r = client.put(f"/api/admin/users/{ids[target]}", json=_profile_body(db_connection, ids[target]),
                   headers=_h(client, "own1"))
    if target == "owner2":
        assert r.status_code == 403  # owners don't manage peer owners (A2)
    else:
        assert r.status_code == 200, r.text
        assert _row(db_connection, ids[target])["phone"] == "+1 555 0100"
    assert _row(db_connection, ids[target])["role"] == before


def test_sole_owner_editing_own_profile_stays_owner(db_connection):
    from main import app

    me = _user(db_connection, "solo", "owner")
    client = TestClient(app)
    r = client.put(f"/api/admin/users/{me}", json=_profile_body(db_connection, me), headers=_h(client, "solo"))
    assert r.status_code == 200, r.text
    assert _row(db_connection, me) == {"role": "owner", "is_admin": 1, "phone": "+1 555 0100", "susp": 0}


@pytest.mark.parametrize("target", ["support", "user"])
def test_admin_can_save_lower_profiles_without_403(db_connection, staff, target):
    client, ids = staff
    before = _row(db_connection, ids[target])["role"]
    r = client.put(f"/api/admin/users/{ids[target]}", json=_profile_body(db_connection, ids[target]),
                   headers=_h(client, "adm1"))
    assert r.status_code == 200, r.text
    assert _row(db_connection, ids[target])["role"] == before


def test_legacy_support_row_with_is_admin_flag_keeps_role(db_connection):
    from main import app

    _user(db_connection, "bossman", "owner")
    legacy = _user(db_connection, "oldsupport", "support", is_admin=1)
    client = TestClient(app)
    r = client.put(f"/api/admin/users/{legacy}", json=_profile_body(db_connection, legacy),
                   headers=_h(client, "bossman"))
    assert r.status_code == 200, r.text
    assert _row(db_connection, legacy)["role"] == "support"


@pytest.mark.parametrize("payload", [{"is_admin": True}, {"role": "admin"}, {"role": "owner"}])
def test_profile_endpoint_refuses_role_changes_even_for_owner(db_connection, staff, payload):
    client, ids = staff
    body = _profile_body(db_connection, ids["user"], **payload)
    r = client.put(f"/api/admin/users/{ids['user']}", json=body, headers=_h(client, "own1"))
    assert r.status_code == 409
    assert "Change role" in r.json()["detail"]
    assert _row(db_connection, ids["user"]) == {"role": "user", "is_admin": 0, "phone": None, "susp": 0}


def test_owner_role_change_is_explicit_and_audited(db_connection, staff):
    client, ids = staff
    h = _h(client, "own1")
    r = client.put(f"/api/admin/users/{ids['user']}/role", json={"role": "support", "reason": "helpdesk"}, headers=h)
    assert r.status_code == 200, r.text
    assert _row(db_connection, ids["user"])["role"] == "support"
    assert _row(db_connection, ids["user"])["is_admin"] == 0
    r = client.put(f"/api/admin/users/{ids['support']}/role", json={"role": "admin"}, headers=h)
    assert r.status_code == 200
    assert _row(db_connection, ids["support"])["is_admin"] == 1
    cur = db_connection.cursor()
    cur.execute("SELECT COUNT(*) FROM audit_events WHERE action = 'admin.user.role_change'")
    assert cur.fetchone()[0] == 2


@pytest.mark.parametrize("actor", ["adm1", "sup1", "usr1"])
def test_only_owner_can_change_roles(db_connection, staff, actor):
    client, ids = staff
    r = client.put(f"/api/admin/users/{ids['user']}/role", json={"role": "admin"}, headers=_h(client, actor))
    assert r.status_code == 403
    assert _row(db_connection, ids["user"])["role"] == "user"


def test_owner_cannot_change_own_or_peer_owner_role(db_connection, staff):
    client, ids = staff
    h = _h(client, "own1")
    assert client.put(f"/api/admin/users/{ids['owner']}/role", json={"role": "admin"}, headers=h).status_code == 400
    assert client.put(f"/api/admin/users/{ids['owner2']}/role", json={"role": "user"}, headers=h).status_code == 403
    assert _row(db_connection, ids["owner"])["role"] == "owner"
    assert _row(db_connection, ids["owner2"])["role"] == "owner"


def test_invalid_role_rejected(db_connection, staff):
    client, ids = staff
    r = client.put(f"/api/admin/users/{ids['user']}/role", json={"role": "superuser"}, headers=_h(client, "own1"))
    assert r.status_code == 400


# ---------------------------------------------------------------- A2 -------

@pytest.mark.parametrize("target", ["owner", "admin2"])
def test_admin_cannot_suspend_or_delete_owner_or_peer_admin(db_connection, staff, target):
    client, ids = staff
    h = _h(client, "adm1")
    tid = ids[target]
    r = client.post(f"/api/admin/users/{tid}/suspend", json={"reason": "x"}, headers=h)
    assert r.status_code == 403, r.text
    assert "can't suspend" in r.json()["detail"]
    assert _row(db_connection, tid)["susp"] == 0

    # Even if the target is already suspended (e.g. by an owner) the admin can't delete or unsuspend it.
    cur = db_connection.cursor()
    cur.execute("UPDATE users SET is_suspended = 1 WHERE id = ?", (tid,))
    db_connection.commit()
    assert client.delete(f"/api/admin/users/{tid}", headers=h).status_code == 403
    assert client.post(f"/api/admin/users/{tid}/unsuspend", headers=h).status_code == 403
    assert _row(db_connection, tid) is not None
    assert client.put(f"/api/admin/users/{tid}", json={"phone": "1"}, headers=h).status_code == 403


def test_admin_cannot_deny_or_restore_pending_staff(db_connection, staff):
    client, ids = staff
    pending_admin = _user(db_connection, "pendadm", "admin", approved=0)
    denied_owner = _user(db_connection, "denown", "owner", approved=-1)
    h = _h(client, "adm1")
    assert client.post(f"/api/admin/users/{pending_admin}/deny", headers=h).status_code == 403
    assert client.post(f"/api/admin/users/{denied_owner}/restore", headers=h).status_code == 403


def test_admin_still_manages_lower_ranks(db_connection, staff):
    client, ids = staff
    h = _h(client, "adm1")
    for name in ("user", "support"):
        tid = ids[name]
        assert client.post(f"/api/admin/users/{tid}/suspend", json={"reason": "abuse"}, headers=h).status_code == 200
        assert _row(db_connection, tid)["susp"] == 1
        assert client.post(f"/api/admin/users/{tid}/unsuspend", headers=h).status_code == 200
        assert client.post(f"/api/admin/users/{tid}/suspend", json={"reason": "abuse"}, headers=h).status_code == 200
        # Permanent deletion is owner-only.
        assert client.delete(f"/api/admin/users/{tid}", headers=h).status_code == 403
        assert _row(db_connection, tid) is not None
        assert client.delete(f"/api/admin/users/{tid}", headers=_h(client, "own1")).status_code == 200
        assert _row(db_connection, tid) is None
    pending = _user(db_connection, "newbie", "user", approved=0)
    assert client.post(f"/api/admin/users/{pending}/deny", headers=h).status_code == 200
    assert client.post(f"/api/admin/users/{pending}/restore", headers=h).status_code == 200


def test_owner_manages_admins_but_not_peer_owners(db_connection, staff):
    client, ids = staff
    h = _h(client, "own1")
    assert client.post(f"/api/admin/users/{ids['admin']}/suspend", json={"reason": "r"}, headers=h).status_code == 200
    assert client.delete(f"/api/admin/users/{ids['admin']}", headers=h).status_code == 200
    assert client.post(f"/api/admin/users/{ids['owner2']}/suspend", json={"reason": "r"}, headers=h).status_code == 403
    assert _row(db_connection, ids["owner2"])["susp"] == 0


def test_self_actions_still_refused(db_connection, staff):
    client, ids = staff
    h = _h(client, "adm1")
    assert client.post(f"/api/admin/users/{ids['admin']}/suspend", json={}, headers=h).status_code == 400
    assert client.delete(f"/api/admin/users/{ids['owner']}", headers=_h(client, "own1")).status_code == 400


def test_support_cannot_mutate_anyone(db_connection, staff):
    client, ids = staff
    h = _h(client, "sup1")
    assert client.post(f"/api/admin/users/{ids['user']}/suspend", json={}, headers=h).status_code == 403
    assert client.put(f"/api/admin/users/{ids['user']}", json={"phone": "1"}, headers=h).status_code == 403
    assert client.delete(f"/api/admin/users/{ids['user']}", headers=h).status_code == 403


# ------------------------------------------- owner-only actions and grants --

def _balance(conn, uid):
    cur = conn.cursor()
    cur.execute("SELECT credit_balance FROM users WHERE id = ?", (uid,))
    return int(cur.fetchone()[0] or 0)


def test_live_payments_toggle_is_owner_only(db_connection, staff):
    client, ids = staff
    body = {"value": "true"}
    assert client.put("/api/admin/settings/enable_live_payments", json=body, headers=_h(client, "adm1")).status_code == 403
    assert client.put("/api/admin/settings/enable_live_payments", json=body, headers=_h(client, "own1")).status_code == 200
    # other settings stay admin-level
    assert client.put("/api/admin/settings/starting_credits", json={"value": "50"},
                      headers=_h(client, "adm1")).status_code == 200


@pytest.mark.parametrize("actor,target,expected", [
    ("adm1", "user", 200), ("adm1", "support", 200),
    ("adm1", "admin2", 403), ("adm1", "owner", 403), ("adm1", "admin", 403),   # admin -> admin/owner/self
    ("own1", "admin", 200), ("own1", "owner", 200),                              # owner -> admin, self
    ("own1", "owner2", 403),                                                     # owner -> other owner
    ("sup1", "user", 403),
])
def test_grant_rank_rules(db_connection, staff, actor, target, expected):
    client, ids = staff
    before = _balance(db_connection, ids[target])
    r = client.post(f"/api/admin/users/{ids[target]}/credits", json={"amount": 25, "reason": "goodwill"},
                    headers=_h(client, actor))
    assert r.status_code == expected, r.text
    assert _balance(db_connection, ids[target]) == before + (25 if expected == 200 else 0)


@pytest.mark.parametrize("body", [
    {"amount": 0, "reason": "x"}, {"amount": -10, "reason": "x"}, {"amount": 25},
    {"amount": 25, "reason": "   "}, {"amount": 2_000_000, "reason": "x"},
])
def test_grant_must_be_positive_with_reason(db_connection, staff, body):
    client, ids = staff
    r = client.post(f"/api/admin/users/{ids['user']}/credits", json=body, headers=_h(client, "own1"))
    assert r.status_code == 422, r.text
    assert _balance(db_connection, ids["user"]) == 0
    cur = db_connection.cursor()
    cur.execute("SELECT COUNT(*) FROM credit_ledger WHERE user_id = ?", (ids["user"],))
    assert cur.fetchone()[0] == 0


def test_credit_request_approval_follows_grant_rules(db_connection, staff):
    client, ids = staff
    cur = db_connection.cursor()
    req = {}
    for name in ("admin2", "user", "owner"):
        cur.execute("INSERT INTO credit_requests (user_id, amount_requested, reason, status, created_at) "
                    "VALUES (?, 40, 'need', 'pending', ?)", (ids[name], datetime.now().isoformat()))
        req[name] = cur.lastrowid
    db_connection.commit()
    h = _h(client, "adm1")
    assert client.post(f"/api/admin/credits/requests/{req['admin2']}/approve", headers=h).status_code == 403
    assert _balance(db_connection, ids["admin2"]) == 0
    r = client.post("/api/admin/credits/requests/bulk-approve",
                    json={"request_ids": [req["user"], req["owner"]]}, headers=h)
    assert r.status_code == 200 and r.json()["request_ids"] == [req["user"]] and r.json()["skipped"] == 1
    assert _balance(db_connection, ids["user"]) == 40 and _balance(db_connection, ids["owner"]) == 0
