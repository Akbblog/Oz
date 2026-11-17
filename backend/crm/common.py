"""Shared CRM helpers: errors, UTC time, SQL dialect, rows, cursors, validation.

Conventions (docs/CRM_PHASE1_CONTRACT.md section 0):
* Every timestamp is stored as UTC. MariaDB columns are DATETIME(6), SQLite
  columns TEXT; both receive the same fixed-width text form
  ``YYYY-MM-DD HH:MM:SS.ffffff`` so comparisons and ordering agree.
* The API returns ``...Z`` ISO strings.
* SQL uses ``?`` placeholders (converted for MySQL by database.py) and never a
  literal ``%`` (pymysql would treat it as a format directive): LIKE patterns
  are always parameters.
"""

from __future__ import annotations

import base64
import collections
import json
import os
import re
import threading
import time
import uuid
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple
from urllib.parse import urlparse

from database import _get_db_type, get_db


# --------------------------------------------------------------------------- #
# Errors
# --------------------------------------------------------------------------- #

class CRMError(Exception):
    """An error with a plain-sentence ``detail`` and a machine ``code``."""

    def __init__(self, status: int, detail: str, code: str, **extra: Any):
        super().__init__(detail)
        self.status = status
        self.detail = detail
        self.code = code
        self.extra = extra

    def body(self) -> Dict[str, Any]:
        out = {"detail": self.detail, "code": self.code}
        out.update(self.extra)
        return out


def not_found() -> CRMError:
    return CRMError(404, "Not found", "not_found")


def invalid(detail: str) -> CRMError:
    return CRMError(422, detail, "validation_error")


def invalid_transition(detail: str) -> CRMError:
    return CRMError(409, detail, "invalid_transition")


# --------------------------------------------------------------------------- #
# Feature flag and rate limit
# --------------------------------------------------------------------------- #

def crm_enabled() -> bool:
    return os.getenv("CRM_ENABLED", "false").strip().lower() in ("1", "true", "t", "yes", "y", "on")


class _SlidingWindowLimiter:
    """In-process per-key limit (like the other in-process guards; per worker process)."""

    def __init__(self) -> None:
        self._hits: Dict[Any, collections.deque] = {}
        self._lock = threading.Lock()

    def hit(self, key: Any, limit: int, window_seconds: float = 60.0) -> bool:
        now = time.monotonic()
        with self._lock:
            q = self._hits.setdefault(key, collections.deque())
            while q and now - q[0] >= window_seconds:
                q.popleft()
            if len(q) >= limit:
                return False
            q.append(now)
            return True

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()


import_limiter = _SlidingWindowLimiter()


def import_rate_limit() -> int:
    try:
        return max(1, int(os.getenv("CRM_IMPORT_RATE_PER_MIN", "30")))
    except ValueError:
        return 30


def check_import_rate(user_id: int) -> None:
    if not import_limiter.hit(("import", int(user_id)), import_rate_limit()):
        raise CRMError(429, "Too many import requests. Wait a minute and try again.", "rate_limited")


# --------------------------------------------------------------------------- #
# Time
# --------------------------------------------------------------------------- #

