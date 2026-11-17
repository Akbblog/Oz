"""API changes for the user-UX redesign (USER_UX_AUDIT_PLAN.md section 8, API-1..4, API-6).

Covers: GET /api/jobs pagination / status filter / counts / derived location,
partial downloads and export hardening, /api/credits/config refund policy,
curated location data invariants, and one end-to-end credit run.
"""
import asyncio
import base64
import io
import json
import os
import uuid
import zipfile
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

BACKEND = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASSWORD = "pw-strong-123"


# --------------------------------------------------------------------------- #
# helpers
# --------------------------------------------------------------------------- #

def _user(conn, username="ux_user", balance=1000):
    from auth import get_password_hash

    cur = conn.cursor()
    cur.execute(
        "INSERT INTO users (username, email, password_hash, is_approved, is_admin, role, created_at, credit_balance) "
        "VALUES (?, ?, ?, 1, 0, 'user', ?, ?)",
        (username, f"{username}@example.com", get_password_hash(PASSWORD), datetime.now().isoformat(), balance),
    )
    conn.commit()
    return cur.lastrowid


def _job(conn, uid, status="completed", cities=("Doha, Qatar",), created_offset=0, category="cafes",
         settled=True, failed_cities=0, max_results=10):
    job_id = str(uuid.uuid4())
    created = (datetime(2026, 1, 1) + timedelta(minutes=created_offset)).isoformat()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO jobs (job_id, user_id, category, cities_data, max_results_per_city, status, progress, "
        "total_cities, created_at, credit_charged, credit_refunded, completed_cities, failed_cities, settled_at) "
        "VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, 20, 0, 0, ?, ?)",
        (job_id, uid, category, json.dumps(list(cities)), max_results, status, len(cities), created,
         failed_cities, created if settled else None),
    )
    conn.commit()
    return job_id


def _result(conn, job_id, n, **over):
    row = {
        "business_name": f"Biz {n}", "phone": "123", "website": "https://example.com", "email": "a@example.com",
        "address": f"{n} Street", "category": "cafes", "city": "Doha", "state": "Qatar",
        "google_maps_url": f"https://www.google.com/maps/place/B{n}",
    }
    row.update(over)
    cols = ", ".join(row)
    conn.cursor().execute(
        f"INSERT INTO results (job_id, {cols}) VALUES (?, {', '.join('?' * len(row))})",
        (job_id, *row.values()),
    )
    conn.commit()


def _client_and_headers(username="ux_user"):
    from main import app

    client = TestClient(app)
    r = client.post("/api/auth/login", json={"username": username, "password": PASSWORD})
    assert r.status_code == 200, r.text
    return client, {"Authorization": f"Bearer {r.json()['access_token']}"}


def _download_workbook(client, headers, job_id):
    import openpyxl

    r = client.get(f"/api/jobs/{job_id}/download", headers=headers)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["encoding"] == "base64" and body["filename"].endswith(".xlsx")
    raw = base64.b64decode(body["content"])
    return body, raw, openpyxl.load_workbook(io.BytesIO(raw))


# --------------------------------------------------------------------------- #
# GET /api/jobs
# --------------------------------------------------------------------------- #

def _seed_mix(conn, uid):
    statuses = ["completed"] * 5 + ["cancelled"] * 3 + ["failed"] * 2 + ["running", "pending"]
    return [_job(conn, uid, status=s, created_offset=i) for i, s in enumerate(statuses)]


def test_jobs_without_params_is_backward_compatible(db_connection):
    uid = _user(db_connection)
    ids = _seed_mix(db_connection, uid)
    client, h = _client_and_headers()

    body = client.get("/api/jobs", headers=h).json()
    assert [j["job_id"] for j in body["jobs"]] == list(reversed(ids))  # all jobs, newest first
    assert body["total"] == 12
    assert body["counts"] == {"all": 12, "active": 2, "completed": 5, "cancelled": 3, "failed": 2}
    job = body["jobs"][0]
    for key in ("job_id", "category", "status", "progress", "total_cities", "credit_estimate", "credit_charged",
                "created_at", "completed_at", "cities", "result_count", "top_city", "completed_cities",
                "credit_refunded", "error", "current_city",
                "max_results_per_city", "failed_cities", "settled", "country", "region", "regions"):
        assert key in job, key


