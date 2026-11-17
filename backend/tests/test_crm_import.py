"""CRM import: one / selected / all, idempotency, possible matches, resolve, job state, deletion."""
import uuid

from tests.crm_fixtures import maps_url, crm  # noqa: F401  (fixture)


def _count(conn, table, where="1 = 1", params=()):
    cur = conn.cursor()
    cur.execute(f"SELECT COUNT(*) FROM {table} WHERE {where}", params)
    return cur.fetchone()[0]


def test_import_one_snapshots_the_stored_row(crm):
    a = crm.user("alice")
    job = crm.job(a.id, category="dentists", cities=("Doha, Doha",))
    rid = crm.result(job, 1, business_name="Smile Clinic", website="=HYPERLINK(\"x\")")
    body = a.import_ids(job, [rid])
    assert body["done"] is True and body["processed"] == 1 and body["remaining"] == 0
    assert body["summary"] == {"created": 1, "already_added": 0, "possible_match": 0, "rejected": 0}
    rec = a.record(body["created"][0]["record_id"])
    assert rec["title"] == "Smile Clinic" and rec["type"] == "lead" and rec["outcome"] == "open"
    assert rec["stage"]["key"] == "new" and rec["source_count"] == 1 and rec["version"] == 1
    assert rec["company"]["source_snapshot"]["business_name"] == "Smile Clinic"
    assert rec["company"]["source_snapshot_label"] == "found online"
    assert rec["company"]["phone"] == "+974 50000001"
    src = rec["sources"][0]
    assert src["job_id"] == job and src["result_id"] == rid and src["category"] == "dentists"
    assert src["city"] == "Doha" and src["available"] is True and src["imported_at"].endswith("Z")
    assert [e["type"] for e in rec["events"]] == ["imported"]


def test_import_fifty_selected_and_refresh(crm):
    a = crm.user("alice")
    job = crm.job(a.id)
    ids = crm.results(job, 60)
    body = a.import_ids(job, ids[:50])
    assert body["summary"]["created"] == 50 and len({c["record_id"] for c in body["created"]}) == 50
    assert [c["result_id"] for c in body["created"]] == ids[:50]
    listed = a.ok(a.get("/records", limit=100))
    assert listed["total"] == 50 and len(listed["items"]) == 50
    # refresh: same records, nothing new
    again = a.ok(a.get("/records", limit=100))
    assert sorted(i["id"] for i in again["items"]) == sorted(i["id"] for i in listed["items"])
    state = a.ok(a.get(f"/jobs/{job}/state"))
    assert state["counts"] == {"not_added": 10, "added": 50, "possible_match": 0}
    assert state["results"][str(ids[0])]["state"] == "added"
    assert state["results"][str(ids[0])]["record_id"] == body["created"][0]["record_id"]


def test_import_all_is_resumable_in_batches_of_200(crm):
    a = crm.user("alice")
    job = crm.job(a.id)
    ids = crm.results(job, 450)
    key = uuid.uuid4().hex
    calls = a.import_all(job, key)
    assert [c["done"] for c in calls] == [False, False, True]
    assert [c["processed"] for c in calls] == [200, 400, 450]
    assert [c["remaining"] for c in calls] == [250, 50, 0]
    assert [len(c["created"]) for c in calls] == [200, 200, 50]
    assert calls[-1]["summary"]["created"] == 450 and len({c["import_id"] for c in calls}) == 1
    assert _count(crm.conn, "crm_records") == 450 and _count(crm.conn, "crm_source_links") == 450
    # replaying the finished key returns the stored response unchanged
    replay = a.ok(a.post("/import", {"job_id": job, "all": True, "idempotency_key": key}))
    assert replay == calls[-1]
    # a new "all" import of the same search adds nothing
    again = a.import_all(job)
    assert again[-1]["summary"] == {"created": 0, "already_added": 450, "possible_match": 0, "rejected": 0}
    assert _count(crm.conn, "crm_records") == 450
    assert a.ok(a.get("/records", source_job_id=job, limit=1))["total"] == 450
    assert ids


