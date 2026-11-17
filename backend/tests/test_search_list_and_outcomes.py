"""My searches server-side query/date/sort/pagination, per-city outcomes and lead ids.

Finishing pass items 2, 4 and 6: the list endpoint filters, sorts and pages
on the server across all of a user's searches (tested with > 20 jobs), every
search reports cities searched / with leads / empty / timed out, and every
lead carries a stable ``lead_id`` (+ ``lead_key``).
"""
import json
import uuid
from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from tests.test_user_ux_api import PASSWORD, _client_and_headers, _user


def _job(conn, uid, *, category="cafes", cities=("Doha, Qatar",), status="completed", created=None,
         completed_cities=None, logs=()):
    job_id = str(uuid.uuid4())
    created = (created or datetime(2026, 1, 1)).isoformat()
    done = len(cities) if completed_cities is None else completed_cities
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO jobs (job_id, user_id, category, cities_data, max_results_per_city, status, progress, "
        "total_cities, created_at, credit_charged, credit_refunded, completed_cities, failed_cities, settled_at) "
        "VALUES (?, ?, ?, ?, 10, ?, 0, ?, ?, 20, 0, ?, 0, ?)",
        (job_id, uid, category, json.dumps(list(cities)), status, len(cities), created, done, created),
    )
    for msg in logs:
        cur.execute("INSERT INTO job_logs (job_id, log_message, created_at) VALUES (?, ?, ?)", (job_id, msg, created))
    conn.commit()
    return job_id


def _leads(conn, job_id, city, state, n, start=0):
    cur = conn.cursor()
    for i in range(n):
        k = f"{job_id[:8]}-{city}-{start + i}"
        cur.execute(
            "INSERT INTO results (job_id, business_name, phone, website, email, address, category, city, state, "
            "google_maps_url, dedupe_key) VALUES (?, ?, '1', '', '', 'addr', 'cafes', ?, ?, ?, ?)",
            (job_id, f"Biz {k}", city, state, f"https://maps.example/{k}", "id:" + k),
        )
    conn.commit()


@pytest.fixture
def many(db_connection):
    """25 searches: 23 'cafes' (Doha, newest first by minute), 1 'plumbers' far back, 1 'dentists' in Montréal."""
    uid = _user(db_connection)
    base = datetime(2026, 3, 1, 12, 0)
    ids = []
    for i in range(23):
        jid = _job(db_connection, uid, created=base + timedelta(hours=i))
        _leads(db_connection, jid, "Doha", "Qatar", i % 5)
        ids.append(jid)
    old = _job(db_connection, uid, category="plumbers", cities=("Lusail, Qatar",), created=datetime(2025, 6, 1))
    _leads(db_connection, old, "Lusail", "Qatar", 40)
    accent = _job(db_connection, uid, category="dentists", cities=("Montréal, Quebec",), status="failed",
                  created=base - timedelta(days=1), completed_cities=0)
    other = _user(db_connection, "someone_else")
    _job(db_connection, other, category="plumbers")
    client, h = _client_and_headers()
    return {"client": client, "h": h, "ids": ids, "old": old, "accent": accent}


def _get(m, **params):
    r = m["client"].get("/api/jobs", params=params, headers=m["h"])
    assert r.status_code == 200, r.text
    return r.json()


def test_query_finds_a_search_beyond_the_first_page(many):
    first = _get(many, limit=20, offset=0)
    assert first["total"] == 25 and first["overall_total"] == 25
    assert many["old"] not in [j["job_id"] for j in first["jobs"]]  # oldest -> not on page 1
    hit = _get(many, limit=20, offset=0, q="PLUMB")
    assert [j["job_id"] for j in hit["jobs"]] == [many["old"]]
    assert hit["total"] == 1 and hit["counts"]["all"] == 1 and hit["overall_total"] == 25


def test_query_matches_city_names_including_accents_and_job_id(many):
    assert [j["job_id"] for j in _get(many, q="montréal")["jobs"]] == [many["accent"]]
    assert [j["job_id"] for j in _get(many, q="lusail")["jobs"]] == [many["old"]]
    prefix = many["ids"][7][:8]
    assert many["ids"][7] in [j["job_id"] for j in _get(many, q=prefix)["jobs"]]
    # LIKE wildcards are literal
    assert _get(many, q="%")["total"] == 0
    assert _get(many, q="_")["total"] == 0


def test_pagination_is_exact_across_pages_with_filters(many):
    seen = []
    for offset in (0, 20):
        page = _get(many, limit=20, offset=offset, q="cafes")
        assert page["total"] == 23
        seen += [j["job_id"] for j in page["jobs"]]
    assert len(seen) == 23 and len(set(seen)) == 23
    assert seen == list(reversed(many["ids"]))  # newest first, no gaps/duplicates


def test_date_range_runs_on_the_server(many):
    # 2026-03-01 12:00 .. 2026-03-02 10:00 local == the 23 cafes jobs
    r = _get(many, limit=5, **{"from": "2026-03-01T00:00:00", "to": "2026-03-02T00:00:00"})
    assert r["total"] == 12  # hours 12..23 on 2026-03-01
    r = _get(many, limit=5, **{"from": "2026-03-01T00:00:00"})
    assert r["total"] == 23
    assert r["counts"]["failed"] == 0  # accent job is 2026-02-28
    r = _get(many, **{"to": "2026-01-01T00:00:00"})
    assert [j["job_id"] for j in r["jobs"]] == [many["old"]]
    bad = many["client"].get("/api/jobs", params={"from": "yesterday"}, headers=many["h"])
    assert bad.status_code == 422