def test_jobs_pagination_and_status_filter(db_connection):
    uid = _user(db_connection)
    ids = _seed_mix(db_connection, uid)
    newest_first = list(reversed(ids))
    client, h = _client_and_headers()

    p1 = client.get("/api/jobs?limit=5&offset=0", headers=h).json()
    p2 = client.get("/api/jobs?limit=5&offset=5", headers=h).json()
    p3 = client.get("/api/jobs?limit=5&offset=10", headers=h).json()
    assert [j["job_id"] for j in p1["jobs"] + p2["jobs"] + p3["jobs"]] == newest_first
    assert len(p3["jobs"]) == 2 and p1["total"] == p3["total"] == 12

    active = client.get("/api/jobs?status=active", headers=h).json()
    assert {j["status"] for j in active["jobs"]} == {"running", "pending"} and active["total"] == 2
    cancelled = client.get("/api/jobs?status=cancelled&limit=2", headers=h).json()
    assert len(cancelled["jobs"]) == 2 and cancelled["total"] == 3
    assert all(j["status"] == "cancelled" for j in cancelled["jobs"])
    assert cancelled["counts"]["all"] == 12  # counts ignore the filter
    failed = client.get("/api/jobs?status=failed&limit=10&offset=1", headers=h).json()
    assert len(failed["jobs"]) == 1 and failed["total"] == 2
    assert client.get("/api/jobs?status=all", headers=h).json()["total"] == 12

    assert client.get("/api/jobs?limit=0", headers=h).status_code == 422
    assert client.get("/api/jobs?limit=101", headers=h).status_code == 422
    assert client.get("/api/jobs?offset=-1", headers=h).status_code == 422
    assert client.get("/api/jobs?status=bogus", headers=h).status_code == 422


def test_jobs_only_lists_own_jobs(db_connection):
    uid = _user(db_connection)
    other = _user(db_connection, username="someone_else")
    _job(db_connection, uid)
    _job(db_connection, other)
    client, h = _client_and_headers()
    body = client.get("/api/jobs", headers=h).json()
    assert body["total"] == 1 and body["counts"]["all"] == 1 and len(body["jobs"]) == 1


def test_job_fields_and_derived_location(db_connection):
    uid = _user(db_connection)
    qatar = _job(db_connection, uid, cities=["Doha, Qatar", "West Bay, Doha"], failed_cities=1, max_results=20,
                 settled=False, created_offset=1)
    multi = _job(db_connection, uid, cities=["Helsinki, Uusimaa", "Turku, Varsinais-Suomi"], created_offset=2)
    ksa = _job(db_connection, uid, cities=["Al Hamra, Jeddah"], created_offset=3)
    unknown = _job(db_connection, uid, cities=["Nowhere, Atlantis", "free text"], created_offset=4)
    client, h = _client_and_headers()

    jobs = {j["job_id"]: j for j in client.get("/api/jobs", headers=h).json()["jobs"]}
    q = jobs[qatar]
    assert (q["country"], q["region"], q["regions"]) == ("Qatar", "Doha", ["Doha"])
    assert q["max_results_per_city"] == 20 and q["failed_cities"] == 1 and q["settled"] is False
    m = jobs[multi]
    assert (m["country"], m["region"], m["regions"]) == ("Finland", "Uusimaa", ["Uusimaa", "Varsinais-Suomi"])
    assert m["settled"] is True
    assert (jobs[ksa]["country"], jobs[ksa]["region"]) == ("KSA", "Makkah Region")
    assert (jobs[unknown]["country"], jobs[unknown]["region"], jobs[unknown]["regions"]) == (None, None, [])

    # Same derived fields on the single-job and active endpoints (job_service.job_payload)
    single = client.get(f"/api/jobs/{multi}", headers=h).json()
    assert (single["country"], single["region"], single["regions"]) == ("Finland", "Uusimaa",
                                                                         ["Uusimaa", "Varsinais-Suomi"])
    running = _job(db_connection, uid, status="running", cities=["Toronto, Ontario"], created_offset=5)
    active = client.get("/api/jobs/active", headers=h).json()["jobs"]
    assert [(j["job_id"], j["country"], j["region"]) for j in active] == [(running, "Canada", "Ontario")]

    # Read-time only: stored data untouched
    cur = db_connection.cursor()
    cur.execute("SELECT cities_data FROM jobs WHERE job_id = ?", (unknown,))
    assert json.loads(cur.fetchone()[0]) == ["Nowhere, Atlantis", "free text"]


def test_old_names_still_importable_from_main():
    import locations
    import main

    assert main._COUNTRY_DATA_FILES is locations.COUNTRY_DATA_FILES
    assert main._find_country_for_region("Uusimaa") == "Finland"
    assert "Uusimaa" in main._load_country_data("Finland")
    assert main._COUNTRY_REGION_FIELD["Canada"] == "province"