def test_exact_retry_same_key_and_different_key_never_duplicate(crm):
    a = crm.user("alice")
    job = crm.job(a.id)
    ids = crm.results(job, 5)
    first = a.import_ids(job, ids, key="retry-key-0001")
    same = a.import_ids(job, ids, key="retry-key-0001")
    assert same == first
    other = a.import_ids(job, list(reversed(ids)), key="retry-key-0002")
    assert other["summary"] == {"created": 0, "already_added": 5, "possible_match": 0, "rejected": 0}
    assert {x["record_id"] for x in other["already_added"]} == {x["record_id"] for x in first["created"]}
    assert _count(crm.conn, "crm_records") == 5 and _count(crm.conn, "crm_source_links") == 5
    assert _count(crm.conn, "crm_events", "type = 'imported'") == 5
    # the same key with a different request is refused, not silently replayed
    r = a.post("/import", {"job_id": job, "result_ids": ids[:2], "idempotency_key": "retry-key-0001"})
    assert r.status_code == 422 and r.json()["code"] == "validation_error"


def test_import_validation(crm):
    a = crm.user("alice")
    job = crm.job(a.id)
    ids = crm.results(job, 2)
    bad = [
        {"job_id": job, "idempotency_key": "k-00000001"},
        {"job_id": job, "result_ids": ids, "all": True, "idempotency_key": "k-00000002"},
        {"job_id": job, "result_ids": [], "idempotency_key": "k-00000003"},
        {"job_id": job, "result_ids": list(range(1, 202)), "idempotency_key": "k-00000004"},
        {"job_id": job, "result_ids": ["1"], "idempotency_key": "k-00000005"},
        {"job_id": job, "result_ids": ids, "idempotency_key": "short"},
        {"job_id": job, "result_ids": ids},
    ]
    for body in bad:
        r = a.post("/import", body)
        assert r.status_code == 422 and r.json()["code"] == "validation_error", body
    # duplicates inside one request are de-duplicated
    body = a.import_ids(job, [ids[0], ids[0], ids[1]])
    assert body["summary"]["created"] == 2


def test_unknown_and_foreign_result_ids_are_rejected_without_details(crm):
    a = crm.user("alice")
    b = crm.user("bob")
    job_a = crm.job(a.id)
    job_a2 = crm.job(a.id)
    job_b = crm.job(b.id)
    mine = crm.result(job_a, 1)
    other_job = crm.result(job_a2, 2)
    foreign = crm.result(job_b, 3, business_name="Bob Secret LLC")
    body = a.import_ids(job_a, [mine, other_job, foreign, 999999])
    assert [c["result_id"] for c in body["created"]] == [mine]
    assert body["rejected"] == [{"result_id": other_job, "reason": "not_found"},
                                {"result_id": foreign, "reason": "not_found"},
                                {"result_id": 999999, "reason": "not_found"}]
    r = a.post("/import", {"job_id": job_b, "all": True, "idempotency_key": "foreign-job-1"})
    assert r.status_code == 404 and r.json() == {"detail": "Not found", "code": "not_found"}
    assert a.get(f"/jobs/{job_b}/state").status_code == 404


def test_running_job_imports_only_persisted_rows(crm):
    a = crm.user("alice")
    job = crm.job(a.id, status="running")
    ids = crm.results(job, 3)
    calls = a.import_all(job, key="running-job-01")
    assert calls[-1]["done"] is True and calls[-1]["summary"]["created"] == 3
    # an id the scraper has not saved yet is not importable
    body = a.import_ids(job, [ids[-1] + 1000])
    assert body["rejected"] == [{"result_id": ids[-1] + 1000, "reason": "not_found"}]
    # rows saved later are picked up by a new import; nothing is imported twice
    later = crm.results(job, 2, start=10)
    body = a.import_ids(job, ids + later)
    assert body["summary"] == {"created": 2, "already_added": 3, "possible_match": 0, "rejected": 0}


