"""
analytics/visits.py — Visitor tracking: who opened the app, from where, on what.

One row per browser session in `site_visits` (migration 019). The frontend
posts a small beacon on every page change; the first hit of a session inserts
the row (IP, geo, referrer, UTM, device), later hits bump page_count,
last_seen_at and exit_path, and attach the user once they sign in.

Writes never raise: analytics must never break the caller. Reads are plain
dict/list builders for the admin /api/admin/visitors* endpoints.
"""

from __future__ import annotations

import logging
import re
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Mapping, Optional, Tuple
from urllib.parse import unquote, urlparse

from db.base import execute_query

logger = logging.getLogger(__name__)

MAX_DAYS = 365
MAX_LIMIT = 200
ACTIVE_WINDOW_SECONDS = 300
TOP_N = 8

_ID_RE = re.compile(r"^[A-Za-z0-9_.:-]{6,64}$")


# ─── Small sanitizers ─────────────────────────────────────────────────────────

def _trunc(value: Any, max_len: int) -> Optional[str]:
    if value is None or isinstance(value, (dict, list, tuple, set, bool)):
        return None
    s = str(value).replace("\x00", "").strip()
    return s[:max_len] if s else None


def _clean_id(value: Any) -> Optional[str]:
    s = _trunc(value, 64)
    return s if s and _ID_RE.match(s) else None


def _safe_int(value: Any, lo: int = 0, hi: int = 20000) -> Optional[int]:
    if isinstance(value, bool):
        return None
    try:
        n = int(value)
    except (TypeError, ValueError):
        return None
    return n if lo <= n <= hi else None


def _now() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def _iso(dt: datetime) -> str:
    return dt.isoformat()


def _parse_ts(value: Any) -> Optional[datetime]:
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (TypeError, ValueError):
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def clean_path(value: Any) -> Optional[str]:
    """Route path only: no query string or fragment, and no one-time tokens."""
    s = _trunc(value, 1024)
    if not s:
        return None
    if "://" in s:
        s = urlparse(s).path or "/"
    s = s.split("?", 1)[0].split("#", 1)[0] or "/"
    if not s.startswith("/"):
        s = "/" + s
    low = s.lower()
    for prefix in ("/reset-password", "/verify-email", "/payment/return", "/payment-return"):
        if low.startswith(prefix + "/"):
            s = prefix
            break
    return s[:255]


# ─── Client IP + geo from proxy headers ───────────────────────────────────────

def _header(headers: Mapping[str, str], name: str) -> str:
    try:
        return (headers.get(name) or "").strip()
    except Exception:
        return ""


def came_through_vercel(headers: Mapping[str, str]) -> bool:
    return bool(_header(headers, "x-vercel-id") or _header(headers, "x-vercel-forwarded-for"))


def resolve_client_ip(headers: Mapping[str, str], client_host: Optional[str] = None) -> Optional[str]:
    """Browser → Vercel rewrite → Cloudflare tunnel → backend.

    Vercel sets x-vercel-forwarded-for to the real browser IP; behind it,
    cf-connecting-ip is only Vercel's egress address, so it comes second.
    """
    for name, first_only in (("x-vercel-forwarded-for", True), ("cf-connecting-ip", False),
                             ("x-forwarded-for", True)):
        raw = _header(headers, name)
        if raw:
            ip = raw.split(",")[0].strip() if first_only else raw
            if ip:
                return ip[:64]
    host = (client_host or "").strip()
    return host[:64] if host and host != "unknown" else None


def resolve_geo(headers: Mapping[str, str]) -> Dict[str, Optional[str]]:
    """Country / region / city of the browser, or None when unknown.

    cf-ipcountry is trusted only when the request did not pass through Vercel;
    otherwise it describes Vercel's egress location, not the visitor.
    """
    country = _header(headers, "x-vercel-ip-country")
    if not country and not came_through_vercel(headers):
        country = _header(headers, "cf-ipcountry")
    country = country.upper()
    if country in ("", "XX", "T1") or not re.match(r"^[A-Z0-9]{2,8}$", country):
        country = ""
    region = _header(headers, "x-vercel-ip-country-region")
    city = _header(headers, "x-vercel-ip-city")
    try:
        city = unquote(city)
    except Exception:
        pass
    return {
        "country": country or None,
        "region": _trunc(region, 64),
        "city": _trunc(city, 128),
    }


# ─── User agent ───────────────────────────────────────────────────────────────

