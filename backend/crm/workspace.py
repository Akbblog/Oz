"""Private workspace per account, created lazily and race-safely."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from .common import (
    begin_write, db_ts, fetch_all, fetch_one, is_unique_violation, new_id, utcnow,
)

DEFAULT_STAGES = [
    ("new", "New", "open"),
    ("contacted", "Contacted", "open"),
    ("qualified", "Qualified", "open"),
    ("proposal", "Proposal", "open"),
    ("won", "Won", "won"),
]
DEFAULT_LOST_REASONS = ["Not interested", "No response", "Not a fit", "Duplicate", "Other"]


def _find(cur, user_id: int) -> Optional[Dict[str, Any]]:
    return fetch_one(
        cur,
        "SELECT w.id, w.name, w.currency_default, m.role FROM crm_workspaces w "
        "JOIN crm_memberships m ON m.workspace_id = w.id AND m.user_id = ? AND m.status = 'active' "
        "WHERE w.owner_user_id = ?",
        (user_id, user_id),
    )


def _create(conn, user: Dict[str, Any]) -> None:
    cur = conn.cursor()
    now = db_ts(utcnow())
    ws_id = new_id()
    cur.execute(
        "INSERT INTO crm_workspaces (id, owner_user_id, name, currency_default, created_at, updated_at) "
        "VALUES (?, ?, ?, NULL, ?, ?)",
        (ws_id, user["id"], "My CRM", now, now),
    )
    cur.execute(
        "INSERT INTO crm_memberships (id, workspace_id, user_id, role, status, joined_at) "
        "VALUES (?, ?, ?, 'owner', 'active', ?)",
        (new_id(), ws_id, user["id"], now),
    )
    pipeline_id = new_id()
    cur.execute(
        "INSERT INTO crm_pipelines (id, workspace_id, name, is_default, active, created_at) VALUES (?, ?, 'Sales', 1, 1, ?)",
        (pipeline_id, ws_id, now),
    )
    for pos, (key, name, kind) in enumerate(DEFAULT_STAGES):
        cur.execute(
            "INSERT INTO crm_stages (id, workspace_id, pipeline_id, stage_key, name, position, outcome_kind, active, created_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)",
            (new_id(), ws_id, pipeline_id, key, name, pos, kind, now),
        )
    for pos, name in enumerate(DEFAULT_LOST_REASONS):
        cur.execute(
            "INSERT INTO crm_lost_reasons (id, workspace_id, name, is_system, active, position, created_at) "
            "VALUES (?, ?, ?, 1, 1, ?, ?)",
            (new_id(), ws_id, name, pos, now),
        )


def get_or_create(conn, user: Dict[str, Any]) -> Dict[str, Any]:
    """The caller's workspace ``{id, name, currency_default, role, pipeline_id}``.

    Created on first use. ``UNIQUE(owner_user_id)`` makes concurrent first calls
    safe: the loser of the race rolls back and reads the winner's workspace.
    """
    cur = conn.cursor()
    ws = _find(cur, user["id"])
    if ws is None:
        try:
            begin_write(conn)
            cur = conn.cursor()
            if _find(cur, user["id"]) is None:
                _create(conn, user)
            conn.commit()
        except Exception as exc:
            conn.rollback()
            if not is_unique_violation(exc):
                raise
        cur = conn.cursor()
        ws = _find(cur, user["id"])
        if ws is None:  # pragma: no cover - only if the row vanished
            raise RuntimeError("CRM workspace could not be created")
    pipe = fetch_one(
        cur, "SELECT id FROM crm_pipelines WHERE workspace_id = ? AND is_default = 1 ORDER BY created_at LIMIT 1",
        (ws["id"],),
    )
    ws["pipeline_id"] = pipe["id"] if pipe else None
    ws["viewer_id"] = user["id"]  # for per-viewer flags such as a note's can_edit
    return ws


def stages(cur, ws_id: str, pipeline_id: str, active_only: bool = True) -> List[Dict[str, Any]]:
    sql = (
        "SELECT id, stage_key, name, position, outcome_kind, active, color FROM crm_stages "
        "WHERE workspace_id = ? AND pipeline_id = ?"
    )
    if active_only:
        sql += " AND active = 1"
    return fetch_all(cur, sql + " ORDER BY position, id", (ws_id, pipeline_id))


def stage_api(s: Dict[str, Any]) -> Dict[str, Any]:
    return {"id": s["id"], "key": s["stage_key"], "name": s["name"], "position": int(s["position"]),
            "outcome_kind": s["outcome_kind"]}


def lost_reasons(cur, ws_id: str) -> List[Dict[str, Any]]:
    return fetch_all(
        cur, "SELECT id, name FROM crm_lost_reasons WHERE workspace_id = ? AND active = 1 ORDER BY position, name",
        (ws_id,),
    )


def tags(cur, ws_id: str) -> List[Dict[str, Any]]:
    return fetch_all(cur, "SELECT id, name, color FROM crm_tags WHERE workspace_id = ? ORDER BY name, id", (ws_id,))


def workspace_payload(conn, ws: Dict[str, Any]) -> Dict[str, Any]:
    cur = conn.cursor()
    pipe = fetch_one(cur, "SELECT id, name FROM crm_pipelines WHERE id = ?", (ws["pipeline_id"],))
    return {
        "id": ws["id"],
        "name": ws["name"],
        "role": ws["role"],
        "pipeline": {
            "id": pipe["id"],
            "name": pipe["name"],
            "stages": [stage_api(s) for s in stages(cur, ws["id"], ws["pipeline_id"])],
        },
        "lost_reasons": [{"id": r["id"], "name": r["name"]} for r in lost_reasons(cur, ws["id"])],
        "tags": [{"id": t["id"], "name": t["name"], "color": t["color"]} for t in tags(cur, ws["id"])],
        "currency_default": ws.get("currency_default"),
    }