def utcnow() -> datetime:
    """Naive UTC now (microsecond precision)."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def db_ts(dt: Optional[datetime]) -> Optional[str]:
    if dt is None:
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt.strftime("%Y-%m-%d %H:%M:%S.%f")


def from_db_ts(value: Any) -> Optional[datetime]:
    """Stored UTC value (datetime from MariaDB, text from SQLite) -> naive UTC datetime."""
    if value is None or value == "":
        return None
    if isinstance(value, datetime):
        return value.replace(tzinfo=None) if value.tzinfo is None else value.astimezone(timezone.utc).replace(tzinfo=None)
    try:
        dt = datetime.fromisoformat(str(value).strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone(timezone.utc).replace(tzinfo=None)
    return dt


def api_ts(value: Any) -> Optional[str]:
    dt = from_db_ts(value)
    if dt is None:
        return None
    return dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def cursor_ts(value: Any) -> Optional[str]:
    """Canonical text form of a stored timestamp, used inside pagination cursors."""
    dt = from_db_ts(value)
    return db_ts(dt) if dt else None


def api_date(value: Any) -> Optional[str]:
    if value is None or value == "":
        return None
    if isinstance(value, (date, datetime)):
        return value.strftime("%Y-%m-%d")
    return str(value)[:10]


def parse_aware(value: Any, field: str) -> datetime:
    """Timezone-aware ISO-8601 -> naive UTC. Naive input is rejected."""
    if not isinstance(value, str) or not value.strip():
        raise invalid(f"{field} must be an ISO-8601 date-time with a timezone.")
    raw = value.strip()
    if raw.endswith(("Z", "z")):
        raw = raw[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(raw)
    except ValueError:
        raise invalid(f"{field} must be an ISO-8601 date-time with a timezone.")
    if dt.tzinfo is None or dt.utcoffset() is None:
        raise invalid(f"{field} must include a timezone, for example 2026-11-18T09:00:00+01:00.")
    return dt.astimezone(timezone.utc).replace(tzinfo=None)


def tz_offset(value: Optional[int]) -> timedelta:
    """Client offset (minutes east of UTC, e.g. +60 for UTC+1)."""
    if value is None:
        return timedelta(0)
    try:
        minutes = int(value)
    except (TypeError, ValueError):
        raise invalid("tz_offset_minutes must be a whole number of minutes.")
    if minutes < -14 * 60 or minutes > 14 * 60:
        raise invalid("tz_offset_minutes must be between -840 and 840.")
    return timedelta(minutes=minutes)


def local_day_bounds(now_utc: datetime, offset: timedelta, day: Optional[date] = None) -> Tuple[datetime, datetime]:
    """UTC [start, end) of the client's local calendar day (today by default)."""
    local = now_utc + offset
    d = day or local.date()
    start_local = datetime(d.year, d.month, d.day)
    return start_local - offset, start_local - offset + timedelta(days=1)


# --------------------------------------------------------------------------- #
# DB helpers
# --------------------------------------------------------------------------- #

def is_mysql() -> bool:
    return _get_db_type() == "mysql"


def for_update() -> str:
    return " FOR UPDATE" if is_mysql() else ""


def new_id() -> str:
    return str(uuid.uuid4())


def begin_write(conn) -> None:
    """Start a write transaction that serialises with other writers."""
    if is_mysql():
        conn.commit()  # end any implicit snapshot opened by earlier reads
        return
    if getattr(conn, "in_transaction", False):
        conn.commit()
    conn.execute("BEGIN IMMEDIATE")


def is_unique_violation(exc: Exception) -> bool:
    msg = str(exc).lower()
    if "unique constraint failed" in msg or "duplicate entry" in msg:
        return True
    try:
        return int(getattr(exc, "args", [None])[0]) == 1062
    except Exception:
        return False


def fetch_all(cur, sql: str, params: Sequence[Any] = ()) -> List[Dict[str, Any]]:
    cur.execute(sql, tuple(params))
    cols = [d[0] for d in (cur.description or [])]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def fetch_one(cur, sql: str, params: Sequence[Any] = ()) -> Optional[Dict[str, Any]]:
    cur.execute(sql, tuple(params))
    row = cur.fetchone()
    if row is None:
        return None
    cols = [d[0] for d in (cur.description or [])]
    return dict(zip(cols, row))


def scalar(cur, sql: str, params: Sequence[Any] = ()) -> Any:
    cur.execute(sql, tuple(params))
    row = cur.fetchone()
    return row[0] if row else None


def placeholders(n: int) -> str:
    return ",".join("?" * n)


def chunks(items: Sequence[Any], size: int = 500) -> Iterable[Sequence[Any]]:
    for i in range(0, len(items), size):
        yield items[i:i + size]


def like_param(text: str) -> str:
    """Case-folded LIKE pattern with ! as the (portable) escape character."""
    t = text.casefold().replace("!", "!!").replace("%", "!%").replace("_", "!_")
    return f"%{t}%"


def to_json(value: Any) -> Optional[str]:
    if value is None:
        return None
    return json.dumps(value, ensure_ascii=False, default=str, separators=(",", ":"))


def from_json(value: Any, default: Any = None) -> Any:
    if value is None or value == "":
        return default
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return default


def num(value: Any) -> Optional[float]:
    """DECIMAL/NUMERIC column -> JSON number (2 decimals) or None."""
    if value is None or value == "":
        return None
    try:
        return float(round(Decimal(str(value)), 2))
    except (InvalidOperation, ValueError):
        return None


# --------------------------------------------------------------------------- #
# Keyset cursors
# --------------------------------------------------------------------------- #

