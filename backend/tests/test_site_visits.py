"""Visitor tracking (analytics/visits.py, migration 019).

Covers IP/geo header precedence behind Vercel + Cloudflare, user-agent parsing,
traffic-source classification, the per-session upsert, and the admin endpoints
(auth, filters, zero-filled summary, detail + 404).

Runs on SQLite by default and on MariaDB with IL_TEST_MYSQL_URL (see conftest).
"""
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from analytics import visits

PW = "pw-strong-123"
CHROME = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
          "Chrome/131.0.0.0 Safari/537.36")
IPHONE = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 "
          "(KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1")
OWN = ["infinity-leads.vercel.app"]


def _user(conn, username, role="user"):
    from auth import get_password_hash

    now = datetime.now().isoformat()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO users (username, email, password_hash, is_approved, is_admin, role, created_at, credit_balance, "
        "approved_at) VALUES (?, ?, ?, 1, ?, ?, ?, 0, ?)",
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

    return TestClient(app)


@pytest.fixture
def admin(db_connection):
    return _user(db_connection, "adm1", "admin")


def _beacon(client, session_id, path="/", headers=None, **body):
    h = {"user-agent": CHROME}
    h.update(headers or {})
    payload = {"session_id": session_id, "visitor_id": body.pop("visitor_id", "visitor-aaaa"), "path": path}
    payload.update(body)
    return client.post("/api/analytics/visit", json=payload, headers=h)


def _row(conn, session_id):
    cur = conn.cursor()
    cur.execute(
        "SELECT user_id, ip_address, country, city, source, referrer_host, landing_path, exit_path, page_count, "
        "browser, os, device_type, is_bot FROM site_visits WHERE session_id = ?", (session_id,))
    return cur.fetchone()


# --------------------------------------------------------------------------- #
# pure helpers
# --------------------------------------------------------------------------- #

def test_ip_prefers_vercel_then_cloudflare_then_xff_then_socket():
    all_headers = {"x-vercel-forwarded-for": "203.0.113.7, 10.0.0.1", "cf-connecting-ip": "76.76.21.21",
                   "x-forwarded-for": "198.51.100.9, 76.76.21.21"}
    assert visits.resolve_client_ip(all_headers, "127.0.0.1") == "203.0.113.7"
    assert visits.resolve_client_ip({"cf-connecting-ip": "76.76.21.21",
                                     "x-forwarded-for": "198.51.100.9"}, "127.0.0.1") == "76.76.21.21"
    assert visits.resolve_client_ip({"x-forwarded-for": "198.51.100.9, 10.0.0.1"}, "127.0.0.1") == "198.51.100.9"
    assert visits.resolve_client_ip({}, "192.0.2.4") == "192.0.2.4"
    assert visits.resolve_client_ip({}, None) is None


def test_geo_uses_vercel_headers_and_ignores_cloudflare_country_behind_vercel():
    geo = visits.resolve_geo({"x-vercel-ip-country": "pk", "x-vercel-ip-country-region": "PB",
                              "x-vercel-ip-city": "Dera%20Ghazi%20Khan", "cf-ipcountry": "US"})
    assert geo == {"country": "PK", "region": "PB", "city": "Dera Ghazi Khan"}
    # Through Vercel but no Vercel geo: Cloudflare only saw Vercel's egress, so unknown.
    assert visits.resolve_geo({"x-vercel-id": "fra1::abc", "cf-ipcountry": "US"})["country"] is None
    # Direct to the tunnel: Cloudflare's country is the visitor's.
    assert visits.resolve_geo({"cf-ipcountry": "GB"}) == {"country": "GB", "region": None, "city": None}
    assert visits.resolve_geo({"cf-ipcountry": "XX"})["country"] is None
    assert visits.resolve_geo({}) == {"country": None, "region": None, "city": None}


@pytest.mark.parametrize("ua,browser,os_name,device,is_bot", [
    (CHROME, "Chrome", "Windows", "desktop", False),
    (IPHONE, "Safari", "iOS", "mobile", False),
    ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 "
     "Safari/537.36 Edg/131.0.0.0", "Edge", "Windows", "desktop", False),
    ("Mozilla/5.0 (X11; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0", "Firefox", "Linux", "desktop", False),
    ("Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 "
     "Mobile Safari/537.36", "Chrome", "Android", "mobile", False),
    ("Mozilla/5.0 (iPad; CPU OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 "
     "Mobile/15E148 Safari/604.1", "Safari", "iOS", "tablet", False),
    ("Mozilla/5.0 (Linux; Android 13; SM-X700) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 "
     "Safari/537.36", "Chrome", "Android", "tablet", False),
    ("Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)", "Bot", "Other", "bot", True),
    ("python-requests/2.32.3", "Bot", "Other", "bot", True),
    ("", None, None, "bot", True),
])
def test_user_agent_parsing(ua, browser, os_name, device, is_bot):
    assert visits.parse_user_agent(ua) == {"browser": browser, "os": os_name, "device_type": device,
                                           "is_bot": is_bot}


