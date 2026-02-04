from __future__ import annotations

import json
import logging
from dataclasses import dataclass
from typing import Any, Dict, Optional, Tuple

from db.base import execute_query
from promotions.promo_service import PromoEffect, PromoService
from utils.tax_calculator import calculate_tax_cents

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class PricingTier:
    id: int
    name: str
    price_per_credit_cents: float
    discount_percentage: float
    requires_approval: bool


class PricingEngine:
    def __init__(self) -> None:
        self._promo_service = PromoService()

    def _get_user_billing_address(self, user_id: int) -> Optional[Dict[str, Any]]:
        row = execute_query(
            "SELECT billing_address FROM users WHERE id = ?",
            (user_id,),
            fetch_one=True,
            commit=False,
        )
        if not row or not row[0]:
            return None
        try:
            return json.loads(row[0]) if isinstance(row[0], str) else row[0]
        except Exception:
            return None

    def _get_user_forced_tier_id(self, user_id: int) -> Optional[int]:
        row = execute_query(
            "SELECT pricing_tier_id FROM users WHERE id = ?",
            (user_id,),
            fetch_one=True,
            commit=False,
        )
        if not row:
            return None
        return None if row[0] is None else int(row[0])

    def _get_monthly_credits_purchased(self, user_id: int) -> int:
        # SQLite: created_at is typically TEXT; datetime(created_at) works for "YYYY-MM-DDTHH:MM:SS" and "YYYY-MM-DD HH:MM:SS"
        row = execute_query(
            """
            SELECT COALESCE(SUM(credits_purchased), 0)
            FROM payment_transactions
            WHERE user_id = ?
              AND status = 'completed'
              AND datetime(created_at) >= datetime('now', '-30 days')
            """,
            (user_id,),
            fetch_one=True,
            commit=False,
        )
        return int(row[0] or 0) if row else 0

    def get_user_pricing_tier(self, user_id: int) -> Optional[PricingTier]:
        forced_tier_id = self._get_user_forced_tier_id(user_id)
        rows = execute_query(
            """
            SELECT id, name, min_monthly_credits, max_monthly_credits,
                   price_per_credit_cents, discount_percentage, requires_approval
            FROM pricing_tiers
            WHERE is_active = 1
            ORDER BY min_monthly_credits ASC
            """,
            fetch_all=True,
            commit=False,
        )
        if not rows:
            return None

        monthly_credits = self._get_monthly_credits_purchased(user_id)
        chosen: Optional[Tuple[Any, ...]] = None

        # If user is explicitly assigned a tier, use it even if it requires approval.
        if forced_tier_id is not None:
            for row in rows:
                if int(row[0]) == forced_tier_id:
                    chosen = row
                    break

        if chosen is None:
            for row in rows:
                tier_id = int(row[0])
                min_c = int(row[2] or 0)
                max_c = None if row[3] is None else int(row[3])
                requires_approval = int(row[6] or 0) == 1
                if requires_approval:
                    continue
                if monthly_credits < min_c:
                    continue
                if max_c is not None and monthly_credits > max_c:
                    continue
                chosen = row
                break

        if chosen is None:
            # Default to the first non-approval tier.
            for row in rows:
                if int(row[6] or 0) == 0:
                    chosen = row
                    break

        if chosen is None:
            return None

        return PricingTier(
            id=int(chosen[0]),
            name=str(chosen[1]),
            price_per_credit_cents=float(chosen[4]),
            discount_percentage=float(chosen[5] or 0.0),
            requires_approval=int(chosen[6] or 0) == 1,
        )

    def calculate_for_package(
        self,
        *,
        user_id: int,
        package_id: int,
        quantity: int = 1,
        promo_code: Optional[str] = None,
    ) -> Dict[str, Any]:
        package = execute_query(
            """
            SELECT id, credits, base_price_cents, discount_percentage
            FROM credit_packages
            WHERE id = ? AND is_active = 1
            """,
            (package_id,),
            fetch_one=True,
            commit=False,
        )
        if not package:
            raise ValueError("Package not found")

        credits = int(package[1])
        base_price_cents = int(package[2])
        pkg_discount_pct = float(package[3] or 0.0)

        tier = self.get_user_pricing_tier(user_id)
        if tier:
            tier_subtotal = int(round(credits * tier.price_per_credit_cents)) * quantity
        else:
            tier_subtotal = base_price_cents * quantity

        subtotal = tier_subtotal

        # Apply package discount (marketing discount)
        if pkg_discount_pct > 0:
            subtotal = max(0, subtotal - int(round(subtotal * (pkg_discount_pct / 100.0))))

        # Apply tier discount
        if tier and tier.discount_percentage > 0:
            subtotal = max(0, subtotal - int(round(subtotal * (tier.discount_percentage / 100.0))))

        promo_effect: Optional[PromoEffect] = None
        promo_discount = 0
        bonus_credits = 0
        if promo_code:
            promo_effect = self._promo_service.validate_and_calculate(
                user_id=user_id,
                code=promo_code,
                subtotal_cents=subtotal,
                applies_to="packages",
            )
            if promo_effect:
                promo_discount = promo_effect.discount_cents
                bonus_credits = promo_effect.bonus_credits

        discounted_subtotal = max(0, subtotal - promo_discount)

        tax_cents, tax_label = calculate_tax_cents(
            subtotal_cents=discounted_subtotal,
            billing_address=self._get_user_billing_address(user_id),
        )

        total = discounted_subtotal + tax_cents

        return {
            "subtotal_cents": subtotal,
            "discount_cents": promo_discount,
            "tax_cents": tax_cents,
            "tax_label": tax_label,
            "total_cents": total,
            "credits_to_receive": credits * quantity,
            "bonus_credits": bonus_credits,
            "promo": promo_effect,
            "tier": tier,
        }