# --------------------------------------------------------------------------- #
# GET /api/jobs/{id}/download
# --------------------------------------------------------------------------- #

@pytest.mark.parametrize("status", ["completed", "cancelled", "failed"])
def test_download_terminal_job_with_leads(db_connection, status):
    uid = _user(db_connection)
    jid = _job(db_connection, uid, status=status)
    for n in range(3):
        _result(db_connection, jid, n)
    client, h = _client_and_headers()

    body, _, wb = _download_workbook(client, h, jid)
    ws = wb.active
    assert [c.value for c in ws[1]][:3] == ["#", "Business Name", "Phone"]
    assert [ws.cell(row=r, column=2).value for r in range(2, ws.max_row + 1)] == ["Biz 0", "Biz 1", "Biz 2"]
    assert ws.cell(row=2, column=4).hyperlink.target == "https://example.com"
    assert ws.cell(row=2, column=5).hyperlink.target == "mailto:a@example.com"
    assert body["content_type"] == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


@pytest.mark.parametrize("status", ["completed", "cancelled", "failed"])
def test_download_terminal_job_without_leads_is_404(db_connection, status):
    uid = _user(db_connection)
    jid = _job(db_connection, uid, status=status)
    client, h = _client_and_headers()
    r = client.get(f"/api/jobs/{jid}/download", headers=h)
    assert r.status_code == 404 and r.json()["detail"] == "No leads were saved for this search"


@pytest.mark.parametrize("status", ["running", "pending"])
def test_download_active_job_is_409(db_connection, status):
    uid = _user(db_connection)
    jid = _job(db_connection, uid, status=status)
    _result(db_connection, jid, 1)
    client, h = _client_and_headers()
    r = client.get(f"/api/jobs/{jid}/download", headers=h)
    assert r.status_code == 409 and r.json()["detail"] == "This search is still running"


def test_download_of_someone_elses_job_is_404(db_connection):
    _user(db_connection)
    other = _user(db_connection, username="owner2")
    jid = _job(db_connection, other)
    _result(db_connection, jid, 1)
    client, h = _client_and_headers()
    assert client.get(f"/api/jobs/{jid}/download", headers=h).status_code == 404


def test_download_blocks_formula_injection(db_connection):
    uid = _user(db_connection)
    jid = _job(db_connection, uid)
    evil = '=HYPERLINK("http://evil","x")'
    _result(db_connection, jid, 1, business_name=evil, phone="+1 555 0100", address="@SUM(1)",
            website="=cmd|' /C calc'!A0", email="-2+3", city="\tTabbed", state="\rCR",
            google_maps_url="javascript:alert(1)")
    client, h = _client_and_headers()

    _, raw, wb = _download_workbook(client, h, jid)
    ws = wb.active
    row = {ws.cell(row=1, column=c).value: ws.cell(row=2, column=c) for c in range(1, 10)}
    expected = {"Business Name": evil, "Phone": "+1 555 0100", "Address": "@SUM(1)",
                "Website": "=cmd|' /C calc'!A0", "Email": "-2+3", "City": "\tTabbed"}
    for header, value in expected.items():
        cell = row[header]
        assert cell.value == value, header          # unchanged text, no apostrophe added
        assert cell.data_type == "s", header        # string, not formula
    assert row["Website"].hyperlink is None and row["Email"].hyperlink is None
    assert row["Google Maps"].value == "N/A" and row["Google Maps"].hyperlink is None

    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        sheet_xml = z.read("xl/worksheets/sheet1.xml").decode("utf-8")
    assert "<f>" not in sheet_xml and "<f " not in sheet_xml


def test_download_sheet_title_and_filename_are_sanitised(db_connection):
    uid = _user(db_connection)
    jid = _job(db_connection, uid, category="Cafés/Bars: [24*7]? \\ ok")
    _result(db_connection, jid, 1, city="Düsseldorf")
    client, h = _client_and_headers()

    body, _, wb = _download_workbook(client, h, jid)
    title = wb.active.title
    assert len(title) <= 31 and not any(ch in title for ch in "[]:*?/\\")
    assert body["filename"].endswith(".xlsx")
    stem = body["filename"][:-5]
    assert stem and all(ch.isascii() and (ch.isalnum() or ch in "-_") for ch in stem)
    assert stem.startswith("Dusseldorf_Cafes")


