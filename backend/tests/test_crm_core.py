"""CRM: migration, feature flag, workspace creation and cross-account isolation."""
import os
import threading

import pytest

from tests.crm_fixtures import CRM, crm  # noqa: F401  (fixture)

CRM_TABLES = ["crm_workspaces", "crm_memberships", "crm_pipelines", "crm_stages", "crm_companies", "crm_people",
              "crm_records", "crm_source_links", "crm_activities", "crm_notes", "crm_events", "crm_tags",
              "crm_record_tags", "crm_lost_reasons", "crm_imports"]


def test_migration_creates_tables_and_is_safe_to_rerun(db_connection):
    from database import init_database
    from db.migration_runner import _get_db_type, apply_migration, get_applied_migrations

    cur = db_connection.cursor()
    for t in CRM_TABLES:
        cur.execute(f"SELECT COUNT(*) FROM {t}")
        assert cur.fetchone()[0] == 0
    assert "017" in get_applied_migrations(db_connection)

    # Repeated startup: nothing pending, nothing breaks.
    assert init_database() == 0

    # Re-applying the 017 file itself (a partially applied run) is harmless.
    backend = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    name = "017_crm.sql" if _get_db_type() == "mysql" else "017_crm_sqlite.sql"
    cur.execute("DELETE FROM schema_migrations WHERE version = '017'")
    db_connection.commit()
    from database import get_db

    conn = get_db()
    try:
        assert apply_migration(conn, os.path.join(backend, "migrations", name), "017", name) is True
    finally:
        conn.close()
    assert "017" in get_applied_migrations(db_connection)


def test_no_foreign_keys_to_jobs_or_results(db_connection):
    from db.migration_runner import _get_db_type

    cur = db_connection.cursor()
    if _get_db_type() == "mysql":
        cur.execute("SELECT COUNT(*) FROM information_schema.KEY_COLUMN_USAGE WHERE TABLE_SCHEMA = DATABASE() "
                    "AND TABLE_NAME LIKE ? ESCAPE '!' AND REFERENCED_TABLE_NAME IS NOT NULL", ("crm!_%",))
        assert cur.fetchone()[0] == 0
    else:
        for t in CRM_TABLES:
            cur.execute(f"PRAGMA foreign_key_list({t})")
            assert cur.fetchall() == []


def test_flag_off_returns_404_everywhere_but_status(crm, monkeypatch):
    a = crm.user("alice")
    monkeypatch.setenv("CRM_ENABLED", "false")
    assert a.ok(a.get("/status")) == {"enabled": False}
    for method, path in [("get", "/workspace"), ("get", "/records"), ("get", "/pipeline"), ("get", "/agenda"),
                         ("get", "/reports"), ("get", "/export"), ("get", "/records/xyz"), ("get", "/jobs/j/state")]:
        r = getattr(a, method)(path)
        assert r.status_code == 404 and r.json() == {"detail": "CRM is not enabled", "code": "crm_disabled"}
    r = a.post("/import", {"job_id": "x", "all": True, "idempotency_key": "abcdefgh"})
    assert r.status_code == 404 and r.json()["code"] == "crm_disabled"
    # flag check runs before auth: no token still gets the flag answer, never data
    assert a.client.get("/api/crm/records").json()["code"] == "crm_disabled"
    # no workspace was created while disabled
    cur = crm.conn.cursor()
    cur.execute("SELECT COUNT(*) FROM crm_workspaces")
    assert cur.fetchone()[0] == 0
    monkeypatch.setenv("CRM_ENABLED", "true")
    assert a.ok(a.get("/status")) == {"enabled": True}


def test_status_requires_auth(crm):
    a = crm.user("alice")
    assert a.client.get("/api/crm/status").status_code in (401, 403)


def test_workspace_is_created_lazily_once_with_defaults(crm):
    a = crm.user("alice")
    ws = a.ok(a.get("/workspace"))
    assert ws["role"] == "owner" and ws["currency_default"] is None and ws["tags"] == []
    assert [s["key"] for s in ws["pipeline"]["stages"]] == ["new", "contacted", "qualified", "proposal", "won"]
    assert [s["outcome_kind"] for s in ws["pipeline"]["stages"]] == ["open"] * 4 + ["won"]
    assert ws["pipeline"]["name"] == "Sales"
    assert [r["name"] for r in ws["lost_reasons"]] == ["Not interested", "No response", "Not a fit", "Duplicate", "Other"]
    assert a.ok(a.get("/workspace"))["id"] == ws["id"]
    cur = crm.conn.cursor()
    cur.execute("SELECT COUNT(*) FROM crm_workspaces WHERE owner_user_id = ?", (a.id,))
    assert cur.fetchone()[0] == 1


