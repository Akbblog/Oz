"""
Audit data retention: archival, purging, and tamper-evidence verification.

Hot data: 90 days in audit_events (queryable).
Archive: 1-2 years in audit_events_archive.
Purge: Records older than max_age_days removed from archive.
"""

import hashlib
import logging
from datetime import datetime, timedelta
from typing import Dict, Any

from db.base import execute_query, get_db_cursor

logger = logging.getLogger(__name__)


def archive_old_events(hot_days: int = 90) -> int:
    """Move audit_events older than hot_days into audit_events_archive."""
    cutoff = (datetime.now() - timedelta(days=hot_days)).isoformat()
    now = datetime.now().isoformat()

    with get_db_cursor() as cursor:
        # Copy to archive
        cursor.execute(
            """
            INSERT INTO audit_events_archive
                (id, request_id, actor_user_id, actor_username, action,
                 target_type, target_id, before_snapshot, after_snapshot,
                 ip_address, user_agent, status, failure_reason,
                 metadata, prev_hash, record_hash, created_at, archived_at)
            SELECT
                id, request_id, actor_user_id, actor_username, action,
                target_type, target_id, before_snapshot, after_snapshot,
                ip_address, user_agent, status, failure_reason,
                metadata, prev_hash, record_hash, created_at, ?
            FROM audit_events
            WHERE created_at < ?
            """,
            (now, cutoff),
        )
        archived_count = cursor.rowcount

        # Delete from hot table
        cursor.execute(
            "DELETE FROM audit_events WHERE created_at < ?",
            (cutoff,),
        )

    logger.info(f"Archived {archived_count} audit events older than {hot_days} days")
    return archived_count


def purge_archive(max_age_days: int = 730) -> int:
    """Delete archived events older than max_age_days (default 2 years)."""
    cutoff = (datetime.now() - timedelta(days=max_age_days)).isoformat()
    deleted = execute_query(
        "DELETE FROM audit_events_archive WHERE created_at < ?",
        (cutoff,),
    )
    count = deleted if isinstance(deleted, int) else 0
    logger.info(f"Purged {count} archived audit events older than {max_age_days} days")
    return count


def verify_hash_chain(limit: int = 1000) -> Dict[str, Any]:
    """
    Verify integrity of the last N audit records.
    Returns {"valid": bool, "checked": int, "first_broken_id": int|None}
    """
    rows = execute_query(
        """
        SELECT id, request_id, actor_user_id, action, target_type,
               target_id, created_at, prev_hash, record_hash
        FROM audit_events
        ORDER BY id DESC
        LIMIT ?
        """,
        (limit,),
        fetch_all=True,
        commit=False,
    )
    if not rows:
        return {"valid": True, "checked": 0, "first_broken_id": None}

    # Reverse to check oldest first
    rows = list(reversed(rows))
    checked = 0
    first_broken_id = None

    for i, row in enumerate(rows):
        row_id = row[0]
        request_id = row[1]
        actor_user_id = row[2]
        action = row[3]
        target_type = row[4]
        target_id = row[5]
        created_at = row[6]
        prev_hash = row[7]
        stored_hash = row[8]

        # Recompute hash
        payload = (
            f"{request_id}|{actor_user_id}|{action}|"
            f"{target_type}|{target_id}|{created_at}|{prev_hash or ''}"
        )
        expected_hash = hashlib.sha256(payload.encode("utf-8")).hexdigest()

        if stored_hash != expected_hash:
            first_broken_id = row_id
            break

        # Verify chain: this row's prev_hash should match the previous row's record_hash
        if i > 0:
            prev_row_hash = rows[i - 1][8]  # record_hash of previous row
            if prev_hash != prev_row_hash:
                first_broken_id = row_id
                break

        checked += 1

    return {
        "valid": first_broken_id is None,
        "checked": checked,
        "first_broken_id": first_broken_id,
    }
