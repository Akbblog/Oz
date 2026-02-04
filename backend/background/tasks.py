from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from background.celery_app import celery_app
from db.base import execute_query
from payments.coinbase_service import CoinbaseCommerceService
from payments.payment_processor import PaymentProcessor
from payments.stripe_service import StripeService
from utils.time_utils import now_db_string

logger = logging.getLogger(__name__)


def _coinbase_status_to_internal(charge: Dict[str, Any]) -> str:
    timeline = charge.get("timeline") or []
    status = str(timeline[-1]["status"]) if timeline else "NEW"
    status = status.upper()
    if status in ("COMPLETED", "RESOLVED"):
        return "completed"
    if status in ("EXPIRED", "CANCELED"):
        return "failed"
    return "processing"


@celery_app.task(name="background.tasks.reconcile_processing_transactions")
def reconcile_processing_transactions() -> int:
    """
    Best-effort safety net:
    - For transactions stuck in 'processing', poll the provider to see if they completed.
    - Helps when webhooks are delayed/dropped.
    """
    processor = PaymentProcessor()
    stripe_svc = StripeService()
    coinbase_svc = CoinbaseCommerceService()

    rows = execute_query(
        """
        SELECT transaction_id, payment_provider, provider_transaction_id, amount_cents, created_at
        FROM payment_transactions
        WHERE status = 'processing'
        ORDER BY created_at ASC
        LIMIT 100
        """,
        fetch_all=True,
        commit=False,
    )
    if not rows:
        return 0

    processed = 0
    for row in rows:
        txn_uuid = str(row[0])
        provider = str(row[1])
        provider_id = row[2]

        if not provider_id:
            continue

        try:
            if provider == "stripe":
                intent = stripe_svc.retrieve_payment_intent(str(provider_id))
                status = str(intent.get("status") or "")
                if status == "succeeded":
                    processor.finalize_transaction_completed(
                        transaction_id=txn_uuid,
                        provider_txn_id=str(provider_id),
                        provider="stripe",
                        paid_amount_cents=int(intent.get("amount_received") or intent.get("amount") or 0),
                    )
                    processed += 1
                elif status in ("canceled",):
                    execute_query(
                        "UPDATE payment_transactions SET status = 'failed', updated_at = ? WHERE transaction_id = ?",
                        (now_db_string(), txn_uuid),
                    )
                    processed += 1

            elif provider == "coinbase":
                charge = coinbase_svc.get_charge(str(provider_id))
                internal = _coinbase_status_to_internal(charge)
                if internal == "completed":
                    processor.finalize_transaction_completed(
                        transaction_id=txn_uuid,
                        provider_txn_id=str(provider_id),
                        provider="coinbase",
                    )
                    processed += 1
                elif internal == "failed":
                    execute_query(
                        "UPDATE payment_transactions SET status = 'failed', updated_at = ? WHERE transaction_id = ?",
                        (now_db_string(), txn_uuid),
                    )
                    processed += 1
        except Exception:
            logger.exception("Reconcile failed for transaction %s", txn_uuid)

    return processed


@celery_app.task(name="background.tasks.send_invoice_email")
def send_invoice_email(invoice_id: int) -> bool:
    """
    Generate invoice PDF (if needed) and email it to the user.
    """
    try:
        from db.payment_crud import get_invoice_by_id
        from invoices.invoice_service import ensure_invoice_pdf
        from notifications.email_service import send_invoice_email as _send

        inv = get_invoice_by_id(int(invoice_id))
        if not inv:
            return False

        # invoices schema: id, invoice_number, user_id, ...
        invoice_number = str(inv[1])
        user_id = int(inv[2])
        amount_cents = int(inv[8] or 0)
        created_at = str(inv[15] or "")

        user_row = execute_query(
            "SELECT email, billing_email FROM users WHERE id = ?",
            (user_id,),
            fetch_one=True,
            commit=False,
        )
        if not user_row:
            return False
        to_email = str(user_row[1] or user_row[0] or "")
        if not to_email:
            return False

        _, pdf_bytes = ensure_invoice_pdf(int(invoice_id))
        amount_display = f"${amount_cents / 100.0:,.2f}"
        _send(
            to_email=to_email,
            invoice_number=invoice_number,
            invoice_pdf_bytes=pdf_bytes,
            amount_display=amount_display,
            date_display=created_at,
        )
        return True
    except Exception:
        logger.exception("Failed sending invoice email")
        return False