def test_possible_match_across_two_searches_and_resolve(crm):
    a = crm.user("alice")
    first = crm.job(a.id, category="cafes")
    second = crm.job(a.id, category="coffee shops")
    r1 = crm.results(first, 3)                       # Biz 1..3
    a.import_ids(first, r1)
    rec1 = a.ok(a.get("/records", limit=10))["items"]
    by_name = {i["title"]: i["id"] for i in rec1}
    # stage + note on the existing record must survive a link
    stage_qualified = [s for s in a.ok(a.get("/workspace"))["pipeline"]["stages"] if s["key"] == "qualified"][0]
    a.ok(a.post(f"/records/{by_name['Biz 1']}/stage", {"stage_id": stage_qualified["id"]}))
    a.ok(a.post(f"/records/{by_name['Biz 1']}/notes", {"body": "Met the owner"}))
    a.ok(a.patch(f"/records/{by_name['Biz 1']}", {"company": {"phone": "+974 1111 2222"}}))

    # same places found again by another search (same Maps ids), plus one new
    r2 = [crm.result(second, n, website="", phone="") for n in (1, 2, 3)] + [crm.result(second, 7)]
    body = a.import_ids(second, r2)
    assert body["summary"] == {"created": 1, "already_added": 0, "possible_match": 3, "rejected": 0}
    pm = {p["result_id"]: p for p in body["possible_matches"]}
    assert pm[r2[0]]["business_name"] == "Biz 1"
    cand = pm[r2[0]]["candidates"]
    assert [c["record_id"] for c in cand] == [by_name["Biz 1"]] and cand[0]["reasons"] == ["same_maps_place"]
    assert cand[0]["stage"]["key"] == "qualified"

    state = a.ok(a.get(f"/jobs/{second}/state"))
    assert state["counts"] == {"not_added": 0, "added": 1, "possible_match": 3}
    s0 = state["results"][str(r2[0])]
    assert s0["state"] == "possible_match" and s0["candidate_record_ids"] == [by_name["Biz 1"]]
    assert s0["reasons"] == ["same_maps_place"]

    decisions = [{"result_id": r2[0], "action": "link", "record_id": by_name["Biz 1"]},
                 {"result_id": r2[1], "action": "add_new"},
                 {"result_id": r2[2], "action": "skip"}]
    res = a.ok(a.post("/import/resolve", {"job_id": second, "idempotency_key": "resolve-0001", "decisions": decisions}))
    assert res["linked"] == [{"result_id": r2[0], "record_id": by_name["Biz 1"]}]
    assert [c["result_id"] for c in res["created"]] == [r2[1]]
    assert res["skipped"] == [{"result_id": r2[2]}] and res["rejected"] == []
    # exact replay of the resolve
    assert a.ok(a.post("/import/resolve", {"job_id": second, "idempotency_key": "resolve-0001",
                                           "decisions": decisions})) == res

    rec = a.record(by_name["Biz 1"])
    assert rec["stage"]["key"] == "qualified" and rec["company"]["phone"] == "+974 1111 2222"
    assert rec["notes"][0]["body"] == "Met the owner" and rec["source_count"] == 2
    assert [s["job_id"] for s in rec["sources"]] == [first, second]
    assert rec["events"][0]["type"] == "source_linked"
    assert rec["title"] == "Biz 1"

    state = a.ok(a.get(f"/jobs/{second}/state"))
    assert state["results"][str(r2[0])] == {"state": "added", "record_id": by_name["Biz 1"],
                                           "candidate_record_ids": [], "reasons": []}
    assert state["results"][str(r2[2])]["state"] == "possible_match"  # skipped: still not added
    assert state["counts"]["added"] == 3
    # filtering by the second search shows linked + newly created records
    assert a.ok(a.get("/records", source_job_id=second))["total"] == 3
    # a resolve that links to a record that is not in the workspace is rejected per item
    b = crm.user("bob")
    b_rec = b.new_record("Bob Co")
    res = a.ok(a.post("/import/resolve", {"job_id": second, "idempotency_key": "resolve-0002",
                                          "decisions": [{"result_id": r2[2], "action": "link", "record_id": b_rec["id"]}]}))
    assert res["rejected"] == [{"result_id": r2[2], "reason": "record_not_found"}] and res["linked"] == []


