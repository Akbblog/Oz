from datetime import datetime

from fastapi.testclient import TestClient


def _insert_user(conn, *, username: str, email: str, password: str, is_approved: int):
    from auth import get_password_hash

    cursor = conn.cursor()
    cursor.execute(
        """
        INSERT INTO users (username, email, password_hash, is_approved, created_at, credit_balance)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        (
            username,
            email,
            get_password_hash(password),
            is_approved,
            datetime.now().isoformat(),
            0,
        ),
    )
    conn.commit()


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

    approved = client.post(
        "/api/auth/login",
        json={"username": "approved_user", "password": "pw"},
    )
    assert approved.status_code == 200
    body = approved.json()
    assert body.get("access_token")
    assert body.get("user", {}).get("username") == "approved_user"
