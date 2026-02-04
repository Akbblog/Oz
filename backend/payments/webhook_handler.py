from __future__ import annotations

import json
import logging
from typing import Any, Dict, Optional

from db.payment_crud import create_webhook_event, mark_webhook_failed, mark_webhook_processed
from payments.coinbase_service import CoinbaseCommerceService
from payments.payment_processor import PaymentProcessor
from payments.stripe_service import StripeService
from subscriptions.subscription_manager import SubscriptionManager

logger = logging.getLogger(__name__)


class WebhookHandler:
    def __init__(self) -> None:
        self._stripe = StripeService()
        self._coinbase = CoinbaseCommerceService()
        self._processor = PaymentProcessor()
        self._subs = SubscriptionManager()

    def handle_stripe_webhook(self, raw_body: bytes, signature: str) -> Dict[str, Any]:
        event = self._stripe.construct_event(raw_body, signature)
        webhook_id = str(event.get("id") or "")
        event_type = str(event.get("type") or "")

        webhook_db_id = create_webhook_event(
            webhook_id=webhook_id,
            provider="stripe",
            event_type=event_type,
            payload=json.dumps(event),
            status="pending",
        )

        try:
            obj = (event.get("data") or {}).get("object") or {}

            if event_type == "payment_intent.succeeded":
                payment_intent_id = str(obj.get("id"))
                metadata = obj.get("metadata") or {}
                txn_uuid = metadata.get("transaction_id")
                if txn_uuid:
                    self._processor.finalize_transaction_completed(
                        transaction_id=str(txn_uuid),
                        provider_txn_id=payment_intent_id,
                        provider="stripe",
                        paid_amount_cents=int(obj.get("amount_received") or obj.get("amount") or 0),
                    )

            elif event_type == "payment_intent.payment_failed":
                payment_intent_id = str(obj.get("id"))
                metadata = obj.get("metadata") or {}
                txn_uuid = metadata.get("transaction_id")
                if txn_uuid:
                    # best-effort mark failed
                    from db.base import execute_query
                    from utils.time_utils import now_db_string

                    execute_query(
                        """
                        UPDATE payment_transactions
                        SET status = 'failed', provider_transaction_id = ?, updated_at = ?
                        WHERE transaction_id = ?
                        """,
                        (payment_intent_id, now_db_string(), str(txn_uuid)),
                    )

            elif event_type == "invoice.paid":
                # Subscription renewal/first payment
                subscription_id = obj.get("subscription")
                if subscription_id:
                    self._subs.handle_invoice_paid(str(subscription_id), invoice_obj=obj)

            elif event_type in ("customer.subscription.updated", "customer.subscription.deleted"):
                subscription_id = str(obj.get("id") or "")
                if subscription_id:
                    self._subs.sync_from_stripe_subscription(subscription_obj=obj)

            mark_webhook_processed(webhook_db_id)
            return {"received": True}

        except Exception as e:
            logger.exception("Stripe webhook processing failed")
            mark_webhook_failed(webhook_db_id, str(e))
            raise

    def handle_coinbase_webhook(self, raw_body: bytes, signature: str) -> Dict[str, Any]:
        if not self._coinbase.verify_webhook(raw_body, signature):
            raise ValueError("Invalid Coinbase webhook signature")

        event = json.loads(raw_body.decode("utf-8"))
        webhook_id = str(event.get("id") or "")
        event_type = str(event.get("type") or "")
        webhook_db_id = create_webhook_event(
            webhook_id=webhook_id,
            provider="coinbase",
            event_type=event_type,
            payload=json.dumps(event),
            status="pending",
        )

        try:
            data = (event.get("data") or {})
            charge_id = str(data.get("id") or "")
            metadata = data.get("metadata") or {}
            txn_uuid = metadata.get("transaction_id")

            # Coinbase event types can vary; treat "charge:confirmed"/"charge:resolved" as success
            if event_type in ("charge:confirmed", "charge:resolved"):
                if txn_uuid and charge_id:
                    self._processor.finalize_transaction_completed(
                        transaction_id=str(txn_uuid),
                        provider_txn_id=charge_id,
                        provider="coinbase",
                    )
            elif event_type in ("charge:failed", "charge:canceled"):
                if txn_uuid and charge_id:
                    from db.base import execute_query
                    from utils.time_utils import now_db_string

                    execute_query(
                        """
                        UPDATE payment_transactions
                        SET status = 'failed', provider_transaction_id = ?, updated_at = ?
                        WHERE transaction_id = ?
                        """,
                        (charge_id, now_db_string(), str(txn_uuid)),
                    )

            mark_webhook_processed(webhook_db_id)
            return {"received": True}
        except Exception as e:
            logger.exception("Coinbase webhook processing failed")
            mark_webhook_failed(webhook_db_id, str(e))
            raise

