"""CRM activities/agenda (timezone aware), reports with known fixtures, formula-safe export."""
import base64
import csv
import io
from datetime import timedelta

from tests.crm_fixtures import crm, iso, utcnow  # noqa: F401  (fixture)


def _offset_for_local_hour(hour):
    """Minutes east of UTC that make the client's local time now ~= hour:00."""
    now = utcnow()
    diff = (hour * 60) - (now.hour * 60 + now.minute)
    while diff > 720:
        diff -= 1440
    while diff <= -720:
        diff += 1440
    return diff


def _record(crm, a):
    job = crm.job(a.id)
    return a.import_ids(job, [crm.result(job, 1)])["created"][0]["record_id"]


def test_activity_due_dates_must_be_timezone_aware_and_are_stored_utc(crm):
    a = crm.user("alice")
    rid = _record(crm, a)
    for due in ("2026-12-01T10:00:00", "tomorrow", "", None, "2026-13-01T10:00:00Z"):
        r = a.post(f"/records/{rid}/activities", {"type": "call", "subject": "Call", "due_at": due})
        assert r.status_code == 422 and r.json()["code"] == "validation_error", due
    assert a.post(f"/records/{rid}/activities", {"type": "fax", "subject": "x", "due_at": "2026-12-01T10:00:00Z"}).status_code == 422
    act = a.ok(a.post(f"/records/{rid}/activities", {"type": "meeting", "subject": "Demo", "due_at": "2026-12-01T10:00:00+03:00",
                                                    "notes": "bring brochure"}))
    assert act["due_at"] == "2026-12-01T07:00:00.000Z" and act["status"] == "open" and act["overdue"] is False
    rec = a.record(rid)
    assert rec["next_activity"]["id"] == act["id"] and rec["next_activity"]["due_at"] == "2026-12-01T07:00:00.000Z"


def test_agenda_buckets_and_counts_follow_the_client_offset(crm):
    a = crm.user("alice")
    rid = _record(crm, a)
    now = utcnow()
    morning = _offset_for_local_hour(10)   # local 10:00 -> +3h is still today
    evening = _offset_for_local_hour(22)   # local 22:00 -> +3h is tomorrow
    overdue = a.ok(a.post(f"/records/{rid}/activities", {"type": "call", "subject": "Overdue call",
                                                        "due_at": iso(now - timedelta(hours=2), morning)}))
    soon = a.ok(a.post(f"/records/{rid}/activities", {"type": "task", "subject": "In three hours",
                                                     "due_at": iso(now + timedelta(hours=3), evening)}))
    later = a.ok(a.post(f"/records/{rid}/activities", {"type": "email", "subject": "Next week",
                                                      "due_at": iso(now + timedelta(days=7))}))
    assert overdue["overdue"] is True and soon["overdue"] is False

    c_morning = a.ok(a.get("/agenda/counts", tz_offset_minutes=morning))
    assert c_morning == {"overdue": 1, "today": 1, "upcoming": 1, "no_next_activity": 0}
    c_evening = a.ok(a.get("/agenda/counts", tz_offset_minutes=evening))
    assert c_evening == {"overdue": 1, "today": 0, "upcoming": 2, "no_next_activity": 0}

    today = a.ok(a.get("/agenda", bucket="today", tz_offset_minutes=morning))
    assert [i["id"] for i in today["items"]] == [soon["id"]] and today["items"][0]["record_title"] == "Biz 1"
    assert today["items"][0]["record"] == {"id": rid, "title": "Biz 1"}
    assert [i["id"] for i in a.ok(a.get("/agenda", bucket="overdue"))["items"]] == [overdue["id"]]
    up = a.ok(a.get("/agenda", bucket="upcoming", tz_offset_minutes=evening, limit=1))
    assert [i["id"] for i in up["items"]] == [soon["id"]] and up["total"] == 2 and up["next_cursor"]
    up2 = a.ok(a.get("/agenda", bucket="upcoming", tz_offset_minutes=evening, limit=1, cursor=up["next_cursor"]))
    assert [i["id"] for i in up2["items"]] == [later["id"]] and up2["next_cursor"] is None
    assert a.get("/agenda", bucket="someday").status_code == 422
    assert a.get("/agenda/counts", tz_offset_minutes="2000").status_code == 422

    # the record list/pipeline agree with the agenda
    assert a.ok(a.get("/records", due="overdue"))["total"] == 1
    pipe = a.ok(a.get("/pipeline", tz_offset_minutes=morning))
    assert pipe["summary"]["overdue"] == 1 and pipe["summary"]["no_next_activity"] == 0

    # done -> next activity moves on, counts follow; reopen restores it
    done = a.ok(a.post(f"/activities/{overdue['id']}/done", {"outcome": "Left a voicemail"}))
    assert done["status"] == "done" and done["completed_at"] and done["outcome"] == "Left a voicemail"
    assert a.ok(a.post(f"/activities/{overdue['id']}/done"))["completed_at"] == done["completed_at"]  # idempotent
    assert a.ok(a.get("/agenda/counts", tz_offset_minutes=morning))["overdue"] == 0
    assert a.record(rid)["next_activity"]["id"] == soon["id"]
    assert [i["id"] for i in a.ok(a.get("/agenda", bucket="done"))["items"]] == [overdue["id"]]
    a.ok(a.post(f"/activities/{overdue['id']}/reopen"))
    assert a.ok(a.get("/agenda/counts", tz_offset_minutes=morning))["overdue"] == 1

    # reschedule the overdue call to next month
    moved = a.ok(a.patch(f"/activities/{overdue['id']}", {"due_at": iso(now + timedelta(days=30), 60),
                                                          "subject": "Call again"}))
    assert moved["overdue"] is False and moved["subject"] == "Call again"
    assert a.ok(a.get("/agenda/counts"))["overdue"] == 0
    assert a.patch(f"/activities/{overdue['id']}", {"status": "done"}).status_code == 422
    rec = a.record(rid)
    types = [e["type"] for e in reversed(rec["events"])]
    assert types == ["imported", "activity_scheduled", "activity_scheduled", "activity_scheduled", "activity_done",
                     "activity_reopened", "activity_rescheduled"]
    assert [x["status"] for x in rec["activities"]] == ["open", "open", "open"]

    # archived records drop out of the agenda; records without activity are counted
    a.ok(a.post(f"/records/{rid}/archive"))
    assert a.ok(a.get("/agenda/counts")) == {"overdue": 0, "today": 0, "upcoming": 0, "no_next_activity": 0}
    a.new_record("No plans yet")
    assert a.ok(a.get("/agenda/counts"))["no_next_activity"] == 1


