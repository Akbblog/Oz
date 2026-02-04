from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

from db.base import execute_query


def _db_type() -> str:
    import os

    return os.getenv("DB_TYPE", "sqlite").lower()


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _fmt_db(dt: datetime) -> str:
    if _db_type() == "mysql":
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    return dt.replace(microsecond=0).isoformat()


def revenue_between_cents(start: datetime, end: datetime) -> int:
    start_s = _fmt_db(start)
    end_s = _fmt_db(end)
    if _db_type() == "sqlite":
        row = execute_query(
            """
            SELECT COALESCE(SUM(amount_cents), 0)
            FROM payment_transactions
            WHERE status = 'completed'
              AND datetime(created_at) >= datetime(?)
              AND datetime(created_at) < datetime(?)
            """,
            (start_s, end_s),
            fetch_one=True,
            commit=False,
        )
    else:
        row = execute_query(
            """
            SELECT COALESCE(SUM(amount_cents), 0)
            FROM payment_transactions
            WHERE status = 'completed'
              AND created_at >= ?
              AND created_at < ?
            """,
            (start_s, end_s),
            fetch_one=True,
            commit=False,
        )
    return int(row[0] or 0) if row else 0


def get_recent_transactions(limit: int = 25) -> List[Dict[str, Any]]:
    rows = execute_query(
        """
        SELECT pt.transaction_id, pt.user_id, pt.payment_provider, pt.amount_cents, pt.currency,
               pt.status, pt.created_at, u.username, u.email
        FROM payment_transactions pt
        JOIN users u ON u.id = pt.user_id
        ORDER BY pt.created_at DESC
        LIMIT ?
        """,
        (limit,),
        fetch_all=True,
        commit=False,
    )
    out: List[Dict[str, Any]] = []
    for r in rows or []:
        out.append(
            {
                "transaction_id": r[0],
                "user_id": r[1],
                "payment_provider": r[2],
                "amount_cents": r[3],
                "currency": r[4],
                "status": r[5],
                "created_at": r[6],
                "username": r[7],
                "email": r[8],
            }
        )
    return out


def get_top_customers(limit: int = 10) -> List[Dict[str, Any]]:
    rows = execute_query(
        """
        SELECT u.id, u.username, u.email,
               COALESCE(SUM(pt.amount_cents), 0) AS spent_cents,
               COALESCE(SUM(pt.credits_purchased), 0) AS credits
        FROM users u
        LEFT JOIN payment_transactions pt
          ON pt.user_id = u.id AND pt.status = 'completed'
        GROUP BY u.id, u.username, u.email
        ORDER BY spent_cents DESC
        LIMIT ?
        """,
        (limit,),
        fetch_all=True,
        commit=False,
    )
    out: List[Dict[str, Any]] = []
    for r in rows or []:
        out.append(
            {
                "user_id": r[0],
                "username": r[1],
                "email": r[2],
                "spent_cents": int(r[3] or 0),
                "credits_purchased": int(r[4] or 0),
            }
        )
    return out


def get_mrr_cents() -> int:
    """
    Approximate MRR from currently active/trialing subscriptions.
    For yearly plans, divide by 12.
    """
    rows = execute_query(
        """
        SELECT sp.billing_interval, sp.base_price_cents
        FROM user_subscriptions us
        JOIN subscription_plans sp ON sp.id = us.subscription_plan_id
        WHERE us.status IN ('active', 'trialing') AND sp.is_active = 1
        """,
        fetch_all=True,
        commit=False,
    )
    total = 0
    for r in rows or []:
        interval = str(r[0] or "monthly")
        price = int(r[1] or 0)
        if interval == "yearly":
            total += int(round(price / 12.0))
        else:
            total += price
    return total


def get_conversion_funnel() -> Dict[str, int]:
    total_users = execute_query("SELECT COUNT(*) FROM users", fetch_one=True, commit=False)
    approved = execute_query("SELECT COUNT(*) FROM users WHERE is_approved = 1", fetch_one=True, commit=False)
    purchasers = execute_query(
        "SELECT COUNT(DISTINCT user_id) FROM payment_transactions WHERE status = 'completed'",
        fetch_one=True,
        commit=False,
    )
    return {
        "registered_users": int(total_users[0] or 0) if total_users else 0,
        "approved_users": int(approved[0] or 0) if approved else 0,
        "purchasers": int(purchasers[0] or 0) if purchasers else 0,
    }


def get_revenue_dashboard() -> Dict[str, Any]:
    now = _now_utc()
    start_today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    start_week = start_today - timedelta(days=7)
    start_month = start_today - timedelta(days=30)

    revenue_today = revenue_between_cents(start_today, now)
    revenue_week = revenue_between_cents(start_week, now)
    revenue_month = revenue_between_cents(start_month, now)
    mrr = get_mrr_cents()

    active_subs = execute_query(
        "SELECT COUNT(*) FROM user_subscriptions WHERE status IN ('active', 'trialing')",
        fetch_one=True,
        commit=False,
    )

    return {
        "revenue_today_cents": revenue_today,
        "revenue_last_7d_cents": revenue_week,
        "revenue_last_30d_cents": revenue_month,
        "mrr_cents": mrr,
        "active_subscriptions": int(active_subs[0] or 0) if active_subs else 0,
        "top_customers": get_top_customers(limit=10),
        "recent_transactions": get_recent_transactions(limit=25),
        "conversion_funnel": get_conversion_funnel(),
    }


def get_mrr_series(months: int = 6) -> List[Dict[str, Any]]:
    """
    Simple series for charting: repeats current MRR for past months (no history table yet).
    """
    now = _now_utc()
    mrr = get_mrr_cents()
    out = []
    for i in range(months - 1, -1, -1):
        dt = now - timedelta(days=30 * i)
        label = dt.strftime("%Y-%m")
        out.append({"month": label, "mrr_cents": mrr})
    return out


def get_churn_summary() -> Dict[str, Any]:
    """
    Approximate churn over last 30 days using user_subscriptions.updated_at and status.
    """
    now = _now_utc()
    start = now - timedelta(days=30)
    start_s = _fmt_db(start)

    if _db_type() == "sqlite":
        canceled_row = execute_query(
            """
            SELECT COUNT(*)
            FROM user_subscriptions
            WHERE status = 'canceled' AND datetime(updated_at) >= datetime(?)
            """,
            (start_s,),
            fetch_one=True,
            commit=False,
        )
    else:
        canceled_row = execute_query(
            """
            SELECT COUNT(*)
            FROM user_subscriptions
            WHERE status = 'canceled' AND updated_at >= ?
            """,
            (start_s,),
            fetch_one=True,
            commit=False,
        )

    active_row = execute_query(
        "SELECT COUNT(*) FROM user_subscriptions WHERE status IN ('active', 'trialing')",
        fetch_one=True,
        commit=False,
    )

    canceled = int(canceled_row[0] or 0) if canceled_row else 0
    active = int(active_row[0] or 0) if active_row else 0
    denom = max(1, active + canceled)
    churn_rate = canceled / denom

    return {"canceled_last_30d": canceled, "active": active, "churn_rate": churn_rate}

