"""Honest CRM reports and formula-safe CSV/XLSX export."""

from __future__ import annotations

import base64
import csv
import io
from datetime import date, datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

from .common import (
    api_date, api_ts, db_ts, fetch_all, from_db_ts, invalid, local_day_bounds, num, placeholders, scalar,
    tz_offset, utcnow,
)
from .records import query_records, stage_map
from .workspace import stage_api, stages

DEFINITIONS = {
    "period": "from/to are calendar dates in the viewer's timezone (tz_offset_minutes) and are inclusive; "
              "without them the period is all time. Each metric states which date it uses.",
    "imported_companies": "Businesses added to the CRM from search results whose first source link was imported in the "
                          "period. Later links of the same business (found again in another search) are not new imports.",
    "open_leads": "Records of type lead that are open and not archived right now (not limited to the period).",
    "opportunities": "Records converted to opportunity, or created as an opportunity, in the period (conversion date).",
    "by_stage": "Open, not archived records per stage right now; the Won column counts won records.",
    "by_source": "Records imported in the period, per source search (import date). A record found in several searches "
                 "counts once per search.",
    "won": "Records marked Won in the period (close date). A scraped result is not a sale; only a user's Won counts.",
    "lost": "Records marked Lost in the period (close date).",
    "won_rate": "Won divided by Won + Lost among records closed in the period (leads and opportunities). "
                "null when nothing was closed.",
    "overdue_activities": "Open activities whose due time is before now, on records that are not archived.",
    "activities_completed": "Activities marked done in the period (completion date).",
    "lost_reasons": "Reasons of records marked Lost in the period.",
    "value_by_currency": "Sum of the deal values that users entered, per ISO currency; currencies are never added "
                         "together or converted. open_total: open, not archived records now; won_total: records won in "
                         "the period. Records without a value are excluded (see records_without_value).",
    "records_without_value": "Open, not archived opportunities that have no deal value.",
}


def _period(from_: Optional[str], to: Optional[str], offset_minutes: Any) -> Tuple[Optional[datetime], Optional[datetime]]:
    off = tz_offset(offset_minutes)

    def parse(value: str, end: bool) -> datetime:
        try:
            d = date.fromisoformat(value.strip()[:10])
        except ValueError:
            raise invalid("from and to must be dates like 2026-11-01.")
        start, stop = local_day_bounds(utcnow(), off, d)
        return stop if end else start

    start = parse(from_, False) if from_ else None
    end = parse(to, True) if to else None
    if start and end and start >= end:
        raise invalid("from must be on or before to.")
    return start, end


def _range(col: str, start: Optional[datetime], end: Optional[datetime]) -> Tuple[str, List[Any]]:
    sql, params = "", []
    if start:
        sql += f" AND {col} >= ?"
        params.append(db_ts(start))
    if end:
        sql += f" AND {col} < ?"
        params.append(db_ts(end))
    return sql, params


