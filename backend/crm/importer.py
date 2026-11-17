"""Import search results into the CRM, resolve possible matches, per-job CRM state.

Rules (docs/CRM_PHASE1_CONTRACT.md "Import"):
* Rows are read from ``results`` of the caller's own job; client business data
  is never accepted. Unknown IDs / IDs of other jobs -> ``rejected: not_found``.
* ``UNIQUE(workspace_id, source_result_id)`` makes an exact repeat idempotent
  (``already_added``) whatever idempotency key is used.
* Probable matches (place / website+name / phone+name) are never auto-merged:
  they are returned for review and resolved with ``/import/resolve``.
* Each call is one transaction. ``all`` processes at most 200 rows per call and
  remembers its position in ``crm_imports.cursor_result_id``.
"""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime
from typing import Any, Dict, List, Optional, Sequence, Tuple

from . import matching
from .common import (
    CRMError, begin_write, chunks, db_ts, fetch_all, fetch_one, for_update, from_json, invalid, is_unique_violation,
    new_id, not_found, placeholders, scalar, to_json, utcnow,
)
from .records import add_event, first_open_stage, insert_company, insert_record, stage_map, touch

BATCH = 200
KEY_RE = re.compile(r"^[A-Za-z0-9_.:\-]{8,80}$")
RESULT_COLS = "id, job_id, dedupe_key, business_name, phone, website, email, address, category, city, state, google_maps_url"
SNAPSHOT_FIELDS = ("business_name", "phone", "website", "email", "address", "city", "state", "category", "google_maps_url")


# --------------------------------------------------------------------------- #
# Validation helpers
# --------------------------------------------------------------------------- #

def _job_id(value: Any) -> str:
    if not isinstance(value, str) or not value.strip() or len(value) > 255:
        raise invalid("job_id is required.")
    return value.strip()


def _key(value: Any) -> str:
    if not isinstance(value, str) or not KEY_RE.match(value):
        raise invalid("idempotency_key must be 8-80 letters, digits or the characters _ . : -")
    return value


def _int_id(value: Any) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise invalid("result_ids must be positive whole numbers.")
    return int(value)


def _request_hash(payload: Dict[str, Any]) -> str:
    return hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def _load_job(cur, job_id: str, user_id: int) -> Dict[str, Any]:
    job = fetch_one(cur, "SELECT job_id, user_id, category, cities_data, created_at, status FROM jobs WHERE job_id = ? AND user_id = ?",
                    (job_id, user_id))
    if job is None:
        raise not_found()
    return job


def _job_context(job: Dict[str, Any]) -> Dict[str, Any]:
    from job_service import _parse_local, parse_cities
    from locations import derive_job_location

    try:
        country = derive_job_location(parse_cities(job.get("cities_data")))["country"]
    except Exception:
        country = None
    created_local = _parse_local(job.get("created_at"))
    job_created = created_local.astimezone() if created_local else None  # naive server-local -> aware
    return {"country": country, "job_created_at": job_created, "category": job.get("category")}


# --------------------------------------------------------------------------- #
# Candidates
# --------------------------------------------------------------------------- #

def _keys_of(row: Dict[str, Any]) -> Dict[str, Optional[str]]:
    return matching.keys_for(row.get("business_name"), row.get("phone"), row.get("website"), row.get("google_maps_url"))


def _companies_matching(cur, ws_id: str, keys_list: Sequence[Dict[str, Optional[str]]]) -> List[Dict[str, Any]]:
    found: Dict[str, Dict[str, Any]] = {}
    for col in ("match_place_key", "match_host", "match_phone"):
        values = sorted({k[col] for k in keys_list if k.get(col)})
        for part in chunks(values, 400):
            for c in fetch_all(
                cur,
                f"SELECT id, name, match_place_key, match_host, match_phone, match_name FROM crm_companies "
                f"WHERE workspace_id = ? AND {col} IN ({placeholders(len(part))})",
                (ws_id, *part),
            ):
                found[c["id"]] = c
    return list(found.values())