@pytest.mark.parametrize("referrer,utm,expected", [
    (None, None, "direct"),
    ("", None, "direct"),
    ("https://www.google.com/", None, "search"),
    ("https://www.google.co.uk/search?q=leads", None, "search"),
    ("https://duckduckgo.com/", None, "search"),
    ("https://www.reddit.com/r/buildinpublic/", None, "social"),
    ("https://t.co/abc", None, "social"),
    ("https://l.facebook.com/l.php", None, "social"),
    ("https://some-blog.example/post", None, "referral"),
    ("https://notgoogle.example/", None, "referral"),
    ("https://infinity-leads.vercel.app/pricing", None, "internal"),
    ("https://www.google.com/", "newsletter", "campaign"),
    (None, "reddit", "campaign"),
])
def test_source_classification(referrer, utm, expected):
    assert visits.classify_source(referrer, utm_source=utm, own=OWN) == expected


def test_paths_drop_query_strings_and_one_time_tokens():
    assert visits.clean_path("/pricing?ref=abc#top") == "/pricing"
    assert visits.clean_path("/reset-password/SECRET-TOKEN") == "/reset-password"
    assert visits.clean_path("https://infinity-leads.vercel.app/admin?x=1") == "/admin"
    assert visits.clean_path("find") == "/find"
    assert visits.clean_path(None) is None


# --------------------------------------------------------------------------- #
# beacon / upsert
# --------------------------------------------------------------------------- #

def test_first_hit_inserts_and_later_hits_bump_the_same_row(client, db_connection):
    headers = {"x-vercel-forwarded-for": "203.0.113.7", "cf-connecting-ip": "76.76.21.21",
               "x-vercel-ip-country": "PK", "x-vercel-ip-city": "Lahore"}
    r = _beacon(client, "sess-000001", "/login?next=/home", headers,
                referrer="https://www.reddit.com/r/buildinpublic/", language="en-US",
                screen_w=1920, screen_h=1080, timezone="Asia/Karachi")
    assert r.status_code == 200 and r.json() == {"ok": True}
    assert _beacon(client, "sess-000001", "/register", headers).json() == {"ok": True}
    assert _beacon(client, "sess-000001", "/pricing", headers).json() == {"ok": True}

    row = _row(db_connection, "sess-000001")
    assert row is not None
    (user_id, ip, country, city, source, ref_host, landing, exit_path, pages, browser, os_name, device, is_bot) = row
    assert user_id is None
    assert (ip, country, city) == ("203.0.113.7", "PK", "Lahore")
    assert (source, ref_host) == ("social", "reddit.com")
    assert (landing, exit_path, pages) == ("/login", "/pricing", 3)
    assert (browser, os_name, device, int(is_bot)) == ("Chrome", "Windows", "desktop", 0)

    cur = db_connection.cursor()
    cur.execute("SELECT COUNT(*) FROM site_visits")
    assert cur.fetchone()[0] == 1


def test_user_is_attached_once_signed_in_and_token_wins_over_body(client, db_connection, admin):
    assert _beacon(client, "sess-000002", "/login").json()["ok"] is True
    assert _row(db_connection, "sess-000002")[0] is None
    auth = _h(client, "adm1")
    assert _beacon(client, "sess-000002", "/home", auth, user_id=999999).json()["ok"] is True
    assert _row(db_connection, "sess-000002")[0] == admin
    # A later anonymous hit (token expired) must not detach the user.
    assert _beacon(client, "sess-000002", "/find").json()["ok"] is True
    row = _row(db_connection, "sess-000002")
    assert row[0] == admin and row[8] == 3