def encode_cursor(values: List[Any]) -> str:
    raw = json.dumps(values, separators=(",", ":"), default=str).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def decode_cursor(cursor: Optional[str], length: int) -> Optional[List[Any]]:
    if not cursor:
        return None
    try:
        pad = "=" * (-len(cursor) % 4)
        values = json.loads(base64.urlsafe_b64decode((cursor + pad).encode("ascii")).decode("utf-8"))
    except Exception:
        raise invalid("The cursor is not valid. Reload the list.")
    if not isinstance(values, list) or len(values) != length:
        raise invalid("The cursor is not valid. Reload the list.")
    return values


def page_limit(limit: Optional[int], default: int = 50, maximum: int = 100) -> int:
    if limit is None:
        return default
    try:
        n = int(limit)
    except (TypeError, ValueError):
        raise invalid("limit must be a number between 1 and 100.")
    if n < 1 or n > maximum:
        raise invalid(f"limit must be between 1 and {maximum}.")
    return n


# --------------------------------------------------------------------------- #
# Field validation
# --------------------------------------------------------------------------- #

_EMAIL_RE = re.compile(r"^[A-Za-z0-9._%+'-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$")
_CURRENCY_RE = re.compile(r"^[A-Z]{3}$")
_PHONE_RE = re.compile(r"^[0-9+()./\- x#*]{3,64}$", re.IGNORECASE)


def clean_text(value: Any, field: str, max_len: int, *, required: bool = False) -> Optional[str]:
    if value is None:
        if required:
            raise invalid(f"{field} is required.")
        return None
    if not isinstance(value, str):
        raise invalid(f"{field} must be text.")
    text = value.strip()
    if not text:
        if required:
            raise invalid(f"{field} is required.")
        return None
    if len(text) > max_len:
        raise invalid(f"{field} must be at most {max_len} characters.")
    return text


def clean_email(value: Any, field: str = "Email") -> Optional[str]:
    text = clean_text(value, field, 254)
    if text is not None and not _EMAIL_RE.match(text):
        raise invalid(f"{field} is not a valid email address.")
    return text


def clean_phone(value: Any, field: str = "Phone") -> Optional[str]:
    text = clean_text(value, field, 64)
    if text is not None and (not _PHONE_RE.match(text) or sum(c.isdigit() for c in text) < 3):
        raise invalid(f"{field} is not a valid phone number.")
    return text


def clean_url(value: Any, field: str = "Website") -> Optional[str]:
    text = clean_text(value, field, 2048)
    if text is None:
        return None
    if any(ch.isspace() for ch in text):
        raise invalid(f"{field} must be an http or https address.")
    try:
        parsed = urlparse(text)
    except ValueError:
        raise invalid(f"{field} must be an http or https address.")
    if parsed.scheme.lower() not in ("http", "https") or not parsed.netloc:
        raise invalid(f"{field} must be an http or https address.")
    return text


def clean_currency(value: Any) -> Optional[str]:
    if value is None or (isinstance(value, str) and not value.strip()):
        return None
    if not isinstance(value, str) or not _CURRENCY_RE.match(value.strip().upper()):
        raise invalid("Currency must be a 3-letter ISO code such as USD.")
    return value.strip().upper()


def clean_value(value: Any) -> Optional[str]:
    """Deal value -> canonical decimal text (2 places) or None."""
    if value is None or (isinstance(value, str) and not value.strip()):
        return None
    if isinstance(value, bool):
        raise invalid("Value must be a number.")
    try:
        d = Decimal(str(value).strip())
    except (InvalidOperation, ValueError):
        raise invalid("Value must be a number.")
    if not d.is_finite() or d < 0 or d >= Decimal("1000000000000"):
        raise invalid("Value must be between 0 and 999,999,999,999.99.")
    return str(d.quantize(Decimal("0.01")))


def clean_int(value: Any, field: str, lo: int, hi: int) -> Optional[int]:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or int(value) != value:
        raise invalid(f"{field} must be a whole number between {lo} and {hi}.")
    n = int(value)
    if n < lo or n > hi:
        raise invalid(f"{field} must be a whole number between {lo} and {hi}.")
    return n


def clean_date(value: Any, field: str) -> Optional[str]:
    if value is None or (isinstance(value, str) and not value.strip()):
        return None
    if not isinstance(value, str) or not re.match(r"^\d{4}-\d{2}-\d{2}$", value.strip()):
        raise invalid(f"{field} must be a date like 2026-12-31.")
    try:
        return date.fromisoformat(value.strip()).isoformat()
    except ValueError:
        raise invalid(f"{field} must be a date like 2026-12-31.")