def _records_of(cur, ws: Dict[str, Any], company_ids: Sequence[str]) -> Dict[str, List[Dict[str, Any]]]:
    out: Dict[str, List[Dict[str, Any]]] = {}
    smap = None
    for part in chunks(list(company_ids), 400):
        rows = fetch_all(
            cur,
            f"SELECT id, company_id, title, stage_id, outcome, archived_at FROM crm_records "
            f"WHERE workspace_id = ? AND company_id IN ({placeholders(len(part))}) ORDER BY created_at, id",
            (ws["id"], *part),
        )
        if rows and smap is None:
            smap = stage_map(cur, ws)
        for r in rows:
            out.setdefault(r["company_id"], []).append(r)
    for recs in out.values():
        for r in recs:
            s = (smap or {}).get(r["stage_id"])
            r["stage"] = {"id": s["id"], "key": s["stage_key"], "name": s["name"]} if s else None
    return out


def _candidates(keys: Dict[str, Optional[str]], companies: Sequence[Dict[str, Any]],
                records_by_company: Dict[str, List[Dict[str, Any]]]) -> List[Dict[str, Any]]:
    out = []
    for c in companies:
        reasons = matching.match_reasons(keys, c)
        if not reasons:
            continue
        for r in records_by_company.get(c["id"], []):
            out.append({"record_id": r["id"], "name": r["title"], "stage": r.get("stage"), "outcome": r["outcome"],
                        "archived": r["archived_at"] is not None, "reasons": reasons})
    return out


def _find_candidates(cur, ws: Dict[str, Any], keys: Dict[str, Optional[str]]) -> List[Dict[str, Any]]:
    companies = _companies_matching(cur, ws["id"], [keys])
    if not companies:
        return []
    return _candidates(keys, companies, _records_of(cur, ws, [c["id"] for c in companies]))


# --------------------------------------------------------------------------- #
# Creating / linking
# --------------------------------------------------------------------------- #

def _snapshot(row: Dict[str, Any]) -> Dict[str, Any]:
    return {k: row.get(k) for k in SNAPSHOT_FIELDS}


def _insert_link(cur, ws_id: str, *, company_id: str, record_id: str, row: Dict[str, Any], ctx: Dict[str, Any],
                 user_id: int, now: datetime) -> None:
    cur.execute(
        "INSERT INTO crm_source_links (id, workspace_id, company_id, record_id, source_job_id, source_result_id, category, "
        "city, region, country, job_created_at, snapshot, imported_at, imported_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (new_id(), ws_id, company_id, record_id, row["job_id"], int(row["id"]), ctx.get("category"), row.get("city"),
         row.get("state"), ctx.get("country"), db_ts(ctx.get("job_created_at")), to_json(_snapshot(row)), db_ts(now), user_id),
    )


def _create_from_row(cur, ws: Dict[str, Any], user: Dict[str, Any], row: Dict[str, Any], ctx: Dict[str, Any],
                     stage_id: str, now: datetime, import_id: str) -> str:
    name = (str(row.get("business_name") or "").strip() or "Unnamed business")[:300]
    cid = insert_company(
        cur, ws["id"], name=name, phone=(row.get("phone") or None), email=(row.get("email") or None),
        website=(row.get("website") or None), address=(row.get("address") or None), city=(row.get("city") or None),
        region=(row.get("state") or None), country=ctx.get("country"), maps_url=(row.get("google_maps_url") or None),
        category=(row.get("category") or ctx.get("category")), snapshot=_snapshot(row), now=now,
    )
    rid = insert_record(cur, ws, company_id=cid, title=name, stage_id=stage_id, type_="lead", actor_id=user["id"], now=now)
    _insert_link(cur, ws["id"], company_id=cid, record_id=rid, row=row, ctx=ctx, user_id=user["id"], now=now)
    add_event(cur, ws["id"], rid, user["id"], "imported", None,
              {"job_id": row["job_id"], "result_id": int(row["id"]), "import_id": import_id}, now)
    return rid


def _existing_links(cur, ws_id: str, result_ids: Sequence[int]) -> Dict[int, str]:
    out: Dict[int, str] = {}
    for part in chunks(list(result_ids), 400):
        for l in fetch_all(
            cur, f"SELECT source_result_id, record_id FROM crm_source_links WHERE workspace_id = ? "
                 f"AND source_result_id IN ({placeholders(len(part))})", (ws_id, *part)):
            out[int(l["source_result_id"])] = l["record_id"]
    return out


def _load_rows(cur, job_id: str, ids: Sequence[int]) -> Dict[int, Dict[str, Any]]:
    out: Dict[int, Dict[str, Any]] = {}
    for part in chunks(list(ids), 400):
        for r in fetch_all(cur, f"SELECT {RESULT_COLS} FROM results WHERE job_id = ? AND id IN ({placeholders(len(part))})",
                           (job_id, *part)):
            out[int(r["id"])] = r
    return out