def test_match_rules_website_phone_and_name_alone(crm):
    a = crm.user("alice")
    j1 = crm.job(a.id)
    j2 = crm.job(a.id)
    base = crm.result(j1, 1, business_name="Blue Bottle Coffee", website="https://www.bluebottle.example/doha",
                      phone="+974 4444 5555", google_maps_url="https://maps.example/no-place-id")
    a.import_ids(j1, [base])
    same_site = crm.result(j2, 2, business_name="Blue Bottle Coffee LLC", website="http://bluebottle.example",
                           phone="", google_maps_url="")
    same_phone = crm.result(j2, 3, business_name="blue bottle coffee", website="", phone="44445555",
                            google_maps_url="")
    name_only = crm.result(j2, 4, business_name="Blue Bottle Coffee", website="https://other.example", phone="+974 9999 0000",
                           google_maps_url="")
    site_other_name = crm.result(j2, 5, business_name="Totally Different Bakery", website="https://bluebottle.example",
                                 phone="", google_maps_url="")
    social = crm.result(j2, 6, business_name="Blue Bottle Coffee", website="https://facebook.com/bluebottle", phone="",
                        google_maps_url="")
    body = a.import_ids(j2, [same_site, same_phone, name_only, site_other_name, social])
    pm = {p["result_id"]: p["candidates"][0]["reasons"] for p in body["possible_matches"]}
    assert pm == {same_site: ["same_website_and_name"], same_phone: ["same_phone_and_name"]}
    assert {c["result_id"] for c in body["created"]} == {name_only, site_other_name, social}


def test_chain_branches_with_different_places_are_not_matches(crm):
    a = crm.user("alice")
    j1 = crm.job(a.id)
    j2 = crm.job(a.id)
    one = crm.result(j1, 1, business_name="Chain Cafe", website="https://chain.example", google_maps_url=maps_url(500))
    a.import_ids(j1, [one])
    other_branch = crm.result(j2, 2, business_name="Chain Cafe", website="https://chain.example", google_maps_url=maps_url(501))
    body = a.import_ids(j2, [other_branch])
    assert body["summary"]["created"] == 1 and body["possible_matches"] == []


def test_matches_never_cross_workspaces(crm):
    a = crm.user("alice")
    b = crm.user("bob")
    ja, jb = crm.job(a.id), crm.job(b.id)
    a.import_ids(ja, [crm.result(ja, 1)])
    body = b.import_ids(jb, [crm.result(jb, 1)])  # same place, other account
    assert body["summary"]["created"] == 1 and body["possible_matches"] == []


def test_deleting_the_source_search_keeps_record_and_snapshot(crm):
    a = crm.user("alice")
    job = crm.job(a.id)
    rid = crm.result(job, 1, business_name="Keep Me Cafe")
    rec_id = a.import_ids(job, [rid])["created"][0]["record_id"]
    r = a.client.delete(f"/api/jobs/{job}", headers=a.h)
    assert r.status_code == 200, r.text
    assert _count(crm.conn, "results", "job_id = ?", (job,)) == 0
    rec = a.record(rec_id)
    assert rec["title"] == "Keep Me Cafe" and rec["company"]["source_snapshot"]["business_name"] == "Keep Me Cafe"
    src = rec["sources"][0]
    assert src["available"] is False and src["job_id"] == job and src["category"] == "cafes"
    assert src["snapshot"]["business_name"] == "Keep Me Cafe"
    assert a.ok(a.get("/records", source_job_id=job))["total"] == 1
    assert a.get(f"/jobs/{job}/state").status_code == 404


def test_import_rate_limit(crm, monkeypatch):
    monkeypatch.setenv("CRM_IMPORT_RATE_PER_MIN", "3")
    a = crm.user("alice")
    job = crm.job(a.id)
    rid = crm.result(job, 1)
    for _ in range(3):
        a.import_ids(job, [rid])
    r = a.post("/import", {"job_id": job, "result_ids": [rid], "idempotency_key": uuid.uuid4().hex})
    assert r.status_code == 429 and r.json()["code"] == "rate_limited"
    # another account is not affected
    b = crm.user("bob")
    jb = crm.job(b.id)
    b.import_ids(jb, [crm.result(jb, 2)])