def test_sheet_title_rules():
    import main

    assert main.safe_sheet_title("a/b:c") == "abc"
    assert main.safe_sheet_title("[]:*?/\\") == "Leads"
    assert main.safe_sheet_title("'quoted'") == "quoted"
    assert main.safe_sheet_title("History") == "Leads"
    assert len(main.safe_sheet_title("x" * 80)) == 31
    assert main.safe_download_filename("//", "**") == "Leads.xlsx"


def test_download_survives_illegal_control_characters(db_connection):
    uid = _user(db_connection)
    jid = _job(db_connection, uid, category="bad\x01cat")
    _result(db_connection, jid, 1, business_name="Bad\x00\x07Name\x1f", address="x\x0by", email="a\x01@example.com")
    client, h = _client_and_headers()

    _, _, wb = _download_workbook(client, h, jid)
    ws = wb.active
    assert ws.cell(row=2, column=2).value == "BadName"
    assert ws.cell(row=2, column=6).value == "xy"
    assert "\x01" not in ws.title


def test_historical_job_with_removed_city_still_lists_and_downloads(db_connection):
    from locations import load_country_data

    removed = _removed()
    city = removed["Finland"]["Uusimaa"][0]  # e.g. "Pohja, Uusimaa"
    assert city not in load_country_data("Finland")["Uusimaa"]
    uid = _user(db_connection)
    jid = _job(db_connection, uid, cities=[city])
    _result(db_connection, jid, 1, city=city.split(",")[0], state="Uusimaa")
    client, h = _client_and_headers()

    listed = client.get("/api/jobs", headers=h).json()["jobs"]
    assert listed[0]["job_id"] == jid and listed[0]["cities"] == [city]
    assert (listed[0]["country"], listed[0]["region"]) == ("Finland", "Uusimaa")
    _, _, wb = _download_workbook(client, h, jid)
    assert wb.active.max_row == 2


# --------------------------------------------------------------------------- #
# GET /api/credits/config
# --------------------------------------------------------------------------- #

@pytest.mark.parametrize("policy", ["delivered", "unattempted", "none"])
def test_credits_config_exposes_refund_policy_and_min_cost(db_connection, monkeypatch, policy):
    import job_service
    from database import get_credit_config

    monkeypatch.setenv("JOB_REFUND_POLICY", policy)
    _user(db_connection)
    client, h = _client_and_headers()
    body = client.get("/api/credits/config", headers=h).json()
    assert body["refund_policy"] == policy
    assert body["min_job_cost"] == job_service.estimate_cost(1, 10)
    for key, value in get_credit_config().items():
        assert body[key] == value  # existing keys unchanged
    assert "refund_policy" not in get_credit_config()  # shared config dict not mutated


# --------------------------------------------------------------------------- #
# Location data invariants (D6)
# --------------------------------------------------------------------------- #

def _removed():
    with open(os.path.join(BACKEND, "data", "removed_locations.json"), encoding="utf-8") as f:
        return json.load(f)


def _raw_region_keys(country):
    import locations

    keys = []

    def hook(pairs):
        keys.append([k for k, _ in pairs])
        return dict(pairs)

    with open(os.path.join(BACKEND, locations.COUNTRY_DATA_FILES[country]), encoding="utf-8") as f:
        json.load(f, object_pairs_hook=hook)
    return keys[-1]


def test_location_data_invariants():
    import locations

    for country in locations.COUNTRY_DATA_FILES:
        data = locations.load_country_data(country)
        top = _raw_region_keys(country)
        assert len(top) == len(set(top)), f"{country}: duplicate region keys"
        for region, items in data.items():
            assert items, f"{country}/{region} is empty"
            for item in items:
                assert isinstance(item, str) and "," in item, (country, region, item)
                assert item == item.strip() and item.split(",")[0].strip(), (country, region, item)
            assert len(items) == len(set(items)), f"{country}/{region} has duplicates"


def test_removed_locations_file_is_consistent():
    import locations

    removed = _removed()
    assert set(removed) <= set(locations.COUNTRY_DATA_FILES)
    assert removed, "curation removed nothing?"
    for country, regions in removed.items():
        data = locations.load_country_data(country)
        listed = {x for items in data.values() for x in items}
        for region, items in regions.items():
            assert region in data, (country, region)
            assert items and len(items) == len(set(items)), (country, region)
            for item in items:
                assert "," in item and item not in listed, (country, region, item)
                # still resolvable for historical jobs
                assert locations.resolve_location(item) == (country, region)
    for sample in ("Pohja, Uusimaa", "Karjalohja, Uusimaa", "Nummi-Pusula, Uusimaa"):
        assert sample in removed["Finland"]["Uusimaa"]
    for sample in ("Hamad International Airport, Doha", "Retail District, Doha", "Entertainment City, Doha",
                   "Educational District, Doha"):
        assert sample in removed["Qatar"]["Doha"]


