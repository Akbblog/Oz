"""
analytics/ingest.py — Batch insert frontend behavioral events.

Validates and sanitizes each event from the tracker.js payload,
then bulk-inserts into analytics_events. Never raises — analytics
failures must never affect the caller.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from db.base import execute_query, get_db_cursor

logger = logging.getLogger(__name__)

# Allowed event names — reject anything outside this set
_VALID_EVENT_NAMES = frozenset({
    "page_view",
    "page_exit",
    "click",
    "feature_use",
    "search_start",
    "search_complete",
    "credit_purchase",
    "register",
    "login",
})

_MAX_BATCH = 100    # hard cap per request
_MAX_STR   = 255    # max length for string columns


def _trunc(value: Any, max_len: int = _MAX_STR) -> Optional[str]:
    """Coerce to string and truncate, or return None."""
    if value is None:
        return None
    s = str(value).strip()
    return s[:max_len] if s else None


def _safe_float(value: Any, lo: float = 0.0, hi: float = 100.0) -> Optional[float]:
    """Parse float and clamp to range, or return None."""
    try:
        f = float(value)
        return round(max(lo, min(hi, f)), 4)
    except (TypeError, ValueError):
        return None


def _safe_int(value: Any, lo: int = 0, hi: int = 65535) -> Optional[int]:
    try:
        return max(lo, min(hi, int(value)))
    except (TypeError, ValueError):
        return None


def _validate_event(raw: Dict[str, Any], auth_user_id: Optional[int]) -> Optional[Dict[str, Any]]:
    """
    Sanitize one raw event dict from the tracker payload.
    Returns a clean dict ready for INSERT, or None if invalid.
    """
    event_name = _trunc(raw.get("event_name"), 100)
    if not event_name or event_name not in _VALID_EVENT_NAMES:
        return None  # silently drop unknown event types

    session_id = _trunc(raw.get("session_id"), 36)
    if not session_id:
        return None  # session_id is required

    # Trust the server-side user_id (from JWT) over client-supplied value
    user_id = auth_user_id if auth_user_id is not None else _safe_int(raw.get("user_id"), 0, 2**31)

    # Heatmap coordinates (client sends % of viewport, 0-100)
    click_x = _safe_float(raw.get("click_x"))
    click_y = _safe_float(raw.get("click_y"))
    # Only meaningful for click events
    if event_name != "click":
        click_x = click_y = None

    # Determine date_bucket from created_at or fall back to today
    created_at_raw = raw.get("created_at")
    try:
        dt = datetime.fromisoformat(str(created_at_raw).replace("Z", "+00:00"))
        date_bucket = dt.strftime("%Y-%m-%d")
        created_at  = dt.replace(microsecond=0).isoformat()
    except (TypeError, ValueError):
        now = datetime.now(timezone.utc)
        date_bucket = now.strftime("%Y-%m-%d")
        created_at  = now.replace(microsecond=0).isoformat()

    # Serialize extra_json — strip the columns we already have dedicated fields for
    extra = raw.get("extra_json") or {}
    if isinstance(extra, dict):
        extra.pop("element",  None)
        extra.pop("feature",  None)
        extra.pop("click_x",  None)
        extra.pop("click_y",  None)
        extra_str = json.dumps(extra) if extra else None
    else:
        extra_str = None

    return {
        "user_id":    user_id,
        "session_id": session_id,
        "event_name": event_name,
        "page":       _trunc(raw.get("page")),
        "element":    _trunc(raw.get("element")),
        "feature":    _trunc(raw.get("feature"), 100),
        "click_x":    click_x,
        "click_y":    click_y,
        "viewport_w": _safe_int(raw.get("viewport_w"), 0, 8192),
        "viewport_h": _safe_int(raw.get("viewport_h"), 0, 8192),
        "extra_json": extra_str,
        "date_bucket": date_bucket,
        "created_at":  created_at,
    }


def ingest_events(
    raw_events: List[Dict[str, Any]],
    auth_user_id: Optional[int] = None,
) -> int:
    """
    Validate and bulk-insert a batch of analytics events.

    Returns the number of rows successfully inserted.
    Never raises — all exceptions are caught and logged.
    """
    if not raw_events:
        return 0

    events = []
    for raw in raw_events[:_MAX_BATCH]:
        cleaned = _validate_event(raw, auth_user_id)
        if cleaned:
            events.append(cleaned)

    if not events:
        return 0

    try:
        with get_db_cursor() as cur:
            cur.executemany(
                """
                INSERT INTO analytics_events
                    (user_id, session_id, event_name, page, element, feature,
                     click_x, click_y, viewport_w, viewport_h,
                     extra_json, date_bucket, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    (
                        e["user_id"], e["session_id"], e["event_name"],
                        e["page"], e["element"], e["feature"],
                        e["click_x"], e["click_y"],
                        e["viewport_w"], e["viewport_h"],
                        e["extra_json"], e["date_bucket"], e["created_at"],
                    )
                    for e in events
                ],
            )
        return len(events)
    except Exception:
        logger.exception("analytics ingest failed (non-fatal), batch size=%d", len(events))
        return 0
