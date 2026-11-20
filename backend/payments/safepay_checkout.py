"""Safepay checkout, verification and exactly-once credit fulfilment.

Rules (see docs/SAFEPAY_RELEASE_REPORT.md):
* Credits are granted ONLY when Safepay itself proves the payment: a webhook whose
  HMAC-SHA512 signature verifies with the active environment's shared secret, or a
  server-to-server tracker lookup (``GET /reporter/api/v1/payments/{tracker}``) in
  state ``TRACKER_ENDED``. The browser return URL only *asks* the server to check.
* Before crediting, tracker, order id (= our transaction_id), amount (minor units),
  currency and environment must all match the stored transaction.
* The status flip ``-> completed`` and the credit grant run in ONE database
  transaction guarded by ``WHERE status <> 'completed'``, so duplicate, concurrent or
  late confirmations credit the account exactly once.
"""
from __future__ import annotations

import json
import logging
import threading
import time
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

import config
from db.base import execute_query, get_db_cursor, get_placeholder
from payments.pricing_engine import PricingEngine
from payments.safepay_service import (
    DEAD_STATES,
    PAID_STATE,
    SafepayError,
    SafepayNotConfigured,
    SafepayService,
    SafepayUnavailable,
    active_environment,
    summarize_tracker,
)
from utils.time_utils import now_db_string

logger = logging.getLogger(__name__)

PROVIDER = "safepay"

_TXN_COLUMNS = (
    "id, transaction_id, user_id, payment_provider, provider_transaction_id, amount_cents, currency, "
    "credits_purchased, status, promo_code_id, provider_environment, provider_status, status_detail, "
    "invoice_id, created_at, updated_at"
)


class CheckoutUnavailable(Exception):
    """Checkout cannot be started for this user right now (message is user-facing)."""


def _q(sql: str) -> str:
    return sql.replace("?", "%s") if get_placeholder() == "%s" else sql


def _row_to_txn(row) -> Optional[Dict[str, Any]]:
    if not row:
        return None
    keys = [k.strip() for k in _TXN_COLUMNS.split(",")]
    return dict(zip(keys, row))


def get_transaction(transaction_id: str) -> Optional[Dict[str, Any]]:
    return _row_to_txn(execute_query(
        f"SELECT {_TXN_COLUMNS} FROM payment_transactions WHERE transaction_id = ?",
        (transaction_id,), fetch_one=True, commit=False,
    ))


def _service() -> SafepayService:
    return SafepayService()


# ---------------------------------------------------------------- availability
def checkout_availability(user: Dict[str, Any]) -> Tuple[bool, Optional[str], str]:
    """Return (available, user-facing reason when not, environment)."""
    try:
        env = active_environment()
        svc = SafepayService(env)
    except SafepayNotConfigured:
        return False, "Card payments are not configured yet.", str(config.SAFEPAY_ENV)
    if not svc.checkout_configured():
        return False, "Card payments are not configured yet.", env
    if config.SAFEPAY_CHECKOUT_ALLOWLIST:
        ident = {str(user.get("id", "")).lower(), str(user.get("email") or "").strip().lower()}
        if not ident & set(config.SAFEPAY_CHECKOUT_ALLOWLIST):
            return False, "Card payments are launching soon. Please check back shortly.", env
    elif env == "sandbox" and not config.SAFEPAY_SANDBOX_OPEN_TO_ALL:
        return False, "Card payments are launching soon. Please check back shortly.", env
    return True, None, env


