"""CRM records: transitions, versions, PATCH allowlist, list/pipeline, notes, people, tags."""
from tests.crm_fixtures import crm  # noqa: F401  (fixture)


def _stages(a):
    return {s["key"]: s for s in a.ok(a.get("/workspace"))["pipeline"]["stages"]}


def _imported(crm, a, n=1):
    job = crm.job(a.id)
    body = a.import_ids(job, crm.results(job, n))
    return [c["record_id"] for c in body["created"]], job


def test_stage_change_versions_conflict_and_idempotency(crm):
    a = crm.user("alice")
    st = _stages(a)
    (rid,), _ = _imported(crm, a)
    rec = a.record(rid)
    moved = a.ok(a.post(f"/records/{rid}/stage", {"stage_id": st["contacted"]["id"], "version": rec["version"]}))
    assert moved["stage"]["key"] == "contacted" and moved["version"] == rec["version"] + 1
    # stale version -> 409 with the current record
    r = a.post(f"/records/{rid}/stage", {"stage_id": st["qualified"]["id"], "version": rec["version"]})
    assert r.status_code == 409
    body = r.json()
    assert body["code"] == "version_conflict" and body["current"]["stage"]["key"] == "contacted"
    assert body["current"]["version"] == moved["version"]
    # same stage again (even with the old version) is idempotent: no new event, no version bump
    same = a.ok(a.post(f"/records/{rid}/stage", {"stage_id": st["contacted"]["id"], "version": rec["version"]}))
    assert same["version"] == moved["version"]
    assert [e["type"] for e in same["events"]].count("stage_changed") == 1
    # unknown stage / another workspace's stage
    assert a.post(f"/records/{rid}/stage", {"stage_id": "nope"}).status_code == 404
    b = crm.user("bob")
    assert a.post(f"/records/{rid}/stage", {"stage_id": _stages(b)["new"]["id"]}).status_code == 404
    assert a.post(f"/records/{rid}/stage", {}).status_code == 422
    # child changes do not make the client's version stale
    a.ok(a.post(f"/records/{rid}/notes", {"body": "n"}))
    a.ok(a.post(f"/records/{rid}/stage", {"stage_id": st["qualified"]["id"], "version": moved["version"]}))


def test_convert_won_lost_reopen_archive_restore_event_order(crm):
    a = crm.user("alice")
    st = _stages(a)
    (rid,), _ = _imported(crm, a)
    a.ok(a.post(f"/records/{rid}/stage", {"stage_id": st["proposal"]["id"]}))
    conv = a.ok(a.post(f"/records/{rid}/convert"))
    assert conv["type"] == "opportunity" and conv["converted_at"]
    assert a.ok(a.post(f"/records/{rid}/convert"))["version"] == conv["version"]  # once
    a.ok(a.patch(f"/records/{rid}", {"value": 1500, "currency": "usd", "probability": 40,
                                     "expected_close_date": "2026-12-31"}))
    won = a.ok(a.post(f"/records/{rid}/won"))
    assert won["outcome"] == "won" and won["stage"]["key"] == "won" and won["closed_at"]
    assert a.post(f"/records/{rid}/lost", {"reason_id": a.ok(a.get("/workspace"))["lost_reasons"][0]["id"]}).status_code == 409
    reopened = a.ok(a.post(f"/records/{rid}/reopen"))
    assert reopened["outcome"] == "open" and reopened["stage"]["key"] == "proposal" and reopened["closed_at"] is None
    # Lost requires a reason
    r = a.post(f"/records/{rid}/lost", {})
    assert r.status_code == 422 and r.json()["code"] == "validation_error"
    lost = a.ok(a.post(f"/records/{rid}/lost", {"custom_reason": "Chose a competitor", "note": "price"}))
    assert lost["outcome"] == "lost" and lost["lost_reason"]["name"] == "Chose a competitor" and lost["lost_note"] == "price"
    assert "Chose a competitor" in [r["name"] for r in a.ok(a.get("/workspace"))["lost_reasons"]]
    # same custom reason again reuses the workspace reason
    a.ok(a.post(f"/records/{rid}/reopen"))
    lost2 = a.ok(a.post(f"/records/{rid}/lost", {"custom_reason": "chose a COMPETITOR"}))
    assert lost2["lost_reason"]["id"] == lost["lost_reason"]["id"]
    assert a.post(f"/records/{rid}/won").status_code == 409
    a.ok(a.post(f"/records/{rid}/reopen"))
    arch = a.ok(a.post(f"/records/{rid}/archive"))
    assert arch["archived"] is True
    r = a.post(f"/records/{rid}/stage", {"stage_id": st["new"]["id"]})
    assert r.status_code == 409 and r.json()["code"] == "invalid_transition"
    assert a.ok(a.get("/records"))["total"] == 0
    assert a.ok(a.get("/records", archived="true"))["total"] == 1
    restored = a.ok(a.post(f"/records/{rid}/restore"))
    assert restored["archived"] is False
    a.ok(a.post(f"/records/{rid}/restore"))  # idempotent
    events = [e["type"] for e in reversed(restored["events"])]
    assert events == ["imported", "stage_changed", "converted", "updated", "won", "reopened", "lost", "reopened",
                      "lost", "reopened", "archived", "restored"]
    times = [e["occurred_at"] for e in reversed(restored["events"])]
    assert times == sorted(times)
    page = a.ok(a.get(f"/records/{rid}/events", limit=5))
    assert page["total"] == 12 and len(page["items"]) == 5 and page["next_cursor"]
    rest = a.ok(a.get(f"/records/{rid}/events", limit=50, cursor=page["next_cursor"]))
    assert [e["type"] for e in page["items"] + rest["items"]] == list(reversed(events))


