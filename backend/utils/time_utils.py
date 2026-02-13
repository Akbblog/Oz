from __future__ import annotations

from datetime import datetime, timezone

from db.base import get_db_type


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def now_db_string() -> str:
    """
    Return a timestamp string that is safe to store in both SQLite TEXT columns
    and MySQL DATETIME/TIMESTAMP columns.
    """
    db_type = get_db_type()
    if db_type == "mysql":
        # MySQL reliably parses "YYYY-MM-DD HH:MM:SS"
        return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()