def test_junk_is_ignored_quietly(client, db_connection):
    for body in ({}, {"session_id": ""}, {"session_id": "x"}, {"session_id": "has spaces!!"},
                 {"session_id": {"a": 1}}, [1, 2], "nope"):
        r = client.post("/api/analytics/visit", json=body, headers={"user-agent": CHROME})
        assert r.status_code == 200 and r.json() == {"ok": False}, body
    r = _beacon(client, "sess-000003", "/" + "p" * 2000, referrer="https://e.example/" + "r" * 3000,
                screen_w="wide", screen_h=-5, language="x" * 500, utm_source=["a"])
    assert r.json() == {"ok": True}
    cur = db_connection.cursor()
    cur.execute("SELECT landing_path, referrer, screen_w, screen_h, language, utm_source, source FROM site_visits")
    rows = cur.fetchall()
    assert len(rows) == 1
    landing, referrer, sw, sh, lang, utm, source = rows[0]
    assert len(landing) == 255 and len(referrer) == 512 and len(lang) == 32
    assert sw is None and sh is None and utm is None and source == "referral"


def test_record_visit_never_raises(monkeypatch):
    def boom(*a, **k):
        raise RuntimeError("db down")

    monkeypatch.setattr(visits, "execute_query", boom)
    assert visits.record_visit({"session_id": "sess-000004", "path": "/"}, {"user-agent": CHROME}) is False
    assert visits.record_visit(None, {}) is False


# --------------------------------------------------------------------------- #
# admin endpoints
# --------------------------------------------------------------------------- #

def test_admin_endpoints_require_admin(client, db_connection, admin):
    _user(db_connection, "plain1", "user")
    for url in ("/api/admin/visitors", "/api/admin/visitors/summary", "/api/admin/visitors/sess-000001"):
        assert client.get(url).status_code in (401, 403), url
        assert client.get(url, headers=_h(client, "plain1")).status_code == 403, url
    assert client.get("/api/admin/visitors", headers=_h(client, "adm1")).status_code == 200


def _seed(client, admin_headers):
    pk = {"x-vercel-forwarded-for": "203.0.113.7", "x-vercel-ip-country": "PK", "x-vercel-ip-city": "Lahore"}
    us = {"x-vercel-forwarded-for": "198.51.100.9", "x-vercel-ip-country": "US", "x-vercel-ip-city": "Austin",
          "user-agent": IPHONE}
    _beacon(client, "sess-anon-pk", "/", pk, visitor_id="visitor-pk", referrer="https://www.google.com/")
    _beacon(client, "sess-anon-pk", "/pricing", pk, visitor_id="visitor-pk")
    _beacon(client, "sess-anon-us", "/login", us, visitor_id="visitor-us",
            referrer="https://www.reddit.com/r/x/")
    _beacon(client, "sess-user-pk", "/home", {**pk, **admin_headers}, visitor_id="visitor-pk")
    _beacon(client, "sess-bot-001", "/", {"user-agent": "Mozilla/5.0 (compatible; Googlebot/2.1)",
                                          "x-vercel-forwarded-for": "192.0.2.50"}, visitor_id="visitor-bot")


def test_list_shape_filters_and_pagination(client, db_connection, admin):
    auth = _h(client, "adm1")
    _seed(client, auth)

    body = client.get("/api/admin/visitors", headers=auth).json()
    assert body["total"] == 4 and body["limit"] == 50 and body["offset"] == 0
    by_session = {v["session_id"]: v for v in body["visits"]}
    assert set(by_session["sess-anon-pk"]) == {
        "id", "session_id", "visitor_id", "user_id", "username", "ip_address", "country", "region", "city",
        "referrer", "referrer_host", "source", "utm_source", "utm_medium", "utm_campaign", "landing_path",
        "exit_path", "page_count", "browser", "os", "device_type", "is_bot", "language", "timezone", "screen_w",
        "screen_h", "user_agent", "first_seen_at", "last_seen_at", "duration_seconds", "is_returning"}
    anon = by_session["sess-anon-pk"]
    assert anon["page_count"] == 2 and anon["source"] == "search" and anon["is_bot"] is False
    assert anon["username"] is None and anon["duration_seconds"] >= 0
    signed = by_session["sess-user-pk"]
    assert signed["user_id"] == admin and signed["username"] == "adm1"
    assert by_session["sess-bot-001"]["is_bot"] is True and by_session["sess-bot-001"]["device_type"] == "bot"

    def sessions(**params):
        r = client.get("/api/admin/visitors", params=params, headers=auth)
        assert r.status_code == 200, r.text
        return {v["session_id"] for v in r.json()["visits"]}

    assert sessions(kind="anonymous") == {"sess-anon-pk", "sess-anon-us"}
    assert sessions(kind="user") == {"sess-user-pk"}
    assert sessions(kind="bot") == {"sess-bot-001"}
    assert sessions(country="pk") == {"sess-anon-pk", "sess-user-pk"}
    assert sessions(source="social") == {"sess-anon-us"}
    assert sessions(q="198.51.100") == {"sess-anon-us"}
    assert sessions(q="adm1") == {"sess-user-pk"}
    assert sessions(q="reddit") == {"sess-anon-us"}
    assert sessions(q="Austin") == {"sess-anon-us"}
    assert sessions(q="/pric") == set()  # landing path, not exit path
    assert sessions(q="100%") == set()   # wildcard is escaped, not a match-all

    page = client.get("/api/admin/visitors", params={"limit": 1, "offset": 1}, headers=auth).json()
    assert page["total"] == 4 and len(page["visits"]) == 1 and page["limit"] == 1 and page["offset"] == 1
    capped = client.get("/api/admin/visitors", params={"limit": 5000, "days": 99999}, headers=auth).json()
    assert capped["limit"] == 200


