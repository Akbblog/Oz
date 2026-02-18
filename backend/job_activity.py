"""
Job activity tracking helpers.

Provides a dedicated, query-friendly event stream for job lifecycle monitoring
and action-to-result drilldown in the admin dashboard.
"""

import json
import logging
import uuid
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from db.base import execute_query

logger = logging.getLogger(__name__)


def _loads_json(payload: Optional[str]) -> Optional[Dict[str, Any]]:
    if not payload:
        return None
    try:
        data = json.loads(payload)
        return data if isinstance(data, dict) else None
    except Exception:
        return None


def record_job_activity_event(
    *,
    job_id: str,
    user_id: int,
    event_type: str,
    job_status: str,
    job_type: str,
    result_count: int = 0,
    error_message: Optional[str] = None,
    metadata: Optional[Dict[str, Any]] = None,
    created_at: Optional[str] = None,
) -> Optional[int]:
    """
    Insert one immutable job activity event.

    Returns inserted row id on success, or None if logging fails.
    """
    try:
        timestamp = created_at or datetime.now().isoformat()
        row_id = execute_query(
            """
            INSERT INTO job_activity_events
                (event_uuid, job_id, user_id, event_type, job_status, job_type,
                 result_count, error_message, metadata_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                str(uuid.uuid4()),
                job_id,
                user_id,
                event_type,
                job_status,
                job_type,
                int(result_count or 0),
                error_message,
                json.dumps(metadata) if metadata else None,
                timestamp,
            ),
            commit=True,
        )
        return int(row_id) if row_id is not None else None
    except Exception:
        logger.exception(
            "Failed to record job activity event (non-fatal): job_id=%s, event_type=%s",
            job_id,
            event_type,
        )
        return None


def _build_where(
    *,
    user_id: Optional[int] = None,
    event_type: Optional[str] = None,
    job_status: Optional[str] = None,
    job_type: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
) -> Tuple[str, List[Any]]:
    clauses: List[str] = []
    params: List[Any] = []

    if user_id is not None:
        clauses.append("e.user_id = ?")
        params.append(user_id)
    if event_type:
        clauses.append("e.event_type = ?")
        params.append(event_type)
    if job_status:
        clauses.append("e.job_status = ?")
        params.append(job_status)
    if job_type:
        clauses.append("e.job_type = ?")
        params.append(job_type)
    if date_from:
        clauses.append("e.created_at >= ?")
        params.append(date_from)
    if date_to:
        clauses.append("e.created_at <= ?")
        params.append(date_to + "T23:59:59" if "T" not in date_to else date_to)

    return (" AND ".join(clauses) if clauses else "1=1"), params


def _row_to_event(row: Tuple[Any, ...]) -> Dict[str, Any]:
    return {
        "id": row[0],
        "event_uuid": row[1],
        "job_id": row[2],
        "user_id": row[3],
        "username": row[4],
        "event_type": row[5],
        "job_status": row[6],
        "job_type": row[7],
        "result_count": int(row[8] or 0),
        "error_message": row[9],
        "metadata": _loads_json(row[10]),
        "created_at": row[11],
    }


def get_job_activity_feed(
    *,
    user_id: Optional[int] = None,
    event_type: Optional[str] = None,
    job_status: Optional[str] = None,
    job_type: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
) -> List[Dict[str, Any]]:
    where, params = _build_where(
        user_id=user_id,
        event_type=event_type,
        job_status=job_status,
        job_type=job_type,
        date_from=date_from,
        date_to=date_to,
    )
    params.extend([limit, offset])

    rows = execute_query(
        f"""
        SELECT e.id, e.event_uuid, e.job_id, e.user_id,
               COALESCE(u.username, '') as username,
               e.event_type, e.job_status, e.job_type, e.result_count,
               e.error_message, e.metadata_json, e.created_at
        FROM job_activity_events e
        LEFT JOIN users u ON u.id = e.user_id
        WHERE {where}
        ORDER BY e.created_at DESC
        LIMIT ? OFFSET ?
        """,
        tuple(params),
        fetch_all=True,
        commit=False,
    )
    return [_row_to_event(r) for r in (rows or [])]


def get_job_activity_count(
    *,
    user_id: Optional[int] = None,
    event_type: Optional[str] = None,
    job_status: Optional[str] = None,
    job_type: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
) -> int:
    where, params = _build_where(
        user_id=user_id,
        event_type=event_type,
        job_status=job_status,
        job_type=job_type,
        date_from=date_from,
        date_to=date_to,
    )
    row = execute_query(
        f"SELECT COUNT(*) FROM job_activity_events e WHERE {where}",
        tuple(params) if params else None,
        fetch_one=True,
        commit=False,
    )
    return int(row[0]) if row else 0


def get_job_activity_event(event_id: int) -> Optional[Dict[str, Any]]:
    row = execute_query(
        """
        SELECT e.id, e.event_uuid, e.job_id, e.user_id,
               COALESCE(u.username, '') as username,
               e.event_type, e.job_status, e.job_type, e.result_count,
               e.error_message, e.metadata_json, e.created_at
        FROM job_activity_events e
        LEFT JOIN users u ON u.id = e.user_id
        WHERE e.id = ?
        LIMIT 1
        """,
        (event_id,),
        fetch_one=True,
        commit=False,
    )
    return _row_to_event(row) if row else None


def get_job_activity_filters() -> Dict[str, List[str]]:
    job_types_rows = execute_query(
        """
        SELECT DISTINCT job_type
        FROM job_activity_events
        WHERE job_type IS NOT NULL AND job_type <> ''
        ORDER BY job_type
        """,
        fetch_all=True,
        commit=False,
    )
    event_types_rows = execute_query(
        """
        SELECT DISTINCT event_type
        FROM job_activity_events
        WHERE event_type IS NOT NULL AND event_type <> ''
        ORDER BY event_type
        """,
        fetch_all=True,
        commit=False,
    )
    statuses_rows = execute_query(
        """
        SELECT DISTINCT job_status
        FROM job_activity_events
        WHERE job_status IS NOT NULL AND job_status <> ''
        ORDER BY job_status
        """,
        fetch_all=True,
        commit=False,
    )

    return {
        "job_types": [r[0] for r in (job_types_rows or [])],
        "event_types": [r[0] for r in (event_types_rows or [])],
        "job_statuses": [r[0] for r in (statuses_rows or [])],
    }

