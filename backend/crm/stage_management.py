"""Manage the stages of a private CRM pipeline without losing its records."""

from __future__ import annotations

from typing import Any, Dict

from .common import CRMError, begin_write, clean_text, db_ts, fetch_all, fetch_one, for_update, invalid, new_id, not_found, utcnow
from .records import add_event
from .workspace import stage_api, stages


def _lock(cur, ws):
    pipe = fetch_one(cur, "SELECT id FROM crm_pipelines WHERE id = ? AND workspace_id = ?" + for_update(),
                     (ws["pipeline_id"], ws["id"]))
    if pipe is None:
        raise not_found()


def _ordered(cur, ws):
    return stages(cur, ws["id"], ws["pipeline_id"])


def _find(cur, ws, stage_id):
    row = fetch_one(cur, "SELECT id, stage_key, name, position, outcome_kind, active FROM crm_stages "
                    "WHERE id = ? AND workspace_id = ? AND pipeline_id = ? AND active = 1",
                    (stage_id, ws["id"], ws["pipeline_id"]))
    if row is None:
        raise not_found()
    return row


def _compact(cur, ws):
    for position, stage in enumerate(_ordered(cur, ws)):
        cur.execute("UPDATE crm_stages SET position = ? WHERE id = ? AND workspace_id = ?",
                    (position, stage["id"], ws["id"]))


def list_stages(conn, ws):
    cur = conn.cursor()
    result = []
    for stage in _ordered(cur, ws):
        count = fetch_one(cur, "SELECT COUNT(*) AS n FROM crm_records WHERE workspace_id = ? AND stage_id = ?",
                          (ws["id"], stage["id"]))
        dependent = fetch_one(cur, "SELECT COUNT(*) AS n FROM crm_records "
                              "WHERE workspace_id = ? AND (stage_id = ? OR last_open_stage_id = ?)",
                              (ws["id"], stage["id"], stage["id"]))
        result.append({**stage_api(stage), "record_count": int(count["n"]), "dependent_count": int(dependent["n"])})
    return {"stages": result}


def create(conn, ws, body: Dict[str, Any]):
    name = clean_text(body.get("name"), "Stage name", 120, required=True)
    begin_write(conn)
    try:
        cur = conn.cursor()
        _lock(cur, ws)
        current = _ordered(cur, ws)
        if len(current) >= 20:
            raise invalid("A pipeline can have at most 20 stages.")
        if any(s["name"].casefold() == name.casefold() for s in current):
            raise CRMError(409, "A stage with that name already exists.", "duplicate_stage")
        won = next((s for s in current if s["outcome_kind"] == "won"), None)
        position = int(won["position"]) if won else len(current)
        stage_id = new_id()
        cur.execute("INSERT INTO crm_stages (id, workspace_id, pipeline_id, stage_key, name, position, outcome_kind, active, created_at) "
                    "VALUES (?, ?, ?, ?, ?, ?, 'open', 1, ?)",
                    (stage_id, ws["id"], ws["pipeline_id"], "custom_" + stage_id.replace("-", "")[:32], name,
                     position, db_ts(utcnow())))
        # New open stage sits immediately before Won.
        order = [s["id"] for s in current if s["outcome_kind"] != "won"] + [stage_id]
        if won:
            order.append(won["id"])
        for i, sid in enumerate(order):
            cur.execute("UPDATE crm_stages SET position = ? WHERE id = ?", (i, sid))
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    return list_stages(conn, ws)


def rename(conn, ws, stage_id: str, body: Dict[str, Any]):
    name = clean_text(body.get("name"), "Stage name", 120, required=True)
    begin_write(conn)
    try:
        cur = conn.cursor()
        _lock(cur, ws)
        _find(cur, ws, stage_id)
        if any(s["id"] != stage_id and s["name"].casefold() == name.casefold() for s in _ordered(cur, ws)):
            raise CRMError(409, "A stage with that name already exists.", "duplicate_stage")
        cur.execute("UPDATE crm_stages SET name = ? WHERE id = ? AND workspace_id = ?", (name, stage_id, ws["id"]))
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    return list_stages(conn, ws)


def reorder(conn, ws, body: Dict[str, Any]):
    ids = body.get("stage_ids")
    if not isinstance(ids, list) or any(not isinstance(s, str) for s in ids):
        raise invalid("stage_ids must be an ordered list of stage IDs.")
    begin_write(conn)
    try:
        cur = conn.cursor()
        _lock(cur, ws)
        current = _ordered(cur, ws)
        if len(ids) != len(current) or set(ids) != {s["id"] for s in current}:
            raise CRMError(409, "The stages changed. Reload and try again.", "stages_changed")
        won = next((s for s in current if s["outcome_kind"] == "won"), None)
        if won and ids[-1] != won["id"]:
            raise invalid("Won must remain the last stage.")
        for i, sid in enumerate(ids):
            cur.execute("UPDATE crm_stages SET position = ? WHERE id = ? AND workspace_id = ?", (i, sid, ws["id"]))
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    return list_stages(conn, ws)


def delete(conn, ws, user, stage_id: str, body: Dict[str, Any]):
    replacement_id = body.get("replacement_stage_id")
    begin_write(conn)
    try:
        cur = conn.cursor()
        _lock(cur, ws)
        stage = _find(cur, ws, stage_id)
        if stage["outcome_kind"] == "won":
            raise invalid("Won is required and cannot be deleted.")
        others = [s for s in _ordered(cur, ws) if s["id"] != stage_id and s["outcome_kind"] == "open"]
        if not others:
            raise invalid("Keep at least one open stage.")
        records = fetch_all(cur, "SELECT id, stage_id, last_open_stage_id FROM crm_records "
                            "WHERE workspace_id = ? AND (stage_id = ? OR last_open_stage_id = ?)",
                            (ws["id"], stage_id, stage_id))
        if records:
            if not isinstance(replacement_id, str) or replacement_id not in {s["id"] for s in others}:
                raise invalid("Choose another open stage to receive these records.")
            now = utcnow()
            now_s = db_ts(now)
            for record in records:
                cur.execute("UPDATE crm_records SET stage_id = ?, last_open_stage_id = ?, updated_at = ?, version = version + 1 "
                            "WHERE id = ? AND workspace_id = ?",
                            (replacement_id if record["stage_id"] == stage_id else record["stage_id"],
                             replacement_id if record["last_open_stage_id"] == stage_id else record["last_open_stage_id"],
                             now_s, record["id"], ws["id"]))
                changed_current = record["stage_id"] == stage_id
                add_event(cur, ws["id"], record["id"], user["id"],
                          "stage_changed" if changed_current else "updated",
                          {"stage_id" if changed_current else "last_open_stage_id": stage_id},
                          {"stage_id" if changed_current else "last_open_stage_id": replacement_id,
                           "reason": "stage_deleted"}, now)
        cur.execute("UPDATE crm_stages SET active = 0 WHERE id = ? AND workspace_id = ?", (stage_id, ws["id"]))
        _compact(cur, ws)
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    return {"moved_records": len(records), **list_stages(conn, ws)}
