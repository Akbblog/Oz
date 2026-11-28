"""
contact_messages.py - the contact form.

Anyone (signed in or not) can send a message. It is stored, shown in the admin
console under Messages with a badge for unread ones, and an admin marks it
read / replied / archived and can leave a note. Nothing is emailed from here:
the admin replies from their own mail or WhatsApp.
"""

from __future__ import annotations

import logging
import re
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Mapping, Optional

from db.base import execute_query

logger = logging.getLogger(__name__)

STATUSES = ("new", "read", "replied", "archived")
TOPICS = ("general", "sales", "support", "billing", "partnership", "feedback")
MAX_MESSAGE = 4000
MIN_MESSAGE = 10
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$")

# Public write endpoint: a few messages per IP per hour is plenty for a person.
_LIMIT_PER_HOUR = 5
_sent: Dict[str, List[float]] = {}


class ContactError(ValueError):
    """The submission cannot be accepted; the message is safe to show the sender."""


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def _text(value: Any, max_len: int) -> Optional[str]:
    if value is None:
        return None
    text = re.sub(r"[ \t\r\f\v]+", " ", str(value)).strip()
    return text[:max_len] or None


def _allow(ip: Optional[str]) -> bool:
    key = ip or "unknown"
    now = time.monotonic()
    recent = [t for t in _sent.get(key, []) if now - t < 3600]
    if len(recent) >= _LIMIT_PER_HOUR:
        _sent[key] = recent
        return False
    recent.append(now)
    if len(_sent) > 20000:
        _sent.clear()
    _sent[key] = recent
    return True


