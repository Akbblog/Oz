from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Dict, Optional

from db.base import execute_query
from payments.stripe_service import StripeService
from utils.time_utils import now_db_string

logger = logging.getLogger(__name__)


def _ts_to_iso(ts: Optional[int]) -> Optional[str]:
    if not ts:
        return None
    return datetime.fromtimestamp(int(ts), tz=timezone.utc).replace(microsecond=0).isoformat()


class SubscriptionManager:
    def __init__(self) -> None:
        self._stripe = StripeService()

    def get_plan(self, plan_id: int) -> Dict[str, Any]:
        row = execute_query(
            """
            SELECT id, name, billing_interval, credits_per_period, base_price_cents,
                   stripe_price_id, rollover_credits, max_rollover_credits, trial_days, is_active
            FROM subscription_plans
            WHERE id = ? AND is_active = 1
            """,
            (plan_id,),
            fetch_one=True,
            commit=False,
        )
        if not row:
            raise ValueError("Plan not found")
        return {
            "id": int(row[0]),
            "name": str(row[1]),
            "billing_interval": str(row[2]),
            "credits_per_period": int(row[3]),
            "base_price_cents": int(row[4]),
            "stripe_price_id": str(row[5] or ""),
            "rollover_credits": int(row[6] or 0) == 1,
            "max_rollover_credits": int(row[7] or 0),
            "trial_days": int(row[8] or 0),
        }

    def create_subscription(
        self,
        *,
        user_id: int,
        email: str,
        plan_id: int,
        idempotency_key: str,
    ) -> Dict[str, Any]:
        plan = self.get_plan(plan_id)
        if not plan["stripe_price_id"]:
            raise ValueError("Plan is not configured with a Stripe price")

        sub = self._stripe.create_subscription(
            user_id=user_id,
            email=email,
            stripe_price_id=plan["stripe_price_id"],
            idempotency_key=idempotency_key,
            metadata={"subscription_plan_id": str(plan_id)},
            trial_period_days=plan["trial_days"] or None,
        )

        stripe_sub_id = str(sub["id"])
        status = str(sub.get("status") or "active")
        cps = _ts_to_iso(sub.get("current_period_start"))
        cpe = _ts_to_iso(sub.get("current_period_end"))

        now = now_db_string()
        sub_db_id = execute_query(
            """
            INSERT INTO user_subscriptions (
                user_id, subscription_plan_id, stripe_subscription_id, status,
                current_period_start, current_period_end, next_billing_date,
                cancel_at_period_end, credits_allocated_this_period, credits_used_this_period, credits_rolled_over,
                created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                plan_id,
                stripe_sub_id,
                status,
                cps,
                cpe,
                cpe,
                0,
                0,
                0,
                0,
                now,
                now,
            ),
        )

        latest_invoice = sub.get("latest_invoice") or {}
        payment_intent = (latest_invoice.get("payment_intent") or {}) if isinstance(latest_invoice, dict) else {}

        return {
            "user_subscription_id": int(sub_db_id),
            "stripe_subscription_id": stripe_sub_id,
            "status": status,
            "client_secret": payment_intent.get("client_secret"),
        }

    def cancel(self, stripe_subscription_id: str, *, at_period_end: bool) -> Dict[str, Any]:
        sub = self._stripe.cancel_subscription(stripe_subscription_id, at_period_end=at_period_end)
        execute_query(
            """
            UPDATE user_subscriptions
            SET status = ?, cancel_at_period_end = ?, updated_at = ?
            WHERE stripe_subscription_id = ?
            """,
            (str(sub.get("status") or "canceled"), 1 if at_period_end else 0, now_db_string(), stripe_subscription_id),
        )
        return sub

    def pause(self, stripe_subscription_id: str) -> Dict[str, Any]:
        sub = self._stripe.pause_subscription(stripe_subscription_id)
        execute_query(
            """
            UPDATE user_subscriptions
            SET status = 'paused', updated_at = ?
            WHERE stripe_subscription_id = ?
            """,
            (now_db_string(), stripe_subscription_id),
        )
        return sub

    def resume(self, stripe_subscription_id: str) -> Dict[str, Any]:
        sub = self._stripe.resume_subscription(stripe_subscription_id)
        execute_query(
            """
            UPDATE user_subscriptions
            SET status = ?, updated_at = ?
            WHERE stripe_subscription_id = ?
            """,
            (str(sub.get("status") or "active"), now_db_string(), stripe_subscription_id),
        )
        return sub

    def sync_from_stripe_subscription(self, subscription_obj: Dict[str, Any]) -> None:
        stripe_sub_id = str(subscription_obj.get("id") or "")
        if not stripe_sub_id:
            return
        status = str(subscription_obj.get("status") or "active")
        cps = _ts_to_iso(subscription_obj.get("current_period_start"))
        cpe = _ts_to_iso(subscription_obj.get("current_period_end"))
        execute_query(
            """
            UPDATE user_subscriptions
            SET status = ?, current_period_start = ?, current_period_end = ?, next_billing_date = ?, updated_at = ?
            WHERE stripe_subscription_id = ?
            """,
            (status, cps, cpe, cpe, now_db_string(), stripe_sub_id),
        )

    def handle_invoice_paid(self, stripe_subscription_id: str, invoice_obj: Dict[str, Any]) -> None:
        """
        Allocate periodic credits when Stripe marks an invoice paid for a subscription.
        """
        sub_row = execute_query(
            """
            SELECT id, user_id, subscription_plan_id, credits_allocated_this_period, credits_used_this_period, credits_rolled_over
            FROM user_subscriptions
            WHERE stripe_subscription_id = ?
            """,
            (stripe_subscription_id,),
            fetch_one=True,
            commit=False,
        )
        if not sub_row:
            return
        user_sub_id = int(sub_row[0])
        user_id = int(sub_row[1])
        plan_id = int(sub_row[2])

        plan_row = execute_query(
            "SELECT credits_per_period, rollover_credits, max_rollover_credits FROM subscription_plans WHERE id = ?",
            (plan_id,),
            fetch_one=True,
            commit=False,
        )
        if not plan_row:
            return
        credits_per_period = int(plan_row[0])
        rollover_enabled = int(plan_row[1] or 0) == 1
        max_rollover = int(plan_row[2] or 0)

        credits_used = int(sub_row[4] or 0)
        allocated_prev = int(sub_row[3] or 0)
        rolled_prev = int(sub_row[5] or 0)

        rollover = 0
        if rollover_enabled:
            remaining = max(0, allocated_prev + rolled_prev - credits_used)
            rollover = min(remaining, max_rollover) if max_rollover > 0 else remaining

        total_allocate = credits_per_period + rollover
        if total_allocate <= 0:
            return

        # Allocate credits (subscription credits are promotional-like; don't add to lifetime_spent)
        created_at = now_db_string()
        execute_query(
            "UPDATE users SET credit_balance = COALESCE(credit_balance, 0) + ? WHERE id = ?",
            (total_allocate, user_id),
        )
        bal_row = execute_query(
            "SELECT credit_balance FROM users WHERE id = ?",
            (user_id,),
            fetch_one=True,
            commit=False,
        )
        balance_after = int(bal_row[0] or 0) if bal_row else 0

        ledger_id = execute_query(
            """
            INSERT INTO credit_ledger (user_id, job_id, amount, balance_after, transaction_type, reason, created_at, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (user_id, None, total_allocate, balance_after, "promotional", "Subscription renewal", created_at, None),
        )

        execute_query(
            """
            UPDATE user_subscriptions
            SET credits_allocated_this_period = ?, credits_used_this_period = 0, credits_rolled_over = ?,
                current_period_start = ?, current_period_end = ?, next_billing_date = ?, updated_at = ?
            WHERE id = ?
            """,
            (
                credits_per_period,
                rollover,
                created_at,
                created_at,
                created_at,
                created_at,
                user_sub_id,
            ),
        )