def _process(cur, ws, user, ctx, ordered_ids: Sequence[int], rows: Dict[int, Dict[str, Any]], now: datetime,
             import_id: str) -> Dict[str, List[Dict[str, Any]]]:
    out: Dict[str, List[Dict[str, Any]]] = {"created": [], "already_added": [], "possible_matches": [], "rejected": []}
    links = _existing_links(cur, ws["id"], [i for i in ordered_ids if i in rows])
    stage_id = first_open_stage(cur, ws)["id"]
    for rid in ordered_ids:
        row = rows.get(rid)
        if row is None:
            out["rejected"].append({"result_id": rid, "reason": "not_found"})
            continue
        if rid in links:
            out["already_added"].append({"result_id": rid, "record_id": links[rid]})
            continue
        cands = _find_candidates(cur, ws, _keys_of(row))
        if cands:
            out["possible_matches"].append({"result_id": rid, "business_name": row.get("business_name"), "candidates": cands})
            continue
        record_id = _create_from_row(cur, ws, user, row, ctx, stage_id, now, import_id)
        links[rid] = record_id
        out["created"].append({"result_id": rid, "record_id": record_id})
    return out


def _summary(out: Dict[str, List[Any]]) -> Dict[str, int]:
    return {"created": len(out["created"]), "already_added": len(out["already_added"]),
            "possible_match": len(out["possible_matches"]), "rejected": len(out["rejected"])}


# --------------------------------------------------------------------------- #
# Import
# --------------------------------------------------------------------------- #

def _lock_import(cur, ws_id: str, key: str) -> Optional[Dict[str, Any]]:
    return fetch_one(
        cur, "SELECT id, request_hash, job_id, mode, status, cursor_result_id, totals, response FROM crm_imports "
             "WHERE workspace_id = ? AND idempotency_key = ?" + for_update(), (ws_id, key))


def _insert_import(cur, ws_id: str, user_id: int, key: str, req_hash: str, job_id: str, mode: str, now: datetime) -> Dict[str, Any]:
    imp = {"id": new_id(), "request_hash": req_hash, "job_id": job_id, "mode": mode, "status": "running",
           "cursor_result_id": 0, "totals": None, "response": None}
    cur.execute(
        "INSERT INTO crm_imports (id, workspace_id, user_id, idempotency_key, request_hash, job_id, mode, status, "
        "cursor_result_id, totals, response, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, 'running', 0, NULL, NULL, ?, ?)",
        (imp["id"], ws_id, user_id, key, req_hash, job_id, mode, db_ts(now), db_ts(now)),
    )
    return imp


def _with_retries(conn, fn, attempts: int = 3):
    """Run ``fn`` in a write transaction; a unique-key race (concurrent identical import) retries."""
    for attempt in range(attempts):
        begin_write(conn)
        try:
            result = fn(conn.cursor())
            conn.commit()
            return result
        except CRMError:
            conn.rollback()
            raise
        except Exception as exc:
            conn.rollback()
            if is_unique_violation(exc) and attempt < attempts - 1:
                continue
            raise


