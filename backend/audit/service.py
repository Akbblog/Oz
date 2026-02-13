"""
Core audit event recording service.

Provides a single append-only function for writing immutable audit records
with SHA-256 hash chaining for tamper evidence.
"""

import uuid
import json
import hashlib
import logging
from datetime import datetime
from typing import Optional, Any, Dict

logger = logging.getLogger(__name__)

# Module-level cache for hash chain continuity
_last_record_hash: Optional[str] = None


def _compute_record_hash(
    request_id: str,
    actor_user_id: Optional[int],
    action: str,
    target_type: Optional[str],
    target_id: Optional[str],
    created_at: str,
    prev_hash: Optional[str],
) -> str:
    """SHA-256 hash of core fields for tamper evidence."""
    payload = (
        f"{request_id}|{actor_user_id}|{action}|"
        f"{target_type}|{target_id}|{created_at}|{prev_hash or ''}"
    )
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _get_last_hash() -> Optional[str]:
    """Retrieve the record_hash of the most recent audit_events row."""
    global _last_record_hash
    if _last_record_hash is not None:
        return _last_record_hash
    try:
        from db.base import execute_query
        row = execute_query(
            "SELECT record_hash FROM audit_events ORDER BY id DESC LIMIT 1",
            fetch_one=True,
            commit=False,
        )
        _last_record_hash = row[0] if row else None
    except Exception:
        _last_record_hash = None
    return _last_record_hash


def record_audit_event(
    action: str,
    *,
    request_id: Optional[str] = None,
    actor_user_id: Optional[int] = None,
    actor_username: Optional[str] = None,
    target_type: Optional[str] = None,
    target_id: Optional[str] = None,
    before: Optional[Dict[str, Any]] = None,
    after: Optional[Dict[str, Any]] = None,
    ip_address: Optional[str] = None,
    user_agent: Optional[str] = None,
    status: str = "success",
    failure_reason: Optional[str] = None,
    metadata: Optional[Dict[str, Any]] = None,
) -> Optional[int]:
    """
    Write a single immutable audit record.

    Returns the inserted row id, or None on error.
    Audit recording never blocks business logic -- all exceptions are caught.
    """
    global _last_record_hash
    try:
        from db.base import execute_query

        if request_id is None:
            request_id = str(uuid.uuid4())
        created_at = datetime.now().isoformat()
        prev_hash = _get_last_hash()
        record_hash = _compute_record_hash(
            request_id, actor_user_id, action,
            target_type, target_id, created_at, prev_hash,
        )

        row_id = execute_query(
            """
            INSERT INTO audit_events
                (request_id, actor_user_id, actor_username, action,
                 target_type, target_id, before_snapshot, after_snapshot,
                 ip_address, user_agent, status, failure_reason,
                 metadata, prev_hash, record_hash, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                request_id,
                actor_user_id,
                actor_username,
                action,
                target_type,
                target_id,
                json.dumps(before) if before else None,
                json.dumps(after) if after else None,
                ip_address,
                (user_agent or "")[:512],
                status,
                failure_reason,
                json.dumps(metadata) if metadata else None,
                prev_hash,
                record_hash,
                created_at,
            ),
        )
        _last_record_hash = record_hash
        return row_id
    except Exception:
        logger.exception("Failed to write audit event (non-fatal)")
        return None