def test_drag_to_won_column_marks_won(crm):
    a = crm.user("alice")
    st = _stages(a)
    (rid,), _ = _imported(crm, a)
    won = a.ok(a.post(f"/records/{rid}/stage", {"stage_id": st["won"]["id"]}))
    assert won["outcome"] == "won" and won["events"][0]["type"] == "won"
    assert a.ok(a.post(f"/records/{rid}/reopen"))["stage"]["key"] == "new"
    # frontend flow: a won card dragged to an open column = reopen, then stage (with the returned version)
    a.ok(a.post(f"/records/{rid}/won"))
    reopened = a.ok(a.post(f"/records/{rid}/reopen", {"version": a.record(rid)["version"]}))
    for k in ("id", "version", "stage", "outcome", "company", "tags", "next_activity", "events_next_cursor"):
        assert k in reopened
    moved = a.ok(a.post(f"/records/{rid}/stage", {"stage_id": st["proposal"]["id"], "version": reopened["version"]}))
    assert moved["outcome"] == "open" and moved["stage"]["key"] == "proposal"


def test_patch_allowlist_and_validation(crm):
    a = crm.user("alice")
    (rid,), _ = _imported(crm, a)
    for body in [{"outcome": "won"}, {"stage_id": "x"}, {"workspace_id": "x"}, {"company": {"name": "x"}},
                 {"currency": "dollars"}, {"probability": 101}, {"probability": 1.5}, {"value": -1},
                 {"value": "abc"}, {"value": 10}, {"expected_close_date": "31/12/2026"}, {"priority": 4},
                 {"title": ""}, {"title": "x" * 301}, {"company": {"website": "javascript:alert(1)"}},
                 {"company": {"email": "not-an-email"}}, {"company": {"phone": "call me"}}]:
        r = a.patch(f"/records/{rid}", body)
        assert r.status_code == 422 and r.json()["code"] == "validation_error", body
    rec = a.record(rid)
    out = a.ok(a.patch(f"/records/{rid}", {"title": "Renamed", "value": "99.5", "currency": "EUR", "priority": 2,
                                           "company": {"website": "https://new.example", "city": "Lusail"},
                                           "version": rec["version"]}))
    assert out["title"] == "Renamed" and out["value"] == 99.5 and out["currency"] == "EUR" and out["priority"] == 2
    assert out["company"]["website"] == "https://new.example" and out["company"]["city"] == "Lusail"
    # snapshot is not touched by edits
    assert out["company"]["source_snapshot"]["website"] == "https://biz1.example.com"
    upd = [e for e in out["events"] if e["type"] == "updated"][0]
    assert upd["after"]["title"] == "Renamed" and upd["before"]["company"]["city"] == "Doha"
    # no-op patch writes nothing
    same = a.ok(a.patch(f"/records/{rid}", {"title": "Renamed"}))
    assert same["version"] == out["version"]
    r = a.patch(f"/records/{rid}", {"title": "Again", "version": rec["version"]})
    assert r.status_code == 409 and r.json()["code"] == "version_conflict"
    # clearing the value is allowed
    assert a.ok(a.patch(f"/records/{rid}", {"value": None}))["value"] is None