# ---------------------------------------------------------------- start checkout
def start_package_checkout(
    *,
    user: Dict[str, Any],
    package_id: int,
    quantity: int,
    promo_code: Optional[str],
    idempotency_key: str,
) -> Dict[str, Any]:
    available, reason, env = checkout_availability(user)
    if not available:
        raise CheckoutUnavailable(reason or "Card payments are unavailable.")
    if quantity != 1:
        raise ValueError("Only one credit pack can be bought per checkout")
    if not idempotency_key or len(idempotency_key) > 200:
        raise ValueError("A valid idempotency key is required")

    user_id = int(user["id"])
    idem = f"safepay:{user_id}:{idempotency_key}"
    existing = execute_query(
        "SELECT transaction_id, status FROM payment_transactions WHERE idempotency_key = ?",
        (idem,), fetch_one=True, commit=False,
    )
    if existing:
        raise ValueError("This checkout was already started. Refresh the page to start a new one.")

    price = PricingEngine().calculate_for_package(
        user_id=user_id, package_id=package_id, quantity=1, promo_code=promo_code,
    )
    total_cents = int(price["total_cents"])
    credits = int(price["credits_to_receive"])
    if total_cents < int(config.PAYMENT_CONFIG["min_purchase_cents"]):
        raise ValueError("Purchase amount below minimum")
    if total_cents > int(config.PAYMENT_CONFIG["max_purchase_cents"]):
        raise ValueError("Purchase amount above maximum")
    promo = price.get("promo")
    promo_code_id = promo.promo_code_id if promo else None
    currency = config.SAFEPAY_CHARGE_CURRENCY

    transaction_id = str(uuid.uuid4())
    now = now_db_string()
    execute_query(
        """
        INSERT INTO payment_transactions (
            transaction_id, user_id, payment_provider, provider_transaction_id, amount_cents, currency,
            credits_purchased, status, idempotency_key, package_id, subscription_id, promo_code_id,
            invoice_id, provider_environment, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (transaction_id, user_id, PROVIDER, None, total_cents, currency, credits, "pending", idem,
         package_id, None, promo_code_id, None, env, now, now),
    )

    svc = SafepayService(env)
    try:
        tracker = svc.create_session(amount_minor=total_cents, currency=currency, order_id=transaction_id)
        summary = summarize_tracker(tracker)
        execute_query(
            """
            UPDATE payment_transactions
            SET provider_transaction_id = ?, status = 'processing', provider_status = ?,
                provider_base_amount = ?, provider_base_currency = ?, provider_fx_rate = ?, updated_at = ?
            WHERE transaction_id = ?
            """,
            (summary["token"], summary["state"] or "TRACKER_STARTED", summary["base_amount"],
             summary["base_currency"], summary["fx_rate"], now_db_string(), transaction_id),
        )
        tbt = svc.create_auth_token()
    except Exception as exc:
        _mark_failed(transaction_id, "checkout_start_failed", provider_status=None, only_if_open=True)
        logger.warning("Safepay checkout start failed txn=%s: %s", transaction_id, exc)
        raise

    base = config.FRONTEND_URL
    url = svc.checkout_url(
        tracker=summary["token"],
        tbt=tbt,
        order_id=transaction_id,
        redirect_url=f"{base}/payment/return/{transaction_id}",
        cancel_url=f"{base}/payment/cancelled/{transaction_id}",
    )
    return {
        "transaction_id": transaction_id,
        "payment_provider": PROVIDER,
        "environment": env,
        "amount_cents": total_cents,
        "currency": currency,
        "credits_purchased": credits,
        "bonus_credits": int(price.get("bonus_credits") or 0),
        "provider_transaction_id": summary["token"],
        "checkout_url": url,
        "hosted_url": url,
        "expires_in_seconds": 3600,
    }


# ---------------------------------------------------------------- state changes
def _mark_failed(transaction_id: str, detail: str, *, provider_status: Optional[str], only_if_open: bool) -> int:
    where = "status IN ('pending', 'processing')" if only_if_open else "status <> 'completed'"
    return int(execute_query(
        f"""
        UPDATE payment_transactions
        SET status = 'failed', status_detail = ?, provider_status = COALESCE(?, provider_status), updated_at = ?
        WHERE transaction_id = ? AND {where}
        """,
        (detail[:255], provider_status, now_db_string(), transaction_id),
    ) or 0)


def _flag_for_review(transaction_id: str, detail: str) -> None:
    execute_query(
        "UPDATE payment_transactions SET status_detail = ?, updated_at = ? WHERE transaction_id = ? AND status <> 'completed'",
        (("review: " + detail)[:255], now_db_string(), transaction_id),
    )
    logger.error("Safepay transaction %s needs review: %s", transaction_id, detail)
    _audit("payment.safepay.review", transaction_id, {"detail": detail}, status="failure")


def _audit(action: str, transaction_id: str, after: Dict[str, Any], status: str = "success") -> None:
    try:
        from audit.service import record_audit_event

        record_audit_event(action, target_type="payment_transaction", target_id=transaction_id,
                           after=after, status=status)
    except Exception:
        logger.exception("audit event failed (ignored)")


def _evidence_mismatch(txn: Dict[str, Any], *, tracker: str, order_id: Optional[str], amount: Optional[int],
                       currency: str, environment: str) -> Optional[str]:
    if str(txn["payment_provider"]) != PROVIDER:
        return "not a Safepay transaction"
    if not txn.get("provider_transaction_id") or tracker != str(txn["provider_transaction_id"]):
        return "tracker does not match"
    if order_id is not None and str(order_id) != str(txn["transaction_id"]):
        return "order id does not match"
    if amount is None or int(amount) != int(txn["amount_cents"]):
        return f"amount {amount} does not match {txn['amount_cents']}"
    if str(currency).upper() != str(txn["currency"] or "").upper():
        return f"currency {currency} does not match {txn['currency']}"
    if environment != str(txn.get("provider_environment") or ""):
        return f"environment {environment} does not match {txn.get('provider_environment')}"
    return None


def fulfill(transaction_id: str, *, tracker: str, source: str, provider_status: str = PAID_STATE) -> Dict[str, Any]:
    """Atomically mark completed and grant credits. Returns {'credited': bool, ...}."""
    last_exc: Optional[Exception] = None
    for attempt in range(3):
        try:
            result = _fulfill_once(transaction_id, tracker=tracker, source=source, provider_status=provider_status)
            break
        except Exception as exc:  # invoice-number race or transient DB error: retry the whole transaction
            last_exc = exc
            logger.warning("Safepay fulfilment attempt %s failed txn=%s: %s", attempt + 1, transaction_id, exc)
            time.sleep(0.2 * (attempt + 1))
    else:
        raise last_exc  # type: ignore[misc]

    if result.get("credited"):
        _after_fulfilment(result)
        _audit("payment.safepay.completed", transaction_id,
               {"source": source, "credits": result["credits_added"], "bonus": result["bonus_credits_added"],
                "amount_cents": result["amount_cents"], "tracker": tracker})
    return result


def _fulfill_once(transaction_id: str, *, tracker: str, source: str, provider_status: str) -> Dict[str, Any]:
    now = now_db_string()
    with get_db_cursor() as cur:
        cur.execute(_q("""
            UPDATE payment_transactions
            SET status = 'completed', provider_status = ?, status_detail = NULL, completed_at = ?, updated_at = ?
            WHERE transaction_id = ? AND payment_provider = 'safepay' AND provider_transaction_id = ?
              AND status <> 'completed'
        """), (provider_status, now, now, transaction_id, tracker))
        if cur.rowcount != 1:
            return {"credited": False, "transaction_id": transaction_id, "status": "completed"}

        cur.execute(_q("""
            SELECT id, user_id, credits_purchased, amount_cents, promo_code_id, provider_environment
            FROM payment_transactions WHERE transaction_id = ?
        """), (transaction_id,))
        txn_db_id, user_id, credits, amount_cents, promo_code_id, env = cur.fetchone()
        txn_db_id, user_id, credits, amount_cents = int(txn_db_id), int(user_id), int(credits), int(amount_cents)

        env_tag = "" if env == "production" else f" [{env}]"
        balance = _grant(cur, user_id, credits, amount_cents, f"Safepay payment {tracker}{env_tag}", "credit",
                         int(config.DEFAULT_CREDIT_CONFIG.get("credit_expiry_days", 0) or 0), now)

        bonus = 0
        if promo_code_id is not None:
            cur.execute(_q("SELECT type, bonus_credits FROM promo_codes WHERE id = ?"), (int(promo_code_id),))
            prow = cur.fetchone()
            if prow and str(prow[0]) == "bonus_credits" and int(prow[1] or 0) > 0:
                bonus = int(prow[1])
                balance = _grant(cur, user_id, bonus, 0, f"Promo bonus credits ({tracker}){env_tag}", "bonus",
                                 int(config.DEFAULT_CREDIT_CONFIG.get("bonus_expiry_days", 0) or 0), now)

        invoice_number = _next_invoice_number(cur)
        cur.execute(_q("""
            INSERT INTO invoices (
                invoice_number, user_id, transaction_id, subscription_id, invoice_type,
                amount_cents, tax_amount_cents, total_amount_cents, status,
                pdf_path, line_items, billing_name, billing_email, billing_address, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """), (invoice_number, user_id, txn_db_id, None, "purchase", amount_cents, 0, amount_cents, "paid",
               None, json.dumps([{"description": f"{credits} credits", "amount_cents": amount_cents}]),
               None, None, None, now, now))
        invoice_id = int(cur.lastrowid)
        cur.execute(_q("UPDATE payment_transactions SET invoice_id = ? WHERE id = ?"), (invoice_id, txn_db_id))

    logger.info("Safepay txn %s completed via %s: +%s credits (+%s bonus) user=%s",
                transaction_id, source, credits, bonus, user_id)
    return {
        "credited": True,
        "status": "completed",
        "transaction_id": transaction_id,
        "transaction_db_id": txn_db_id,
        "user_id": user_id,
        "amount_cents": amount_cents,
        "promo_code_id": promo_code_id,
        "credits_added": credits,
        "bonus_credits_added": bonus,
        "credit_balance": balance,
        "invoice_id": invoice_id,
        "invoice_number": invoice_number,
    }


def _grant(cur, user_id: int, credits: int, amount_cents: int, reason: str, kind: str,
           expires_days: int, now: str) -> int:
    cur.execute(_q("""
        UPDATE users
        SET credit_balance = COALESCE(credit_balance, 0) + ?,
            lifetime_credits_purchased = COALESCE(lifetime_credits_purchased, 0) + ?,
            lifetime_spent_cents = COALESCE(lifetime_spent_cents, 0) + ?
        WHERE id = ?
    """), (credits, credits if kind == "credit" else 0, amount_cents, user_id))
    if cur.rowcount != 1:
        raise RuntimeError(f"user {user_id} not found while granting credits")
    cur.execute(_q("SELECT credit_balance FROM users WHERE id = ?"), (user_id,))
    balance = int(cur.fetchone()[0] or 0)
    cur.execute(_q("""
        INSERT INTO credit_ledger (user_id, job_id, amount, balance_after, transaction_type, reason, created_at, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """), (user_id, None, credits, balance, kind, reason[:255], now, None))
    ledger_id = int(cur.lastrowid)
    expires_at = None
    if expires_days > 0:
        expires_at = (datetime.utcnow() + timedelta(days=expires_days)).replace(microsecond=0).isoformat()
    cur.execute(_q("""
        INSERT INTO credit_expiry (user_id, credit_ledger_id, credits_granted, credits_remaining, expiry_type,
                                   expires_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """), (user_id, ledger_id, credits, credits, "purchased" if kind == "credit" else "bonus", expires_at, now, now))
    return balance


def _next_invoice_number(cur) -> str:
    year = datetime.now(timezone.utc).year
    prefix = str(config.PAYMENT_CONFIG.get("invoice_prefix", "INV"))
    cur.execute(_q("SELECT invoice_number FROM invoices WHERE invoice_number LIKE ? ORDER BY id DESC LIMIT 1"),
                (f"{prefix}-{year}-%",))
    row = cur.fetchone()
    seq = 1
    if row and row[0]:
        try:
            seq = int(str(row[0]).split("-")[-1]) + 1
        except ValueError:
            seq = 1
    return f"{prefix}-{year}-{seq:05d}"


def _after_fulfilment(result: Dict[str, Any]) -> None:
    """Side effects that run once, only for the caller that performed the transition."""
    if result.get("promo_code_id") is not None:
        try:
            from promotions.promo_service import PromoService

            PromoService().record_usage(
                promo_code_id=int(result["promo_code_id"]), user_id=int(result["user_id"]),
                transaction_db_id=int(result["transaction_db_id"]),
                credits_awarded=int(result["bonus_credits_added"]), discount_amount_cents=0,
            )
        except Exception:
            logger.exception("Failed recording promo usage")
    try:
        from promotions.referral_service import ReferralService

        ReferralService().maybe_reward_on_purchase(
            referred_user_id=int(result["user_id"]), paid_amount_cents=int(result["amount_cents"]))
    except Exception:
        logger.exception("Referral reward processing failed")


# ---------------------------------------------------------------- verification paths
def apply_tracker(txn: Dict[str, Any], tracker_data: Dict[str, Any], *, source: str) -> Dict[str, Any]:
    """Act on an authoritative server-side tracker lookup."""
    s = summarize_tracker(tracker_data)
    if s["state"] == PAID_STATE:
        mismatch = _evidence_mismatch(txn, tracker=s["token"], order_id=s["order_id"], amount=s["amount"],
                                      currency=s["currency"], environment=s["environment"] or "?")
        if mismatch:
            _flag_for_review(txn["transaction_id"], mismatch)
            return {"status": "review", "detail": mismatch}
        return fulfill(txn["transaction_id"], tracker=s["token"], source=source)
    if s["state"] in DEAD_STATES:
        detail = "expired" if s["state"] == "TRACKER_EXPIRED" else "cancelled"
        _mark_failed(txn["transaction_id"], detail, provider_status=s["state"], only_if_open=True)
        return {"status": detail}
    if s["state"] and s["state"] != str(txn.get("provider_status") or ""):
        execute_query(
            "UPDATE payment_transactions SET provider_status = ?, updated_at = ? WHERE transaction_id = ? AND status <> 'completed'",
            (s["state"], now_db_string(), txn["transaction_id"]),
        )
    return {"status": "processing", "provider_state": s["state"]}


def reconcile(transaction_id: str, *, source: str) -> Dict[str, Any]:
    txn = get_transaction(transaction_id)
    if not txn or txn["payment_provider"] != PROVIDER:
        raise ValueError("Transaction not found")
    if txn["status"] == "completed" or not txn.get("provider_transaction_id"):
        return {"status": txn["status"]}
    env = active_environment()
    if str(txn.get("provider_environment") or "") != env:
        # A sandbox transaction is never looked up with production credentials (or vice versa).
        return {"status": txn["status"], "detail": "environment changed"}
    data = SafepayService(env).fetch_tracker(str(txn["provider_transaction_id"]))
    return apply_tracker(txn, data, source=source)


_last_check: Dict[str, float] = {}
_last_check_lock = threading.Lock()


def status_for_user(transaction_id: str, user_id: int, *, check_provider: bool = True) -> Dict[str, Any]:
    """User-facing status; may ask Safepay (server-to-server) whether an open payment completed."""
    txn = get_transaction(transaction_id)
    if not txn or int(txn["user_id"]) != int(user_id):
        raise LookupError("Transaction not found")
    if check_provider and txn["payment_provider"] == PROVIDER and txn["status"] in ("pending", "processing", "failed"):
        now = time.monotonic()
        with _last_check_lock:
            due = now - _last_check.get(transaction_id, 0.0) >= 4.0
            if due:
                _last_check[transaction_id] = now
        if due and not (txn["status"] == "failed" and _age_minutes(txn) > config.SAFEPAY_CHECKOUT_EXPIRY_MINUTES + 15):
            try:
                reconcile(transaction_id, source="status_check")
            except (SafepayUnavailable, SafepayError, SafepayNotConfigured) as exc:
                logger.warning("Safepay status check failed txn=%s: %s", transaction_id, exc)
            txn = get_transaction(transaction_id) or txn
    return public_status(txn)


def public_status(txn: Dict[str, Any]) -> Dict[str, Any]:
    status = str(txn["status"])
    detail = str(txn.get("status_detail") or "")
    if status == "completed":
        ui = "completed"
    elif status == "failed":
        ui = {"cancelled": "cancelled", "expired": "expired"}.get(detail, "failed")
        if detail == "checkout_start_failed":
            ui = "failed"
    elif detail.startswith("review:"):
        ui = "review"
    else:
        ui = "processing"
    return {
        "transaction_id": txn["transaction_id"],
        "payment_provider": txn["payment_provider"],
        "status": ui,
        "raw_status": status,
        "provider_status": txn.get("provider_status"),
        "amount_cents": int(txn["amount_cents"] or 0),
        "currency": txn.get("currency"),
        "credits_purchased": int(txn["credits_purchased"] or 0),
        "environment": txn.get("provider_environment"),
        "invoice_id": txn.get("invoice_id"),
        "created_at": str(txn.get("created_at") or ""),
    }


def cancel_by_user(transaction_id: str, user_id: int) -> Dict[str, Any]:
    """The shopper came back via cancel_url. Check Safepay first: a paid tracker still credits."""
    txn = get_transaction(transaction_id)
    if not txn or int(txn["user_id"]) != int(user_id) or txn["payment_provider"] != PROVIDER:
        raise LookupError("Transaction not found")
    if txn["status"] in ("pending", "processing"):
        try:
            result = reconcile(transaction_id, source="cancel_return")
        except (SafepayUnavailable, SafepayError, SafepayNotConfigured) as exc:
            logger.warning("Safepay check on cancel failed txn=%s: %s", transaction_id, exc)
            result = {"status": "processing"}
        if result.get("status") == "processing":
            _mark_failed(transaction_id, "cancelled", provider_status=None, only_if_open=True)
    return public_status(get_transaction(transaction_id) or txn)


# ---------------------------------------------------------------- webhook
class WebhookRejected(Exception):
    """Signature/authenticity failure -> HTTP 401 (Safepay will retry)."""


def handle_webhook(raw_body: bytes, signature: str) -> Dict[str, Any]:
    from db.payment_crud import begin_webhook_event, mark_webhook_failed, mark_webhook_processed

    env = active_environment()
    svc = SafepayService(env)
    if not svc.webhook_configured():
        raise WebhookRejected("Safepay webhook secret is not configured for this environment")
    if not svc.verify_webhook_signature(raw_body, signature):
        raise WebhookRejected("Invalid Safepay webhook signature")
    try:
        event = json.loads(raw_body.decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as exc:
        raise WebhookRejected("Malformed webhook body") from exc
    if not isinstance(event, dict):
        raise WebhookRejected("Malformed webhook body")
    merchant_key = event.get("merchant_api_key")
    if merchant_key and str(merchant_key) != svc.creds.api_key:
        raise WebhookRejected("Webhook belongs to a different Safepay merchant/environment")

    event_type = str(event.get("type") or "")
    data = event.get("data") if isinstance(event.get("data"), dict) else {}
    tracker = str(data.get("tracker") or "")
    meta = data.get("metadata") if isinstance(data.get("metadata"), dict) else {}
    order_id = meta.get("order_id")
    if isinstance(order_id, dict):
        order_id = order_id.get("value")
    event_id = str(event.get("token") or "") or f"{event_type}:{tracker}:{data.get('state')}"

    db_id, already = begin_webhook_event(webhook_id=event_id, provider=PROVIDER, event_type=event_type[:100],
                                         payload=raw_body.decode("utf-8", errors="replace"))
    if already:
        return {"received": True, "duplicate": True}

    try:
        txn = None
        if order_id:
            txn = get_transaction(str(order_id))
        if txn is None and tracker:
            row = execute_query(
                f"SELECT {_TXN_COLUMNS} FROM payment_transactions WHERE provider_transaction_id = ? AND payment_provider = 'safepay'",
                (tracker,), fetch_one=True, commit=False,
            )
            txn = _row_to_txn(row)
        if txn is None:
            mark_webhook_failed(db_id, "no matching transaction")
            logger.warning("Safepay webhook %s (%s) matched no transaction", event_id, event_type)
            return {"received": True, "ignored": "unknown transaction"}

        result: Dict[str, Any] = {"status": txn["status"]}
        if event_type == "payment.succeeded":
            amount = data.get("amount")
            try:
                amount = int(amount)
            except (TypeError, ValueError):
                amount = None
            mismatch = _evidence_mismatch(txn, tracker=tracker, order_id=None if order_id is None else str(order_id),
                                          amount=amount, currency=str(data.get("currency") or ""), environment=env)
            if mismatch is None and str(data.get("state") or PAID_STATE) != PAID_STATE:
                mismatch = f"unexpected tracker state {data.get('state')}"
            if mismatch:
                _flag_for_review(txn["transaction_id"], mismatch)
                mark_webhook_failed(db_id, mismatch)
                return {"received": True, "ignored": "mismatch"}
            result = fulfill(txn["transaction_id"], tracker=tracker, source="webhook")
        elif event_type == "payment.failed":
            if tracker == str(txn.get("provider_transaction_id") or ""):
                msg = str(data.get("message") or data.get("code") or "declined")
                execute_query(
                    """
                    UPDATE payment_transactions
                    SET status = 'failed', status_detail = ?, provider_status = ?, updated_at = ?
                    WHERE transaction_id = ? AND status IN ('pending', 'processing')
                    """,
                    (("declined: " + msg)[:255], str(data.get("state") or "")[:40] or None, now_db_string(),
                     txn["transaction_id"]),
                )
                result = {"status": "failed"}
        # Other event types (refunds, authorizations, subscriptions) are acknowledged and stored only.
        mark_webhook_processed(db_id)
        return {"received": True, **{k: v for k, v in result.items() if k in ("status", "credited")}}
    except Exception as exc:
        mark_webhook_failed(db_id, str(exc)[:500])
        raise


# ---------------------------------------------------------------- background reconciliation
def _age_minutes(txn: Dict[str, Any]) -> float:
    raw = txn.get("created_at")
    if isinstance(raw, datetime):
        created = raw if raw.tzinfo else raw.replace(tzinfo=timezone.utc)
    else:
        text = str(raw or "").replace("Z", "+00:00")
        try:
            created = datetime.fromisoformat(text)
        except ValueError:
            return 0.0
        if created.tzinfo is None:
            created = created.replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - created).total_seconds() / 60.0


def reconcile_open_transactions(limit: int = 50) -> Dict[str, int]:
    """Check open Safepay payments with Safepay; expire abandoned ones. Safe to run repeatedly."""
    try:
        env = active_environment()
        if not SafepayService(env).checkout_configured():
            return {"checked": 0}
    except SafepayNotConfigured:
        return {"checked": 0}
    rows = execute_query(
        f"""
        SELECT {_TXN_COLUMNS} FROM payment_transactions
        WHERE payment_provider = 'safepay' AND provider_environment = ?
          AND status IN ('pending', 'processing', 'failed') AND provider_transaction_id IS NOT NULL
        ORDER BY id DESC LIMIT {int(limit) * 4}
        """,
        (env,), fetch_all=True, commit=False,
    ) or []
    counts = {"checked": 0, "completed": 0, "expired": 0, "errors": 0}
    expiry = float(config.SAFEPAY_CHECKOUT_EXPIRY_MINUTES)
    for row in rows:
        txn = _row_to_txn(row)
        age = _age_minutes(txn)
        if txn["status"] == "failed" and (age > expiry + 15 or str(txn.get("status_detail") or "") == "checkout_start_failed"):
            continue
        if age > 48 * 60 or str(txn.get("status_detail") or "").startswith("review:"):
            continue
        if counts["checked"] >= limit:
            break
        counts["checked"] += 1
        try:
            result = reconcile(txn["transaction_id"], source="reconciler")
            if result.get("credited"):
                counts["completed"] += 1
            elif result.get("status") == "processing" and age > expiry and txn["status"] != "failed":
                if _mark_failed(txn["transaction_id"], "expired", provider_status=None, only_if_open=True):
                    counts["expired"] += 1
        except Exception as exc:
            counts["errors"] += 1
            logger.warning("Safepay reconcile failed txn=%s: %s", txn["transaction_id"], exc)
    return counts


def list_admin_recent(limit: int = 50) -> List[Dict[str, Any]]:
    rows = execute_query(
        f"SELECT {_TXN_COLUMNS} FROM payment_transactions WHERE payment_provider = 'safepay' ORDER BY id DESC LIMIT {int(limit)}",
        fetch_all=True, commit=False,
    ) or []
    return [public_status(_row_to_txn(r)) for r in rows]