def test_returning_flag_and_old_visits_fall_out_of_the_window(client, db_connection, admin):
    auth = _h(client, "adm1")
    _beacon(client, "sess-old-0001", "/", visitor_id="visitor-rr")
    old = (datetime.now(timezone.utc) - timedelta(days=20)).replace(microsecond=0)
    cur = db_connection.cursor()
    cur.execute("UPDATE site_visits SET first_seen_at = ?, last_seen_at = ?, date_bucket = ? WHERE session_id = ?",
                (old.isoformat(), old.isoformat(), old.strftime("%Y-%m-%d"), "sess-old-0001"))
    db_connection.commit()
    _beacon(client, "sess-new-0001", "/", visitor_id="visitor-rr")

    week = client.get("/api/admin/visitors", params={"days": 7}, headers=auth).json()
    assert [v["session_id"] for v in week["visits"]] == ["sess-new-0001"]
    assert week["visits"][0]["is_returning"] is True
    month = client.get("/api/admin/visitors", params={"days": 30}, headers=auth).json()
    assert [v["session_id"] for v in month["visits"]] == ["sess-new-0001", "sess-old-0001"]
    assert month["visits"][1]["is_returning"] is False

    totals = client.get("/api/admin/visitors/summary", params={"days": 7}, headers=auth).json()["totals"]
    assert (totals["visits"], totals["unique_visitors"]) == (1, 1)
    assert (totals["new_visitors"], totals["returning_visitors"]) == (0, 1)
    assert totals["active_now"] == 1


def test_summary_is_zero_filled_when_empty(client, db_connection, admin):
    body = client.get("/api/admin/visitors/summary", params={"days": 7}, headers=_h(client, "adm1")).json()
    assert body["days"] == 7
    assert body["totals"] == {"visits": 0, "unique_visitors": 0, "unique_ips": 0, "signed_in": 0, "anonymous": 0,
                              "bots": 0, "page_views": 0, "active_now": 0, "avg_pages": 0, "new_visitors": 0,
                              "returning_visitors": 0}
    today = datetime.now(timezone.utc).date()
    assert [d["date"] for d in body["series"]] == [(today - timedelta(days=i)).isoformat() for i in range(6, -1, -1)]
    assert all(d["visits"] == 0 and d["unique_visitors"] == 0 for d in body["series"])
    for key in ("top_sources", "top_referrers", "top_countries", "top_pages", "devices", "browsers", "os"):
        assert body[key] == [], key


def test_summary_counts_humans_and_reports_bots_separately(client, db_connection, admin):
    auth = _h(client, "adm1")
    _seed(client, auth)
    body = client.get("/api/admin/visitors/summary", params={"days": 3}, headers=auth).json()
    t = body["totals"]
    assert (t["visits"], t["bots"], t["signed_in"], t["anonymous"]) == (3, 1, 1, 2)
    assert (t["unique_visitors"], t["unique_ips"], t["page_views"]) == (2, 2, 4)
    assert t["avg_pages"] == 1.33 and t["active_now"] == 3
    assert (t["new_visitors"], t["returning_visitors"]) == (1, 1)
    assert len(body["series"]) == 3
    assert body["series"][-1] == {"date": datetime.now(timezone.utc).date().isoformat(), "visits": 3,
                                  "unique_visitors": 2}
    assert body["series"][0]["visits"] == 0

    def as_map(key):
        return {x["label"]: x["count"] for x in body[key]}

    assert as_map("top_sources") == {"direct": 1, "search": 1, "social": 1}
    assert as_map("top_referrers") == {"google.com": 1, "reddit.com": 1}
    assert as_map("top_countries") == {"PK": 2, "US": 1}
    assert as_map("top_pages") == {"/": 1, "/login": 1, "/home": 1}
    assert as_map("devices") == {"desktop": 2, "mobile": 1}
    assert as_map("browsers") == {"Chrome": 2, "Safari": 1}
    assert as_map("os") == {"Windows": 2, "iOS": 1}
    assert body["top_countries"][0] == {"label": "PK", "count": 2}