def test_manual_create(crm):
    a = crm.user("alice")
    st = _stages(a)
    rec = a.ok(a.post("/records", {"title": "Deal", "type": "opportunity", "stage_id": st["qualified"]["id"],
                                   "company": {"name": "Acme", "website": "https://acme.example", "phone": "+1 555 0100"}}))
    assert rec["type"] == "opportunity" and rec["stage"]["key"] == "qualified" and rec["source_count"] == 0
    assert rec["sources"] == [] and rec["events"][0]["type"] == "created" and rec["converted_at"]
    assert a.post("/records", {"title": "x", "company": {"name": "y"}, "stage_id": st["won"]["id"]}).status_code == 422
    assert a.post("/records", {"title": "x"}).status_code == 422
    assert a.post("/records", {"title": "x", "company": {"name": "y", "website": "ftp://x"}}).status_code == 422


def test_list_filters_search_and_keyset_pagination(crm):
    a = crm.user("alice")
    ids, job = _imported(crm, a, 25)
    st = _stages(a)
    a.ok(a.post(f"/records/{ids[3]}/notes", {"body": "Prefers WhatsApp 100% of the time"}))
    tag = a.ok(a.post("/tags", {"name": "Hot_lead", "color": "#ff0000"}))
    a.ok(a.put(f"/records/{ids[5]}/tags", {"tag_ids": [tag["id"]]}))
    a.ok(a.post(f"/records/{ids[7]}/stage", {"stage_id": st["contacted"]["id"]}))
    a.ok(a.post(f"/records/{ids[8]}/won"))

    for sort in ("updated", "created", "name", "next_activity"):
        seen, cursor = [], None
        while True:
            params = {"limit": 7, "sort": sort}
            if cursor:
                params["cursor"] = cursor
            page = a.ok(a.get("/records", **params))
            assert page["total"] == 24
            seen += [i["id"] for i in page["items"]]
            cursor = page["next_cursor"]
            if not cursor:
                break
        assert len(seen) == 24 and len(set(seen)) == 24, sort
    names = [i["title"] for i in a.ok(a.get("/records", sort="name", limit=100))["items"]]
    assert names == sorted(names, key=str.lower)

    assert a.ok(a.get("/records", q="100%"))["total"] == 1       # notes, literal %
    assert a.ok(a.get("/records", q="hot_"))["total"] == 1       # tags, literal _
    assert a.ok(a.get("/records", q="biz12.example"))["total"] == 1  # website
    assert a.ok(a.get("/records", q="info13@"))["total"] == 1    # email
    assert a.ok(a.get("/records", q="50000014"))["total"] == 1   # phone
    assert a.ok(a.get("/records", q="nothing-like-this"))["total"] == 0
    assert a.ok(a.get("/records", tag_id=tag["id"]))["items"][0]["tags"][0]["name"] == "Hot_lead"
    assert a.ok(a.get("/records", stage_id=st["contacted"]["id"]))["total"] == 1
    assert a.ok(a.get("/records", stage_id=st["won"]["id"]))["total"] == 1  # won column defaults to won
    assert a.ok(a.get("/records", stage_id=st["won"]["id"], outcome="won", archived="false"))["total"] == 1
    assert a.ok(a.get("/records", stage_id=st["contacted"]["id"], outcome="open", archived="false"))["total"] == 1
    assert a.ok(a.get("/records", outcome="won"))["total"] == 1
    assert a.ok(a.get("/records", outcome="all"))["total"] == 25
    assert a.ok(a.get("/records", type="opportunity"))["total"] == 0
    assert a.ok(a.get("/records", source_job_id=job, outcome="all"))["total"] == 25
    assert a.ok(a.get("/records", source_job_id="other"))["total"] == 0
    assert a.ok(a.get("/records", due="none"))["total"] == 24
    assert a.get("/records", sort="bogus").status_code == 422
    assert a.get("/records", outcome="bogus").status_code == 422

    pipe = a.ok(a.get("/pipeline", per_stage=10))
    cols = {c["stage"]["key"]: c for c in pipe["stages"]}
    assert [c["stage"]["key"] for c in pipe["stages"]] == ["new", "contacted", "qualified", "proposal", "won"]
    assert cols["new"]["count"] == 23 and len(cols["new"]["items"]) == 10 and cols["new"]["next_cursor"]
    assert cols["contacted"]["count"] == 1 and cols["won"]["count"] == 1 and cols["qualified"]["count"] == 0
    more = a.ok(a.get("/records", stage_id=st["new"]["id"], cursor=cols["new"]["next_cursor"], limit=50))
    assert len(more["items"]) == 13
    assert not {i["id"] for i in more["items"]} & {i["id"] for i in cols["new"]["items"]}
    assert pipe["summary"] == {"open": 24, "due_today": 0, "overdue": 0, "no_next_activity": 24}
    item = cols["new"]["items"][0]
    for k in ("id", "title", "type", "outcome", "stage", "company", "tags", "next_activity", "source_count", "value",
              "currency", "archived", "updated_at", "created_at", "version"):
        assert k in item