def test_workspace_get_or_create_is_race_safe(crm):
    from crm.workspace import get_or_create
    from database import get_db

    a = crm.user("alice")
    user = {"id": a.id}
    ids, errors = [], []

    def worker():
        conn = get_db()
        try:
            ids.append(get_or_create(conn, user)["id"])
        except Exception as exc:  # pragma: no cover - failure path
            errors.append(exc)
        finally:
            conn.close()

    threads = [threading.Thread(target=worker) for _ in range(6)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert not errors and len(set(ids)) == 1
    cur = crm.conn.cursor()
    cur.execute("SELECT COUNT(*) FROM crm_workspaces WHERE owner_user_id = ?", (a.id,))
    assert cur.fetchone()[0] == 1
    cur.execute("SELECT COUNT(*) FROM crm_stages WHERE workspace_id = ?", (ids[0],))
    assert cur.fetchone()[0] == 5


def test_another_user_cannot_read_or_change_anything(crm):
    a = crm.user("alice")
    b = crm.user("bob")
    job = crm.job(a.id)
    ids = crm.results(job, 3)
    rec_id = a.import_ids(job, ids)["created"][0]["record_id"]
    person = a.ok(a.post(f"/records/{rec_id}/people", {"name": "Sara", "email": "sara@biz1.example.com"}))
    note = a.ok(a.post(f"/records/{rec_id}/notes", {"body": "secret pricing"}))
    act = a.ok(a.post(f"/records/{rec_id}/activities", {"type": "call", "subject": "Call back",
                                                       "due_at": "2026-01-01T10:00:00Z"}))
    tag = a.ok(a.post("/tags", {"name": "VIP"}))

    not_found = {"detail": "Not found", "code": "not_found"}
    for path in [f"/records/{rec_id}", f"/records/{rec_id}/events", f"/jobs/{job}/state"]:
        r = b.get(path)
        assert r.status_code == 404 and r.json() == not_found, path
    for path, body in [(f"/records/{rec_id}/stage", {"stage_id": "x"}), (f"/records/{rec_id}/won", {}),
                       (f"/records/{rec_id}/archive", {}), (f"/records/{rec_id}/notes", {"body": "x"}),
                       (f"/records/{rec_id}/people", {"name": "x"}), (f"/activities/{act['id']}/done", {}),
                       (f"/records/{rec_id}/activities", {"type": "call", "subject": "x", "due_at": "2026-01-01T10:00:00Z"})]:
        r = b.post(path, body)
        assert r.status_code == 404 and r.json() == not_found, path
    assert b.patch(f"/records/{rec_id}", {"title": "pwned"}).status_code == 404
    assert b.patch(f"/notes/{note['id']}", {"body": "x"}).status_code == 404
    assert b.patch(f"/people/{person['id']}", {"name": "x"}).status_code == 404
    assert b.delete(f"/people/{person['id']}").status_code == 404
    assert b.patch(f"/activities/{act['id']}", {"subject": "x"}).status_code == 404
    assert b.put(f"/records/{rec_id}/tags", {"tag_ids": []}).status_code == 404
    # b's own record cannot be tagged with a's tag
    b_rec = b.new_record("Bob Co")
    assert b.put(f"/records/{b_rec['id']}/tags", {"tag_ids": [tag["id"]]}).status_code == 404

    # Lists are scoped: b sees only his own data.
    assert [i["id"] for i in b.ok(b.get("/records", outcome="all", archived="all"))["items"]] == [b_rec["id"]]
    assert b.ok(b.get("/people"))["items"] == []
    assert b.ok(b.get("/agenda", bucket="overdue"))["items"] == []
    assert b.ok(b.get("/agenda/counts"))["overdue"] == 0
    assert b.ok(b.get("/tags"))["items"] == []
    rep = b.ok(b.get("/reports"))
    assert rep["imported_companies"] == 0 and rep["open_leads"] == 1
    import base64

    exp = b.ok(b.get("/export", format="csv"))
    text = base64.b64decode(exp["content"]).decode("utf-8-sig")
    assert "Biz 1" not in text and "Bob Co" in text and exp["count"] == 1
    # import of a's job / a's result ids from b's account
    r = b.post("/import", {"job_id": job, "result_ids": ids, "idempotency_key": "bob-key-0001"})
    assert r.status_code == 404 and r.json() == not_found
    b_job = crm.job(b.id)
    body = b.import_ids(b_job, ids)
    assert body["created"] == [] and [x["reason"] for x in body["rejected"]] == ["not_found"] * 3
    assert "Biz" not in str(body["rejected"])


def test_product_admin_gets_no_access_to_other_workspaces(crm):
    a = crm.user("alice")
    admin = crm.user("root_admin")
    cur = crm.conn.cursor()
    cur.execute("UPDATE users SET role = 'owner', is_admin = 1 WHERE id = ?", (admin.id,))
    crm.conn.commit()
    rec = a.new_record("Alice Co")
    assert admin.get(f"/records/{rec['id']}").status_code == 404
    assert admin.ok(admin.get("/records"))["total"] == 0


def test_validation_errors_have_contract_shape(crm):
    a = crm.user("alice")
    r = a.post("/import", {"job_id": "x"})
    assert r.status_code == 422 and r.json()["code"] == "validation_error"
    r = a.client.post("/api/crm/records", content="not json", headers={**a.h, "Content-Type": "application/json"})
    assert r.status_code == 422 and r.json()["code"] == "validation_error"
    r = a.get("/records", limit="500")
    assert r.status_code == 422 and r.json()["code"] == "validation_error"
    r = a.get("/records", cursor="!!garbage!!")
    assert r.status_code == 422 and r.json()["code"] == "validation_error"
