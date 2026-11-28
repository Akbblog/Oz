"""Contact form: stored, listed for admins, status workflow (synthetic data only)."""
from datetime import datetime

import pytest
from fastapi.testclient import TestClient

import contact_messages

PW = "pw-strong-123"
CHROME = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
          "Chrome/131.0.0.0 Safari/537.36")
EDGE = {"x-vercel-forwarded-for": "203.0.113.7", "x-vercel-id": "iad1::t", "user-agent": CHROME}


def _user(conn, username, role="user"):
    from auth import get_password_hash

    now = datetime.now().isoformat()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO users (username, email, password_hash, is_approved, is_admin, role, created_at, "
        "credit_balance, approved_at) VALUES (?, ?, ?, 1, ?, ?, ?, 0, ?)",
        (username, f"{username}@example.com", get_password_hash(PW),
         1 if role in ("admin", "owner") else 0, role, now, now),
    )
    conn.commit()
    return cur.lastrowid


def _h(client, username):
    r = client.post("/api/auth/login", json={"username": username, "password": PW})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


@pytest.fixture
def client(db_connection):
    from main import app

    contact_messages._sent.clear()
    yield TestClient(app)
    contact_messages._sent.clear()


def _send(client, headers=None, **over):
    body = {"name": "Maria Lopez", "email": "Maria@Example.com", "topic": "sales",
            "message": "Do you cover dentists in Karachi and Lahore?"}
    body.update(over)
    return client.post("/api/contact", json=body, headers=headers or EDGE)


def test_a_visitor_message_is_stored_with_where_it_came_from(client, db_connection):
    r = _send(client, phone="0300 1234567", phone_country="PK", geo_country="PK", geo_city="Lahore",
              page="/?utm=x", visitor_id="visitor-contact-1")
    assert r.status_code == 200 and r.json()["ok"] is True
    cur = db_connection.cursor()
    cur.execute("SELECT user_id, name, email, phone, topic, message, status, ip_address, country, city, device, "
                "page, visitor_id FROM contact_messages")
    rows = cur.fetchall()
    assert len(rows) == 1
    assert tuple(rows[0]) == (None, "Maria Lopez", "maria@example.com", "+923001234567", "sales",
                              "Do you cover dentists in Karachi and Lahore?", "new", "203.0.113.7", "PK",
                              "Lahore", "Chrome · Windows · desktop", "/", "visitor-contact-1")


def test_a_signed_in_user_message_is_linked_to_the_account(client, db_connection):
    uid = _user(db_connection, "plain1")
    r = _send(client, headers=dict(EDGE, **_h(client, "plain1")), topic="not-a-topic")
    assert r.status_code == 200
    cur = db_connection.cursor()
    cur.execute("SELECT user_id, topic FROM contact_messages")
    assert tuple(cur.fetchone()) == (uid, "general")


@pytest.mark.parametrize("over,needle", [
    ({"name": " "}, "name"),
    ({"email": "maria@"}, "email"),
    ({"message": "hi"}, "little more"),
])
def test_incomplete_messages_are_refused_with_a_reason(client, db_connection, over, needle):
    r = _send(client, **over)
    assert r.status_code == 400 and needle in r.json()["detail"]
    cur = db_connection.cursor()
    cur.execute("SELECT COUNT(*) FROM contact_messages")
    assert cur.fetchone()[0] == 0


def test_bots_and_floods_do_not_fill_the_inbox(client, db_connection, monkeypatch):
    # The hidden field is filled: looks accepted, stores nothing.
    assert _send(client, website="http://spam.example").json()["ok"] is True
    monkeypatch.setattr(contact_messages, "_LIMIT_PER_HOUR", 2)
    assert [_send(client).status_code for _ in range(3)] == [200, 200, 400]
    other = dict(EDGE, **{"x-vercel-forwarded-for": "203.0.113.99"})
    assert _send(client, headers=other).status_code == 200
    cur = db_connection.cursor()
    cur.execute("SELECT COUNT(*) FROM contact_messages")
    assert cur.fetchone()[0] == 3


def test_admin_inbox_counts_search_and_status_workflow(client, db_connection):
    _user(db_connection, "adm1", "admin")
    _user(db_connection, "plain1")
    _send(client)
    _send(client, name="Omar Haddad", email="omar@example.com", message="Invoice question about last month.",
          topic="billing")
    for url in ("/api/admin/contact", "/api/admin/contact/summary"):
        assert client.get(url).status_code in (401, 403)
        assert client.get(url, headers=_h(client, "plain1")).status_code == 403
    auth = _h(client, "adm1")

    assert client.get("/api/admin/contact/summary", headers=auth).json() == {
        "new": 2, "read": 0, "replied": 0, "archived": 0, "total": 2}
    data = client.get("/api/admin/contact", headers=auth).json()
    assert [m["name"] for m in data["messages"]] == ["Omar Haddad", "Maria Lopez"]
    assert data["total"] == 2 and data["counts"]["new"] == 2
    found = client.get("/api/admin/contact", params={"q": "invoice"}, headers=auth).json()["messages"]
    assert [m["email"] for m in found] == ["omar@example.com"]

    mid = found[0]["id"]
    r = client.put(f"/api/admin/contact/{mid}", headers=auth, json={"status": "read"})
    assert r.status_code == 200 and r.json()["status"] == "read" and r.json()["handled_at"] is None
    r = client.put(f"/api/admin/contact/{mid}", headers=auth,
                   json={"status": "replied", "admin_note": "Answered by email."})
    body = r.json()
    assert (body["status"], body["admin_note"], body["handled_by_username"]) == (
        "replied", "Answered by email.", "adm1")
    assert body["handled_at"]
    assert client.put(f"/api/admin/contact/{mid}", headers=auth, json={"status": "nope"}).status_code == 400
    assert client.put("/api/admin/contact/99999", headers=auth, json={"status": "read"}).status_code == 404

    assert client.get("/api/admin/contact/summary", headers=auth).json()["new"] == 1
    open_ = client.get("/api/admin/contact", params={"status": "open"}, headers=auth).json()["messages"]
    assert [m["name"] for m in open_] == ["Maria Lopez"]