def test_pipeline_values_per_currency_never_summed(crm):
    a = crm.user("alice")
    ids, _ = _imported(crm, a, 3)
    a.ok(a.patch(f"/records/{ids[0]}", {"value": 100, "currency": "USD"}))
    a.ok(a.patch(f"/records/{ids[1]}", {"value": 50.25, "currency": "USD"}))
    a.ok(a.patch(f"/records/{ids[2]}", {"value": 70, "currency": "EUR"}))
    col = a.ok(a.get("/pipeline"))["stages"][0]
    assert col["values"] == [{"currency": "EUR", "total": 70.0}, {"currency": "USD", "total": 150.25}]


def test_notes_people_and_tags(crm):
    a = crm.user("alice")
    (rid,), _ = _imported(crm, a)
    note = a.ok(a.post(f"/records/{rid}/notes", {"body": "First call went well"}))
    assert note["edited_at"] is None and note["can_edit"] is True
    assert note["author"] == {"id": a.id, "name": "alice"} and note["author_name"] == "alice"
    edited = a.ok(a.patch(f"/notes/{note['id']}", {"body": "First call went very well"}))
    assert edited["edited_at"] and edited["body"] == "First call went very well"
    assert a.post(f"/records/{rid}/notes", {"body": "   "}).status_code == 422

    p1 = a.ok(a.post(f"/records/{rid}/people", {"name": "Sara Ali", "role": "Owner", "email": "sara@biz1.example.com",
                                                "is_primary": True}))
    p2 = a.ok(a.post(f"/records/{rid}/people", {"name": "Omar", "phone": "+974 5555 1234"}))
    assert a.post(f"/records/{rid}/people", {"name": "X", "email": "bad"}).status_code == 422
    assert a.post(f"/records/{rid}/people", {"name": "X", "is_admin": True}).status_code == 422
    a.ok(a.patch(f"/people/{p2['id']}", {"is_primary": True, "role": "Manager"}))
    rec = a.record(rid)
    assert rec["notes"][0]["can_edit"] is True and rec["notes"][0]["author"]["name"] == "alice"
    people = {p["name"]: p for p in rec["people"]}
    assert people["Omar"]["is_primary"] is True and people["Sara Ali"]["is_primary"] is False
    contacts = a.ok(a.get("/people", q="sara"))
    assert contacts["total"] == 1 and contacts["items"][0]["company"]["name"] == "Biz 1"
    assert contacts["items"][0]["record_id"] == rid
    assert a.ok(a.delete(f"/people/{p1['id']}")) == {"deleted": True}
    assert a.delete(f"/people/{p1['id']}").status_code == 404
    assert a.ok(a.get("/people"))["total"] == 1

    t1 = a.ok(a.post("/tags", {"name": "VIP"}))
    t2 = a.ok(a.post("/tags", {"name": "Follow-up", "color": "#00ff00"}))
    assert a.ok(a.post("/tags", {"name": "vip"}))["id"] == t1["id"]  # case-insensitive reuse
    assert a.post("/tags", {"name": "x", "color": "red;}"}).status_code == 422
    out = a.ok(a.put(f"/records/{rid}/tags", {"tag_ids": [t1["id"], t2["id"]]}))
    assert [t["name"] for t in out["tags"]] == ["Follow-up", "VIP"]
    out = a.ok(a.put(f"/records/{rid}/tags", {"tag_ids": [t2["id"]]}))
    assert [t["name"] for t in out["tags"]] == ["Follow-up"]
    a.ok(a.put(f"/records/{rid}/tags", {"tag_ids": [t2["id"]]}))  # no-op
    assert a.put(f"/records/{rid}/tags", {"tag_ids": ["missing"]}).status_code == 404
    rec = a.record(rid)
    types = [e["type"] for e in reversed(rec["events"])]
    assert types == ["imported", "note_added", "note_edited", "person_added", "person_added", "person_updated",
                     "person_removed", "tags_changed", "tags_changed"]
    assert [t["name"] for t in a.ok(a.get("/tags"))["items"]] == ["Follow-up", "VIP"]
