from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, Optional, Tuple

from db.base import execute_query
from utils.time_utils import now_db_string

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class PromoEffect:
    promo_code_id: int
    code: str
    discount_cents: int
    bonus_credits: int


def _parse_dt(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        # Accept both "YYYY-MM-DD HH:MM:SS" and ISO with 'T'
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except Exception:
        return None


class PromoService:
    def get_promo_by_code(self, code: str) -> Optional[Dict[str, Any]]:
        row = execute_query(
            """
            SELECT
                id, code, type, discount_percentage, discount_amount_cents, bonus_credits,
                max_uses, uses_count, max_uses_per_user, min_purchase_cents,
                valid_from, valid_until, applies_to, is_active
            FROM promo_codes
            WHERE code = ? AND is_active = 1
            """,
            (code.upper(),),
            fetch_one=True,
            commit=False,
        )
        if not row:
            return None
        return {
            "id": int(row[0]),
            "code": str(row[1]),
            "type": str(row[2]),
            "discount_percentage": float(row[3] or 0.0),
            "discount_amount_cents": int(row[4] or 0),
            "bonus_credits": int(row[5] or 0),
            "max_uses": None if row[6] is None else int(row[6]),
            "uses_count": int(row[7] or 0),
            "max_uses_per_user": int(row[8] or 1),
            "min_purchase_cents": int(row[9] or 0),
            "valid_from": row[10],
            "valid_until": row[11],
            "applies_to": str(row[12] or "all"),
            "is_active": int(row[13] or 0) == 1,
        }

    def _user_usage_count(self, promo_code_id: int, user_id: int) -> int:
        row = execute_query(
            "SELECT COUNT(*) FROM promo_code_usage WHERE promo_code_id = ? AND user_id = ?",
            (promo_code_id, user_id),
            fetch_one=True,
            commit=False,
        )
        return int(row[0] or 0) if row else 0

    def validate_and_calculate(
        self,
        *,
        user_id: int,
        code: str,
        subtotal_cents: int,
        applies_to: str,
    ) -> Optional[PromoEffect]:
        promo = self.get_promo_by_code(code)
        if not promo:
            return None

        now = datetime.utcnow()
        valid_from = _parse_dt(promo["valid_from"])
        valid_until = _parse_dt(promo["valid_until"])
        if valid_from and now < valid_from:
            return None
        if valid_until and now > valid_until:
            return None

        if subtotal_cents < promo["min_purchase_cents"]:
            return None

        if promo["applies_to"] not in ("all", applies_to):
            return None

        if promo["max_uses"] is not None and promo["uses_count"] >= promo["max_uses"]:
            return None

        user_uses = self._user_usage_count(promo["id"], user_id)
        if user_uses >= promo["max_uses_per_user"]:
            return None

        discount_cents = 0
        bonus_credits = 0

        if promo["type"] == "percentage_off":
            pct = max(0.0, min(100.0, promo["discount_percentage"]))
            discount_cents = int(round(subtotal_cents * (pct / 100.0)))
        elif promo["type"] == "fixed_amount_off":
            discount_cents = min(subtotal_cents, int(promo["discount_amount_cents"]))
        elif promo["type"] == "bonus_credits":
            bonus_credits = int(promo["bonus_credits"])
        else:
            return None

        return PromoEffect(
            promo_code_id=promo["id"],
            code=promo["code"],
            discount_cents=discount_cents,
            bonus_credits=bonus_credits,
        )

    def record_usage(
        self,
        *,
        promo_code_id: int,
        user_id: int,
        transaction_db_id: Optional[int],
        credits_awarded: int,
        discount_amount_cents: int,
    ) -> int:
        used_at = now_db_string()
        usage_id = execute_query(
            """
            INSERT INTO promo_code_usage (
                promo_code_id, user_id, transaction_id, credits_awarded, discount_amount_cents, used_at
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            (promo_code_id, user_id, transaction_db_id, credits_awarded, discount_amount_cents, used_at),
        )

        execute_query(
            "UPDATE promo_codes SET uses_count = uses_count + 1, updated_at = ? WHERE id = ?",
            (used_at, promo_code_id),
        )
        return int(usage_id)