_BOT_RE = re.compile(
    r"bot\b|bot/|crawl|spider|slurp|headless|lighthouse|pagespeed|preview|monitor|uptime|pingdom|"
    r"facebookexternalhit|whatsapp|telegram|discord|embedly|python-requests|python-urllib|aiohttp|httpx|"
    r"curl/|wget/|go-http-client|okhttp|java/|libwww|scrapy|phantomjs|puppeteer|playwright|selenium|"
    r"postmanruntime|insomnia|axios/|node-fetch|gptbot|claudebot|bytespider|ahrefs|semrush|vercel",
    re.IGNORECASE,
)


def parse_user_agent(user_agent: Optional[str]) -> Dict[str, Any]:
    """Tiny UA sniffing: {browser, os, device_type, is_bot}. Good enough for a dashboard."""
    ua = (user_agent or "").strip()
    if not ua:
        return {"browser": None, "os": None, "device_type": "bot", "is_bot": True}

    if "Windows" in ua:
        os_name = "Windows"
    elif re.search(r"iPhone|iPad|iPod", ua):
        os_name = "iOS"
    elif "Android" in ua:
        os_name = "Android"
    elif "CrOS" in ua:
        os_name = "ChromeOS"
    elif "Mac OS X" in ua or "Macintosh" in ua:
        os_name = "macOS"
    elif "Linux" in ua:
        os_name = "Linux"
    else:
        os_name = "Other"

    if _BOT_RE.search(ua):
        return {"browser": "Bot", "os": os_name, "device_type": "bot", "is_bot": True}

    if "Edg/" in ua or "EdgA/" in ua or "EdgiOS/" in ua or "Edge/" in ua:
        browser = "Edge"
    elif "OPR/" in ua or "Opera" in ua:
        browser = "Opera"
    elif "SamsungBrowser/" in ua:
        browser = "Samsung Internet"
    elif "Firefox/" in ua or "FxiOS/" in ua:
        browser = "Firefox"
    elif "Chrome/" in ua or "CriOS/" in ua or "Chromium/" in ua:
        browser = "Chrome"
    elif "Safari/" in ua:
        browser = "Safari"
    else:
        browser = "Other"

    if "iPad" in ua or "Tablet" in ua or ("Android" in ua and "Mobile" not in ua):
        device = "tablet"
    elif re.search(r"Mobi|iPhone|iPod|Android", ua):
        device = "mobile"
    else:
        device = "desktop"

    return {"browser": browser, "os": os_name, "device_type": device, "is_bot": False}


# ─── Traffic source ───────────────────────────────────────────────────────────

_SEARCH_HOSTS = ("google.", "bing.com", "duckduckgo.com", "yahoo.", "yandex.", "baidu.com", "ecosia.org",
                 "brave.com", "startpage.com", "perplexity.ai", "chatgpt.com", "openai.com")
_SOCIAL_HOSTS = ("facebook.com", "fb.com", "fb.me", "instagram.com", "twitter.com", "x.com", "t.co",
                 "linkedin.com", "lnkd.in", "reddit.com", "youtube.com", "youtu.be", "tiktok.com",
                 "pinterest.", "whatsapp.com", "wa.me", "telegram.org", "t.me", "discord.com",
                 "threads.net", "snapchat.com", "quora.com", "medium.com")


def referrer_host(referrer: Optional[str]) -> Optional[str]:
    if not referrer:
        return None
    try:
        raw = referrer if "://" in referrer else "//" + referrer
        host = (urlparse(raw).hostname or "").lower()
    except Exception:
        return None
    if host.startswith("www."):
        host = host[4:]
    return host[:255] or None


def _host_matches(host: str, needle: str) -> bool:
    if needle.endswith("."):  # "google." matches google.com, google.co.uk, news.google.com
        return host.startswith(needle) or ("." + needle) in host
    return host == needle or host.endswith("." + needle)


def own_hosts(extra: Optional[List[str]] = None) -> List[str]:
    """Hostnames that count as "our own site" (internal navigation, not a referral)."""
    hosts = set()
    candidates: List[str] = list(extra or [])
    try:
        import config

        candidates.append(getattr(config, "FRONTEND_URL", "") or "")
        candidates.append(getattr(config, "APP_URL", "") or "")
        candidates.extend(getattr(config, "ALLOWED_ORIGINS", []) or [])
    except Exception:
        pass
    for c in candidates:
        h = referrer_host(c)
        if h and h not in ("localhost", "127.0.0.1"):
            hosts.add(h)
    return sorted(hosts)