def test_detail_has_page_trail_and_other_visits_and_404s(client, db_connection, admin):
    auth = _h(client, "adm1")
    _seed(client, auth)
    now = datetime.now(timezone.utc).replace(microsecond=0)
    events = [{"session_id": "sess-anon-pk", "event_name": "page_view", "page": page,
               "created_at": (now + timedelta(seconds=i)).isoformat()}
              for i, page in enumerate(["/", "/pricing"])]
    assert client.post("/api/analytics/events", json={"events": events}).json() == {"ingested": 2}

    body = client.get("/api/admin/visitors/sess-anon-pk", headers=auth).json()
    assert set(body) == {"visit", "pages", "other_visits"}
    assert body["visit"]["session_id"] == "sess-anon-pk" and body["visit"]["page_count"] == 2
    assert [(p["page"], p["event_name"]) for p in body["pages"]] == [("/", "page_view"), ("/pricing", "page_view")]
    assert set(body["pages"][0]) == {"page", "event_name", "created_at"}
    assert [v["session_id"] for v in body["other_visits"]] == ["sess-user-pk"]

    assert client.get("/api/admin/visitors/does-not-exist", headers=auth).status_code == 404
    # "summary" is a real route, never treated as a session id.
    assert "totals" in client.get("/api/admin/visitors/summary", headers=auth).json()


def test_heartbeat_keeps_a_session_live_without_counting_a_page(client, db_connection, admin):
    auth = _h(client, "adm1")
    _beacon(client, "sess-live-0001", "/find")
    _beacon(client, "sess-idle-0001", "/pricing")
    stale = (datetime.now(timezone.utc) - timedelta(minutes=30)).replace(microsecond=0).isoformat()
    cur = db_connection.cursor()
    cur.execute("UPDATE site_visits SET last_seen_at = ?", (stale,))
    db_connection.commit()

    live = client.get("/api/admin/visitors", params={"live": "true"}, headers=auth).json()
    assert live["visits"] == [] and live["total"] == 0

    assert _beacon(client, "sess-live-0001", "/find", heartbeat=True).json() == {"ok": True}
    live = client.get("/api/admin/visitors", params={"live": "true"}, headers=auth).json()
    assert [v["session_id"] for v in live["visits"]] == ["sess-live-0001"]
    assert live["visits"][0]["page_count"] == 1, "a heartbeat is not a page view"
    assert live["visits"][0]["exit_path"] == "/find"

    # A heartbeat for a session the server has never seen still creates it.
    assert _beacon(client, "sess-new-hb-01", "/home", heartbeat=True).json() == {"ok": True}
    live = client.get("/api/admin/visitors", params={"live": "true"}, headers=auth).json()
    assert {v["session_id"] for v in live["visits"]} == {"sess-live-0001", "sess-new-hb-01"}


def test_beacons_are_rate_limited_per_ip(client, db_connection, monkeypatch):
    monkeypatch.setattr(visits, "_RATE_LIMIT_PER_MINUTE", 3)
    visits._rate.clear()
    flood = {"x-vercel-forwarded-for": "203.0.113.200", "x-vercel-id": "iad1::t"}
    results = [_beacon(client, f"sess-flood-{i:03d}", "/", flood).json()["ok"] for i in range(5)]
    assert results == [True, True, True, False, False]
    other = {"x-vercel-forwarded-for": "203.0.113.201", "x-vercel-id": "iad1::t"}
    assert _beacon(client, "sess-other-001", "/", other).json() == {"ok": True}
    cur = db_connection.cursor()
    cur.execute("SELECT COUNT(*) FROM site_visits")
    assert cur.fetchone()[0] == 4
    visits._rate.clear()


@pytest.fixture(autouse=True)
def _fresh_rate_limit():
    visits._rate.clear()
    yield
    visits._rate.clear()