def _report_fixture(crm, a):
    job = crm.job(a.id, category="cafes")
    ids = [c["record_id"] for c in a.import_ids(job, crm.results(job, 4))["created"]]
    reasons = {r["name"]: r["id"] for r in a.ok(a.get("/workspace"))["lost_reasons"]}
    for rid in ids[:3]:
        a.ok(a.post(f"/records/{rid}/convert"))
    a.ok(a.patch(f"/records/{ids[0]}", {"value": 1000, "currency": "USD"}))
    a.ok(a.post(f"/records/{ids[0]}/won"))
    a.ok(a.patch(f"/records/{ids[1]}", {"value": 500, "currency": "EUR"}))
    a.ok(a.post(f"/records/{ids[1]}/won"))
    a.ok(a.post(f"/records/{ids[3]}/lost", {"reason_id": reasons["No response"]}))
    manual = a.new_record("Walk-in")
    a.ok(a.patch(f"/records/{manual['id']}", {"value": 200, "currency": "USD"}))
    now = utcnow()
    a.ok(a.post(f"/records/{ids[2]}/activities", {"type": "call", "subject": "late", "due_at": iso(now - timedelta(days=1))}))
    done = a.ok(a.post(f"/records/{ids[2]}/activities", {"type": "call", "subject": "done", "due_at": iso(now)}))
    a.ok(a.post(f"/activities/{done['id']}/done"))
    return job, ids, manual


def test_reports_with_known_fixtures_two_currencies_and_missing_values(crm):
    a = crm.user("alice")
    job, ids, manual = _report_fixture(crm, a)
    rep = a.ok(a.get("/reports"))
    assert set(rep["definitions"]) >= {"imported_companies", "open_leads", "opportunities", "won_rate",
                                       "value_by_currency", "records_without_value"}
    assert rep["imported_companies"] == 4
    assert rep["open_leads"] == 1 and rep["opportunities"] == 3
    assert {s["stage"]["key"]: s["count"] for s in rep["by_stage"]} == {"new": 2, "contacted": 0, "qualified": 0,
                                                                         "proposal": 0, "won": 2}
    assert rep["by_source"] == [{"job_id": job, "category": "cafes", "count": 4}]
    assert rep["won"] == 2 and rep["lost"] == 1
    assert rep["won_rate"] == {"value": 0.6667, "numerator": 2, "denominator": 3}
    assert rep["overdue_activities"] == 1 and rep["activities_completed"] == 1
    assert rep["lost_reasons"] == [{"name": "No response", "count": 1}]
    assert rep["value_by_currency"] == [{"currency": "EUR", "open_total": None, "won_total": 500.0},
                                        {"currency": "USD", "open_total": 200.0, "won_total": 1000.0}]
    assert rep["records_without_value"] == 1

    # move the EUR win into last year: period filters use the close date
    cur = crm.conn.cursor()
    cur.execute("UPDATE crm_records SET closed_at = ? WHERE id = ?", ("2025-06-01 12:00:00.000000", ids[1]))
    crm.conn.commit()
    this_year = a.ok(a.get("/reports", **{"from": "2026-01-01", "to": "2026-12-31"}))
    assert this_year["won"] == 1 and this_year["won_rate"] == {"value": 0.5, "numerator": 1, "denominator": 2}
    assert this_year["value_by_currency"] == [{"currency": "USD", "open_total": 200.0, "won_total": 1000.0}]
    last_year = a.ok(a.get("/reports", **{"from": "2025-01-01", "to": "2025-12-31"}))
    assert last_year["won"] == 1 and last_year["lost"] == 0 and last_year["imported_companies"] == 0
    assert last_year["by_source"] == [] and last_year["activities_completed"] == 0
    empty = a.ok(a.get("/reports", **{"from": "2030-01-01", "to": "2030-01-31"}))
    assert empty["won_rate"] == {"value": None, "numerator": 0, "denominator": 0} and empty["lost_reasons"] == []
    assert a.get("/reports", **{"from": "2026-02-01", "to": "2026-01-01"}).status_code == 422
    assert a.get("/reports", **{"from": "yesterday"}).status_code == 422