def reports(conn, ws: Dict[str, Any], from_: Optional[str], to: Optional[str], offset_minutes: Any) -> Dict[str, Any]:
    cur = conn.cursor()
    ws_id = ws["id"]
    now = utcnow()
    start, end = _period(from_, to, offset_minutes)

    rs, rp = _range("m.first_at", start, end)
    imported = int(scalar(
        cur, f"SELECT COUNT(*) FROM (SELECT company_id, MIN(imported_at) AS first_at FROM crm_source_links WHERE workspace_id = ? "
             f"GROUP BY company_id) m WHERE 1 = 1{rs}", (ws_id, *rp)) or 0)
    open_leads = int(scalar(cur, "SELECT COUNT(*) FROM crm_records WHERE workspace_id = ? AND type = 'lead' AND outcome = 'open' "
                                 "AND archived_at IS NULL", (ws_id,)) or 0)
    cs, cp = _range("converted_at", start, end)
    opportunities = int(scalar(cur, f"SELECT COUNT(*) FROM crm_records WHERE workspace_id = ? AND type = 'opportunity' "
                                    f"AND converted_at IS NOT NULL{cs}", (ws_id, *cp)) or 0)

    by_stage = []
    for s in stages(cur, ws_id, ws["pipeline_id"]):
        outcome = "won" if s["outcome_kind"] == "won" else "open"
        n = int(scalar(cur, "SELECT COUNT(*) FROM crm_records WHERE workspace_id = ? AND stage_id = ? AND outcome = ? "
                            "AND archived_at IS NULL", (ws_id, s["id"], outcome)) or 0)
        by_stage.append({"stage": stage_api(s), "count": n})

    ss, sp = _range("imported_at", start, end)
    by_source = [
        {"job_id": row["source_job_id"], "category": row["category"], "count": int(row["n"])}
        for row in fetch_all(
            cur, f"SELECT source_job_id, MAX(category) AS category, COUNT(DISTINCT record_id) AS n FROM crm_source_links "
                 f"WHERE workspace_id = ? AND record_id IS NOT NULL{ss} GROUP BY source_job_id ORDER BY n DESC, source_job_id",
            (ws_id, *sp))
    ]

    ks, kp = _range("closed_at", start, end)
    won = int(scalar(cur, f"SELECT COUNT(*) FROM crm_records WHERE workspace_id = ? AND outcome = 'won' AND closed_at IS NOT NULL{ks}",
                     (ws_id, *kp)) or 0)
    lost = int(scalar(cur, f"SELECT COUNT(*) FROM crm_records WHERE workspace_id = ? AND outcome = 'lost' AND closed_at IS NOT NULL{ks}",
                      (ws_id, *kp)) or 0)
    denom = won + lost
    won_rate = {"value": (round(won / denom, 4) if denom else None), "numerator": won, "denominator": denom}

    overdue = int(scalar(
        cur, "SELECT COUNT(*) FROM crm_activities a JOIN crm_records r ON r.id = a.record_id AND r.workspace_id = a.workspace_id "
             "WHERE a.workspace_id = ? AND a.status = 'open' AND a.due_at < ? AND r.archived_at IS NULL", (ws_id, db_ts(now))) or 0)
    ds, dp = _range("completed_at", start, end)
    completed = int(scalar(cur, f"SELECT COUNT(*) FROM crm_activities WHERE workspace_id = ? AND status = 'done'{ds}",
                           (ws_id, *dp)) or 0)

    lost_reasons = [
        {"name": row["name"], "count": int(row["n"])}
        for row in fetch_all(
            cur, f"SELECT lr.name, COUNT(*) AS n FROM crm_records r JOIN crm_lost_reasons lr ON lr.id = r.lost_reason_id "
                 f"WHERE r.workspace_id = ? AND lr.workspace_id = ? AND r.outcome = 'lost' AND r.closed_at IS NOT NULL"
                 f"{_range('r.closed_at', start, end)[0]} GROUP BY lr.name ORDER BY n DESC, lr.name",
            (ws_id, ws_id, *_range("r.closed_at", start, end)[1]))
    ]

    totals: Dict[str, Dict[str, Optional[float]]] = {}
    for row in fetch_all(cur, "SELECT currency, SUM(value) AS t FROM crm_records WHERE workspace_id = ? AND outcome = 'open' "
                              "AND archived_at IS NULL AND value IS NOT NULL AND currency IS NOT NULL GROUP BY currency", (ws_id,)):
        totals.setdefault(row["currency"], {"open_total": None, "won_total": None})["open_total"] = num(row["t"])
    for row in fetch_all(cur, f"SELECT currency, SUM(value) AS t FROM crm_records WHERE workspace_id = ? AND outcome = 'won' "
                              f"AND value IS NOT NULL AND currency IS NOT NULL AND closed_at IS NOT NULL{ks} GROUP BY currency",
                         (ws_id, *kp)):
        totals.setdefault(row["currency"], {"open_total": None, "won_total": None})["won_total"] = num(row["t"])
    value_by_currency = [{"currency": c, **v} for c, v in sorted(totals.items())]
    without_value = int(scalar(cur, "SELECT COUNT(*) FROM crm_records WHERE workspace_id = ? AND type = 'opportunity' "
                                    "AND outcome = 'open' AND archived_at IS NULL AND value IS NULL", (ws_id,)) or 0)

    return {
        "definitions": DEFINITIONS,
        "period": {"from": api_ts(start), "to": api_ts(end)},
        "imported_companies": imported,
        "open_leads": open_leads,
        "opportunities": opportunities,
        "by_stage": by_stage,
        "by_source": by_source,
        "won": won,
        "lost": lost,
        "won_rate": won_rate,
        "overdue_activities": overdue,
        "activities_completed": completed,
        "lost_reasons": lost_reasons,
        "value_by_currency": value_by_currency,
        "records_without_value": without_value,
    }


# --------------------------------------------------------------------------- #
# Export
# --------------------------------------------------------------------------- #

EXPORT_LIMIT = 10000
HEADERS = ["Title", "Company", "Type", "Stage", "Outcome", "Archived", "Phone", "Email", "Website", "Address", "City",
           "Region", "Country", "Value", "Currency", "Probability", "Expected close", "Tags", "Next activity",
           "Next activity due (UTC)", "Source searches", "Created (UTC)", "Updated (UTC)"]
_FORMULA_PREFIXES = ("=", "+", "-", "@", "\t", "\r")


def csv_safe(value: Any) -> str:
    text = "" if value is None else str(value)
    return "'" + text if text.startswith(_FORMULA_PREFIXES) else text


