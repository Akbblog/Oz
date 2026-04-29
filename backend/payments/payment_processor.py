from __future__ import annotations

import json
import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Dict, Optional

import config
from db.base import execute_query
from payments.coinbase_service import CoinbaseCommerceService
from payments.paypal_service import PayPalService
from payments.pricing_engine import PricingEngine
from payments.stripe_service import StripeService
from promotions.promo_service import PromoEffect, PromoService
from promotions.referral_service import ReferralService
from utils.time_utils import now_db_string

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class PurchaseInitResult:
    transaction_id: str
    provider: str
    amount_cents: int
    currency: str
    credits: int
    bonus_credits: int
    provider_transaction_id: str
    client_secret: Optional[str] = None
    hosted_url: Optional[str] = None


class PaymentProcessor:
    def __init__(self) -> None:
        self._stripe = StripeService()
        self._coinbase = CoinbaseCommerceService()
        self._paypal = PayPalService()
        self._pricing = PricingEngine()
        self._promos = PromoService()
        self._referrals = ReferralService()

    def _get_transaction_by_idempotency_key(self, idempotency_key: str) -> Optional[Dict[str, Any]]:
        row = execute_query(
            """
            SELECT id, transaction_id, payment_provider, provider_transaction_id, amount_cents, currency,
                   credits_purchased, status, idempotency_key, promo_code_id
            FROM payment_transactions
            WHERE idempotency_key = ?
            """,
            (idempotency_key,),
            fetch_one=True,
            commit=False,
        )
        if not row:
            return None
        return {
            "db_id": int(row[0]),
            "transaction_id": str(row[1]),
            "payment_provider": str(row[2]),
            "provider_transaction_id": row[3],
            "amount_cents": int(row[4]),
            "currency": str(row[5]),
            "credits_purchased": int(row[6]),
            "status": str(row[7]),
            "idempotency_key": str(row[8]),
            "promo_code_id": None if row[9] is None else int(row[9]),
        }

    def _create_transaction(
        self,
        *,
        user_id: int,
        provider: str,
        amount_cents: int,
        currency: str,
        credits: int,
        package_id: int,
        idempotency_key: str,
        promo_code_id: Optional[int],
    ) -> str:
        txn_uuid = str(uuid.uuid4())
        now = now_db_string()
        execute_query(
            """
            INSERT INTO payment_transactions (
                transaction_id, user_id, payment_provider, provider_transaction_id,
                amount_cents, currency, credits_purchased, status, idempotency_key,
                package_id, subscription_id, promo_code_id, invoice_id,
                created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                txn_uuid,
                user_id,
                provider,
                None,
                amount_cents,
                currency,
                credits,
                "pending",
                idempotency_key,
                package_id,
                None,
                promo_code_id,
                None,
                now,
                now,
            ),
        )
        return txn_uuid

    def _update_transaction_provider_id(self, transaction_id: str, provider_txn_id: str, status: str) -> None:
        execute_query(
            """
            UPDATE payment_transactions
            SET provider_transaction_id = ?, status = ?, updated_at = ?
            WHERE transaction_id = ?
            """,
            (provider_txn_id, status, now_db_string(), transaction_id),
        )

    def initiate_stripe_package_purchase(
        self,
        *,
        user_id: int,
        email: str,
        package_id: int,
        quantity: int,
        promo_code: Optional[str],
        idempotency_key: str,
        currency: str = "USD",
    ) -> PurchaseInitResult:
        existing = self._get_transaction_by_idempotency_key(idempotency_key)
        if existing:
            if existing["status"] == "completed":
                return PurchaseInitResult(
                    transaction_id=existing["transaction_id"],
                    provider=existing["payment_provider"],
                    amount_cents=existing["amount_cents"],
                    currency=existing["currency"],
                    credits=existing["credits_purchased"],
                    bonus_credits=0,
                    provider_transaction_id=str(existing["provider_transaction_id"] or ""),
                )
            if existing["status"] in ("pending", "processing"):
                raise ValueError("Payment already processing for this idempotency key")
            # If failed, allow retry by reusing the same transaction row.

        price = self._pricing.calculate_for_package(
            user_id=user_id,
            package_id=package_id,
            quantity=quantity,
            promo_code=promo_code,
        )

        total_cents = int(price["total_cents"])
        if total_cents < int(config.PAYMENT_CONFIG["min_purchase_cents"]):
            raise ValueError("Purchase amount below minimum")
        if total_cents > int(config.PAYMENT_CONFIG["max_purchase_cents"]):
            raise ValueError("Purchase amount above maximum")

        promo_effect: Optional[PromoEffect] = price.get("promo")
        promo_code_id = promo_effect.promo_code_id if promo_effect else None

        if existing and existing["status"] == "failed":
            transaction_id = existing["transaction_id"]
            execute_query(
                """
                UPDATE payment_transactions
                SET amount_cents = ?, currency = ?, credits_purchased = ?, package_id = ?, promo_code_id = ?,
                    status = 'pending', provider_transaction_id = NULL, updated_at = ?
                WHERE transaction_id = ?
                """,
                (
                    total_cents,
                    currency,
                    int(price["credits_to_receive"]),
                    package_id,
                    promo_code_id,
                    now_db_string(),
                    transaction_id,
                ),
            )
        else:
            transaction_id = self._create_transaction(
                user_id=user_id,
                provider="stripe",
                amount_cents=total_cents,
                currency=currency,
                credits=int(price["credits_to_receive"]),
                package_id=package_id,
                idempotency_key=idempotency_key,
                promo_code_id=promo_code_id,
            )

        intent = self._stripe.create_payment_intent(
            user_id=user_id,
            email=email,
            amount_cents=total_cents,
            currency=currency,
            transaction_id=transaction_id,
            idempotency_key=idempotency_key,
            metadata={"package_id": str(package_id)},
        )

        self._update_transaction_provider_id(transaction_id, str(intent["id"]), "processing")

        return PurchaseInitResult(
            transaction_id=transaction_id,
            provider="stripe",
            amount_cents=total_cents,
            currency=currency,
            credits=int(price["credits_to_receive"]),
            bonus_credits=int(price["bonus_credits"]),
            provider_transaction_id=str(intent["id"]),
            client_secret=str(intent.get("client_secret") or ""),
        )

    def initiate_coinbase_package_purchase(
        self,
        *,
        user_id: int,
        package_id: int,
        quantity: int,
        promo_code: Optional[str],
        idempotency_key: str,
        currency: str = "USD",
    ) -> PurchaseInitResult:
        existing = self._get_transaction_by_idempotency_key(idempotency_key)
        if existing:
            if existing["status"] == "completed":
                return PurchaseInitResult(
                    transaction_id=existing["transaction_id"],
                    provider=existing["payment_provider"],
                    amount_cents=existing["amount_cents"],
                    currency=existing["currency"],
                    credits=existing["credits_purchased"],
                    bonus_credits=0,
                    provider_transaction_id=str(existing["provider_transaction_id"] or ""),
                )
            if existing["status"] in ("pending", "processing"):
                raise ValueError("Payment already processing for this idempotency key")
            # If failed, allow retry by reusing the same transaction row.

        price = self._pricing.calculate_for_package(
            user_id=user_id,
            package_id=package_id,
            quantity=quantity,
            promo_code=promo_code,
        )
        total_cents = int(price["total_cents"])

        promo_effect: Optional[PromoEffect] = price.get("promo")
        promo_code_id = promo_effect.promo_code_id if promo_effect else None

        if existing and existing["status"] == "failed":
            transaction_id = existing["transaction_id"]
            execute_query(
                """
                UPDATE payment_transactions
                SET amount_cents = ?, currency = ?, credits_purchased = ?, package_id = ?, promo_code_id = ?,
                    status = 'pending', provider_transaction_id = NULL, updated_at = ?
                WHERE transaction_id = ?
                """,
                (
                    total_cents,
                    currency,
                    int(price["credits_to_receive"]),
                    package_id,
                    promo_code_id,
                    now_db_string(),
                    transaction_id,
                ),
            )
        else:
            transaction_id = self._create_transaction(
                user_id=user_id,
                provider="coinbase",
                amount_cents=total_cents,
                currency=currency,
                credits=int(price["credits_to_receive"]),
                package_id=package_id,
                idempotency_key=idempotency_key,
                promo_code_id=promo_code_id,
            )

        try:
            charge = self._coinbase.create_charge(
                name="Credit Purchase",
                description=f"Package {package_id} x{quantity}",
                amount=f"{total_cents / 100.0:.2f}",
                currency=currency,
                metadata={
                    "user_id": user_id,
                    "transaction_id": transaction_id,
                    "package_id": package_id,
                },
            )
        except Exception:
            execute_query(
                """
                UPDATE payment_transactions
                SET status = 'failed', updated_at = ?
                WHERE transaction_id = ?
                """,
                (now_db_string(), transaction_id),
            )
            raise

        charge_id = str(charge["id"])
        hosted_url = str(charge.get("hosted_url") or "")

        self._update_transaction_provider_id(transaction_id, charge_id, "processing")

        return PurchaseInitResult(
            transaction_id=transaction_id,
            provider="coinbase",
            amount_cents=total_cents,
            currency=currency,
            credits=int(price["credits_to_receive"]),
            bonus_credits=int(price["bonus_credits"]),
            provider_transaction_id=charge_id,
            hosted_url=hosted_url,
        )

    def initiate_paypal_package_purchase(
        self,
        *,
        user_id: int,
        package_id: int,
        quantity: int,
        promo_code: Optional[str],
        idempotency_key: str,
        currency: str = "USD",
    ) -> PurchaseInitResult:
        existing = self._get_transaction_by_idempotency_key(idempotency_key)
        if existing:
            if existing["status"] == "completed":
                return PurchaseInitResult(
                    transaction_id=existing["transaction_id"],
                    provider=existing["payment_provider"],
                    amount_cents=existing["amount_cents"],
                    currency=existing["currency"],
                    credits=existing["credits_purchased"],
                    bonus_credits=0,
                    provider_transaction_id=str(existing["provider_transaction_id"] or ""),
                )
            if existing["status"] in ("pending", "processing"):
                raise ValueError("Payment already processing for this idempotency key")
            # If failed, allow retry by reusing the same transaction row.

        price = self._pricing.calculate_for_package(
            user_id=user_id,
            package_id=package_id,
            quantity=quantity,
            promo_code=promo_code,
        )

        total_cents = int(price["total_cents"])
        if total_cents < int(config.PAYMENT_CONFIG["min_purchase_cents"]):
            raise ValueError("Purchase amount below minimum")
        if total_cents > int(config.PAYMENT_CONFIG["max_purchase_cents"]):
            raise ValueError("Purchase amount above maximum")

        promo_effect: Optional[PromoEffect] = price.get("promo")
        promo_code_id = promo_effect.promo_code_id if promo_effect else None

        if existing and existing["status"] == "failed":
            transaction_id = existing["transaction_id"]
            execute_query(
                """
                UPDATE payment_transactions
                SET amount_cents = ?, currency = ?, credits_purchased = ?, package_id = ?, promo_code_id = ?,
                    status = 'pending', provider_transaction_id = NULL, updated_at = ?
                WHERE transaction_id = ?
                """,
                (
                    total_cents,
                    currency,
                    int(price["credits_to_receive"]),
                    package_id,
                    promo_code_id,
                    now_db_string(),
                    transaction_id,
                ),
            )
        else:
            transaction_id = self._create_transaction(
                user_id=user_id,
                provider="paypal",
                amount_cents=total_cents,
                currency=currency,
                credits=int(price["credits_to_receive"]),
                package_id=package_id,
                idempotency_key=idempotency_key,
                promo_code_id=promo_code_id,
            )

        # PayPal redirects back to the app, but we keep it simple for now:
        # user can return and press "Complete" (capture) in the UI.
        return_url = f"{config.FRONTEND_URL}/#/wallet"
        cancel_url = f"{config.FRONTEND_URL}/#/wallet"

        order_id, approve_url = self._paypal.create_order(
            amount_cents=total_cents,
            currency=currency,
            description=f"Credit package {package_id} x{quantity}",
            custom_id=transaction_id,
            return_url=return_url,
            cancel_url=cancel_url,
        )

        self._update_transaction_provider_id(transaction_id, str(order_id), "processing")

        return PurchaseInitResult(
            transaction_id=transaction_id,
            provider="paypal",
            amount_cents=total_cents,
            currency=currency,
            credits=int(price["credits_to_receive"]),
            bonus_credits=int(price["bonus_credits"]),
            provider_transaction_id=str(order_id),
            hosted_url=str(approve_url),
        )

    def _generate_invoice_number(self) -> str:
        year = datetime.utcnow().year
        prefix = str(config.PAYMENT_CONFIG.get("invoice_prefix", "INV"))

        row = execute_query(
            "SELECT invoice_number FROM invoices WHERE invoice_number LIKE ? ORDER BY id DESC LIMIT 1",
            (f"{prefix}-{year}-%",),
            fetch_one=True,
            commit=False,
        )
        next_seq = 1
        if row and row[0]:
            try:
                last = str(row[0]).split("-")[-1]
                next_seq = int(last) + 1
            except Exception:
                next_seq = 1

        return f"{prefix}-{year}-{next_seq:05d}"

    def _allocate_credits(
        self,
        *,
        user_id: int,
        credits: int,
        amount_cents: int,
        reason: str,
        transaction_type: str,
        expires_days: Optional[int],
    ) -> int:
        execute_query(
            """
            UPDATE users
            SET credit_balance = COALESCE(credit_balance, 0) + ?,
                lifetime_credits_purchased = COALESCE(lifetime_credits_purchased, 0) + ?,
                lifetime_spent_cents = COALESCE(lifetime_spent_cents, 0) + ?
            WHERE id = ?
            """,
            (credits, credits, amount_cents, user_id),
        )
        row = execute_query(
            "SELECT credit_balance FROM users WHERE id = ?",
            (user_id,),
            fetch_one=True,
            commit=False,
        )
        new_balance = int(row[0] or 0) if row else 0

        created_at = now_db_string()
        ledger_id = execute_query(
            """
            INSERT INTO credit_ledger (user_id, job_id, amount, balance_after, transaction_type, reason, created_at, created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (user_id, None, credits, new_balance, transaction_type, reason, created_at, None),
        )

        expires_at = None
        if expires_days and expires_days > 0:
            expires_at = (datetime.utcnow() + timedelta(days=int(expires_days))).replace(microsecond=0).isoformat()

        execute_query(
            """
            INSERT INTO credit_expiry (
                user_id, credit_ledger_id, credits_granted, credits_remaining, expiry_type, expires_at, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                user_id,
                int(ledger_id),
                credits,
                credits,
                "purchased" if transaction_type == "credit" else "bonus",
                expires_at,
                created_at,
                created_at,
            ),
        )

        return new_balance

    def finalize_transaction_completed(
        self,
        *,
        transaction_id: str,
        provider_txn_id: str,
        provider: str,
        paid_amount_cents: Optional[int] = None,
    ) -> Dict[str, Any]:
        """
        Mark a transaction completed and allocate credits. Safe to call multiple times.
        """
        row = execute_query(
            """
            SELECT id, user_id, credits_purchased, amount_cents, status, promo_code_id
            FROM payment_transactions
            WHERE transaction_id = ?
            """,
            (transaction_id,),
            fetch_one=True,
            commit=False,
        )
        if not row:
            raise ValueError("Transaction not found")

        txn_db_id = int(row[0])
        user_id = int(row[1])
        credits = int(row[2])
        amount_cents = int(paid_amount_cents or row[3] or 0)
        status = str(row[4])
        promo_code_id = None if row[5] is None else int(row[5])

        if status == "completed":
            return {"status": "completed", "transaction_id": transaction_id}

        # Ensure only one caller transitions the transaction to completed.
        updated = execute_query(
            """
            UPDATE payment_transactions
            SET status = 'completed', provider_transaction_id = ?, updated_at = ?
            WHERE transaction_id = ? AND status != 'completed'
            """,
            (provider_txn_id, now_db_string(), transaction_id),
        )
        if not updated:
            return {"status": "completed", "transaction_id": transaction_id}

        # Allocate purchased credits
        balance_after = self._allocate_credits(
            user_id=user_id,
            credits=credits,
            amount_cents=amount_cents,
            reason="Payment confirmed",
            transaction_type="credit",
            expires_days=int(config.DEFAULT_CREDIT_CONFIG.get("credit_expiry_days", 0) or 0),
        )

        # Promo bonus credits (if any)
        bonus_credits = 0
        if promo_code_id is not None:
            promo_row = execute_query(
                "SELECT code, type, bonus_credits FROM promo_codes WHERE id = ?",
                (promo_code_id,),
                fetch_one=True,
                commit=False,
            )
            if promo_row and str(promo_row[1]) == "bonus_credits":
                bonus_credits = int(promo_row[2] or 0)
                if bonus_credits > 0:
                    balance_after = self._allocate_credits(
                        user_id=user_id,
                        credits=bonus_credits,
                        amount_cents=0,
                        reason="Promo bonus credits",
                        transaction_type="bonus",
                        expires_days=int(config.DEFAULT_CREDIT_CONFIG.get("bonus_expiry_days", 0) or 0),
                    )

            # Record usage for analytics (discount amount is not currently stored; record credits instead)
            try:
                self._promos.record_usage(
                    promo_code_id=promo_code_id,
                    user_id=user_id,
                    transaction_db_id=txn_db_id,
                    credits_awarded=bonus_credits,
                    discount_amount_cents=0,
                )
            except Exception:
                logger.exception("Failed recording promo usage")

        # Create invoice record
        invoice_number = self._generate_invoice_number()
        invoice_id = execute_query(
            """
            INSERT INTO invoices (
                invoice_number, user_id, transaction_id, subscription_id, invoice_type,
                amount_cents, tax_amount_cents, total_amount_cents, status,
                pdf_path, line_items, billing_name, billing_email, billing_address,
                created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                invoice_number,
                user_id,
                txn_db_id,
                None,
                "purchase",
                amount_cents,
                0,
                amount_cents,
                "paid",
                None,
                None,
                None,
                None,
                None,
                now_db_string(),
                now_db_string(),
            ),
        )

        execute_query(
            "UPDATE payment_transactions SET invoice_id = ?, updated_at = ? WHERE id = ?",
            (int(invoice_id), now_db_string(), txn_db_id),
        )

        # Referral rewards (first qualifying purchase)
        try:
            self._referrals.maybe_reward_on_purchase(
                referred_user_id=user_id,
                paid_amount_cents=amount_cents,
            )
        except Exception:
            logger.exception("Referral reward processing failed")

        # Best-effort background email delivery
        try:
            from background.celery_app import celery_app

            celery_app.send_task("background.tasks.send_invoice_email", args=[int(invoice_id)])
        except Exception:
            # No celery/redis in dev: ignore
            pass

        return {
            "status": "completed",
            "transaction_id": transaction_id,
            "invoice_id": int(invoice_id),
            "invoice_number": invoice_number,
            "credit_balance": balance_after,
            "credits_added": credits,
            "bonus_credits_added": bonus_credits,
        }
