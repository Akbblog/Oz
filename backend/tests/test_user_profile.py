"""Clean account data: phone + country, email rules, sign-up context (synthetic data only)."""
from datetime import datetime

import pytest
from fastapi.testclient import TestClient

import user_profile

PW = "pw-strong-123"
CHROME = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
          "Chrome/131.0.0.0 Safari/537.36")
EDGE = {"x-vercel-forwarded-for": "203.0.113.7", "x-vercel-id": "iad1::t", "x-vercel-ip-country": "PK",
        "x-vercel-ip-city": "Lahore", "user-agent": CHROME}


def _user(conn, username, role="user", phone=None):
    from auth import get_password_hash

    now = datetime.now().isoformat()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO users (username, email, password_hash, phone, is_approved, is_admin, role, created_at, "
        "credit_balance, approved_at) VALUES (?, ?, ?, ?, 1, ?, ?, ?, 0, ?)",
        (username, f"{username}@example.com", get_password_hash(PW), phone,
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
    from analytics import visits
    from main import app

    visits._rate.clear()
    return TestClient(app)


def _register(client, username, headers=None, **over):
    body = {"username": username, "email": f"{username}@example.com", "password": "UserPass12345!"}
    body.update(over)
    return client.post("/api/auth/register", json=body, headers=headers or {})


def _row(conn, username, cols):
    cur = conn.cursor()
    cur.execute(f"SELECT {cols} FROM users WHERE username = ?", (username,))
    return cur.fetchone()


# ---------------------------------------------------------------- pure rules
@pytest.mark.parametrize("raw,country,phone,iso", [
    ("03001234567", "PK", "+923001234567", "PK"),
    ("0300 123-4567", "pk", "+923001234567", "PK"),
    ("+92 300 1234567", None, "+923001234567", "PK"),
    ("00923001234567", None, "+923001234567", "PK"),
    ("(512) 555-0142", "US", "+15125550142", "US"),
    ("+15125550142", "PK", "+15125550142", "US"),  # the typed international prefix wins
])
def test_phone_is_stored_in_one_format_with_its_country(raw, country, phone, iso):
    out = user_profile.normalize_phone(raw, country)
    assert (out["phone"], out["country"]) == (phone, iso)


def test_a_local_number_without_a_country_is_kept_as_typed_never_guessed():
    assert user_profile.normalize_phone("5550142233", None) == {
        "phone": "5550142233", "country": None, "national": None}
    assert user_profile.normalize_phone("  ", "PK")["phone"] is None


@pytest.mark.parametrize("raw,country", [("12345", "PK"), ("+9254646546", None), ("abcdefgh", "US")])
def test_impossible_numbers_are_refused(raw, country):
    with pytest.raises(user_profile.PhoneError):
        user_profile.normalize_phone(raw, country)
    assert user_profile.normalize_phone(raw, country, strict=False)["country"] is None


def test_email_and_text_cleaning():
    assert user_profile.normalize_email("  Maria.Lopez@Example.COM ") == "maria.lopez@example.com"
    assert user_profile.is_disposable_email("x@Mailinator.com") is True
    assert user_profile.is_disposable_email("x@example.com") is False
    assert user_profile.clean_text("  Maria   Lopez \n") == "Maria Lopez"
    assert user_profile.clean_text("   ") is None
    assert user_profile.clean_country("pk") == "PK" and user_profile.clean_country("PAK") is None


# ------------------------------------------------------------------ sign-up
def test_signup_stores_clean_profile_and_where_it_came_from(client, db_connection):
    client.post("/api/analytics/visit", headers=EDGE, json={
        "visitor_id": "visitor-aaa-001", "session_id": "session-aaa-001", "path": "/find",
        "referrer": "https://www.reddit.com/r/buildinpublic/", "utm_campaign": "launch"})
    r = _register(client, "maria", EDGE, email="Maria.Lopez@Example.com", full_name="  Maria   Lopez ",
                  company="Lopez Dental", phone="0300 1234567", phone_country="PK",
                  visitor_id="visitor-aaa-001", session_id="session-aaa-001")
    assert r.status_code == 201, r.text
    row = _row(db_connection, "maria",
               "email, full_name, company, phone, phone_country, signup_ip, signup_country, signup_city, "
               "signup_device, signup_source, signup_referrer_host, signup_campaign, signup_visitor_id")
    assert row[:5] == ("maria.lopez@example.com", "Maria Lopez", "Lopez Dental", "+923001234567", "PK")
    assert row[5:8] == ("203.0.113.7", "PK", "Lahore")
    assert row[8] == "Chrome · Windows · desktop"
    assert row[9:] == ("campaign", "reddit.com", "launch", "visitor-aaa-001")


def test_an_older_app_version_can_still_register(client, db_connection):
    # No name, no country: exactly what builds before this change send.
    r = _register(client, "legacy", phone="5550142233")
    assert r.status_code == 201, r.text
    assert _row(db_connection, "legacy", "full_name, phone, phone_country") == (None, "5550142233", None)


def test_signup_refusals_say_what_is_wrong(client, db_connection):
    assert _register(client, "first", phone="03001234567", phone_country="PK").status_code == 201

    r = _register(client, "second", email="FIRST@example.com")
    assert (r.status_code, r.json()["detail"]) == (400, "Email already exists")

    r = _register(client, "third", phone="+92 300 1234567")
    assert (r.status_code, r.json()["detail"]) == (400, "This phone number is already registered")

    r = _register(client, "fourth", phone="12345", phone_country="PK")
    assert r.status_code == 400 and "not valid" in r.json()["detail"]

    r = _register(client, "fifth", email="fifth@mailinator.com")
    assert r.status_code == 400 and "permanent email" in r.json()["detail"]

    cur = db_connection.cursor()
    cur.execute("SELECT COUNT(*) FROM users")
    assert cur.fetchone()[0] == 1


def test_sign_in_with_email_ignores_case(client, db_connection):
    _user(db_connection, "casey")
    r = client.post("/api/auth/login", json={"username": "CASEY@Example.com", "password": PW})
    assert r.status_code == 200, r.text


# -------------------------------------------------------------------- admin
def test_admin_list_shows_profile_and_flags_country_mismatch(client, db_connection):
    _user(db_connection, "adm1", "admin")
    abroad = dict(EDGE, **{"x-vercel-ip-country": "DE", "x-vercel-ip-city": "Berlin"})
    assert _register(client, "omar", abroad, full_name="Omar H", phone="03001234567",
                     phone_country="PK").status_code == 201
    assert _register(client, "lena", EDGE, phone="03011234567", phone_country="PK").status_code == 201
    users = {u["username"]: u for u in client.get("/api/admin/users", headers=_h(client, "adm1")).json()["users"]}
    assert users["omar"]["full_name"] == "Omar H"
    assert (users["omar"]["phone_country"], users["omar"]["signup_country"]) == ("PK", "DE")
    assert users["omar"]["country_mismatch"] is True
    assert users["lena"]["country_mismatch"] is False
    assert users["adm1"]["country_mismatch"] is False and users["adm1"]["phone_country"] is None


def test_admin_can_correct_name_company_and_phone(client, db_connection):
    _user(db_connection, "own1", "owner")
    uid = _user(db_connection, "raj", phone="5550142233")
    auth = _h(client, "own1")
    r = client.put(f"/api/admin/users/{uid}", headers=auth,
                   json={"full_name": " Raj  K ", "company": "RK Media", "phone": "0412 345 678",
                         "phone_country": "AU"})
    assert r.status_code == 200, r.text
    assert _row(db_connection, "raj", "full_name, company, phone, phone_country") == (
        "Raj K", "RK Media", "+61412345678", "AU")
    r = client.put(f"/api/admin/users/{uid}", headers=auth, json={"phone": "123", "phone_country": "AU"})
    assert r.status_code == 400
    assert _row(db_connection, "raj", "phone")[0] == "+61412345678"


def test_backfill_only_touches_unambiguous_numbers(db_connection):
    _user(db_connection, "intl", phone="+92 300 1234567")
    _user(db_connection, "local", phone="03001234567")
    _user(db_connection, "broken", phone="+9254646546")
    assert user_profile.backfill_phone_countries() == 1
    assert _row(db_connection, "intl", "phone, phone_country") == ("+923001234567", "PK")
    assert _row(db_connection, "local", "phone, phone_country") == ("03001234567", None)
    assert _row(db_connection, "broken", "phone, phone_country") == ("+9254646546", None)
    assert user_profile.backfill_phone_countries() == 0


def test_geo_hint_and_visits_by_user(client, db_connection):
    assert client.get("/api/geo/hint", headers=EDGE).json() == {"country": "PK"}
    assert client.get("/api/geo/hint").json() == {"country": None}
    _user(db_connection, "adm1", "admin")
    auth = _h(client, "adm1")
    client.post("/api/analytics/visit", headers=dict(EDGE, **auth),
                json={"visitor_id": "visitor-adm-001", "session_id": "session-adm-001", "path": "/home"})
    client.post("/api/analytics/visit", headers=EDGE,
                json={"visitor_id": "visitor-zzz-001", "session_id": "session-zzz-001", "path": "/find"})
    me = client.get("/api/auth/me", headers=auth).json()
    rows = client.get("/api/admin/visitors", params={"user_id": me["id"]}, headers=auth).json()["visits"]
    assert [v["session_id"] for v in rows] == ["session-adm-001"]


def test_shared_dial_codes_keep_the_chosen_country_and_are_not_a_mismatch():
    assert user_profile.normalize_phone("07911 123456", "GB")["country"] == "GB"
    assert user_profile.normalize_phone("5125550142", "US")["country"] == "US"
    assert user_profile.countries_differ("GB", "GG") is False
    assert user_profile.countries_differ("US", "CA") is False
    assert user_profile.countries_differ("PK", "DE") is True
    assert user_profile.countries_differ("PK", None) is False
    assert user_profile.countries_differ("PK", "PK") is False


def test_free_text_phone_from_an_older_app_version_is_never_refused(client, db_connection):
    # No country sent: whatever was typed is kept, valid or not, as before this change.
    assert _register(client, "oldapp", phone="+92 54646546").status_code == 201
    assert _row(db_connection, "oldapp", "phone, phone_country") == ("+92 54646546", None)
    # The current form sends the country, so the same mistake is caught there.
    r = _register(client, "newapp", phone="+92 54646546", phone_country="PK")
    assert r.status_code == 400


def test_signup_location_falls_back_to_what_the_app_reported(client, db_connection):
    bare = {"x-vercel-forwarded-for": "203.0.113.9", "x-vercel-id": "iad1::t", "user-agent": CHROME}
    r = _register(client, "geo1", bare, phone="03001234599", phone_country="PK",
                  geo_country="PK", geo_city="Karachi")
    assert r.status_code == 201, r.text
    assert _row(db_connection, "geo1", "signup_ip, signup_country, signup_city") == (
        "203.0.113.9", "PK", "Karachi")
