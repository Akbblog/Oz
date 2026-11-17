"""Notes, people, tags, activities and the agenda."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

from .common import (
    begin_write, clean_email, clean_phone, clean_text, cursor_ts, db_ts, decode_cursor, encode_cursor, fetch_all,
    fetch_one, for_update, invalid, is_unique_violation, like_param, local_day_bounds, new_id, not_found, page_limit,
    parse_aware, placeholders, scalar, tz_offset, utcnow,
)
from .records import ACTIVITY_COLS, activity_api, add_event, load_record, note_api, person_api, touch

ACTIVITY_TYPES = ("call", "email", "meeting", "message", "task")


def _write(conn, fn):
    begin_write(conn)
    try:
        result = fn(conn.cursor())
        conn.commit()
        return result
    except Exception:
        conn.rollback()
        raise


def _opt_id(value: Any) -> str:
    if not isinstance(value, str) or not value or len(value) > 36:
        raise not_found()
    return value


# --------------------------------------------------------------------------- #
# Notes
# --------------------------------------------------------------------------- #

def add_note(conn, ws, user, record_id: str, body: Dict[str, Any]) -> Dict[str, Any]:
    text = clean_text(body.get("body"), "Note", 10000, required=True)

    def fn(cur):
        load_record(cur, ws["id"], record_id, lock=True)
        now = utcnow()
        nid = new_id()
        cur.execute("INSERT INTO crm_notes (id, workspace_id, record_id, author_user_id, body, created_at, edited_at) "
                    "VALUES (?, ?, ?, ?, ?, ?, NULL)", (nid, ws["id"], record_id, user["id"], text, db_ts(now)))
        add_event(cur, ws["id"], record_id, user["id"], "note_added", None, {"note_id": nid, "excerpt": text[:120]}, now)
        touch(cur, ws["id"], record_id, now)
        return nid

    nid = _write(conn, fn)
    return note_api(fetch_one(conn.cursor(), "SELECT id, record_id, author_user_id, body, created_at, edited_at FROM crm_notes WHERE id = ?", (nid,)))


def edit_note(conn, ws, user, note_id: str, body: Dict[str, Any]) -> Dict[str, Any]:
    text = clean_text(body.get("body"), "Note", 10000, required=True)
    note_id = _opt_id(note_id)

    def fn(cur):
        n = fetch_one(cur, "SELECT id, record_id, author_user_id, body FROM crm_notes WHERE id = ? AND workspace_id = ?" + for_update(),
                      (note_id, ws["id"]))
        if n is None or n["author_user_id"] != user["id"]:
            raise not_found()
        if n["body"] == text:
            return
        now = utcnow()
        cur.execute("UPDATE crm_notes SET body = ?, edited_at = ? WHERE id = ? AND workspace_id = ?", (text, db_ts(now), note_id, ws["id"]))
        add_event(cur, ws["id"], n["record_id"], user["id"], "note_edited", {"excerpt": (n["body"] or "")[:120]},
                  {"note_id": note_id, "excerpt": text[:120]}, now)
        touch(cur, ws["id"], n["record_id"], now)

    _write(conn, fn)
    return note_api(fetch_one(conn.cursor(), "SELECT id, record_id, author_user_id, body, created_at, edited_at FROM crm_notes WHERE id = ?", (note_id,)))


# --------------------------------------------------------------------------- #
# People
# --------------------------------------------------------------------------- #

PERSON_COLS = "id, company_id, record_id, name, role, phone, email, is_primary, created_at, updated_at"


def _person_fields(body: Dict[str, Any], partial: bool) -> Dict[str, Any]:
    allowed = {"name", "role", "phone", "email", "is_primary"}
    unknown = set(body) - allowed
    if unknown:
        raise invalid(f"These fields cannot be set here: {', '.join(sorted(unknown))}.")
    out: Dict[str, Any] = {}
    if "name" in body or not partial:
        out["name"] = clean_text(body.get("name"), "Name", 200, required=True)
    if "role" in body:
        out["role"] = clean_text(body.get("role"), "Role", 120)
    if "phone" in body:
        out["phone"] = clean_phone(body.get("phone"))
    if "email" in body:
        out["email"] = clean_email(body.get("email"))
    if "is_primary" in body:
        if not isinstance(body["is_primary"], bool):
            raise invalid("is_primary must be true or false.")
        out["is_primary"] = 1 if body["is_primary"] else 0
    return out


def add_person(conn, ws, user, record_id: str, body: Dict[str, Any]) -> Dict[str, Any]:
    fields = _person_fields(body, partial=False)

    def fn(cur):
        r = load_record(cur, ws["id"], record_id, lock=True)
        now = utcnow()
        pid = new_id()
        if fields.get("is_primary"):
            cur.execute("UPDATE crm_people SET is_primary = 0 WHERE workspace_id = ? AND company_id = ?", (ws["id"], r["company_id"]))
        cur.execute(
            "INSERT INTO crm_people (id, workspace_id, company_id, record_id, name, role, phone, email, is_primary, created_by, "
            "created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (pid, ws["id"], r["company_id"], r["id"], fields["name"], fields.get("role"), fields.get("phone"),
             fields.get("email"), fields.get("is_primary", 0), user["id"], db_ts(now), db_ts(now)),
        )
        add_event(cur, ws["id"], r["id"], user["id"], "person_added", None, {"person_id": pid, "name": fields["name"]}, now)
        touch(cur, ws["id"], r["id"], now)
        return pid

    pid = _write(conn, fn)
    return person_api(fetch_one(conn.cursor(), f"SELECT {PERSON_COLS} FROM crm_people WHERE id = ?", (pid,)))


def _load_person(cur, ws_id: str, person_id: str, lock: bool = False) -> Dict[str, Any]:
    p = fetch_one(cur, f"SELECT {PERSON_COLS} FROM crm_people WHERE id = ? AND workspace_id = ?" + (for_update() if lock else ""),
                  (_opt_id(person_id), ws_id))
    if p is None:
        raise not_found()
    return p


def _person_record(cur, ws_id: str, p: Dict[str, Any]) -> Optional[str]:
    if p["record_id"]:
        return p["record_id"]
    r = fetch_one(cur, "SELECT id FROM crm_records WHERE workspace_id = ? AND company_id = ? ORDER BY created_at LIMIT 1",
                  (ws_id, p["company_id"]))
    return r["id"] if r else None


def update_person(conn, ws, user, person_id: str, body: Dict[str, Any]) -> Dict[str, Any]:
    fields = _person_fields(body, partial=True)

    def fn(cur):
        p = _load_person(cur, ws["id"], person_id, lock=True)
        changed = {k: v for k, v in fields.items() if p[k] != v and not (k == "is_primary" and bool(p[k]) == bool(v))}
        if not changed:
            return p["id"]
        now = utcnow()
        if changed.get("is_primary"):
            cur.execute("UPDATE crm_people SET is_primary = 0 WHERE workspace_id = ? AND company_id = ?", (ws["id"], p["company_id"]))
        cols = ", ".join(f"{k} = ?" for k in changed)
        cur.execute(f"UPDATE crm_people SET {cols}, updated_at = ? WHERE id = ? AND workspace_id = ?",
                    (*changed.values(), db_ts(now), p["id"], ws["id"]))
        rec = _person_record(cur, ws["id"], p)
        add_event(cur, ws["id"], rec, user["id"], "person_updated", {k: p[k] for k in changed},
                  {"person_id": p["id"], **changed}, now)
        if rec:
            touch(cur, ws["id"], rec, now)
        return p["id"]

    pid = _write(conn, fn)
    return person_api(fetch_one(conn.cursor(), f"SELECT {PERSON_COLS} FROM crm_people WHERE id = ?", (pid,)))


def delete_person(conn, ws, user, person_id: str) -> Dict[str, Any]:
    def fn(cur):
        p = _load_person(cur, ws["id"], person_id, lock=True)
        now = utcnow()
        cur.execute("DELETE FROM crm_people WHERE id = ? AND workspace_id = ?", (p["id"], ws["id"]))
        rec = _person_record(cur, ws["id"], p)
        add_event(cur, ws["id"], rec, user["id"], "person_removed", {"person_id": p["id"], "name": p["name"]}, None, now)
        if rec:
            touch(cur, ws["id"], rec, now)

    _write(conn, fn)
    return {"deleted": True}


def list_people(conn, ws, q: Optional[str], limit: Optional[int], cursor: Optional[str]) -> Dict[str, Any]:
    cur = conn.cursor()
    n = page_limit(limit)
    where = ["p.workspace_id = ?", "c.workspace_id = ?"]
    params: List[Any] = [ws["id"], ws["id"]]
    if q and q.strip():
        if len(q) > 200:
            raise invalid("The search text must be at most 200 characters.")
        pat = like_param(q.strip())
        where.append("(LOWER(p.name) LIKE ? ESCAPE '!' OR LOWER(COALESCE(p.email, '')) LIKE ? ESCAPE '!'"
                     " OR LOWER(COALESCE(p.phone, '')) LIKE ? ESCAPE '!' OR LOWER(COALESCE(p.role, '')) LIKE ? ESCAPE '!'"
                     " OR LOWER(c.name) LIKE ? ESCAPE '!')")
        params.extend([pat] * 5)
    base_where = " AND ".join(where)
    ks = ""
    ks_params: List[Any] = []
    after = decode_cursor(cursor, 2)
    if after:
        ks = " AND (LOWER(p.name) > ? OR (LOWER(p.name) = ? AND p.id > ?))"
        ks_params = [after[0], after[0], after[1]]
    rows = fetch_all(
        cur,
        f"SELECT p.id, p.company_id, p.record_id, p.name, p.role, p.phone, p.email, p.is_primary, p.created_at, p.updated_at, "
        f"LOWER(p.name) AS k1, c.name AS company_name FROM crm_people p JOIN crm_companies c ON c.id = p.company_id "
        f"WHERE {base_where}{ks} ORDER BY LOWER(p.name), p.id LIMIT ?",
        (*params, *ks_params, n + 1),
    )
    total = int(scalar(cur, f"SELECT COUNT(*) FROM crm_people p JOIN crm_companies c ON c.id = p.company_id WHERE {base_where}",
                       params) or 0)
    more = len(rows) > n
    rows = rows[:n]
    items = []
    for p in rows:
        item = person_api(p)
        item["company"] = {"id": p["company_id"], "name": p["company_name"]}
        if not item["record_id"]:
            item["record_id"] = _person_record(cur, ws["id"], p)
        items.append(item)
    return {"items": items, "next_cursor": encode_cursor([rows[-1]["k1"], rows[-1]["id"]]) if more and rows else None,
            "total": total}


# --------------------------------------------------------------------------- #
# Tags
# --------------------------------------------------------------------------- #

def list_tags(conn, ws) -> Dict[str, Any]:
    rows = fetch_all(conn.cursor(), "SELECT id, name, color FROM crm_tags WHERE workspace_id = ? ORDER BY name, id", (ws["id"],))
    return {"items": [{"id": t["id"], "name": t["name"], "color": t["color"]} for t in rows]}


def create_tag(conn, ws, user, body: Dict[str, Any]) -> Dict[str, Any]:
    name = clean_text(body.get("name"), "Tag name", 60, required=True)
    color = clean_text(body.get("color"), "Color", 20)
    if color is not None and not all(ch.isalnum() or ch in "#-" for ch in color):
        raise invalid("Color must be a name or a hex code such as #3366FF.")
    cur = conn.cursor()
    existing = fetch_one(cur, "SELECT id, name, color FROM crm_tags WHERE workspace_id = ? AND LOWER(name) = LOWER(?)", (ws["id"], name))
    if existing:
        return {"id": existing["id"], "name": existing["name"], "color": existing["color"], "created": False}
    tid = new_id()
    try:
        _write(conn, lambda c: c.execute("INSERT INTO crm_tags (id, workspace_id, name, color, created_at) VALUES (?, ?, ?, ?, ?)",
                                         (tid, ws["id"], name, color, db_ts(utcnow()))))
    except Exception as exc:
        if not is_unique_violation(exc):
            raise
        existing = fetch_one(conn.cursor(), "SELECT id, name, color FROM crm_tags WHERE workspace_id = ? AND LOWER(name) = LOWER(?)",
                             (ws["id"], name))
        if existing is None:
            raise
        return {"id": existing["id"], "name": existing["name"], "color": existing["color"], "created": False}
    return {"id": tid, "name": name, "color": color, "created": True}


def set_record_tags(conn, ws, user, record_id: str, body: Dict[str, Any]) -> Dict[str, Any]:
    tag_ids = body.get("tag_ids")
    if not isinstance(tag_ids, list) or len(tag_ids) > 50 or not all(isinstance(t, str) and t for t in tag_ids):
        raise invalid("tag_ids must be a list of at most 50 tag IDs.")
    wanted = list(dict.fromkeys(tag_ids))

    def fn(cur):
        load_record(cur, ws["id"], record_id, lock=True)
        tags = {}
        if wanted:
            tags = {t["id"]: t["name"] for t in fetch_all(
                cur, f"SELECT id, name FROM crm_tags WHERE workspace_id = ? AND id IN ({placeholders(len(wanted))})", (ws["id"], *wanted))}
            if len(tags) != len(wanted):
                raise not_found()
        current = {t["tag_id"]: t["name"] for t in fetch_all(
            cur, "SELECT rt.tag_id, t.name FROM crm_record_tags rt JOIN crm_tags t ON t.id = rt.tag_id "
                 "WHERE rt.workspace_id = ? AND rt.record_id = ?", (ws["id"], record_id))}
        if set(current) == set(tags):
            return
        now = utcnow()
        for tid in set(current) - set(tags):
            cur.execute("DELETE FROM crm_record_tags WHERE record_id = ? AND tag_id = ? AND workspace_id = ?", (record_id, tid, ws["id"]))
        for tid in [t for t in wanted if t not in current]:
            cur.execute("INSERT INTO crm_record_tags (workspace_id, record_id, tag_id, created_at) VALUES (?, ?, ?, ?)",
                        (ws["id"], record_id, tid, db_ts(now)))
        add_event(cur, ws["id"], record_id, user["id"], "tags_changed", {"tags": sorted(current.values())},
                  {"tags": sorted(tags.values())}, now)
        touch(cur, ws["id"], record_id, now)

    _write(conn, fn)
    rows = fetch_all(conn.cursor(), "SELECT t.id, t.name, t.color FROM crm_record_tags rt JOIN crm_tags t ON t.id = rt.tag_id "
                                    "WHERE rt.workspace_id = ? AND rt.record_id = ? ORDER BY t.name, t.id", (ws["id"], record_id))
    return {"record_id": record_id, "tags": [{"id": t["id"], "name": t["name"], "color": t["color"]} for t in rows]}


# --------------------------------------------------------------------------- #
# Activities
# --------------------------------------------------------------------------- #

def refresh_next_activity(cur, ws_id: str, record_id: str) -> None:
    nxt = scalar(cur, "SELECT MIN(due_at) FROM crm_activities WHERE workspace_id = ? AND record_id = ? AND status = 'open'",
                 (ws_id, record_id))
    cur.execute("UPDATE crm_records SET next_activity_at = ? WHERE id = ? AND workspace_id = ?",
                (cursor_ts(nxt), record_id, ws_id))


def _load_activity(cur, ws_id: str, activity_id: str, lock: bool = True) -> Dict[str, Any]:
    a = fetch_one(cur, f"SELECT {ACTIVITY_COLS} FROM crm_activities WHERE id = ? AND workspace_id = ?" + (for_update() if lock else ""),
                  (_opt_id(activity_id), ws_id))
    if a is None:
        raise not_found()
    return a


def _get_activity(conn, ws, aid: str) -> Dict[str, Any]:
    return activity_api(_load_activity(conn.cursor(), ws["id"], aid, lock=False))


def add_activity(conn, ws, user, record_id: str, body: Dict[str, Any]) -> Dict[str, Any]:
    type_ = body.get("type")
    if type_ not in ACTIVITY_TYPES:
        raise invalid("type must be call, email, meeting, message or task.")
    subject = clean_text(body.get("subject"), "Subject", 300, required=True)
    due = parse_aware(body.get("due_at"), "due_at")
    notes = clean_text(body.get("notes"), "Notes", 5000)

    def fn(cur):
        load_record(cur, ws["id"], record_id, lock=True)
        now = utcnow()
        aid = new_id()
        cur.execute(
            "INSERT INTO crm_activities (id, workspace_id, record_id, type, subject, notes, due_at, assignee_user_id, status, "
            "created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'open', ?, ?, ?)",
            (aid, ws["id"], record_id, type_, subject, notes, db_ts(due), user["id"], user["id"], db_ts(now), db_ts(now)),
        )
        refresh_next_activity(cur, ws["id"], record_id)
        add_event(cur, ws["id"], record_id, user["id"], "activity_scheduled", None,
                  {"activity_id": aid, "type": type_, "subject": subject, "due_at": db_ts(due)}, now)
        touch(cur, ws["id"], record_id, now)
        return aid

    return _get_activity(conn, ws, _write(conn, fn))


def update_activity(conn, ws, user, activity_id: str, body: Dict[str, Any]) -> Dict[str, Any]:
    unknown = set(body) - {"subject", "due_at", "notes"}
    if unknown:
        raise invalid(f"These fields cannot be changed here: {', '.join(sorted(unknown))}.")
    sets: Dict[str, Any] = {}
    if "subject" in body:
        sets["subject"] = clean_text(body.get("subject"), "Subject", 300, required=True)
    if "due_at" in body:
        sets["due_at"] = db_ts(parse_aware(body.get("due_at"), "due_at"))
    if "notes" in body:
        sets["notes"] = clean_text(body.get("notes"), "Notes", 5000)

    def fn(cur):
        a = _load_activity(cur, ws["id"], activity_id)
        current = {"subject": a["subject"], "due_at": cursor_ts(a["due_at"]), "notes": a["notes"]}
        changed = {k: v for k, v in sets.items() if current[k] != v}
        if not changed:
            return a["id"]
        now = utcnow()
        cols = ", ".join(f"{k} = ?" for k in changed)
        cur.execute(f"UPDATE crm_activities SET {cols}, updated_at = ? WHERE id = ? AND workspace_id = ?",
                    (*changed.values(), db_ts(now), a["id"], ws["id"]))
        refresh_next_activity(cur, ws["id"], a["record_id"])
        add_event(cur, ws["id"], a["record_id"], user["id"], "activity_rescheduled",
                  {k: current[k] for k in changed}, {"activity_id": a["id"], **changed}, now)
        touch(cur, ws["id"], a["record_id"], now)
        return a["id"]

    return _get_activity(conn, ws, _write(conn, fn))


def complete_activity(conn, ws, user, activity_id: str, body: Dict[str, Any]) -> Dict[str, Any]:
    outcome = clean_text(body.get("outcome"), "Outcome", 2000)

    def fn(cur):
        a = _load_activity(cur, ws["id"], activity_id)
        if a["status"] == "done":
            return a["id"]
        now = utcnow()
        cur.execute("UPDATE crm_activities SET status = 'done', completed_at = ?, outcome = ?, updated_at = ? "
                    "WHERE id = ? AND workspace_id = ?", (db_ts(now), outcome, db_ts(now), a["id"], ws["id"]))
        refresh_next_activity(cur, ws["id"], a["record_id"])
        cur.execute("UPDATE crm_records SET last_activity_at = ? WHERE id = ? AND workspace_id = ?",
                    (db_ts(now), a["record_id"], ws["id"]))
        add_event(cur, ws["id"], a["record_id"], user["id"], "activity_done", None,
                  {"activity_id": a["id"], "type": a["type"], "subject": a["subject"], "outcome": outcome}, now)
        touch(cur, ws["id"], a["record_id"], now)
        return a["id"]

    return _get_activity(conn, ws, _write(conn, fn))


def reopen_activity(conn, ws, user, activity_id: str) -> Dict[str, Any]:
    def fn(cur):
        a = _load_activity(cur, ws["id"], activity_id)
        if a["status"] == "open":
            return a["id"]
        now = utcnow()
        cur.execute("UPDATE crm_activities SET status = 'open', completed_at = NULL, outcome = NULL, updated_at = ? "
                    "WHERE id = ? AND workspace_id = ?", (db_ts(now), a["id"], ws["id"]))
        refresh_next_activity(cur, ws["id"], a["record_id"])
        add_event(cur, ws["id"], a["record_id"], user["id"], "activity_reopened", {"status": "done"},
                  {"activity_id": a["id"], "status": "open"}, now)
        touch(cur, ws["id"], a["record_id"], now)
        return a["id"]

    return _get_activity(conn, ws, _write(conn, fn))


# --------------------------------------------------------------------------- #
# Agenda
# --------------------------------------------------------------------------- #

BUCKETS = ("overdue", "today", "upcoming", "done")


def _bucket_where(bucket: str, now: datetime, offset_minutes: Any) -> tuple:
    _, end = local_day_bounds(now, tz_offset(offset_minutes))
    if bucket == "overdue":
        return "a.status = 'open' AND a.due_at < ?", [db_ts(now)]
    if bucket == "today":
        return "a.status = 'open' AND a.due_at >= ? AND a.due_at < ?", [db_ts(now), db_ts(end)]
    if bucket == "upcoming":
        return "a.status = 'open' AND a.due_at >= ?", [db_ts(end)]
    return "a.status = 'done'", []


_AGENDA_FROM = ("FROM crm_activities a JOIN crm_records r ON r.id = a.record_id AND r.workspace_id = a.workspace_id "
                "WHERE a.workspace_id = ? AND r.archived_at IS NULL")


def agenda(conn, ws, bucket: Optional[str], offset_minutes: Any, limit: Optional[int], cursor: Optional[str]) -> Dict[str, Any]:
    bucket = bucket or "today"
    if bucket not in BUCKETS:
        raise invalid("bucket must be overdue, today, upcoming or done.")
    cur = conn.cursor()
    now = utcnow()
    n = page_limit(limit)
    bw, bp = _bucket_where(bucket, now, offset_minutes)
    if bucket == "done":
        order, col, cmp = "a.completed_at DESC, a.id DESC", "a.completed_at", "<"
    else:
        order, col, cmp = "a.due_at ASC, a.id ASC", "a.due_at", ">"
    ks, kp = "", []
    after = decode_cursor(cursor, 2)
    if after:
        ks = f" AND ({col} {cmp} ? OR ({col} = ? AND a.id {cmp} ?))"
        kp = [after[0], after[0], after[1]]
    cols = ", ".join(f"a.{c.strip()}" for c in ACTIVITY_COLS.split(","))
    rows = fetch_all(cur, f"SELECT {cols}, r.title AS record_title, {col} AS k1 {_AGENDA_FROM} AND {bw}{ks} ORDER BY {order} LIMIT ?",
                     (ws["id"], *bp, *kp, n + 1))
    total = int(scalar(cur, f"SELECT COUNT(*) {_AGENDA_FROM} AND {bw}", (ws["id"], *bp)) or 0)
    more = len(rows) > n
    rows = rows[:n]
    items = []
    for a in rows:
        item = activity_api(a, now)
        item["record_title"] = a["record_title"]
        items.append(item)
    nc = encode_cursor([cursor_ts(rows[-1]["k1"]), rows[-1]["id"]]) if more and rows else None
    return {"bucket": bucket, "items": items, "next_cursor": nc, "total": total}


def agenda_counts(conn, ws, offset_minutes: Any) -> Dict[str, int]:
    cur = conn.cursor()
    now = utcnow()
    out = {}
    for bucket in ("overdue", "today", "upcoming"):
        bw, bp = _bucket_where(bucket, now, offset_minutes)
        out[bucket] = int(scalar(cur, f"SELECT COUNT(*) {_AGENDA_FROM} AND {bw}", (ws["id"], *bp)) or 0)
    out["no_next_activity"] = int(scalar(
        cur, "SELECT COUNT(*) FROM crm_records WHERE workspace_id = ? AND outcome = 'open' AND archived_at IS NULL "
             "AND next_activity_at IS NULL", (ws["id"],)) or 0)
    return out