def classify_source(referrer: Optional[str], utm_source: Optional[str] = None,
                    utm_medium: Optional[str] = None, utm_campaign: Optional[str] = None,
                    own: Optional[List[str]] = None) -> str:
    """direct | search | social | referral | campaign | internal"""
    if utm_source or utm_medium or utm_campaign:
        return "campaign"
    host = referrer_host(referrer)
    if not host:
        return "direct"
    own = own_hosts() if own is None else own
    if host in ("localhost", "127.0.0.1") or any(host == h for h in own):
        return "internal"
    if any(_host_matches(host, n) for n in _SEARCH_HOSTS):
        return "search"
    if any(_host_matches(host, n) for n in _SOCIAL_HOSTS):
        return "social"
    return "referral"


# ─── Write path ───────────────────────────────────────────────────────────────

def record_visit(payload: Any, headers: Mapping[str, str], client_host: Optional[str] = None,
                 auth_user_id: Optional[int] = None) -> bool:
    """Upsert the session's row. Returns False for junk input or any failure; never raises."""
    try:
        return _record_visit(payload, headers, client_host, auth_user_id)
    except Exception:
        logger.exception("visit tracking failed (non-fatal)")
        return False


# Public write endpoint: cap beacons per IP so nobody can fill the table.
_RATE_LIMIT_PER_MINUTE = 90
_rate: Dict[str, List[float]] = {}


def _allow(ip: Optional[str]) -> bool:
    """Fixed one-minute window per IP, kept in process memory."""
    import time
    key = ip or "unknown"
    now = time.monotonic()
    slot = _rate.get(key)
    if slot is None or now - slot[0] >= 60:
        if len(_rate) > 20000:  # bound memory under a flood of distinct IPs
            _rate.clear()
        _rate[key] = [now, 1]
        return True
    slot[1] += 1
    return slot[1] <= _RATE_LIMIT_PER_MINUTE


