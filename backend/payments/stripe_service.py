from __future__ import annotations

import logging
from typing import Any, Dict, Optional

import stripe

import config
from db.base import execute_query

logger = logging.getLogger(__name__)


class StripeService:
    def __init__(self) -> None:
        stripe.api_key = config.STRIPE_SECRET_KEY

    def _get_or_create_customer_id(self, user_id: int, email: str) -> str:
        row = execute_query(
            "SELECT stripe_customer_id FROM users WHERE id = ?",
            (user_id,),
            fetch_one=True,
            commit=False,
        )
        customer_id = row[0] if row else None
        if customer_id:
            return str(customer_id)

        customer = stripe.Customer.create(email=email, metadata={"user_id": str(user_id)})
        customer_id = customer["id"]

        execute_query(
            "UPDATE users SET stripe_customer_id = ? WHERE id = ?",
            (customer_id, user_id),
            commit=True,
        )
        return str(customer_id)

    def create_payment_intent(
        self,
        *,
        user_id: int,
        email: str,
        amount_cents: int,
        currency: str,
        transaction_id: str,
        idempotency_key: str,
        metadata: Optional[Dict[str, str]] = None,
    ) -> Dict[str, Any]:
        customer_id = self._get_or_create_customer_id(user_id, email)
        md = {"user_id": str(user_id), "transaction_id": transaction_id}
        if metadata:
            md.update({k: str(v) for k, v in metadata.items()})

        intent = stripe.PaymentIntent.create(
            amount=amount_cents,
            currency=currency.lower(),
            customer=customer_id,
            automatic_payment_methods={"enabled": True},
            metadata=md,
            idempotency_key=idempotency_key,
        )
        return dict(intent)

    def retrieve_payment_intent(self, payment_intent_id: str) -> Dict[str, Any]:
        intent = stripe.PaymentIntent.retrieve(payment_intent_id)
        return dict(intent)

    def create_subscription(
        self,
        *,
        user_id: int,
        email: str,
        stripe_price_id: str,
        idempotency_key: str,
        metadata: Optional[Dict[str, str]] = None,
        trial_period_days: Optional[int] = None,
    ) -> Dict[str, Any]:
        customer_id = self._get_or_create_customer_id(user_id, email)
        md = {"user_id": str(user_id)}
        if metadata:
            md.update({k: str(v) for k, v in metadata.items()})

        subscription = stripe.Subscription.create(
            customer=customer_id,
            items=[{"price": stripe_price_id}],
            payment_behavior="default_incomplete",
            expand=["latest_invoice.payment_intent"],
            metadata=md,
            trial_period_days=trial_period_days,
            idempotency_key=idempotency_key,
        )
        return dict(subscription)

    def cancel_subscription(self, stripe_subscription_id: str, *, at_period_end: bool) -> Dict[str, Any]:
        if at_period_end:
            sub = stripe.Subscription.modify(stripe_subscription_id, cancel_at_period_end=True)
            return dict(sub)
        sub = stripe.Subscription.delete(stripe_subscription_id)
        return dict(sub)

    def pause_subscription(self, stripe_subscription_id: str) -> Dict[str, Any]:
        sub = stripe.Subscription.modify(
            stripe_subscription_id,
            pause_collection={"behavior": "mark_uncollectible"},
        )
        return dict(sub)

    def resume_subscription(self, stripe_subscription_id: str) -> Dict[str, Any]:
        sub = stripe.Subscription.modify(stripe_subscription_id, pause_collection="")
        return dict(sub)

    def construct_event(self, payload: bytes, sig_header: str) -> Dict[str, Any]:
        event = stripe.Webhook.construct_event(
            payload=payload,
            sig_header=sig_header,
            secret=config.STRIPE_WEBHOOK_SECRET,
        )
        return dict(event)
