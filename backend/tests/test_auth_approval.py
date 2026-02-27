from datetime import datetime
from typing import Optional

from fastapi.testclient import TestClient


def _insert_user(
    conn,
    *,
    username: str,
    email: str,
    password: str,
    is_approved: int,
    is_admin: int = 0,
    role: Optional[str] = None,
    is_suspended: int = 0,
):
    from auth import get_password_hash

    cursor = conn.cursor()
    cursor.execute(
        """
        INSERT INTO users (
            username,
            email,
            password_hash,
            is_approved,
            is_admin,
            role,
            is_suspended,
            created_at,
            credit_balance
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            username,
            email,
            get_password_hash(password),
            is_approved,
            is_admin,
            role or ("admin" if is_admin else "user"),
            is_suspended,
            datetime.now().isoformat(),
            0,
        ),
    )
    conn.commit()
    return cursor.lastrowid


def _auth_headers(client: TestClient, username: str, password: str) -> dict:
    response = client.post(
        "/api/auth/login",
        json={"username": username, "password": password},
    )
    assert response.status_code == 200, response.text
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def test_login_blocks_pending_and_denied_users(db_connection):
    # Import the app after the DB is initialized by fixtures.
    from main import app

    _insert_user(
        db_connection,
        username="pending_user",
        email="pending@example.com",
        password="pw",
        is_approved=0,
    )
    _insert_user(
        db_connection,
        username="denied_user",
        email="denied@example.com",
        password="pw",
        is_approved=-1,
    )
    _insert_user(
        db_connection,
        username="approved_user",
        email="approved@example.com",
        password="pw",
        is_approved=1,
    )
    _insert_user(
        db_connection,
        username="suspended_user",
        email="suspended@example.com",
        password="pw",
        is_approved=1,
        is_suspended=1,
    )

    client = TestClient(app)

    pending = client.post(
        "/api/auth/login",
        json={"username": "pending_user", "password": "pw"},
    )
    assert pending.status_code == 403
    assert pending.json().get("detail") == "Account pending approval"

    denied = client.post(
        "/api/auth/login",
        json={"username": "denied_user", "password": "pw"},
    )
    assert denied.status_code == 403
    assert denied.json().get("detail") == "Account denied"

    suspended = client.post(
        "/api/auth/login",
        json={"username": "suspended_user", "password": "pw"},
    )
    assert suspended.status_code == 403
    assert suspended.json().get("detail") == "Account suspended"

    approved = client.post(
        "/api/auth/login",
        json={"username": "approved_user", "password": "pw"},
    )
    assert approved.status_code == 200
    body = approved.json()
    assert body.get("access_token")
    assert body.get("user", {}).get("username") == "approved_user"


def test_suspended_user_tokens_are_blocked_after_suspension(db_connection):
    from main import app

    _insert_user(
        db_connection,
        username="approved_user",
        email="approved@example.com",
        password="pw",
        is_approved=1,
    )

    client = TestClient(app)
    headers = _auth_headers(client, "approved_user", "pw")

    cursor = db_connection.cursor()
    cursor.execute(
        "UPDATE users SET is_suspended = 1, suspended_at = ? WHERE username = ?",
        (datetime.now().isoformat(), "approved_user"),
    )
    db_connection.commit()

    response = client.get("/api/auth/me", headers=headers)
    assert response.status_code == 403
    assert response.json().get("detail") == "Account suspended"


def test_admin_suspend_restore_and_delete_workflow(db_connection):
    from main import app

    _insert_user(
        db_connection,
        username="admin_user",
        email="admin@example.com",
        password="pw",
        is_approved=1,
        is_admin=1,
        role="admin",
    )
    managed_user_id = _insert_user(
        db_connection,
        username="managed_user",
        email="managed@example.com",
        password="pw",
        is_approved=1,
    )

    client = TestClient(app)
    admin_headers = _auth_headers(client, "admin_user", "pw")

    delete_active = client.delete(
        f"/api/admin/users/{managed_user_id}",
        headers=admin_headers,
    )
    assert delete_active.status_code == 400
    assert delete_active.json().get("detail") == "Suspend the user before deleting."

    suspend = client.post(
        f"/api/admin/users/{managed_user_id}/suspend",
        headers=admin_headers,
        json={"reason": "Manual review"},
    )
    assert suspend.status_code == 200

    users_response = client.get("/api/admin/users", headers=admin_headers)
    assert users_response.status_code == 200
    managed_user = next(
        u for u in users_response.json()["users"] if u["id"] == managed_user_id
    )
    assert managed_user["account_state"] == "suspended"
    assert managed_user["is_suspended"] is True
    assert managed_user["suspension_reason"] == "Manual review"

    suspended_login = client.post(
        "/api/auth/login",
        json={"username": "managed_user", "password": "pw"},
    )
    assert suspended_login.status_code == 403
    assert suspended_login.json().get("detail") == "Account suspended"

    unsuspend = client.post(
        f"/api/admin/users/{managed_user_id}/unsuspend",
        headers=admin_headers,
    )
    assert unsuspend.status_code == 200

    restored_login = client.post(
        "/api/auth/login",
        json={"username": "managed_user", "password": "pw"},
    )
    assert restored_login.status_code == 200

    resuspend = client.post(
        f"/api/admin/users/{managed_user_id}/suspend",
        headers=admin_headers,
    )
    assert resuspend.status_code == 200

    delete_suspended = client.delete(
        f"/api/admin/users/{managed_user_id}",
        headers=admin_headers,
    )
    assert delete_suspended.status_code == 200

    cursor = db_connection.cursor()
    cursor.execute("SELECT id FROM users WHERE id = ?", (managed_user_id,))
    assert cursor.fetchone() is None