def test_reports_for_an_empty_workspace_are_empty_not_fake(crm):
    a = crm.user("alice")
    rep = a.ok(a.get("/reports"))
    assert rep["imported_companies"] == 0 and rep["by_source"] == [] and rep["value_by_currency"] == []
    assert rep["won_rate"]["value"] is None and all(s["count"] == 0 for s in rep["by_stage"])


def _decode_csv(body):
    text = base64.b64decode(body["content"]).decode("utf-8-sig")
    return list(csv.reader(io.StringIO(text)))


def test_export_csv_and_xlsx_are_formula_safe_and_scoped(crm):
    import openpyxl

    a = crm.user("alice")
    job = crm.job(a.id, category="cafes")
    evil = crm.result(job, 1, business_name="=HYPERLINK(\"http://evil\",\"x\")", phone="+974 5555 0000",
                      email="@attacker.example", address="-2+3")
    plain = crm.result(job, 2, business_name="Plain Cafe")
    ids = [c["record_id"] for c in a.import_ids(job, [evil, plain])["created"]]
    a.ok(a.post(f"/records/{ids[1]}/activities", {"type": "call", "subject": "Ring", "due_at": "2030-01-01T09:00:00Z"}))
    a.ok(a.post(f"/records/{ids[1]}/archive"))

    body = a.ok(a.get("/export", format="csv"))
    assert body["filename"].endswith(".csv") and body["encoding"] == "base64" and body["count"] == 1
    rows = _decode_csv(body)
    header, row = rows[0], rows[1]
    assert header[0] == "Title" and "Source searches" in header and "Next activity" in header
    cell = dict(zip(header, row))
    assert cell["Title"].startswith("'=") and cell["Company"].startswith("'=")
    assert cell["Phone"] == "'+974 5555 0000" and cell["Address"] == "'-2+3"
    assert cell["Source searches"] == "cafes - Doha, Doha"

    allrows = _decode_csv(a.ok(a.get("/export", format="csv", archived="all")))
    plain_row = dict(zip(allrows[0], [r for r in allrows[1:] if r[0] == "Plain Cafe"][0]))
    assert plain_row["Next activity"] == "Ring" and plain_row["Next activity due (UTC)"] == "2030-01-01 09:00"
    assert plain_row["Archived"] == "yes"

    x = a.ok(a.get("/export", format="xlsx", archived="all"))
    assert x["filename"].endswith(".xlsx")
    wb = openpyxl.load_workbook(io.BytesIO(base64.b64decode(x["content"])))
    sheet = wb.active
    titles = [sheet.cell(row=r, column=1) for r in range(2, sheet.max_row + 1)]
    evil_cell = [c for c in titles if str(c.value).startswith("=")][0]
    assert evil_cell.data_type == "s"  # stored as text, never a formula
    assert a.get("/export", format="pdf").status_code == 422


def test_report_dates_are_local_and_inclusive_with_negative_offset(crm):
    """New York (UTC-5 = -300): a win at 2026-03-02 03:00Z is local 2026-03-01 22:00."""
    a = crm.user("alice")
    rid = a.new_record("Late deal")["id"]
    a.ok(a.post(f"/records/{rid}/won"))
    cur = crm.conn.cursor()
    cur.execute("UPDATE crm_records SET closed_at = ? WHERE id = ?", ("2026-03-02 03:00:00.000000", rid))
    crm.conn.commit()
    ny = {"tz_offset_minutes": -300}
    assert a.ok(a.get("/reports", **{"from": "2026-03-01", "to": "2026-03-01", **ny}))["won"] == 1
    assert a.ok(a.get("/reports", **{"from": "2026-03-02", "to": "2026-03-02", **ny}))["won"] == 0
    assert a.ok(a.get("/reports", **{"from": "2026-03-02", "to": "2026-03-02"}))["won"] == 1  # UTC
