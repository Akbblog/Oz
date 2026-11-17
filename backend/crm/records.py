"""Records: list/pipeline/detail reads, manual create, PATCH and transitions."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional, Sequence, Tuple

from . import matching
from .common import (
    CRMError, api_date, api_ts, begin_write, clean_currency, clean_date, clean_email, clean_int, clean_phone,
    clean_text, clean_url, clean_value, cursor_ts, db_ts, decode_cursor, encode_cursor, fetch_all, fetch_one,
    for_update, from_db_ts, from_json, invalid, invalid_transition, like_param, local_day_bounds, new_id,
    not_found, num, page_limit, placeholders, scalar, to_json, tz_offset, utcnow,
)
from .workspace import stage_api, stages

RECORD_COLS = (
    "r.id, r.workspace_id, r.company_id, r.pipeline_id, r.stage_id, r.last_open_stage_id, r.type, r.title, "
    "r.assignee_user_id, r.outcome, r.lost_reason_id, r.lost_note, r.value, r.currency, r.probability, "
    "r.expected_close_date, r.priority, r.archived_at, r.closed_at, r.converted_at, r.created_by, r.created_at, "
    "r.updated_at, r.version, r.last_activity_at, r.next_activity_at"
)
COMPANY_COLS = (
    "id, name, match_place_key, match_host, match_phone, match_name, source_snapshot, phone, email, website, "
    "address, city, region, country, maps_url, category, created_at, updated_at, archived_at"
)
COMPANY_EDITABLE = ("phone", "email", "website", "address", "city", "region", "country")
RECORD_TYPES = ("lead", "opportunity")


# --------------------------------------------------------------------------- #
# Events
# --------------------------------------------------------------------------- #

def add_event(cur, ws_id: str, record_id: Optional[str], actor_id: Optional[int], type_: str,
              before: Any = None, after: Any = None, at: Optional[datetime] = None) -> None:
    cur.execute(
        "INSERT INTO crm_events (workspace_id, record_id, actor_user_id, type, before_json, after_json, occurred_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        (ws_id, record_id, actor_id, type_, to_json(before), to_json(after), db_ts(at or utcnow())),
    )


def event_api(e: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": int(e["id"]),
        "type": e["type"],
        "actor_user_id": e["actor_user_id"],
        "before": from_json(e["before_json"]),
        "after": from_json(e["after_json"]),
        "occurred_at": api_ts(e["occurred_at"]),
    }


def list_events(conn, ws: Dict[str, Any], record_id: str, cursor: Optional[str], limit: Optional[int]) -> Dict[str, Any]:
    cur = conn.cursor()
    load_record(cur, ws["id"], record_id)
    n = page_limit(limit)
    params: List[Any] = [ws["id"], record_id]
    sql = "SELECT id, type, actor_user_id, before_json, after_json, occurred_at FROM crm_events WHERE workspace_id = ? AND record_id = ?"
    after = decode_cursor(cursor, 1)
    if after:
        sql += " AND id < ?"
        params.append(int(after[0]))
    rows = fetch_all(cur, sql + " ORDER BY id DESC LIMIT ?", (*params, n + 1))
    total = int(scalar(cur, "SELECT COUNT(*) FROM crm_events WHERE workspace_id = ? AND record_id = ?", (ws["id"], record_id)) or 0)
    more = len(rows) > n
    rows = rows[:n]
    return {
        "items": [event_api(e) for e in rows],
        "next_cursor": encode_cursor([int(rows[-1]["id"])]) if more and rows else None,
        "total": total,
    }


# --------------------------------------------------------------------------- #
# Loading
# --------------------------------------------------------------------------- #

def load_record(cur, ws_id: str, record_id: Any, lock: bool = False) -> Dict[str, Any]:
    if not isinstance(record_id, str) or not record_id or len(record_id) > 36:
        raise not_found()
    row = fetch_one(
        cur, f"SELECT {RECORD_COLS} FROM crm_records r WHERE r.id = ? AND r.workspace_id = ?" + (for_update() if lock else ""),
        (record_id, ws_id),
    )
    if row is None:
        raise not_found()
    return row


def load_company(cur, ws_id: str, company_id: str) -> Dict[str, Any]:
    row = fetch_one(cur, f"SELECT {COMPANY_COLS} FROM crm_companies WHERE id = ? AND workspace_id = ?", (company_id, ws_id))
    if row is None:
        raise not_found()
    return row


def stage_map(cur, ws: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    rows = fetch_all(
        cur, "SELECT id, pipeline_id, stage_key, name, position, outcome_kind, active, color FROM crm_stages WHERE workspace_id = ?",
        (ws["id"],),
    )
    return {s["id"]: s for s in rows}


def _stage_ref(s: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    if not s:
        return None
    return {"id": s["id"], "key": s["stage_key"], "name": s["name"]}


# --------------------------------------------------------------------------- #
# Items
# --------------------------------------------------------------------------- #

def build_items(cur, ws: Dict[str, Any], rows: Sequence[Dict[str, Any]], now: Optional[datetime] = None) -> List[Dict[str, Any]]:
    if not rows:
        return []
    now = now or utcnow()
    ws_id = ws["id"]
    smap = stage_map(cur, ws)
    rec_ids = [r["id"] for r in rows]
    comp_ids = list({r["company_id"] for r in rows})
    ph_r, ph_c = placeholders(len(rec_ids)), placeholders(len(comp_ids))

    companies = {
        c["id"]: c for c in fetch_all(
            cur, f"SELECT id, name, city, region, country, phone, email, website FROM crm_companies "
                 f"WHERE workspace_id = ? AND id IN ({ph_c})", (ws_id, *comp_ids))
    }
    tags: Dict[str, List[Dict[str, Any]]] = {}
    for t in fetch_all(
        cur, f"SELECT rt.record_id, t.id, t.name, t.color FROM crm_record_tags rt JOIN crm_tags t ON t.id = rt.tag_id "
             f"WHERE rt.workspace_id = ? AND t.workspace_id = ? AND rt.record_id IN ({ph_r}) ORDER BY t.name, t.id",
        (ws_id, ws_id, *rec_ids),
    ):
        tags.setdefault(t["record_id"], []).append({"id": t["id"], "name": t["name"], "color": t["color"]})
    next_act: Dict[str, Dict[str, Any]] = {}
    for a in fetch_all(
        cur, f"SELECT id, record_id, type, subject, due_at FROM crm_activities WHERE workspace_id = ? AND status = 'open' "
             f"AND record_id IN ({ph_r}) ORDER BY due_at, id", (ws_id, *rec_ids),
    ):
        if a["record_id"] not in next_act:
            due = from_db_ts(a["due_at"])
            next_act[a["record_id"]] = {"id": a["id"], "type": a["type"], "subject": a["subject"],
                                        "due_at": api_ts(a["due_at"]), "overdue": bool(due and due < now)}
    sources = {
        s["record_id"]: int(s["n"]) for s in fetch_all(
            cur, f"SELECT record_id, COUNT(*) AS n FROM crm_source_links WHERE workspace_id = ? AND record_id IN ({ph_r}) "
                 f"GROUP BY record_id", (ws_id, *rec_ids))
    }
    out = []
    for r in rows:
        c = companies.get(r["company_id"]) or {}
        out.append({
            "id": r["id"],
            "title": r["title"],
            "type": r["type"],
            "outcome": r["outcome"],
            "stage": _stage_ref(smap.get(r["stage_id"])),
            "company": {
                "id": c.get("id"), "name": c.get("name"), "city": c.get("city"), "region": c.get("region"),
                "country": c.get("country"), "phone": c.get("phone"), "email": c.get("email"), "website": c.get("website"),
            },
            "tags": tags.get(r["id"], []),
            "next_activity": next_act.get(r["id"]),
            "source_count": sources.get(r["id"], 0),
            "value": num(r["value"]),
            "currency": r["currency"],
            "priority": int(r["priority"] or 0),
            "archived": r["archived_at"] is not None,
            "updated_at": api_ts(r["updated_at"]),
            "created_at": api_ts(r["created_at"]),
            "version": int(r["version"]),
        })
    return out


# --------------------------------------------------------------------------- #
# List / filters / keyset
# --------------------------------------------------------------------------- #

SORTS = ("updated", "created", "name", "next_activity")


def record_filters(cur, ws: Dict[str, Any], f: Dict[str, Any], now: datetime) -> Tuple[str, List[Any]]:
    """WHERE clause (on ``crm_records r JOIN crm_companies c``) for the list/pipeline/export filters."""
    where = ["r.workspace_id = ?", "c.workspace_id = ?"]
    params: List[Any] = [ws["id"], ws["id"]]

    stage_id = f.get("stage_id")
    outcome = f.get("outcome")
    if stage_id:
        st = fetch_one(cur, "SELECT id, outcome_kind FROM crm_stages WHERE id = ? AND workspace_id = ?", (stage_id, ws["id"]))
        if st is None:
            raise not_found()
        where.append("r.stage_id = ?")
        params.append(stage_id)
        if outcome is None and st["outcome_kind"] == "won":
            outcome = "won"
    outcome = outcome or "open"
    if outcome not in ("open", "won", "lost", "all"):
        raise invalid("outcome must be open, won, lost or all.")
    if outcome != "all":
        where.append("r.outcome = ?")
        params.append(outcome)

    archived = f.get("archived") or "false"
    if archived not in ("false", "true", "all"):
        raise invalid("archived must be false, true or all.")
    if archived == "false":
        where.append("r.archived_at IS NULL")
    elif archived == "true":
        where.append("r.archived_at IS NOT NULL")

    type_ = f.get("type")
    if type_:
        if type_ not in RECORD_TYPES:
            raise invalid("type must be lead or opportunity.")
        where.append("r.type = ?")
        params.append(type_)

    if f.get("tag_id"):
        where.append("EXISTS (SELECT 1 FROM crm_record_tags rt WHERE rt.record_id = r.id AND rt.workspace_id = r.workspace_id AND rt.tag_id = ?)")
        params.append(f["tag_id"])

    if f.get("source_job_id"):
        where.append("EXISTS (SELECT 1 FROM crm_source_links sl WHERE sl.workspace_id = r.workspace_id AND sl.record_id = r.id AND sl.source_job_id = ?)")
        params.append(str(f["source_job_id"])[:255])

    due = f.get("due")
    if due:
        if due == "overdue":
            where.append("r.next_activity_at < ?")
            params.append(db_ts(now))
        elif due == "today":
            _, end = local_day_bounds(now, tz_offset(f.get("tz_offset_minutes")))
            where.append("r.next_activity_at >= ? AND r.next_activity_at < ?")
            params.extend([db_ts(now), db_ts(end)])
        elif due == "none":
            where.append("r.next_activity_at IS NULL")
        else:
            raise invalid("due must be overdue, today or none.")

    q = (f.get("q") or "").strip()
    if q:
        if len(q) > 200:
            raise invalid("The search text must be at most 200 characters.")
        p = like_param(q)
        where.append(
            "(LOWER(r.title) LIKE ? ESCAPE '!' OR LOWER(c.name) LIKE ? ESCAPE '!'"
            " OR LOWER(COALESCE(c.phone, '')) LIKE ? ESCAPE '!' OR LOWER(COALESCE(c.email, '')) LIKE ? ESCAPE '!'"
            " OR LOWER(COALESCE(c.website, '')) LIKE ? ESCAPE '!'"
            " OR EXISTS (SELECT 1 FROM crm_record_tags rt JOIN crm_tags t ON t.id = rt.tag_id"
            "  WHERE rt.record_id = r.id AND rt.workspace_id = r.workspace_id AND LOWER(t.name) LIKE ? ESCAPE '!')"
            " OR EXISTS (SELECT 1 FROM crm_notes n WHERE n.record_id = r.id AND n.workspace_id = r.workspace_id"
            "  AND LOWER(n.body) LIKE ? ESCAPE '!'))"
        )
        params.extend([p] * 7)
    return " AND ".join(where), params


def _sort_sql(sort: str) -> Tuple[str, str]:
    """(select expression for keyset values, ORDER BY)."""
    if sort == "created":
        return "r.created_at AS k1", "r.created_at DESC, r.id DESC"
    if sort == "name":
        return "LOWER(r.title) AS k1", "LOWER(r.title) ASC, r.id ASC"
    if sort == "next_activity":
        return ("CASE WHEN r.next_activity_at IS NULL THEN 1 ELSE 0 END AS k0, r.next_activity_at AS k1",
                "CASE WHEN r.next_activity_at IS NULL THEN 1 ELSE 0 END, r.next_activity_at, r.id")
    return "r.updated_at AS k1", "r.updated_at DESC, r.id DESC"


def _keyset(sort: str, cursor: Optional[str]) -> Tuple[str, List[Any]]:
    if not cursor:
        return "", []
    if sort == "next_activity":
        null_flag, ts, rid = decode_cursor(cursor, 3)
        if int(null_flag) == 1:
            return " AND (r.next_activity_at IS NULL AND r.id > ?)", [rid]
        return (" AND (r.next_activity_at IS NULL OR r.next_activity_at > ? OR (r.next_activity_at = ? AND r.id > ?))",
                [ts, ts, rid])
    k1, rid = decode_cursor(cursor, 2)
    if sort == "name":
        return " AND (LOWER(r.title) > ? OR (LOWER(r.title) = ? AND r.id > ?))", [k1, k1, rid]
    col = "r.created_at" if sort == "created" else "r.updated_at"
    return f" AND ({col} < ? OR ({col} = ? AND r.id < ?))", [k1, k1, rid]


def _cursor_for(sort: str, row: Dict[str, Any]) -> str:
    if sort == "next_activity":
        return encode_cursor([int(row["k0"]), cursor_ts(row["k1"]), row["id"]])
    if sort == "name":
        return encode_cursor([row["k1"], row["id"]])
    return encode_cursor([cursor_ts(row["k1"]), row["id"]])


def query_records(cur, ws: Dict[str, Any], f: Dict[str, Any], *, limit: int, cursor: Optional[str] = None,
                  now: Optional[datetime] = None, with_total: bool = True) -> Tuple[List[Dict[str, Any]], Optional[str], Optional[int]]:
    now = now or utcnow()
    sort = f.get("sort") or "updated"
    if sort not in SORTS:
        raise invalid("sort must be updated, created, name or next_activity.")
    where, params = record_filters(cur, ws, f, now)
    sel, order = _sort_sql(sort)
    ks_sql, ks_params = _keyset(sort, cursor)
    rows = fetch_all(
        cur,
        f"SELECT {RECORD_COLS}, {sel} FROM crm_records r JOIN crm_companies c ON c.id = r.company_id "
        f"WHERE {where}{ks_sql} ORDER BY {order} LIMIT ?",
        (*params, *ks_params, limit + 1),
    )
    more = len(rows) > limit
    rows = rows[:limit]
    next_cursor = _cursor_for(sort, rows[-1]) if more and rows else None
    total = None
    if with_total:
        total = int(scalar(cur, f"SELECT COUNT(*) FROM crm_records r JOIN crm_companies c ON c.id = r.company_id WHERE {where}",
                           params) or 0)
    return rows, next_cursor, total


def list_records(conn, ws: Dict[str, Any], f: Dict[str, Any]) -> Dict[str, Any]:
    cur = conn.cursor()
    now = utcnow()
    rows, next_cursor, total = query_records(cur, ws, f, limit=page_limit(f.get("limit")), cursor=f.get("cursor"), now=now)
    return {"items": build_items(cur, ws, rows, now), "next_cursor": next_cursor, "total": total}


def pipeline(conn, ws: Dict[str, Any], f: Dict[str, Any]) -> Dict[str, Any]:
    cur = conn.cursor()
    now = utcnow()
    per_stage = page_limit(f.get("per_stage"), default=20)
    out_stages = []
    for s in stages(cur, ws["id"], ws["pipeline_id"]):
        sf = {k: f.get(k) for k in ("q", "tag_id", "source_job_id")}
        sf.update({"stage_id": s["id"], "outcome": "won" if s["outcome_kind"] == "won" else "open", "archived": "false",
                   "sort": "updated"})
        rows, next_cursor, total = query_records(cur, ws, sf, limit=per_stage, now=now)
        where, params = record_filters(cur, ws, sf, now)
        values = [
            {"currency": v["currency"], "total": num(v["total"])}
            for v in fetch_all(
                cur,
                f"SELECT r.currency, SUM(r.value) AS total FROM crm_records r JOIN crm_companies c ON c.id = r.company_id "
                f"WHERE {where} AND r.value IS NOT NULL AND r.currency IS NOT NULL GROUP BY r.currency ORDER BY r.currency",
                params,
            )
        ]
        out_stages.append({"stage": stage_api(s), "count": total, "values": values,
                           "items": build_items(cur, ws, rows, now), "next_cursor": next_cursor})
    return {"stages": out_stages, "summary": record_summary(cur, ws, now, f.get("tz_offset_minutes"))}


def record_summary(cur, ws: Dict[str, Any], now: datetime, offset_minutes: Any = None) -> Dict[str, int]:
    _, end = local_day_bounds(now, tz_offset(offset_minutes))
    base = "FROM crm_records WHERE workspace_id = ? AND outcome = 'open' AND archived_at IS NULL"
    n = lambda extra, p=(): int(scalar(cur, f"SELECT COUNT(*) {base}{extra}", (ws["id"], *p)) or 0)  # noqa: E731
    return {
        "open": n(""),
        "due_today": n(" AND next_activity_at >= ? AND next_activity_at < ?", (db_ts(now), db_ts(end))),
        "overdue": n(" AND next_activity_at < ?", (db_ts(now),)),
        "no_next_activity": n(" AND next_activity_at IS NULL"),
    }


# --------------------------------------------------------------------------- #
# Detail
# --------------------------------------------------------------------------- #

def activity_api(a: Dict[str, Any], now: Optional[datetime] = None) -> Dict[str, Any]:
    now = now or utcnow()
    due = from_db_ts(a["due_at"])
    return {
        "id": a["id"], "record_id": a["record_id"], "type": a["type"], "subject": a["subject"], "notes": a["notes"],
        "due_at": api_ts(a["due_at"]), "status": a["status"], "completed_at": api_ts(a["completed_at"]),
        "outcome": a["outcome"], "overdue": a["status"] == "open" and bool(due and due < now),
        "assignee_user_id": a["assignee_user_id"], "created_at": api_ts(a["created_at"]),
        "updated_at": api_ts(a["updated_at"]),
    }


ACTIVITY_COLS = ("id, record_id, type, subject, notes, due_at, assignee_user_id, status, completed_at, outcome, "
                 "created_by, created_at, updated_at")


def person_api(p: Dict[str, Any]) -> Dict[str, Any]:
    return {"id": p["id"], "name": p["name"], "role": p["role"], "phone": p["phone"], "email": p["email"],
            "is_primary": bool(p["is_primary"]), "company_id": p["company_id"], "record_id": p["record_id"],
            "created_at": api_ts(p["created_at"]), "updated_at": api_ts(p["updated_at"])}


NOTE_SELECT = ("SELECT n.id, n.record_id, n.author_user_id, n.body, n.created_at, n.edited_at, u.username AS author_name "
               "FROM crm_notes n LEFT JOIN users u ON u.id = n.author_user_id")


def note_api(n: Dict[str, Any], viewer_id: Optional[int] = None) -> Dict[str, Any]:
    author = {"id": n["author_user_id"], "name": n.get("author_name")} if n["author_user_id"] is not None else None
    return {"id": n["id"], "record_id": n["record_id"], "author_user_id": n["author_user_id"], "author": author,
            "author_name": n.get("author_name"),
            "can_edit": viewer_id is not None and n["author_user_id"] == viewer_id,
            "body": n["body"], "created_at": api_ts(n["created_at"]), "edited_at": api_ts(n["edited_at"])}


def detail(conn, ws: Dict[str, Any], record_id: str) -> Dict[str, Any]:
    cur = conn.cursor()
    now = utcnow()
    r = load_record(cur, ws["id"], record_id)
    item = build_items(cur, ws, [r], now)[0]
    c = load_company(cur, ws["id"], r["company_id"])
    item["company"] = {
        "id": c["id"], "name": c["name"], "phone": c["phone"], "email": c["email"], "website": c["website"],
        "address": c["address"], "city": c["city"], "region": c["region"], "country": c["country"],
        "maps_url": c["maps_url"], "category": c["category"],
        "source_snapshot": from_json(c["source_snapshot"]),
        "source_snapshot_label": "found online",
    }
    links = fetch_all(
        cur,
        "SELECT id, source_job_id, source_result_id, category, city, region, country, job_created_at, imported_at, snapshot "
        "FROM crm_source_links WHERE workspace_id = ? AND record_id = ? ORDER BY imported_at, id",
        (ws["id"], r["id"]),
    )
    available = set()
    rids = [int(l["source_result_id"]) for l in links if l["source_result_id"] is not None]
    if rids:
        for row in fetch_all(cur, f"SELECT id, job_id FROM results WHERE id IN ({placeholders(len(rids))})", rids):
            available.add((int(row["id"]), str(row["job_id"])))
    item["sources"] = [
        {
            "job_id": l["source_job_id"], "result_id": l["source_result_id"], "category": l["category"],
            "city": l["city"], "region": l["region"], "country": l["country"],
            "job_created_at": api_ts(l["job_created_at"]), "imported_at": api_ts(l["imported_at"]),
            "available": l["source_result_id"] is not None and (int(l["source_result_id"]), str(l["source_job_id"])) in available,
            "snapshot": from_json(l["snapshot"]),
        }
        for l in links
    ]
    item["people"] = [person_api(p) for p in fetch_all(
        cur, "SELECT id, company_id, record_id, name, role, phone, email, is_primary, created_at, updated_at FROM crm_people "
             "WHERE workspace_id = ? AND company_id = ? ORDER BY is_primary DESC, name, id", (ws["id"], c["id"]))]
    acts = fetch_all(
        cur, f"SELECT {ACTIVITY_COLS} FROM crm_activities WHERE workspace_id = ? AND record_id = ? AND status = 'open' "
             f"ORDER BY due_at, id LIMIT 100", (ws["id"], r["id"]))
    acts += fetch_all(
        cur, f"SELECT {ACTIVITY_COLS} FROM crm_activities WHERE workspace_id = ? AND record_id = ? AND status = 'done' "
             f"ORDER BY completed_at DESC, id DESC LIMIT 50", (ws["id"], r["id"]))
    item["activities"] = [activity_api(a, now) for a in acts]
    item["notes"] = [note_api(n, ws.get("viewer_id")) for n in fetch_all(
        cur, f"{NOTE_SELECT} WHERE n.workspace_id = ? AND n.record_id = ? ORDER BY n.created_at DESC, n.id DESC LIMIT 50",
        (ws["id"], r["id"]))]
    ev = list_events(conn, ws, r["id"], None, 50)
    item["events"] = ev["items"]
    item["events_next_cursor"] = ev["next_cursor"]
    reason = None
    if r["lost_reason_id"]:
        lr = fetch_one(cur, "SELECT id, name FROM crm_lost_reasons WHERE id = ? AND workspace_id = ?", (r["lost_reason_id"], ws["id"]))
        reason = {"id": lr["id"], "name": lr["name"]} if lr else None
    item.update({
        "lost_reason": reason,
        "lost_note": r["lost_note"],
        "probability": r["probability"],
        "expected_close_date": api_date(r["expected_close_date"]),
        "closed_at": api_ts(r["closed_at"]),
        "converted_at": api_ts(r["converted_at"]),
        "assignee_user_id": r["assignee_user_id"],
        "last_activity_at": api_ts(r["last_activity_at"]),
    })
    return item


# --------------------------------------------------------------------------- #
# Writes
# --------------------------------------------------------------------------- #

def insert_company(cur, ws_id: str, *, name: str, phone=None, email=None, website=None, address=None, city=None,
                   region=None, country=None, maps_url=None, category=None, snapshot: Optional[Dict[str, Any]] = None,
                   now: Optional[datetime] = None) -> str:
    now_s = db_ts(now or utcnow())
    keys = matching.keys_for(name, phone, website, maps_url)
    cid = new_id()
    cur.execute(
        "INSERT INTO crm_companies (id, workspace_id, name, match_place_key, match_host, match_phone, match_name, "
        "source_snapshot, phone, email, website, address, city, region, country, maps_url, category, created_at, updated_at) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (cid, ws_id, name, keys["match_place_key"], keys["match_host"], keys["match_phone"], keys["match_name"],
         to_json(snapshot), phone, email, website, address, city, region, country, maps_url, category, now_s, now_s),
    )
    return cid


def insert_record(cur, ws: Dict[str, Any], *, company_id: str, title: str, stage_id: str, type_: str = "lead",
                  actor_id: Optional[int] = None, now: Optional[datetime] = None) -> str:
    now_s = db_ts(now or utcnow())
    rid = new_id()
    cur.execute(
        "INSERT INTO crm_records (id, workspace_id, company_id, pipeline_id, stage_id, type, title, outcome, priority, "
        "created_by, created_at, updated_at, version, converted_at) VALUES (?, ?, ?, ?, ?, ?, ?, 'open', 0, ?, ?, ?, 1, ?)",
        (rid, ws["id"], company_id, ws["pipeline_id"], stage_id, type_, title, actor_id, now_s, now_s,
         now_s if type_ == "opportunity" else None),
    )
    return rid


def first_open_stage(cur, ws: Dict[str, Any]) -> Dict[str, Any]:
    for s in stages(cur, ws["id"], ws["pipeline_id"]):
        if s["outcome_kind"] == "open":
            return s
    raise RuntimeError("Pipeline has no open stage")


def won_stage(cur, ws: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    for s in stages(cur, ws["id"], ws["pipeline_id"]):
        if s["outcome_kind"] == "won":
            return s
    return None


def _company_fields(raw: Dict[str, Any]) -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    if "phone" in raw:
        out["phone"] = clean_phone(raw.get("phone"))
    if "email" in raw:
        out["email"] = clean_email(raw.get("email"))
    if "website" in raw:
        out["website"] = clean_url(raw.get("website"))
    if "address" in raw:
        out["address"] = clean_text(raw.get("address"), "Address", 1000)
    for k, label, n in (("city", "City", 191), ("region", "Region", 191), ("country", "Country", 100)):
        if k in raw:
            out[k] = clean_text(raw.get(k), label, n)
    return out


def create_record(conn, ws: Dict[str, Any], user: Dict[str, Any], body: Dict[str, Any]) -> Dict[str, Any]:
    title = clean_text(body.get("title"), "Title", 300, required=True)
    comp = body.get("company")
    if not isinstance(comp, dict):
        raise invalid("company is required.")
    name = clean_text(comp.get("name"), "Company name", 300, required=True)
    fields = _company_fields(comp)
    type_ = body.get("type") or "lead"
    if type_ not in RECORD_TYPES:
        raise invalid("type must be lead or opportunity.")
    begin_write(conn)
    try:
        cur = conn.cursor()
        if body.get("stage_id"):
            st = fetch_one(cur, "SELECT id, outcome_kind, active FROM crm_stages WHERE id = ? AND workspace_id = ? AND pipeline_id = ?",
                           (body["stage_id"], ws["id"], ws["pipeline_id"]))
            if st is None:
                raise not_found()
            if st["outcome_kind"] != "open" or not st["active"]:
                raise invalid("A new record must start in an open stage.")
            stage_id = st["id"]
        else:
            stage_id = first_open_stage(cur, ws)["id"]
        now = utcnow()
        cid = insert_company(cur, ws["id"], name=name, now=now, **fields)
        rid = insert_record(cur, ws, company_id=cid, title=title, stage_id=stage_id, type_=type_, actor_id=user["id"], now=now)
        add_event(cur, ws["id"], rid, user["id"], "created", None, {"title": title, "type": type_}, now)
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    return detail(conn, ws, rid)


def _check_version(conn, ws: Dict[str, Any], r: Dict[str, Any], version: Any) -> None:
    if version is None:
        return
    if isinstance(version, bool) or not isinstance(version, int):
        raise invalid("version must be a whole number.")
    if int(r["version"]) != version:
        conn.rollback()
        raise CRMError(409, "This record was changed elsewhere. Review the latest version and try again.",
                       "version_conflict", current=detail(conn, ws, r["id"]))


def _bump(cur, ws_id: str, r: Dict[str, Any], sets: Dict[str, Any], now: datetime) -> None:
    cols = ", ".join(f"{k} = ?" for k in sets)
    cur.execute(
        f"UPDATE crm_records SET {cols}{', ' if cols else ''}updated_at = ?, version = version + 1 "
        f"WHERE id = ? AND workspace_id = ? AND version = ?",
        (*sets.values(), db_ts(now), r["id"], ws_id, r["version"]),
    )
    if cur.rowcount != 1:  # pragma: no cover - guarded by the row lock
        raise CRMError(409, "This record was changed elsewhere. Review the latest version and try again.", "version_conflict")


def touch(cur, ws_id: str, record_id: str, now: datetime) -> None:
    """Child change (note, person, tag, activity): bump updated_at only.

    ``version`` guards the record's own fields and stage; adding a note must not
    make the client's next stage change look stale.
    """
    cur.execute("UPDATE crm_records SET updated_at = ? WHERE id = ? AND workspace_id = ?",
                (db_ts(now), record_id, ws_id))


def patch_record(conn, ws: Dict[str, Any], user: Dict[str, Any], record_id: str, body: Dict[str, Any]) -> Dict[str, Any]:
    allowed = {"title", "value", "currency", "probability", "expected_close_date", "priority", "company", "version"}
    unknown = set(body) - allowed
    if unknown:
        raise invalid(f"These fields cannot be changed here: {', '.join(sorted(unknown))}.")
    sets: Dict[str, Any] = {}
    if "title" in body:
        sets["title"] = clean_text(body["title"], "Title", 300, required=True)
    if "value" in body:
        sets["value"] = clean_value(body["value"])
    if "currency" in body:
        sets["currency"] = clean_currency(body["currency"])
    if "probability" in body:
        sets["probability"] = clean_int(body["probability"], "Probability", 0, 100)
    if "expected_close_date" in body:
        sets["expected_close_date"] = clean_date(body["expected_close_date"], "Expected close date")
    if "priority" in body:
        p = clean_int(body["priority"], "Priority", 0, 3)
        sets["priority"] = 0 if p is None else p
    comp_sets: Dict[str, Any] = {}
    if body.get("company") is not None:
        if not isinstance(body["company"], dict):
            raise invalid("company must be an object.")
        extra = set(body["company"]) - set(COMPANY_EDITABLE)
        if extra:
            raise invalid(f"These company fields cannot be changed here: {', '.join(sorted(extra))}.")
        comp_sets = _company_fields(body["company"])

    begin_write(conn)
    try:
        cur = conn.cursor()
        r = load_record(cur, ws["id"], record_id, lock=True)
        _check_version(conn, ws, r, body.get("version"))
        value = sets.get("value", r["value"])
        currency = sets.get("currency", r["currency"])
        if value is not None and currency is None:
            if ws.get("currency_default"):
                sets["currency"] = currency = ws["currency_default"]
            else:
                raise invalid("Choose a currency for the deal value.")
        before: Dict[str, Any] = {}
        after: Dict[str, Any] = {}
        for k, v in list(sets.items()):
            old = r[k]
            old_cmp = num(old) if k == "value" else (api_date(old) if k == "expected_close_date" else old)
            new_cmp = num(v) if k == "value" else v
            if old_cmp == new_cmp:
                sets.pop(k)
                continue
            before[k], after[k] = old_cmp, new_cmp
        now = utcnow()
        if comp_sets:
            c = load_company(cur, ws["id"], r["company_id"])
            changed = {k: v for k, v in comp_sets.items() if c[k] != v}
            if changed:
                before["company"] = {k: c[k] for k in changed}
                after["company"] = changed
                cols = ", ".join(f"{k} = ?" for k in changed)
                cur.execute(f"UPDATE crm_companies SET {cols}, updated_at = ? WHERE id = ? AND workspace_id = ?",
                            (*changed.values(), db_ts(now), c["id"], ws["id"]))
        if not before:
            conn.rollback()
            return detail(conn, ws, record_id)
        _bump(cur, ws["id"], r, sets, now)
        add_event(cur, ws["id"], r["id"], user["id"], "updated", before, after, now)
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    return detail(conn, ws, record_id)


# --------------------------------------------------------------------------- #
# Transitions
# --------------------------------------------------------------------------- #

def _transition(conn, ws: Dict[str, Any], user: Dict[str, Any], record_id: str, version: Any, fn) -> Dict[str, Any]:
    begin_write(conn)
    try:
        cur = conn.cursor()
        r = load_record(cur, ws["id"], record_id, lock=True)
        now = utcnow()
        result = fn(cur, r, now, lambda: _check_version(conn, ws, r, version))
        if result is None:  # already in the target state: idempotent, nothing written
            conn.rollback()
        else:
            sets, ev_type, before, after = result
            _bump(cur, ws["id"], r, sets, now)
            add_event(cur, ws["id"], r["id"], user["id"], ev_type, before, after, now)
            conn.commit()
    except Exception:
        conn.rollback()
        raise
    return detail(conn, ws, record_id)


def _require_not_archived(r: Dict[str, Any]) -> None:
    if r["archived_at"] is not None:
        raise invalid_transition("This record is archived. Restore it first.")


def move_stage(conn, ws, user, record_id: str, stage_id: Any, version: Any) -> Dict[str, Any]:
    if not isinstance(stage_id, str) or not stage_id:
        raise invalid("stage_id is required.")

    def fn(cur, r, now, check):
        st = fetch_one(cur, "SELECT id, stage_key, name, outcome_kind, active FROM crm_stages "
                            "WHERE id = ? AND workspace_id = ? AND pipeline_id = ?", (stage_id, ws["id"], r["pipeline_id"]))
        if st is None:
            raise not_found()
        if st["id"] == r["stage_id"] and (r["outcome"] == "open" or (st["outcome_kind"] == "won" and r["outcome"] == "won")):
            return None
        _require_not_archived(r)
        if r["outcome"] != "open":
            raise invalid_transition("Only open records can change stage. Reopen it first.")
        if not st["active"]:
            raise invalid_transition("That stage is not active.")
        check()
        if st["outcome_kind"] == "won":
            return ({"stage_id": st["id"], "last_open_stage_id": r["stage_id"], "outcome": "won", "closed_at": db_ts(now)},
                    "won", {"stage_id": r["stage_id"], "outcome": "open"}, {"stage_id": st["id"], "outcome": "won"})
        return ({"stage_id": st["id"], "last_open_stage_id": st["id"]}, "stage_changed",
                {"stage_id": r["stage_id"]}, {"stage_id": st["id"], "stage_key": st["stage_key"]})

    return _transition(conn, ws, user, record_id, version, fn)


def convert(conn, ws, user, record_id: str, version: Any) -> Dict[str, Any]:
    def fn(cur, r, now, check):
        if r["type"] == "opportunity":
            return None
        _require_not_archived(r)
        check()
        return {"type": "opportunity", "converted_at": db_ts(now)}, "converted", {"type": "lead"}, {"type": "opportunity"}

    return _transition(conn, ws, user, record_id, version, fn)


def mark_won(conn, ws, user, record_id: str, version: Any) -> Dict[str, Any]:
    def fn(cur, r, now, check):
        if r["outcome"] == "won":
            return None
        _require_not_archived(r)
        if r["outcome"] == "lost":
            raise invalid_transition("This record is lost. Reopen it before marking it won.")
        check()
        ws_stage = won_stage(cur, ws)
        sets = {"outcome": "won", "closed_at": db_ts(now), "last_open_stage_id": r["stage_id"]}
        if ws_stage:
            sets["stage_id"] = ws_stage["id"]
        return sets, "won", {"outcome": "open", "stage_id": r["stage_id"]}, {"outcome": "won", "stage_id": sets.get("stage_id")}

    return _transition(conn, ws, user, record_id, version, fn)


def _resolve_reason(cur, ws: Dict[str, Any], reason_id: Any, custom: Any, now: datetime) -> Dict[str, Any]:
    if reason_id:
        lr = fetch_one(cur, "SELECT id, name FROM crm_lost_reasons WHERE id = ? AND workspace_id = ?", (reason_id, ws["id"]))
        if lr is None:
            raise not_found()
        return lr
    name = clean_text(custom, "Reason", 120)
    if not name:
        raise invalid("Choose a reason for losing this record.")
    lr = fetch_one(cur, "SELECT id, name FROM crm_lost_reasons WHERE workspace_id = ? AND LOWER(name) = LOWER(?)", (ws["id"], name))
    if lr:
        cur.execute("UPDATE crm_lost_reasons SET active = 1 WHERE id = ? AND workspace_id = ?", (lr["id"], ws["id"]))
        return lr
    pos = int(scalar(cur, "SELECT COALESCE(MAX(position), 0) FROM crm_lost_reasons WHERE workspace_id = ?", (ws["id"],)) or 0) + 1
    rid = new_id()
    cur.execute("INSERT INTO crm_lost_reasons (id, workspace_id, name, is_system, active, position, created_at) "
                "VALUES (?, ?, ?, 0, 1, ?, ?)", (rid, ws["id"], name, pos, db_ts(now)))
    return {"id": rid, "name": name}


def mark_lost(conn, ws, user, record_id: str, body: Dict[str, Any]) -> Dict[str, Any]:
    if not body.get("reason_id") and not (isinstance(body.get("custom_reason"), str) and body["custom_reason"].strip()):
        raise invalid("Choose a reason for losing this record.")
    note = clean_text(body.get("note"), "Note", 2000)

    def fn(cur, r, now, check):
        if r["outcome"] == "lost":
            return None
        _require_not_archived(r)
        if r["outcome"] == "won":
            raise invalid_transition("This record is won. Reopen it before marking it lost.")
        check()
        lr = _resolve_reason(cur, ws, body.get("reason_id"), body.get("custom_reason"), now)
        sets = {"outcome": "lost", "closed_at": db_ts(now), "last_open_stage_id": r["stage_id"], "lost_reason_id": lr["id"],
                "lost_note": note}
        return sets, "lost", {"outcome": "open"}, {"outcome": "lost", "reason": lr["name"], "note": note}

    return _transition(conn, ws, user, record_id, body.get("version"), fn)


def reopen(conn, ws, user, record_id: str, version: Any) -> Dict[str, Any]:
    def fn(cur, r, now, check):
        if r["outcome"] == "open":
            return None
        _require_not_archived(r)
        check()
        target = None
        if r["last_open_stage_id"]:
            target = fetch_one(cur, "SELECT id FROM crm_stages WHERE id = ? AND workspace_id = ? AND outcome_kind = 'open' AND active = 1",
                               (r["last_open_stage_id"], ws["id"]))
        stage_id = target["id"] if target else first_open_stage(cur, ws)["id"]
        sets = {"outcome": "open", "stage_id": stage_id, "closed_at": None, "lost_reason_id": None, "lost_note": None}
        return sets, "reopened", {"outcome": r["outcome"], "closed_at": api_ts(r["closed_at"])}, {"outcome": "open", "stage_id": stage_id}

    return _transition(conn, ws, user, record_id, version, fn)


def archive(conn, ws, user, record_id: str, version: Any) -> Dict[str, Any]:
    def fn(cur, r, now, check):
        if r["archived_at"] is not None:
            return None
        check()
        return {"archived_at": db_ts(now)}, "archived", {"archived": False}, {"archived": True}

    return _transition(conn, ws, user, record_id, version, fn)


def restore(conn, ws, user, record_id: str, version: Any) -> Dict[str, Any]:
    def fn(cur, r, now, check):
        if r["archived_at"] is None:
            return None
        check()
        return {"archived_at": None}, "restored", {"archived": True}, {"archived": False}

    return _transition(conn, ws, user, record_id, version, fn)