def _record_visit(payload: Any, headers: Mapping[str, str], client_host: Optional[str],
                  auth_user_id: Optional[int]) -> bool:
    if not isinstance(payload, dict):
        return False
    if not _allow(resolve_client_ip(headers, client_host)):
        return False
    session_id = _clean_id(payload.get("session_id"))
    if not session_id:
        return False
    path = clean_path(payload.get("path")) or "/"
    now = _iso(_now())

    # Heartbeat: the tab is still open on the same page. Keeps the session
    # "live" without counting another page view.
    if payload.get("heartbeat") is True and _heartbeat(session_id, now, auth_user_id):
        return True

    if _touch(session_id, path, now, auth_user_id):
        return True

    visitor_id = _clean_id(payload.get("visitor_id"))
    ua = _trunc(_header(headers, "user-agent"), 512)
    parsed = parse_user_agent(ua)
    geo = resolve_geo(headers)
    referrer = _trunc(payload.get("referrer"), 512)
    utm_source = _trunc(payload.get("utm_source"), 128)
    utm_medium = _trunc(payload.get("utm_medium"), 128)
    utm_campaign = _trunc(payload.get("utm_campaign"), 128)
    request_hosts = [h for h in (_header(headers, "origin"), _header(headers, "x-forwarded-host")) if h]
    own = own_hosts(request_hosts)
    source = classify_source(referrer, utm_source, utm_medium, utm_campaign, own=own)
    ref_host = referrer_host(referrer)
    if source == "internal" and referrer:
        referrer = referrer.split("?", 1)[0].split("#", 1)[0]  # our own URLs can carry tokens

    try:
        execute_query(
            """
            INSERT INTO site_visits
                (session_id, visitor_id, user_id, ip_address, country, region, city,
                 referrer, referrer_host, source, utm_source, utm_medium, utm_campaign,
                 landing_path, exit_path, page_count, browser, os, device_type, is_bot,
                 language, timezone, screen_w, screen_h, user_agent,
                 first_seen_at, last_seen_at, date_bucket)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                session_id, visitor_id, auth_user_id,
                resolve_client_ip(headers, client_host), geo["country"], geo["region"], geo["city"],
                referrer, ref_host, source, utm_source, utm_medium, utm_campaign,
                path, path, parsed["browser"], parsed["os"], parsed["device_type"],
                1 if parsed["is_bot"] else 0,
                _trunc(payload.get("language"), 32), _trunc(payload.get("timezone"), 64),
                _safe_int(payload.get("screen_w")), _safe_int(payload.get("screen_h")), ua,
                now, now, now[:10],
            ),
        )
        return True
    except Exception as exc:
        # Two first hits of the same session raced on the unique key: the other
        # one inserted, so this one becomes a normal follow-up hit.
        if _touch(session_id, path, now, auth_user_id):
            return True
        logger.warning("visit insert failed (non-fatal): %r", exc)
        return False


def _heartbeat(session_id: str, now: str, auth_user_id: Optional[int]) -> bool:
    """Refresh last_seen_at only. False when the session has no row yet."""
    if auth_user_id is not None:
        changed = execute_query(
            "UPDATE site_visits SET last_seen_at = ?, user_id = ? WHERE session_id = ?",
            (now, auth_user_id, session_id),
        )
    else:
        changed = execute_query(
            "UPDATE site_visits SET last_seen_at = ? WHERE session_id = ?",
            (now, session_id),
        )
    return bool(changed and changed > 0)


def _touch(session_id: str, path: str, now: str, auth_user_id: Optional[int]) -> bool:
    """Follow-up hit: bump the existing row. False when the session has no row yet."""
    if auth_user_id is not None:
        changed = execute_query(
            "UPDATE site_visits SET page_count = page_count + 1, last_seen_at = ?, exit_path = ?, "
            "user_id = ? WHERE session_id = ?",
            (now, path, auth_user_id, session_id),
        )
    else:
        changed = execute_query(
            "UPDATE site_visits SET page_count = page_count + 1, last_seen_at = ?, exit_path = ? "
            "WHERE session_id = ?",
            (now, path, session_id),
        )
    return bool(changed and changed > 0)


# ─── Read path ────────────────────────────────────────────────────────────────

_COLUMNS = (
    "v.id, v.session_id, v.visitor_id, v.user_id, u.username, v.ip_address, v.country, v.region, v.city, "
    "v.referrer, v.referrer_host, v.source, v.utm_source, v.utm_medium, v.utm_campaign, "
    "v.landing_path, v.exit_path, v.page_count, v.browser, v.os, v.device_type, v.is_bot, "
    "v.language, v.timezone, v.screen_w, v.screen_h, v.user_agent, v.first_seen_at, v.last_seen_at, "
    "(SELECT COUNT(*) FROM site_visits p WHERE p.visitor_id = v.visitor_id "
    "   AND p.first_seen_at < v.first_seen_at) AS earlier_visits"
)
_FROM = "FROM site_visits v LEFT JOIN users u ON u.id = v.user_id"
_HUMAN = "v.is_bot = 0"


def _row_to_visit(r) -> Dict[str, Any]:
    first, last = _parse_ts(r[27]), _parse_ts(r[28])
    duration = int((last - first).total_seconds()) if first and last else 0
    return {
        "id": r[0], "session_id": r[1], "visitor_id": r[2], "user_id": r[3], "username": r[4],
        "ip_address": r[5], "country": r[6], "region": r[7], "city": r[8],
        "referrer": r[9], "referrer_host": r[10], "source": r[11],
        "utm_source": r[12], "utm_medium": r[13], "utm_campaign": r[14],
        "landing_path": r[15], "exit_path": r[16], "page_count": int(r[17] or 0),
        "browser": r[18], "os": r[19], "device_type": r[20], "is_bot": bool(r[21]),
        "language": r[22], "timezone": r[23], "screen_w": r[24], "screen_h": r[25],
        "user_agent": r[26], "first_seen_at": r[27], "last_seen_at": r[28],
        "duration_seconds": max(0, duration),
        "is_returning": bool(r[2]) and int(r[29] or 0) > 0,
    }


def _clamp_days(days: Any) -> int:
    try:
        return max(1, min(int(days), MAX_DAYS))
    except (TypeError, ValueError):
        return 7


def _cutoff(days: int) -> str:
    """First day of a `days`-day window that ends today (UTC)."""
    return (_now() - timedelta(days=days - 1)).strftime("%Y-%m-%d")


def _like(value: str) -> str:
    escaped = value.replace("!", "!!").replace("%", "!%").replace("_", "!_")
    return f"%{escaped}%"


def list_visits(days: int = 7, limit: int = 50, offset: int = 0, q: Optional[str] = None,
                country: Optional[str] = None, kind: str = "all",
                source: Optional[str] = None, live: bool = False,
                user_id: Optional[int] = None) -> Dict[str, Any]:
    """Visit log. With live=True: only sessions seen in the last ACTIVE_WINDOW_SECONDS,
    most recently active first (the date range is ignored)."""
    days = _clamp_days(days)
    try:
        limit = max(1, min(int(limit), MAX_LIMIT))
    except (TypeError, ValueError):
        limit = 50
    try:
        offset = max(0, int(offset))
    except (TypeError, ValueError):
        offset = 0

    if live:
        clauses = ["v.last_seen_at >= ?"]
        params: List[Any] = [_iso(_now() - timedelta(seconds=ACTIVE_WINDOW_SECONDS))]
    else:
        clauses = ["v.date_bucket >= ?"]
        params = [_cutoff(days)]
    order = "v.last_seen_at DESC, v.id DESC" if live else "v.first_seen_at DESC, v.id DESC"
    if user_id is not None:
        clauses.append("v.user_id = ?")
        params.append(int(user_id))
    kind = (kind or "all").strip().lower()
    if kind == "anonymous":
        clauses.append("v.is_bot = 0 AND v.user_id IS NULL")
    elif kind == "user":
        clauses.append("v.is_bot = 0 AND v.user_id IS NOT NULL")
    elif kind == "bot":
        clauses.append("v.is_bot = 1")
    country = (country or "").strip().upper()
    if country:
        clauses.append("v.country = ?")
        params.append(country[:8])
    source = (source or "").strip().lower()
    if source:
        clauses.append("v.source = ?")
        params.append(source[:32])
    q = (q or "").strip()[:100]
    if q:
        like = _like(q)
        clauses.append(
            "(v.ip_address LIKE ? ESCAPE '!' OR u.username LIKE ? ESCAPE '!' OR v.referrer_host LIKE ? ESCAPE '!' "
            "OR v.landing_path LIKE ? ESCAPE '!' OR v.city LIKE ? ESCAPE '!')"
        )
        params.extend([like] * 5)
    where = " AND ".join(clauses)

    total_row = execute_query(f"SELECT COUNT(*) {_FROM} WHERE {where}", tuple(params),
                              fetch_one=True, commit=False)
    rows = execute_query(
        f"SELECT {_COLUMNS} {_FROM} WHERE {where} ORDER BY {order} LIMIT ? OFFSET ?",
        tuple(params + [limit, offset]), fetch_all=True, commit=False,
    )
    return {
        "visits": [_row_to_visit(r) for r in (rows or [])],
        "total": int(total_row[0] or 0) if total_row else 0,
        "limit": limit,
        "offset": offset,
    }


def _top(column: str, cutoff: str, *, null_label: Optional[str], extra: str = "") -> List[Dict[str, Any]]:
    rows = execute_query(
        f"SELECT {column} AS label, COUNT(*) AS n FROM site_visits v "
        f"WHERE {_HUMAN} AND v.date_bucket >= ? {extra} GROUP BY {column} ORDER BY n DESC",
        (cutoff,), fetch_all=True, commit=False,
    ) or []
    merged: Dict[str, int] = {}
    for label, n in rows:
        key = str(label).strip() if label is not None and str(label).strip() else null_label
        if key is None:
            continue
        merged[key] = merged.get(key, 0) + int(n or 0)
    ordered = sorted(merged.items(), key=lambda kv: (-kv[1], kv[0]))
    return [{"label": k, "count": v} for k, v in ordered[:TOP_N]]


def get_summary(days: int = 7) -> Dict[str, Any]:
    days = _clamp_days(days)
    cutoff = _cutoff(days)
    now = _now()
    visitor_key = "COALESCE(v.visitor_id, v.session_id)"

    row = execute_query(
        f"""
        SELECT COUNT(*),
               COUNT(DISTINCT {visitor_key}),
               COUNT(DISTINCT v.ip_address),
               COALESCE(SUM(CASE WHEN v.user_id IS NOT NULL THEN 1 ELSE 0 END), 0),
               COALESCE(SUM(v.page_count), 0)
        FROM site_visits v
        WHERE {_HUMAN} AND v.date_bucket >= ?
        """,
        (cutoff,), fetch_one=True, commit=False,
    ) or (0, 0, 0, 0, 0)
    visits = int(row[0] or 0)
    unique_visitors = int(row[1] or 0)
    signed_in = int(row[3] or 0)
    page_views = int(row[4] or 0)

    bots_row = execute_query(
        "SELECT COUNT(*) FROM site_visits v WHERE v.is_bot = 1 AND v.date_bucket >= ?",
        (cutoff,), fetch_one=True, commit=False,
    )
    active_row = execute_query(
        f"SELECT COUNT(*) FROM site_visits v WHERE {_HUMAN} AND v.last_seen_at >= ?",
        (_iso(now - timedelta(seconds=ACTIVE_WINDOW_SECONDS)),), fetch_one=True, commit=False,
    )
    # Returning: a visitor seen in the window who has more than one visit on record.
    returning_row = execute_query(
        f"""
        SELECT COUNT(*) FROM (
            SELECT {visitor_key} AS k
            FROM site_visits v
            WHERE {_HUMAN}
            GROUP BY {visitor_key}
            HAVING MAX(v.date_bucket) >= ? AND COUNT(*) > 1
        ) t
        """,
        (cutoff,), fetch_one=True, commit=False,
    )
    returning = min(unique_visitors, int(returning_row[0] or 0) if returning_row else 0)

    series_rows = execute_query(
        f"SELECT v.date_bucket, COUNT(*), COUNT(DISTINCT {visitor_key}) FROM site_visits v "
        f"WHERE {_HUMAN} AND v.date_bucket >= ? GROUP BY v.date_bucket",
        (cutoff,), fetch_all=True, commit=False,
    ) or []
    by_day = {str(r[0])[:10]: (int(r[1] or 0), int(r[2] or 0)) for r in series_rows}
    series = []
    for i in range(days - 1, -1, -1):
        day = (now - timedelta(days=i)).strftime("%Y-%m-%d")
        v, uv = by_day.get(day, (0, 0))
        series.append({"date": day, "visits": v, "unique_visitors": uv})

    return {
        "days": days,
        "totals": {
            "visits": visits,
            "unique_visitors": unique_visitors,
            "unique_ips": int(row[2] or 0),
            "signed_in": signed_in,
            "anonymous": visits - signed_in,
            "bots": int(bots_row[0] or 0) if bots_row else 0,
            "page_views": page_views,
            "active_now": int(active_row[0] or 0) if active_row else 0,
            "avg_pages": round(page_views / visits, 2) if visits else 0,
            "new_visitors": unique_visitors - returning,
            "returning_visitors": returning,
        },
        "series": series,
        "top_sources": _top("v.source", cutoff, null_label="direct"),
        "top_referrers": _top("v.referrer_host", cutoff, null_label=None,
                              extra="AND COALESCE(v.source, '') <> 'internal'"),
        "top_countries": _top("v.country", cutoff, null_label="Unknown"),
        "top_pages": _top("v.landing_path", cutoff, null_label="/"),
        "devices": _top("v.device_type", cutoff, null_label="Unknown"),
        "browsers": _top("v.browser", cutoff, null_label="Unknown"),
        "os": _top("v.os", cutoff, null_label="Unknown"),
    }


def get_visit_detail(session_id: str) -> Optional[Dict[str, Any]]:
    session_id = (session_id or "").strip()[:64]
    if not session_id:
        return None
    row = execute_query(f"SELECT {_COLUMNS} {_FROM} WHERE v.session_id = ?", (session_id,),
                        fetch_one=True, commit=False)
    if not row:
        return None
    visit = _row_to_visit(row)

    try:
        page_rows = execute_query(
            "SELECT page, event_name, created_at FROM analytics_events WHERE session_id = ? "
            "ORDER BY created_at ASC, id ASC LIMIT 200",
            (session_id,), fetch_all=True, commit=False,
        ) or []
    except Exception as exc:
        logger.warning("visit page trail failed (non-fatal): %r", exc)
        page_rows = []

    other_rows: List[Tuple] = []
    if visit["visitor_id"]:
        other_rows = execute_query(
            f"SELECT {_COLUMNS} {_FROM} WHERE v.visitor_id = ? AND v.session_id <> ? "
            "ORDER BY v.first_seen_at DESC, v.id DESC LIMIT 10",
            (visit["visitor_id"], session_id), fetch_all=True, commit=False,
        ) or []

    return {
        "visit": visit,
        "pages": [{"page": p[0], "event_name": p[1], "created_at": p[2]} for p in page_rows],
        "other_visits": [_row_to_visit(r) for r in other_rows],
    }
