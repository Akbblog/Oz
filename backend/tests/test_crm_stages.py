"""Pipeline stage management keeps records reachable and workspaces isolated."""

from tests.crm_fixtures import crm  # noqa: F401


def test_stage_management_and_record_transfer(crm):
    a = crm.user("stage-owner")
    original = a.ok(a.get("/stages"))["stages"]
    new = a.ok(a.post("/stages", {"name": "Follow up"}))["stages"]
    added = next(s for s in new if s["name"] == "Follow up")
    assert new[-1]["outcome_kind"] == "won"

    renamed = a.ok(a.patch(f"/stages/{added['id']}", {"name": "Negotiating"}))["stages"]
    assert any(s["id"] == added["id"] and s["name"] == "Negotiating" for s in renamed)
    order = [added["id"], *[s["id"] for s in original]]
    reordered = a.ok(a.put("/stages/reorder", {"stage_ids": order}))["stages"]
    assert [s["id"] for s in reordered] == order
    assert a.get("/workspace").json()["pipeline"]["stages"][0]["id"] == added["id"]

    record = a.new_record("My business")
    rid = record["id"]
    current_version = a.record(rid)["version"]
    a.ok(a.post(f"/records/{rid}/stage", {"stage_id": added["id"], "version": current_version}))
    assert a.record(rid)["stage"]["id"] == added["id"]
    assert a.post(f"/stages/{added['id']}/delete", {}).status_code == 422
    destination = original[0]["id"]
    deleted = a.ok(a.post(f"/stages/{added['id']}/delete", {"replacement_stage_id": destination}))
    assert deleted["moved_records"] == 1
    assert a.record(rid)["stage"]["id"] == destination
    assert all(s["id"] != added["id"] for s in deleted["stages"])


def test_stage_restrictions_and_workspace_scope(crm):
    a = crm.user("stage-a")
    b = crm.user("stage-b")
    stages = a.ok(a.get("/stages"))["stages"]
    won = stages[-1]
    assert a.post(f"/stages/{won['id']}/delete", {}).status_code == 422
    assert a.put("/stages/reorder", {"stage_ids": list(reversed([s["id"] for s in stages]))}).status_code == 422
    assert b.patch(f"/stages/{stages[0]['id']}", {"name": "Stolen"}).status_code == 404
    assert b.post(f"/stages/{stages[0]['id']}/delete", {}).status_code == 404
