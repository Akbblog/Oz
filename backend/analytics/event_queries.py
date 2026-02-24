"""
analytics/event_queries.py — Read-only aggregation queries for the Analytics Dashboard.

All functions return plain dicts/lists — no ORM, no side effects.
Designed for the admin /api/admin/analytics/* endpoints.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from db.base import execute_query


# ─── Helpers ──────────────────────────────────────────────────────────────────

def _cutoff_date(days: int) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%d")


def _rows(sql: str, params=None, *, fetch_all: bool = True):
    return execute_query(sql, params, fetch_all=fetch_all, commit=False) or []


# ─── DAU / MAU ────────────────────────────────────────────────────────────────

def get_dau(days: int = 30) -> List[Dict[str, Any]]:
    """
    Daily Active Users for the last N days.
    Returns [{date, dau, sessions, events}] sorted ascending.
    """
    cutoff = _cutoff_date(days)
    rows = _rows(
        """
        SELECT date_bucket,
               COUNT(DISTINCT user_id)   AS dau,
               COUNT(DISTINCT session_id) AS sessions,
               COUNT(*)                   AS events
        FROM   analytics_events
        WHERE  date_bucket >= ?
          AND  user_id IS NOT NULL
        GROUP  BY date_bucket
        ORDER  BY date_bucket
        """,
        (cutoff,),
    )
    return [{"date": r[0], "dau": r[1], "sessions": r[2], "events": r[3]} for r in rows]


def get_mau(months: int = 12) -> List[Dict[str, Any]]:
    """
    Monthly Active Users for the last N months.
    Returns [{month, mau}] — month is 'YYYY-MM'.
    """
    cutoff = _cutoff_date(months * 31)
    rows = _rows(
        """
        SELECT substr(date_bucket, 1, 7)  AS month,
               COUNT(DISTINCT user_id)    AS mau
        FROM   analytics_events
        WHERE  date_bucket >= ?
          AND  user_id IS NOT NULL
        GROUP  BY month
        ORDER  BY month
        """,
        (cutoff,),
    )
    return [{"month": r[0], "mau": r[1]} for r in rows]


# ─── Retention ────────────────────────────────────────────────────────────────

def get_retention(days: int = 30) -> List[Dict[str, Any]]:
    """
    Week-0 retention: for each cohort day (users who first appeared on date D),
    what fraction returned on D+1, D+7, D+30?

    Returns [{cohort_date, cohort_size, d1, d7, d30}]
    This is an approximation using first-seen date as cohort anchor.
    """
    cutoff = _cutoff_date(days)

    # Step 1: first-seen date per user
    first_seen = _rows(
        """
        SELECT user_id, MIN(date_bucket) AS first_date
        FROM   analytics_events
        WHERE  user_id IS NOT NULL
          AND  date_bucket >= ?
        GROUP  BY user_id
        """,
        (cutoff,),
    )
    if not first_seen:
        return []

    # Step 2: all (user_id, date_bucket) pairs for activity
    activity = _rows(
        """
        SELECT DISTINCT user_id, date_bucket
        FROM   analytics_events
        WHERE  user_id IS NOT NULL
          AND  date_bucket >= ?
        """,
        (cutoff,),
    )
    activity_set = {(r[0], r[1]) for r in activity}

    # Step 3: group by cohort_date
    cohorts: Dict[str, Dict] = {}
    for user_id, first_date in first_seen:
        c = cohorts.setdefault(first_date, {"size": 0, "d1": 0, "d7": 0, "d30": 0})
        c["size"] += 1
        from datetime import date as _date
        try:
            fd = _date.fromisoformat(first_date)
            if (user_id, (fd + timedelta(days=1)).isoformat())  in activity_set: c["d1"]  += 1
            if (user_id, (fd + timedelta(days=7)).isoformat())  in activity_set: c["d7"]  += 1
            if (user_id, (fd + timedelta(days=30)).isoformat()) in activity_set: c["d30"] += 1
        except ValueError:
            pass

    return [
        {
            "cohort_date":  dt,
            "cohort_size":  v["size"],
            "d1_retained":  v["d1"],
            "d7_retained":  v["d7"],
            "d30_retained": v["d30"],
            "d1_rate":  round(v["d1"]  / v["size"] * 100, 1) if v["size"] else 0,
            "d7_rate":  round(v["d7"]  / v["size"] * 100, 1) if v["size"] else 0,
            "d30_rate": round(v["d30"] / v["size"] * 100, 1) if v["size"] else 0,
        }
        for dt, v in sorted(cohorts.items())
    ]


# ─── Feature Adoption ─────────────────────────────────────────────────────────

def get_feature_adoption(days: int = 30) -> List[Dict[str, Any]]:
    """
    Feature tab usage for last N days.
    Returns [{feature, uses, unique_users}] sorted by uses desc.
    """
    cutoff = _cutoff_date(days)
    rows = _rows(
        """
        SELECT feature,
               COUNT(*)                   AS uses,
               COUNT(DISTINCT user_id)    AS unique_users
        FROM   analytics_events
        WHERE  event_name = 'feature_use'
          AND  feature IS NOT NULL
          AND  date_bucket >= ?
        GROUP  BY feature
        ORDER  BY uses DESC
        """,
        (cutoff,),
    )
    return [{"feature": r[0], "uses": r[1], "unique_users": r[2]} for r in rows]


# ─── Top Pages ────────────────────────────────────────────────────────────────

def get_top_pages(days: int = 30, limit: int = 20) -> List[Dict[str, Any]]:
    """Page views ranked by unique visitors."""
    cutoff = _cutoff_date(days)
    rows = _rows(
        """
        SELECT page,
               COUNT(*)                 AS views,
               COUNT(DISTINCT user_id)  AS unique_users,
               COUNT(DISTINCT session_id) AS sessions
        FROM   analytics_events
        WHERE  event_name = 'page_view'
          AND  page IS NOT NULL
          AND  date_bucket >= ?
        GROUP  BY page
        ORDER  BY views DESC
        LIMIT  ?
        """,
        (cutoff, limit),
    )
    return [{"page": r[0], "views": r[1], "unique_users": r[2], "sessions": r[3]} for r in rows]


# ─── Click Heatmap ────────────────────────────────────────────────────────────

def get_heatmap_data(page: str, days: int = 30) -> List[Dict[str, Any]]:
    """
    Click coordinates for a specific page.
    Returns [{x, y, element, count}] — client renders as heatmap overlay.
    x/y are % of viewport (0-100).
    """
    cutoff = _cutoff_date(days)
    rows = _rows(
        """
        SELECT click_x, click_y, element, COUNT(*) AS cnt
        FROM   analytics_events
        WHERE  event_name = 'click'
          AND  page = ?
          AND  click_x IS NOT NULL
          AND  date_bucket >= ?
        GROUP  BY ROUND(click_x), ROUND(click_y), element
        ORDER  BY cnt DESC
        LIMIT  500
        """,
        (page, cutoff),
    )
    return [{"x": r[0], "y": r[1], "element": r[2], "count": r[3]} for r in rows]


# ─── Top Clicked Elements ─────────────────────────────────────────────────────

def get_top_clicks(days: int = 30, limit: int = 25) -> List[Dict[str, Any]]:
    """Most-clicked [data-track] elements across all pages."""
    cutoff = _cutoff_date(days)
    rows = _rows(
        """
        SELECT element, page, COUNT(*) AS clicks, COUNT(DISTINCT user_id) AS unique_users
        FROM   analytics_events
        WHERE  event_name = 'click'
          AND  element IS NOT NULL
          AND  date_bucket >= ?
        GROUP  BY element, page
        ORDER  BY clicks DESC
        LIMIT  ?
        """,
        (cutoff, limit),
    )
    return [{"element": r[0], "page": r[1], "clicks": r[2], "unique_users": r[3]} for r in rows]


# ─── Conversion Funnel ────────────────────────────────────────────────────────

def get_conversion_funnel(days: int = 90) -> List[Dict[str, Any]]:
    """
    Classic 4-step conversion funnel:
      Landing → Registration → First Search → Credit Purchase

    Each step counts distinct users (or sessions for anonymous landing).
    Drop-off % is calculated relative to the previous step.
    """
    cutoff = _cutoff_date(days)

    steps = [
        (
            "Landing",
            execute_query(
                """
                SELECT COUNT(DISTINCT COALESCE(CAST(user_id AS TEXT), session_id))
                FROM   analytics_events
                WHERE  event_name = 'page_view'
                  AND  date_bucket >= ?
                """,
                (cutoff,), fetch_one=True, commit=False,
            ),
        ),
        (
            "Registration",
            execute_query(
                "SELECT COUNT(DISTINCT user_id) FROM analytics_events WHERE event_name = 'register' AND user_id IS NOT NULL AND date_bucket >= ?",
                (cutoff,), fetch_one=True, commit=False,
            ),
        ),
        (
            "First Search",
            execute_query(
                "SELECT COUNT(DISTINCT user_id) FROM analytics_events WHERE event_name = 'search_start' AND user_id IS NOT NULL AND date_bucket >= ?",
                (cutoff,), fetch_one=True, commit=False,
            ),
        ),
        (
            "Credit Purchase",
            execute_query(
                "SELECT COUNT(DISTINCT user_id) FROM analytics_events WHERE event_name = 'credit_purchase' AND user_id IS NOT NULL AND date_bucket >= ?",
                (cutoff,), fetch_one=True, commit=False,
            ),
        ),
    ]

    result = []
    prev_count = None
    for label, row in steps:
        count = int(row[0]) if row and row[0] else 0
        drop_pct = None
        if prev_count is not None and prev_count > 0:
            drop_pct = round((1 - count / prev_count) * 100, 1)
        result.append({"step": label, "count": count, "drop_off_pct": drop_pct})
        prev_count = count

    return result


# ─── Credit Usage Patterns ────────────────────────────────────────────────────

def get_credit_usage_over_time(days: int = 30) -> List[Dict[str, Any]]:
    """
    Credit debits and purchases bucketed by day.
    Pulls from credit_ledger (source of truth), not analytics_events.
    Returns [{date, consumed, purchased, net}].
    """
    cutoff = (datetime.now(timezone.utc) - timedelta(days=days)).strftime("%Y-%m-%d")
    rows = _rows(
        """
        SELECT DATE(created_at)                             AS day,
               COALESCE(SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END), 0) AS consumed,
               COALESCE(SUM(CASE WHEN amount > 0 THEN amount  ELSE 0 END), 0) AS purchased
        FROM   credit_ledger
        WHERE  DATE(created_at) >= ?
        GROUP  BY day
        ORDER  BY day
        """,
        (cutoff,),
    )
    return [
        {
            "date":      r[0],
            "consumed":  int(r[1]),
            "purchased": int(r[2]),
            "net":       int(r[2]) - int(r[1]),
        }
        for r in rows
    ]


# ─── Session Stats ────────────────────────────────────────────────────────────

def get_session_stats(days: int = 30) -> Dict[str, Any]:
    """
    Aggregate session metrics: avg duration, bounce rate, total sessions.
    Duration is estimated as (last_event - first_event) per session.
    Bounce = sessions with only 1 event.
    """
    cutoff = _cutoff_date(days)

    row = execute_query(
        """
        SELECT COUNT(DISTINCT session_id)  AS total_sessions,
               COUNT(*)                    AS total_events
        FROM   analytics_events
        WHERE  date_bucket >= ?
        """,
        (cutoff,), fetch_one=True, commit=False,
    ) or (0, 0)

    bounce_row = execute_query(
        """
        SELECT COUNT(*) FROM (
            SELECT session_id
            FROM   analytics_events
            WHERE  date_bucket >= ?
            GROUP  BY session_id
            HAVING COUNT(*) = 1
        ) single
        """,
        (cutoff,), fetch_one=True, commit=False,
    ) or (0,)

    total_sessions = int(row[0]) if row[0] else 0
    bounce_sessions = int(bounce_row[0]) if bounce_row[0] else 0
    bounce_rate = round(bounce_sessions / total_sessions * 100, 1) if total_sessions else 0

    return {
        "total_sessions": total_sessions,
        "total_events":   int(row[1]) if row[1] else 0,
        "bounce_sessions": bounce_sessions,
        "bounce_rate_pct": bounce_rate,
    }


# ─── User Journey (path analysis) ────────────────────────────────────────────

def get_user_journey(user_id: int, limit: int = 100) -> List[Dict[str, Any]]:
    """
    Ordered sequence of events for a single user — their full journey timeline.
    """
    rows = _rows(
        """
        SELECT event_name, page, element, feature, extra_json, created_at
        FROM   analytics_events
        WHERE  user_id = ?
        ORDER  BY created_at DESC
        LIMIT  ?
        """,
        (user_id, limit),
    )
    return [
        {
            "event":   r[0],
            "page":    r[1],
            "element": r[2],
            "feature": r[3],
            "extra":   r[4],
            "time":    r[5],
        }
        for r in rows
    ]
