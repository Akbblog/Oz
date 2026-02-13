"""
Read-only query functions for admin audit/activity endpoints.
"""

import json
import logging
from typing import Optional, List, Dict, Any

from db.base import execute_query

logger = logging.getLogger(__name__)


def _row_to_event(row) -> Dict[str, Any]:
    """Convert a raw audit_events row tuple to dict."""
    return {
        "id": row[0],
        "request_id": row[1],
        "actor_user_id": row[2],
        "actor_username": row[3],
        "action": row[4],
        "target_type": row[5],
        "target_id": row[6],
        "before_snapshot": json.loads(row[7]) if row[7] else None,
        "after_snapshot": json.loads(row[8]) if row[8] else None,
        "ip_address": row[9],
        "user_agent": row[10],
        "status": row[11],
        "failure_reason": row[12],
        "metadata": json.loads(row[13]) if row[13] else None,
        "created_at": row[14],
    }


def _build_where(
    *,
    actor_user_id: Optional[int] = None,
    action: Optional[str] = None,
    target_type: Optional[str] = None,
    status: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
):
    """Build dynamic WHERE clause and params for activity queries."""
    clauses = []
    params: list = []

    if actor_user_id is not None:
        clauses.append("actor_user_id = ?")
        params.append(actor_user_id)
    if action:
        clauses.append("action = ?")
        params.append(action)
    if target_type:
        clauses.append("target_type = ?")
        params.append(target_type)
    if status:
        clauses.append("status = ?")
        params.append(status)
    if date_from:
        clauses.append("created_at >= ?")
        params.append(date_from)
    if date_to:
        clauses.append("created_at <= ?")
        params.append(date_to + "T23:59:59" if "T" not in date_to else date_to)

    where = " AND ".join(clauses) if clauses else "1=1"
    return where, params


def get_activity_feed(
    *,
    actor_user_id: Optional[int] = None,
    action: Optional[str] = None,
    target_type: Optional[str] = None,
    status: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
) -> List[Dict[str, Any]]:
    """Return paginated, filtered activity feed."""
    where, params = _build_where(
        actor_user_id=actor_user_id, action=action,
        target_type=target_type, status=status,
        date_from=date_from, date_to=date_to,
    )
    params.extend([limit, offset])
    rows = execute_query(
        f"""
        SELECT id, request_id, actor_user_id, actor_username, action,
               target_type, target_id, before_snapshot, after_snapshot,
               ip_address, user_agent, status, failure_reason, metadata,
               created_at
        FROM audit_events
        WHERE {where}
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
        """,
        tuple(params),
        fetch_all=True,
        commit=False,
    )
    return [_row_to_event(r) for r in (rows or [])]


def get_audit_event_count(
    *,
    actor_user_id: Optional[int] = None,
    action: Optional[str] = None,
    target_type: Optional[str] = None,
    status: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
) -> int:
    """Total count for pagination."""
    where, params = _build_where(
        actor_user_id=actor_user_id, action=action,
        target_type=target_type, status=status,
        date_from=date_from, date_to=date_to,
    )
    row = execute_query(
        f"SELECT COUNT(*) FROM audit_events WHERE {where}",
        tuple(params) if params else None,
        fetch_one=True,
        commit=False,
    )
    return int(row[0]) if row else 0


def get_user_timeline(
    user_id: int, limit: int = 100, offset: int = 0,
) -> List[Dict[str, Any]]:
    """All audit events for a specific user, chronologically."""
    rows = execute_query(
        """
        SELECT id, request_id, actor_user_id, actor_username, action,
               target_type, target_id, before_snapshot, after_snapshot,
               ip_address, user_agent, status, failure_reason, metadata,
               created_at
        FROM audit_events
        WHERE actor_user_id = ? OR (target_type = 'user' AND target_id = ?)
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
        """,
        (user_id, str(user_id), limit, offset),
        fetch_all=True,
        commit=False,
    )
    return [_row_to_event(r) for r in (rows or [])]


def get_user_kpis(user_id: int) -> Dict[str, Any]:
    """
    Per-user value KPIs:
    jobs_run, results_generated, credits_used, credits_purchased,
    cost_per_result, last_activity, last_login
    """
    # Jobs run
    row = execute_query(
        "SELECT COUNT(*) FROM jobs WHERE user_id = ?",
        (user_id,), fetch_one=True, commit=False,
    )
    jobs_run = int(row[0]) if row else 0

    # Results generated
    row = execute_query(
        """
        SELECT COUNT(*) FROM results r
        JOIN jobs j ON r.job_id = j.job_id
        WHERE j.user_id = ?
        """,
        (user_id,), fetch_one=True, commit=False,
    )
    results_generated = int(row[0]) if row else 0

    # Credits used (negative amounts in ledger = debits)
    row = execute_query(
        "SELECT COALESCE(SUM(-amount), 0) FROM credit_ledger WHERE user_id = ? AND amount < 0",
        (user_id,), fetch_one=True, commit=False,
    )
    credits_used = int(row[0]) if row else 0

    # Credits purchased (positive amounts from 'credit' type)
    row = execute_query(
        "SELECT COALESCE(SUM(amount), 0) FROM credit_ledger WHERE user_id = ? AND transaction_type = 'credit'",
        (user_id,), fetch_one=True, commit=False,
    )
    credits_purchased = int(row[0]) if row else 0

    # Cost per result
    cost_per_result = round(credits_used / results_generated, 2) if results_generated > 0 else 0

    # Last activity from audit_events
    row = execute_query(
        "SELECT MAX(created_at) FROM audit_events WHERE actor_user_id = ?",
        (user_id,), fetch_one=True, commit=False,
    )
    last_activity = row[0] if row and row[0] else None

    # Last login from users table
    row = execute_query(
        "SELECT last_login FROM users WHERE id = ?",
        (user_id,), fetch_one=True, commit=False,
    )
    last_login = row[0] if row and row[0] else None

    return {
        "user_id": user_id,
        "jobs_run": jobs_run,
        "results_generated": results_generated,
        "credits_used": credits_used,
        "credits_purchased": credits_purchased,
        "cost_per_result": cost_per_result,
        "last_activity": last_activity,
        "last_login": last_login,
    }


def get_distinct_actions() -> List[str]:
    """Return list of distinct action strings for filter dropdowns."""
    rows = execute_query(
        "SELECT DISTINCT action FROM audit_events ORDER BY action",
        fetch_all=True, commit=False,
    )
    return [r[0] for r in (rows or [])]


def export_activity_csv(
    *,
    actor_user_id: Optional[int] = None,
    action: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Return all matching audit events as flat dicts for CSV generation."""
    where, params = _build_where(
        actor_user_id=actor_user_id, action=action,
        date_from=date_from, date_to=date_to,
    )
    rows = execute_query(
        f"""
        SELECT id, request_id, actor_user_id, actor_username, action,
               target_type, target_id, ip_address, status, failure_reason,
               created_at
        FROM audit_events
        WHERE {where}
        ORDER BY created_at DESC
        LIMIT 10000
        """,
        tuple(params) if params else None,
        fetch_all=True,
        commit=False,
    )
    return [
        {
            "id": r[0],
            "request_id": r[1],
            "actor_user_id": r[2],
            "actor_username": r[3],
            "action": r[4],
            "target_type": r[5],
            "target_id": r[6],
            "ip_address": r[7],
            "status": r[8],
            "failure_reason": r[9],
            "created_at": r[10],
        }
        for r in (rows or [])
    ]