def _export_rows(cur, ws: Dict[str, Any], f: Dict[str, Any]) -> List[List[Any]]:
    now = utcnow()
    f = dict(f)
    f.pop("cursor", None)
    smap = stage_map(cur, ws)
    out: List[List[Any]] = []
    cursor = None
    while len(out) < EXPORT_LIMIT:
        rows, cursor, _ = query_records(cur, ws, f, limit=500, cursor=cursor, now=now, with_total=False)
        if not rows:
            break
        ids = [r["id"] for r in rows]
        cids = list({r["company_id"] for r in rows})
        ph, cph = placeholders(len(ids)), placeholders(len(cids))
        comps = {c["id"]: c for c in fetch_all(
            cur, f"SELECT id, name, phone, email, website, address, city, region, country FROM crm_companies "
                 f"WHERE workspace_id = ? AND id IN ({cph})", (ws["id"], *cids))}
        tags: Dict[str, List[str]] = {}
        for t in fetch_all(cur, f"SELECT rt.record_id, t.name FROM crm_record_tags rt JOIN crm_tags t ON t.id = rt.tag_id "
                                f"WHERE rt.workspace_id = ? AND rt.record_id IN ({ph}) ORDER BY t.name", (ws["id"], *ids)):
            tags.setdefault(t["record_id"], []).append(t["name"])
        nxt: Dict[str, Dict[str, Any]] = {}
        for a in fetch_all(cur, f"SELECT record_id, subject, due_at FROM crm_activities WHERE workspace_id = ? AND status = 'open' "
                                f"AND record_id IN ({ph}) ORDER BY due_at, id", (ws["id"], *ids)):
            nxt.setdefault(a["record_id"], a)
        srcs: Dict[str, List[str]] = {}
        for s in fetch_all(cur, f"SELECT record_id, category, city, region, imported_at FROM crm_source_links "
                                f"WHERE workspace_id = ? AND record_id IN ({ph}) ORDER BY imported_at, id", (ws["id"], *ids)):
            place = ", ".join(x for x in (s["city"], s["region"]) if x)
            srcs.setdefault(s["record_id"], []).append(" - ".join(x for x in (s["category"], place) if x) or "Search")
        for r in rows:
            c = comps.get(r["company_id"], {})
            st = smap.get(r["stage_id"])
            a = nxt.get(r["id"])
            due = from_db_ts(a["due_at"]) if a else None
            out.append([
                r["title"], c.get("name"), r["type"], st["name"] if st else "", r["outcome"],
                "yes" if r["archived_at"] is not None else "no", c.get("phone"), c.get("email"), c.get("website"),
                c.get("address"), c.get("city"), c.get("region"), c.get("country"),
                "" if r["value"] is None else f"{num(r['value']):.2f}", r["currency"],
                "" if r["probability"] is None else r["probability"], api_date(r["expected_close_date"]) or "",
                "; ".join(tags.get(r["id"], [])), a["subject"] if a else "",
                due.strftime("%Y-%m-%d %H:%M") if due else "", "; ".join(srcs.get(r["id"], [])),
                (from_db_ts(r["created_at"]) or now).strftime("%Y-%m-%d %H:%M"),
                (from_db_ts(r["updated_at"]) or now).strftime("%Y-%m-%d %H:%M"),
            ])
        if not cursor:
            break
    return out[:EXPORT_LIMIT]


def export(conn, ws: Dict[str, Any], fmt: Optional[str], f: Dict[str, Any]) -> Dict[str, Any]:
    fmt = (fmt or "csv").lower()
    if fmt not in ("csv", "xlsx"):
        raise invalid("format must be csv or xlsx.")
    rows = _export_rows(conn.cursor(), ws, f)
    stamp = utcnow().strftime("%Y%m%d")
    if fmt == "csv":
        buf = io.StringIO()
        w = csv.writer(buf, lineterminator="\r\n")
        w.writerow(HEADERS)
        for row in rows:
            w.writerow([csv_safe(v) for v in row])
        data = ("﻿" + buf.getvalue()).encode("utf-8")
        return {"filename": f"CRM_records_{stamp}.csv", "content": base64.b64encode(data).decode("ascii"),
                "content_type": "text/csv; charset=utf-8", "encoding": "base64", "count": len(rows)}

    from openpyxl import Workbook
    from openpyxl.styles import Font

    from main import _xlsx_set_text  # formula-safe text cells shared with the job download

    wb = Workbook()
    ws_x = wb.active
    ws_x.title = "CRM records"
    for col, h in enumerate(HEADERS, 1):
        cell = ws_x.cell(row=1, column=col)
        _xlsx_set_text(cell, h)
        cell.font = Font(bold=True)
    for r_idx, row in enumerate(rows, 2):
        for c_idx, v in enumerate(row, 1):
            _xlsx_set_text(ws_x.cell(row=r_idx, column=c_idx), "" if v is None else v)
    ws_x.freeze_panes = "A2"
    out = io.BytesIO()
    wb.save(out)
    return {"filename": f"CRM_records_{stamp}.xlsx", "content": base64.b64encode(out.getvalue()).decode("ascii"),
            "content_type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "encoding": "base64",
            "count": len(rows)}
