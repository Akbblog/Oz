from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List

from db.base import execute_query


def _db_type() -> str:
    import os

    return os.getenv("DB_TYPE", "sqlite").lower()


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _fmt_db(dt: datetime) -> str:
    if _db_type() == "mysql":
        return dt.strftime("%Y-%m-%d %H:%M:%S")
    return dt.replace(microsecond=0).isoformat()


def get_spending_series(user_id: int, months: int = 6) -> List[Dict[str, Any]]:
    now = _now()
    out: List[Dict[str, Any]] = []
    for i in range(months - 1, -1, -1):
        start = (now - timedelta(days=30 * (i + 1))).replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        end = (now - timedelta(days=30 * i)).replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        start_s = _fmt_db(start)
        end_s = _fmt_db(end)

        if _db_type() == "sqlite":
            row = execute_query(
                """
                SELECT COALESCE(SUM(amount_cents), 0)
                FROM payment_transactions
                WHERE user_id = ? AND status = 'completed'
                  AND datetime(created_at) >= datetime(?)
                  AND datetime(created_at) < datetime(?)
                """,
                (user_id, start_s, end_s),
                fetch_one=True,
                commit=False,
            )
        else:
            row = execute_query(
                """
                SELECT COALESCE(SUM(amount_cents), 0)
                FROM payment_transactions
                WHERE user_id = ? AND status = 'completed'
                  AND created_at >= ?
                  AND created_at < ?
                """,
                (user_id, start_s, end_s),
                fetch_one=True,
                commit=False,
            )

        cents = int(row[0] or 0) if row else 0
        out.append({"month": end.strftime("%Y-%m"), "spent_cents": cents})
    return out


def get_usage_summary(user_id: int, days: int = 30) -> Dict[str, Any]:
    start = _now() - timedelta(days=days)
    start_s = _fmt_db(start)

    if _db_type() == "sqlite":
        credits_spent = execute_query(
            """
            SELECT COALESCE(SUM(-amount), 0)
            FROM credit_ledger
            WHERE user_id = ? AND amount < 0 AND datetime(created_at) >= datetime(?)
            """,
            (user_id, start_s),
            fetch_one=True,
            commit=False,
        )
        credits_earned = execute_query(
            """
            SELECT COALESCE(SUM(amount), 0)
            FROM credit_ledger
            WHERE user_id = ? AND amount > 0 AND datetime(created_at) >= datetime(?)
            """,
            (user_id, start_s),
            fetch_one=True,
            commit=False,
        )
    else:
        credits_spent = execute_query(
            """
            SELECT COALESCE(SUM(-amount), 0)
            FROM credit_ledger
            WHERE user_id = ? AND amount < 0 AND created_at >= ?
            """,
            (user_id, start_s),
            fetch_one=True,
            commit=False,
        )
        credits_earned = execute_query(
            """
            SELECT COALESCE(SUM(amount), 0)
            FROM credit_ledger
            WHERE user_id = ? AND amount > 0 AND created_at >= ?
            """,
            (user_id, start_s),
            fetch_one=True,
            commit=False,
        )

    jobs_row = execute_query(
        "SELECT COUNT(*) FROM jobs WHERE user_id = ?",
        (user_id,),
        fetch_one=True,
        commit=False,
    )

    return {
        "days": days,
        "credits_spent": int(credits_spent[0] or 0) if credits_spent else 0,
        "credits_earned": int(credits_earned[0] or 0) if credits_earned else 0,
        "total_jobs": int(jobs_row[0] or 0) if jobs_row else 0,
    }

