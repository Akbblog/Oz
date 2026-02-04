from __future__ import annotations

import os
from datetime import datetime, timezone


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def now_db_string() -> str:
    """
    Return a timestamp string that is safe to store in both SQLite TEXT columns
    and MySQL DATETIME/TIMESTAMP columns.
    """
    db_type = os.getenv("DB_TYPE", "sqlite").lower()
    if db_type == "mysql":
        # MySQL reliably parses "YYYY-MM-DD HH:MM:SS"
        return datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()