def test_sort_most_leads_and_oldest_span_all_pages(many):
    top = _get(many, limit=3, sort="most_leads")["jobs"]
    assert top[0]["job_id"] == many["old"] and top[0]["result_count"] == 40
    assert [j["result_count"] for j in top[1:]] == [4, 4]
    oldest = _get(many, limit=1, sort="oldest")["jobs"]
    assert oldest[0]["job_id"] == many["old"]
    assert many["client"].get("/api/jobs", params={"sort": "random"}, headers=many["h"]).status_code == 422


def test_status_tab_counts_follow_query_and_dates(many):
    r = _get(many, q="dentists", status="failed")
    assert r["total"] == 1 and r["counts"] == {"all": 1, "active": 0, "completed": 0, "cancelled": 0, "failed": 1}
    r = _get(many, q="dentists", status="completed")
    assert r["total"] == 0 and r["jobs"] == []


def test_no_params_still_returns_everything(many):
    r = _get(many)
    assert len(r["jobs"]) == 25 and r["sort"] == "newest"


# ---------------------------------------------------------------- outcomes --

def test_city_outcomes_distinguish_empty_timed_out_and_not_searched(db_connection):
    uid = _user(db_connection)
    jid = _job(db_connection, uid, status="cancelled",
               cities=("Doha, Qatar", "Lusail, Qatar", "Al Khor, Qatar", "Dukhan, Qatar", "Mesaieed, Qatar"),
               completed_cities=3, logs=("Timeout scraping Al Khor, Qatar after 180s - kept 0 leads found before the timeout",))
    _leads(db_connection, jid, "Doha", "Qatar", 3)
    _leads(db_connection, jid, "Dukhan", "Qatar", 1)  # partial city when cancelled
    client, h = _client_and_headers()

    detail = client.get(f"/api/jobs/{jid}", headers=h).json()
    assert [(c["city"], c["leads"], c["outcome"]) for c in detail["city_outcomes"]] == [
        ("Doha, Qatar", 3, "with_leads"),
        ("Lusail, Qatar", 0, "empty"),
        ("Al Khor, Qatar", 0, "timed_out"),
        ("Dukhan, Qatar", 1, "interrupted"),
        ("Mesaieed, Qatar", 0, "not_searched"),
    ]
    expect = {"cities_total": 5, "cities_searched": 3, "cities_with_leads": 2, "cities_empty": 1,
              "cities_timed_out": 1, "cities_interrupted": 1, "cities_not_searched": 1}
    assert detail["city_summary"] == expect
    listed = client.get("/api/jobs", headers=h).json()["jobs"][0]
    assert listed["city_summary"] == expect


def test_completed_with_no_leads_reports_every_city_empty(db_connection):
    uid = _user(db_connection)
    jid = _job(db_connection, uid, cities=("Doha, Qatar", "Lusail, Qatar"))
    client, h = _client_and_headers()
    s = client.get(f"/api/jobs/{jid}", headers=h).json()
    assert s["result_count"] == 0
    assert s["city_summary"]["cities_searched"] == 2 and s["city_summary"]["cities_empty"] == 2
    assert s["city_summary"]["cities_with_leads"] == 0


def test_city_match_is_case_and_unicode_insensitive(db_connection):
    uid = _user(db_connection)
    jid = _job(db_connection, uid, cities=("Montréal, Quebec",))
    _leads(db_connection, jid, "MONTRÉAL", "quebec", 2)
    client, h = _client_and_headers()
    s = client.get(f"/api/jobs/{jid}", headers=h).json()
    assert s["city_outcomes"] == [{"city": "Montréal, Quebec", "leads": 2, "outcome": "with_leads"}]


# ---------------------------------------------------------------- lead ids --

def test_leads_carry_stable_ids_in_both_result_endpoints(db_connection):
    uid = _user(db_connection)
    jid = _job(db_connection, uid)
    _leads(db_connection, jid, "Doha", "Qatar", 3)
    client, h = _client_and_headers()
    a = client.get(f"/api/jobs/{jid}", headers=h).json()["results"]
    b = client.get(f"/api/jobs/{jid}/results", headers=h).json()["results"]
    assert [r["lead_id"] for r in a] == [r["lead_id"] for r in b]
    assert len({r["lead_id"] for r in a}) == 3 and all(isinstance(r["lead_id"], int) for r in a)
    assert all(r["lead_key"].startswith("id:") for r in a)
    # unchanged on re-read
    again = client.get(f"/api/jobs/{jid}", headers=h).json()["results"]
    assert [r["lead_id"] for r in again] == [r["lead_id"] for r in a]


def test_query_by_country_name_matches_region_suffixes(db_connection):
    uid = _user(db_connection)
    ca = _job(db_connection, uid, category="dentists", cities=("Toronto, Ontario", "Ottawa, Ontario"))
    qa = _job(db_connection, uid, category="dentists", cities=("Doha, Qatar",))
    client, h = _client_and_headers()
    get = lambda q: [j["job_id"] for j in client.get("/api/jobs", params={"q": q}, headers=h).json()["jobs"]]
    assert get("Canada") == [ca]
    assert get("can") == [ca]
    assert get("qatar") == [qa]
    assert sorted(get("dentists")) == sorted([ca, qa])
    # 2 letters: no country/region expansion; only a literal match (e.g. inside a random job id) may appear
    assert all("ca" in jid for jid in get("ca"))