def run_import(conn, ws: Dict[str, Any], user: Dict[str, Any], body: Dict[str, Any]) -> Dict[str, Any]:
    job_id = _job_id(body.get("job_id"))
    key = _key(body.get("idempotency_key"))
    ids_raw = body.get("result_ids")
    all_ = body.get("all")
    if all_ not in (None, True, False):
        raise invalid("all must be true or false.")
    if (ids_raw is not None) == bool(all_):
        raise invalid("Send either result_ids or all: true.")
    ids: List[int] = []
    if ids_raw is not None:
        if not isinstance(ids_raw, list) or not ids_raw:
            raise invalid("result_ids must be a list of 1 to 200 result IDs.")
        seen = set()
        for v in ids_raw:
            n = _int_id(v)
            if n not in seen:
                seen.add(n)
                ids.append(n)
        if len(ids) > BATCH:
            raise invalid("Send at most 200 result IDs per request.")
    mode = "all" if all_ else "ids"
    req_hash = _request_hash({"job_id": job_id, "mode": mode, "result_ids": ids})

    def work(cur):
        now = utcnow()
        imp = _lock_import(cur, ws["id"], key)
        if imp is not None:
            if imp["request_hash"] != req_hash:
                raise invalid("This idempotency key was already used for a different import. Use a new key.")
            if imp["status"] == "done":
                return from_json(imp["response"])
        job = _load_job(cur, job_id, user["id"])
        ctx = _job_context(job)
        if imp is None:
            imp = _insert_import(cur, ws["id"], user["id"], key, req_hash, job_id, mode, now)
        totals = from_json(imp["totals"], {}) or {}
        if mode == "ids":
            rows = _load_rows(cur, job_id, ids)
            out = _process(cur, ws, user, ctx, ids, rows, now, imp["id"])
            processed, remaining, done, cursor_id = len(ids), 0, True, 0
            summary = _summary(out)
        else:
            cursor_id = int(imp["cursor_result_id"] or 0)
            batch = fetch_all(cur, f"SELECT {RESULT_COLS} FROM results WHERE job_id = ? AND id > ? ORDER BY id LIMIT ?",
                              (job_id, cursor_id, BATCH))
            rows = {int(r["id"]): r for r in batch}
            order = [int(r["id"]) for r in batch]
            out = _process(cur, ws, user, ctx, order, rows, now, imp["id"])
            if order:
                cursor_id = order[-1]
            remaining = int(scalar(cur, "SELECT COUNT(*) FROM results WHERE job_id = ? AND id > ?", (job_id, cursor_id)) or 0)
            done = remaining == 0
            processed = int(totals.get("processed", 0)) + len(order)
            batch_summary = _summary(out)
            prev = totals.get("summary") or {}
            summary = {k: int(prev.get(k, 0)) + v for k, v in batch_summary.items()}
        response = {
            "import_id": imp["id"], "job_id": job_id, "done": done, "processed": processed, "remaining": remaining,
            **out, "summary": summary,
        }
        cur.execute(
            "UPDATE crm_imports SET status = ?, cursor_result_id = ?, totals = ?, response = ?, updated_at = ? WHERE id = ?",
            ("done" if done else "running", cursor_id, to_json({"processed": processed, "summary": summary}),
             to_json(response), db_ts(now), imp["id"]),
        )
        return response

    return _with_retries(conn, work)


# --------------------------------------------------------------------------- #
# Resolve
# --------------------------------------------------------------------------- #

ACTIONS = ("add_new", "link", "skip")


def resolve(conn, ws: Dict[str, Any], user: Dict[str, Any], body: Dict[str, Any]) -> Dict[str, Any]:
    job_id = _job_id(body.get("job_id"))
    key = "resolve:" + _key(body.get("idempotency_key"))
    decisions = body.get("decisions")
    if not isinstance(decisions, list) or not decisions or len(decisions) > BATCH:
        raise invalid("decisions must be a list of 1 to 200 items.")
    clean: List[Dict[str, Any]] = []
    seen = set()
    for d in decisions:
        if not isinstance(d, dict):
            raise invalid("Each decision needs result_id and action.")
        rid = _int_id(d.get("result_id"))
        action = d.get("action")
        if action not in ACTIONS:
            raise invalid("action must be add_new, link or skip.")
        record_id = d.get("record_id")
        if action == "link" and (not isinstance(record_id, str) or not record_id):
            raise invalid("Choose the record to link to.")
        if rid in seen:
            raise invalid("Each result can have only one decision.")
        seen.add(rid)
        clean.append({"result_id": rid, "action": action, "record_id": record_id if action == "link" else None})
    req_hash = _request_hash({"job_id": job_id, "decisions": clean})

    def work(cur):
        now = utcnow()
        imp = _lock_import(cur, ws["id"], key)
        if imp is not None:
            if imp["request_hash"] != req_hash:
                raise invalid("This idempotency key was already used for a different request. Use a new key.")
            if imp["status"] == "done":
                return from_json(imp["response"])
        job = _load_job(cur, job_id, user["id"])
        ctx = _job_context(job)
        if imp is None:
            imp = _insert_import(cur, ws["id"], user["id"], key, req_hash, job_id, "resolve", now)
        rows = _load_rows(cur, job_id, [d["result_id"] for d in clean])
        links = _existing_links(cur, ws["id"], list(rows))
        stage_id = first_open_stage(cur, ws)["id"]
        out: Dict[str, List[Dict[str, Any]]] = {"created": [], "linked": [], "skipped": [], "already_added": [], "rejected": []}
        for d in clean:
            rid = d["result_id"]
            row = rows.get(rid)
            if row is None:
                out["rejected"].append({"result_id": rid, "reason": "not_found"})
            elif rid in links:
                out["already_added"].append({"result_id": rid, "record_id": links[rid]})
            elif d["action"] == "skip":
                out["skipped"].append({"result_id": rid})
            elif d["action"] == "add_new":
                record_id = _create_from_row(cur, ws, user, row, ctx, stage_id, now, imp["id"])
                links[rid] = record_id
                out["created"].append({"result_id": rid, "record_id": record_id})
            else:
                target = fetch_one(cur, "SELECT id, company_id FROM crm_records WHERE id = ? AND workspace_id = ?",
                                   (d["record_id"][:36], ws["id"]))
                if target is None:
                    out["rejected"].append({"result_id": rid, "reason": "record_not_found"})
                    continue
                _insert_link(cur, ws["id"], company_id=target["company_id"], record_id=target["id"], row=row, ctx=ctx,
                             user_id=user["id"], now=now)
                add_event(cur, ws["id"], target["id"], user["id"], "source_linked", None,
                          {"job_id": row["job_id"], "result_id": rid, "business_name": row.get("business_name")}, now)
                touch(cur, ws["id"], target["id"], now)
                links[rid] = target["id"]
                out["linked"].append({"result_id": rid, "record_id": target["id"]})
        response = {"import_id": imp["id"], "job_id": job_id, **out,
                    "summary": {k: len(v) for k, v in out.items()}}
        cur.execute("UPDATE crm_imports SET status = 'done', response = ?, totals = ?, updated_at = ? WHERE id = ?",
                    (to_json(response), to_json({"summary": response["summary"]}), db_ts(now), imp["id"]))
        return response

    return _with_retries(conn, work)