def submit(payload: Any, headers: Mapping[str, str], client_host: Optional[str],
           user: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """Validate and store one message. Raises ContactError with a readable reason."""
    if not isinstance(payload, dict):
        raise ContactError("Please fill in the form.")
    # Honeypot: a field people never see. Bots fill it; pretend it worked.
    if _text(payload.get("website"), 200):
        return {"ok": True, "id": None}

    name = _text(payload.get("name"), 120)
    email = (_text(payload.get("email"), 255) or "").lower()
    message = (str(payload.get("message") or "")).strip()[:MAX_MESSAGE]
    if not name or len(name) < 2:
        raise ContactError("Please tell us your name.")
    if not _EMAIL_RE.match(email):
        raise ContactError("Please enter a valid email address so we can reply.")
    if len(message) < MIN_MESSAGE:
        raise ContactError("Please write a little more so we can help.")
    topic = (_text(payload.get("topic"), 40) or "general").lower()
    if topic not in TOPICS:
        topic = "general"

    from analytics import visits

    ip = visits.resolve_client_ip(headers, client_host)
    if not _allow(ip):
        raise ContactError("You have sent several messages already. Please wait a while before sending another.")

    phone = _text(payload.get("phone"), 40)
    phone_country = payload.get("phone_country")
    if phone:
        try:
            import user_profile
            phone = user_profile.normalize_phone(phone, phone_country, strict=False)["phone"]
        except Exception:
            pass

    geo = visits.best_geo(headers, payload)
    ua = visits.parse_user_agent(headers.get("user-agent"))
    device = " · ".join(p for p in (ua.get("browser"), ua.get("os"), ua.get("device_type")) if p)[:128] or None

    execute_query(
        """
        INSERT INTO contact_messages
            (user_id, name, email, phone, topic, message, status,
             ip_address, country, city, device, page, visitor_id, created_at)
        VALUES (?, ?, ?, ?, ?, ?, 'new', ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            int(user["id"]) if user else None, name, email, phone, topic, message,
            ip, geo.get("country"), geo.get("city"), device,
            visits.clean_path(payload.get("page")), visits._clean_id(payload.get("visitor_id")), _now(),
        ),
    )
    return {"ok": True}


# ----------------------------------------------------------------- admin side
_COLUMNS = ("m.id, m.user_id, u.username, m.name, m.email, m.phone, m.topic, m.message, m.status, "
            "m.admin_note, m.handled_by, h.username, m.handled_at, m.ip_address, m.country, m.city, "
            "m.device, m.page, m.visitor_id, m.created_at")
_FROM = ("FROM contact_messages m LEFT JOIN users u ON u.id = m.user_id "
         "LEFT JOIN users h ON h.id = m.handled_by")


def _row(r) -> Dict[str, Any]:
    return {
        "id": r[0], "user_id": r[1], "username": r[2], "name": r[3], "email": r[4], "phone": r[5],
        "topic": r[6], "message": r[7], "status": r[8], "admin_note": r[9], "handled_by": r[10],
        "handled_by_username": r[11], "handled_at": r[12], "ip_address": r[13], "country": r[14],
        "city": r[15], "device": r[16], "page": r[17], "visitor_id": r[18], "created_at": r[19],
    }


def counts() -> Dict[str, int]:
    rows = execute_query("SELECT status, COUNT(*) FROM contact_messages GROUP BY status",
                         fetch_all=True, commit=False) or []
    out = {s: 0 for s in STATUSES}
    for status, n in rows:
        if status in out:
            out[status] = int(n or 0)
    out["total"] = sum(out[s] for s in STATUSES)
    return out


def list_messages(status: Optional[str] = None, q: Optional[str] = None,
                  limit: int = 50, offset: int = 0) -> Dict[str, Any]:
    try:
        limit = max(1, min(int(limit), 200))
        offset = max(0, int(offset))
    except (TypeError, ValueError):
        limit, offset = 50, 0
    clauses, params = ["1 = 1"], []  # type: List[str], List[Any]
    status = (status or "").strip().lower()
    if status in STATUSES:
        clauses.append("m.status = ?")
        params.append(status)
    elif status == "open":
        clauses.append("m.status IN ('new', 'read')")
    q = (q or "").strip()[:100]
    if q:
        like = "%" + q.replace("!", "!!").replace("%", "!%").replace("_", "!_") + "%"
        clauses.append("(m.name LIKE ? ESCAPE '!' OR m.email LIKE ? ESCAPE '!' OR m.message LIKE ? ESCAPE '!' "
                       "OR m.phone LIKE ? ESCAPE '!')")
        params.extend([like] * 4)
    where = " AND ".join(clauses)
    total = execute_query(f"SELECT COUNT(*) {_FROM} WHERE {where}", tuple(params), fetch_one=True, commit=False)
    rows = execute_query(
        f"SELECT {_COLUMNS} {_FROM} WHERE {where} ORDER BY m.created_at DESC, m.id DESC LIMIT ? OFFSET ?",
        tuple(params + [limit, offset]), fetch_all=True, commit=False)
    return {
        "messages": [_row(r) for r in (rows or [])],
        "total": int(total[0] or 0) if total else 0,
        "limit": limit, "offset": offset, "counts": counts(),
    }


def update_message(message_id: int, admin_id: int, status: Optional[str] = None,
                   admin_note: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """Change status and/or note. Returns the updated message, or None if it does not exist."""
    existing = execute_query("SELECT id FROM contact_messages WHERE id = ?", (message_id,),
                             fetch_one=True, commit=False)
    if not existing:
        return None
    sets, params = [], []  # type: List[str], List[Any]
    if status is not None:
        status = status.strip().lower()
        if status not in STATUSES:
            raise ContactError("Unknown status.")
        sets.append("status = ?")
        params.append(status)
        if status in ("replied", "archived"):
            sets += ["handled_by = ?", "handled_at = ?"]
            params += [admin_id, _now()]
    if admin_note is not None:
        sets.append("admin_note = ?")
        params.append(_text(admin_note, 2000))
    if sets:
        execute_query(f"UPDATE contact_messages SET {', '.join(sets)} WHERE id = ?", tuple(params + [message_id]))
    row = execute_query(f"SELECT {_COLUMNS} {_FROM} WHERE m.id = ?", (message_id,), fetch_one=True, commit=False)
    return _row(row) if row else None