def test_curation_doc_lists_every_removed_string():
    with open(os.path.join(BACKEND, "data", "CURATION.md"), encoding="utf-8") as f:
        doc = f.read()
    for regions in _removed().values():
        for items in regions.values():
            for item in items:
                assert item.split(",")[0].strip() in doc, item


# --------------------------------------------------------------------------- #
# End to end: cancelled after saving leads (policy "delivered")
# --------------------------------------------------------------------------- #

def _place(n, city):
    return {"business_name": f"Lead {n}", "phone": "+1 555 0100", "website": "", "email": "", "address": f"{n} St",
            "category": "x", "city": city, "state": "Q",
            "google_maps_url": f"https://www.google.com/maps/place/L{n}/data=!1s0x1:0x{n:06x}"}


class _Scripted:
    job_id = None

    def __init__(self, *a, **k):
        pass

    async def scrape_location(self, category, city, state, max_results=10, *, on_result=None,
                              should_stop=None, exclude_keys=None):
        from database import get_db

        if city == "A":
            for i, n in enumerate([1, 2, 3]):
                await on_result(i, 3, _place(n, city))
            return []
        await on_result(0, 3, _place(4, city))
        c = get_db()
        c.cursor().execute("UPDATE jobs SET status='cancelled' WHERE job_id = ?", (_Scripted.job_id,))
        c.commit()
        c.close()
        for i, n in enumerate([5, 6], start=1):
            if await should_stop():
                return []
            await on_result(i, 3, _place(n, city))
        return []

    async def close(self):
        pass


def test_cancelled_job_with_leads_settles_and_downloads_partial(db_connection, monkeypatch):
    import job_service
    import main

    monkeypatch.setenv("JOB_REFUND_POLICY", "delivered")
    monkeypatch.setattr(main, "GoogleBusinessScraper", _Scripted)
    monkeypatch.setattr(main, "_PER_CITY_TIMEOUT", 3.0)
    monkeypatch.setattr(main, "_HEARTBEAT_SECONDS", 0.05)
    uid = _user(db_connection, balance=1000)
    job = job_service.create_job_atomic(user_id=uid, category="x", cities=["A, Q", "B, Q", "C, Q"],
                                        max_results_per_city=3, idempotency_key=None)
    jid = job["job_id"]
    _Scripted.job_id = jid
    assert job_service.claim_job(jid, "w1")
    asyncio.run(main.run_job_by_id(jid, "w1"))

    row = job_service.fetch_job_row(db_connection.cursor(), jid)
    assert row["status"] == "cancelled" and row["settled_at"]
    cur = db_connection.cursor()
    cur.execute("SELECT business_name FROM results WHERE job_id = ? ORDER BY id", (jid,))
    saved = [r[0] for r in cur.fetchall()]
    assert saved == ["Lead 1", "Lead 2", "Lead 3", "Lead 4"]

    charged = int(row["credit_charged"])
    assert charged == job_service.estimate_cost(3, 3)
    expected_refund = job_service.compute_refund(
        charged=charged, final_status="cancelled", total_cities=3,
        attempted_cities=int(row["completed_cities"]), leads_delivered=len(saved), max_results_per_city=3,
        policy="delivered")
    assert int(row["credit_refunded"]) == expected_refund > 0

    cur.execute("SELECT credit_balance FROM users WHERE id = ?", (uid,))
    balance = cur.fetchone()[0]
    cur.execute("SELECT COALESCE(SUM(amount), 0) FROM credit_ledger WHERE user_id = ?", (uid,))
    assert balance - 1000 == cur.fetchone()[0] == -charged + expected_refund

    client, h = _client_and_headers()
    listed = client.get("/api/jobs?status=cancelled", headers=h).json()["jobs"][0]
    assert listed["settled"] is True and listed["credit_refunded"] == expected_refund
    _, _, wb = _download_workbook(client, h, jid)
    ws = wb.active
    assert [ws.cell(row=r, column=2).value for r in range(2, ws.max_row + 1)] == saved
    assert ws.cell(row=2, column=3).value == "+1 555 0100" and ws.cell(row=2, column=3).data_type == "s"
