import csv
import io
import random
import string
from typing import Any, Dict, Optional

from db.base import execute_query


def generate_random_promo_code(prefix: str = "SAVE", suffix_length: int = 4) -> str:
    """Auto-generate a unique promo code like SAVE2045."""
    safe_prefix = (prefix or "").strip().upper()
    if not safe_prefix:
        safe_prefix = "SAVE"
    suffix_length = max(1, int(suffix_length))

    for _ in range(50):
        suffix = "".join(random.choices(string.digits, k=suffix_length))
        code = f"{safe_prefix}{suffix}"
        exists = execute_query(
            "SELECT 1 FROM promo_codes WHERE code = ? LIMIT 1",
            (code,),
            fetch_one=True,
            commit=False,
        )
        if not exists:
            return code

    raise RuntimeError("Unable to generate a unique promo code after 50 attempts")


def get_promo_analytics(promo_id: int) -> Dict[str, Any]:
    """Get basic analytics for a promo (uses, discount totals, credits awarded)."""
    promo_row = execute_query(
        """
        SELECT
            id, code, type, discount_percentage, discount_amount_cents, bonus_credits,
            max_uses, uses_count, max_uses_per_user, min_purchase_cents,
            valid_from, valid_until, applies_to, is_active, created_at, updated_at
        FROM promo_codes
        WHERE id = ?
        """,
        (int(promo_id),),
        fetch_one=True,
        commit=False,
    )
    if not promo_row:
        raise ValueError("Promo not found")

    usage_row = execute_query(
        """
        SELECT
            COUNT(*),
            COALESCE(SUM(discount_amount_cents), 0),
            COALESCE(SUM(credits_awarded), 0),
            COUNT(DISTINCT user_id)
        FROM promo_code_usage
        WHERE promo_code_id = ?
        """,
        (int(promo_id),),
        fetch_one=True,
        commit=False,
    )
    uses = int((usage_row or [0])[0] or 0)
    discount_total_cents = int((usage_row or [0, 0])[1] or 0)
    credits_awarded = int((usage_row or [0, 0, 0])[2] or 0)
    users_who_used = int((usage_row or [0, 0, 0, 0])[3] or 0)

    return {
        "promo": {
            "id": promo_row[0],
            "code": promo_row[1],
            "type": promo_row[2],
            "discount_percentage": promo_row[3],
            "discount_amount_cents": promo_row[4],
            "bonus_credits": promo_row[5],
            "max_uses": promo_row[6],
            "uses_count": promo_row[7],
            "max_uses_per_user": promo_row[8],
            "min_purchase_cents": promo_row[9],
            "valid_from": promo_row[10],
            "valid_until": promo_row[11],
            "applies_to": promo_row[12],
            "is_active": bool(promo_row[13]),
            "created_at": promo_row[14],
            "updated_at": promo_row[15],
        },
        "usage": {
            "uses": uses,
            "discount_amount_cents": discount_total_cents,
            "credits_awarded": credits_awarded,
            "users_who_used": users_who_used,
        },
    }


def calculate_promotion_roi(promo_id: int) -> Dict[str, float]:
    """
    Calculate rough ROI for a promo.

    Notes:
    - Revenue is computed as the sum of `payment_transactions.amount_cents` for transactions linked in `promo_code_usage`.
    - Cost is `promo_code_usage.discount_amount_cents` (may be 0 depending on how usage is recorded).
    """
    row = execute_query(
        """
        SELECT
            COALESCE(SUM(t.amount_cents), 0) AS revenue_cents,
            COALESCE(SUM(u.discount_amount_cents), 0) AS discount_cents
        FROM promo_code_usage u
        LEFT JOIN payment_transactions t ON t.id = u.transaction_id
        WHERE u.promo_code_id = ?
        """,
        (int(promo_id),),
        fetch_one=True,
        commit=False,
    )
    revenue_cents = float(row[0] or 0) if row else 0.0
    discount_cents = float(row[1] or 0) if row else 0.0

    net_revenue_cents = max(0.0, revenue_cents - discount_cents)
    roi_ratio = (net_revenue_cents / discount_cents) if discount_cents > 0 else 0.0

    return {
        "revenue_cents": revenue_cents,
        "discount_cents": discount_cents,
        "net_revenue_cents": net_revenue_cents,
        "roi_ratio": roi_ratio,
    }


def export_promo_codes(format: str = "csv") -> str:
    """Export promo codes for backup/analysis. Currently supports CSV."""
    fmt = (format or "csv").strip().lower()
    if fmt != "csv":
        raise ValueError("Only 'csv' export is supported")

    rows = execute_query(
        """
        SELECT
            id, code, type, discount_percentage, discount_amount_cents, bonus_credits,
            max_uses, uses_count, max_uses_per_user, min_purchase_cents,
            valid_from, valid_until, applies_to, is_active, created_at, updated_at
        FROM promo_codes
        ORDER BY created_at DESC
        """,
        fetch_all=True,
        commit=False,
    ) or []

    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(
        [
            "id",
            "code",
            "type",
            "discount_percentage",
            "discount_amount_cents",
            "bonus_credits",
            "max_uses",
            "uses_count",
            "max_uses_per_user",
            "min_purchase_cents",
            "valid_from",
            "valid_until",
            "applies_to",
            "is_active",
            "created_at",
            "updated_at",
        ]
    )
    for r in rows:
        writer.writerow(list(r))
    return buf.getvalue()