# --------------------------------------------------------------------------- #
# Per-job CRM state
# --------------------------------------------------------------------------- #

def job_state(conn, ws: Dict[str, Any], user: Dict[str, Any], job_id: str) -> Dict[str, Any]:
    cur = conn.cursor()
    job_id = _job_id(job_id)
    _load_job(cur, job_id, user["id"])
    results = fetch_all(cur, "SELECT id, business_name, phone, website, google_maps_url FROM results WHERE job_id = ? ORDER BY id",
                        (job_id,))
    links = {
        int(l["source_result_id"]): l["record_id"] for l in fetch_all(
            cur, "SELECT source_result_id, record_id FROM crm_source_links WHERE workspace_id = ? AND source_job_id = ? "
                 "AND source_result_id IS NOT NULL", (ws["id"], job_id))
    }
    pending = [(int(r["id"]), _keys_of(r)) for r in results if int(r["id"]) not in links]
    companies = _companies_matching(cur, ws["id"], [k for _, k in pending]) if pending else []
    by_col: Dict[str, Dict[str, List[Dict[str, Any]]]] = {"match_place_key": {}, "match_host": {}, "match_phone": {}}
    for c in companies:
        for col in by_col:
            if c.get(col):
                by_col[col].setdefault(c[col], []).append(c)
    records_by_company = _records_of(cur, ws, [c["id"] for c in companies]) if companies else {}

    state: Dict[str, Dict[str, Any]] = {}
    counts = {"not_added": 0, "added": 0, "possible_match": 0}
    for r in results:
        rid = int(r["id"])
        if rid in links:
            state[str(rid)] = {"state": "added", "record_id": links[rid], "candidate_record_ids": [], "reasons": []}
            counts["added"] += 1
    for rid, keys in pending:
        near: Dict[str, Dict[str, Any]] = {}
        for col in by_col:
            for c in by_col[col].get(keys.get(col) or "", []):
                near[c["id"]] = c
        cands = _candidates(keys, list(near.values()), records_by_company)
        if cands:
            reasons: List[str] = []
            for c in cands:
                reasons.extend(x for x in c["reasons"] if x not in reasons)
            state[str(rid)] = {"state": "possible_match", "record_id": None,
                               "candidate_record_ids": [c["record_id"] for c in cands], "reasons": reasons}
            counts["possible_match"] += 1
        else:
            state[str(rid)] = {"state": "not_added", "record_id": None, "candidate_record_ids": [], "reasons": []}
            counts["not_added"] += 1
    return {"job_id": job_id, "results": state, "counts": counts}
