"""Safepay Payments 2.0 client (Express Checkout / hosted ``/embedded/`` page).

Raw HTTP on purpose: the flow below was verified against Safepay's current
Payments 2.0 docs and the safepay-python 0.1.0 SDK source (the older SDK
releases implement the retired v1 ``/order/v1/init`` + ``sig`` redirect flow).

Flow:
  1. ``POST {api}/order/payments/v3/``  -> tracker token (``track_...``)
  2. ``POST {api}/client/passport/v1/token`` -> short-lived ``tbt`` (1 hour)
  3. browser -> ``{checkout}/embedded/?tbt&tracker&environment&source=hosted&...``
  4. Safepay -> ``POST /api/webhooks/safepay`` (``X-SFPY-SIGNATURE`` =
     hex HMAC-SHA512 of the body with the endpoint's shared secret)
  5. ``GET {api}/reporter/api/v1/payments/{tracker}`` for server-side checks.

The browser redirect carries no signature in Payments 2.0 and is never trusted.
All amounts are integers in minor units (US cents for USD).
"""
from __future__ import annotations

import hashlib
import hmac
import json
import logging
from dataclasses import dataclass
from typing import Any, Dict, Optional
from urllib.parse import urlencode

import requests

import config

logger = logging.getLogger(__name__)

# Hosts are fixed per environment and are NOT configurable, so a typo in an env var
# can never point sandbox credentials at production or the reverse.
ENVIRONMENTS: Dict[str, Dict[str, str]] = {
    "sandbox": {
        "api": "https://sandbox.api.getsafepay.com",
        "checkout": "https://sandbox.api.getsafepay.com",
    },
    "production": {
        "api": "https://api.getsafepay.com",
        "checkout": "https://getsafepay.com",
    },
}

PAID_STATE = "TRACKER_ENDED"
# Tracker states after which no payment will happen on this tracker.
DEAD_STATES = {"TRACKER_CANCELLED", "TRACKER_EXPIRED", "TRACKER_VOIDED", "TRACKER_REVERSED"}


class SafepayError(Exception):
    """Safepay request failed or returned something unusable."""


class SafepayNotConfigured(SafepayError):
    """The active Safepay environment has no credentials."""


class SafepayUnavailable(SafepayError):
    """Network error / 5xx from Safepay - safe to retry later."""


@dataclass(frozen=True)
class SafepayCredentials:
    environment: str
    api_key: str
    secret_key: str
    webhook_secret: str


def active_environment() -> str:
    env = (config.SAFEPAY_ENV or "sandbox").strip().lower()
    if env in ("live", "prod"):
        env = "production"
    if env not in ENVIRONMENTS:
        raise SafepayNotConfigured(f"Unknown SAFEPAY_ENV {env!r} (use 'sandbox' or 'production')")
    return env


def credentials_for(environment: str) -> SafepayCredentials:
    """Each environment reads only its own variables - never a fallback across them."""
    if environment == "sandbox":
        return SafepayCredentials(
            "sandbox",
            config.SAFEPAY_SANDBOX_API_KEY,
            config.SAFEPAY_SANDBOX_SECRET_KEY,
            config.SAFEPAY_SANDBOX_WEBHOOK_SECRET,
        )
    if environment == "production":
        return SafepayCredentials(
            "production",
            config.SAFEPAY_LIVE_API_KEY,
            config.SAFEPAY_LIVE_SECRET_KEY,
            config.SAFEPAY_LIVE_WEBHOOK_SECRET,
        )
    raise SafepayNotConfigured(f"Unknown Safepay environment {environment!r}")


def _check_no_cross_environment_reuse(creds: SafepayCredentials) -> None:
    other = credentials_for("sandbox" if creds.environment == "production" else "production")
    for mine, theirs in (
        (creds.api_key, other.api_key),
        (creds.secret_key, other.secret_key),
        (creds.webhook_secret, other.webhook_secret),
    ):
        if mine and theirs and hmac.compare_digest(mine, theirs):
            raise SafepayNotConfigured(
                "Sandbox and production Safepay credentials are identical; refusing to use them"
            )


class SafepayService:
    def __init__(self, environment: Optional[str] = None, timeout: float = 20.0) -> None:
        self.environment = environment or active_environment()
        self.hosts = ENVIRONMENTS[self.environment]
        self.creds = credentials_for(self.environment)
        self.timeout = timeout

    # ---- configuration -------------------------------------------------
    def checkout_configured(self) -> bool:
        return bool(self.creds.api_key and self.creds.secret_key)

    def webhook_configured(self) -> bool:
        return bool(self.creds.webhook_secret)

    def _require_api(self) -> None:
        if not self.checkout_configured():
            raise SafepayNotConfigured(f"Safepay {self.environment} API credentials are not set")
        _check_no_cross_environment_reuse(self.creds)

    def _headers(self) -> Dict[str, str]:
        return {"X-SFPY-MERCHANT-SECRET": self.creds.secret_key, "Content-Type": "application/json"}

    def _request(self, method: str, path: str, body: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        self._require_api()
        url = f"{self.hosts['api']}{path}"
        try:
            resp = requests.request(method, url, headers=self._headers(), json=body, timeout=self.timeout)
        except requests.RequestException as exc:
            raise SafepayUnavailable(f"Safepay {method} {path} network error: {type(exc).__name__}") from exc
        if resp.status_code >= 500 or resp.status_code == 429:
            raise SafepayUnavailable(f"Safepay {method} {path} returned {resp.status_code}")
        try:
            payload = resp.json()
        except ValueError as exc:
            raise SafepayError(f"Safepay {method} {path} returned non-JSON ({resp.status_code})") from exc
        if resp.status_code >= 400:
            msg = ""
            if isinstance(payload, dict):
                status = payload.get("status") or {}
                msg = "; ".join(str(e) for e in (status.get("errors") or [])) or str(status.get("message") or "")
            raise SafepayError(f"Safepay {method} {path} returned {resp.status_code}: {msg[:200]}")
        if not isinstance(payload, dict):
            raise SafepayError(f"Safepay {method} {path} returned an unexpected body")
        return payload

    # ---- checkout ------------------------------------------------------
    def create_session(self, *, amount_minor: int, currency: str, order_id: str) -> Dict[str, Any]:
        """Create a payment tracker. Returns the ``data.tracker`` object."""
        if int(amount_minor) <= 0:
            raise ValueError("amount must be positive")
        body = {
            "merchant_api_key": self.creds.api_key,
            "intent": "CYBERSOURCE",
            "mode": "payment",
            "currency": currency,
            "amount": int(amount_minor),
            "metadata": {"order_id": order_id},
        }
        payload = self._request("POST", "/order/payments/v3/", body)
        tracker = ((payload.get("data") or {}).get("tracker")) or {}
        token = str(tracker.get("token") or "")
        if not token.startswith("track_"):
            raise SafepayError("Safepay did not return a tracker token")
        quote = ((tracker.get("purchase_totals") or {}).get("quote_amount")) or {}
        if str(quote.get("currency") or "").upper() != currency.upper() or int(quote.get("amount") or -1) != int(amount_minor):
            # Never send a customer to a page showing a different amount than we priced.
            raise SafepayError("Safepay session amount/currency does not match the order")
        return tracker

    def create_auth_token(self) -> str:
        payload = self._request("POST", "/client/passport/v1/token")
        tbt = payload.get("data")
        if not isinstance(tbt, str) or not tbt:
            raise SafepayError("Safepay did not return a checkout auth token")
        return tbt

    def checkout_url(self, *, tracker: str, tbt: str, order_id: str, redirect_url: str, cancel_url: str) -> str:
        query = urlencode({
            "tbt": tbt,
            "tracker": tracker,
            "environment": self.environment,
            "source": "hosted",
            "order_id": order_id,
            "redirect_url": redirect_url,
            "cancel_url": cancel_url,
        })
        return f"{self.hosts['checkout']}/embedded/?{query}"

    # ---- verification --------------------------------------------------
    def fetch_tracker(self, tracker: str) -> Dict[str, Any]:
        if not str(tracker).startswith("track_"):
            raise ValueError("invalid tracker token")
        payload = self._request("GET", f"/reporter/api/v1/payments/{tracker}")
        data = payload.get("data") or {}
        if not isinstance(data, dict):
            raise SafepayError("Safepay tracker lookup returned an unexpected body")
        return data

    def verify_webhook_signature(self, raw_body: bytes, signature: str) -> bool:
        """Hex HMAC-SHA512 with the endpoint shared secret.

        Safepay's SDKs sign the JSON body; the PHP/WooCommerce reference re-encodes it
        compactly before signing, so the compact re-encoding is accepted as a fallback
        (same rule as safepay-python 0.1.0).
        """
        secret = self.creds.webhook_secret
        if not secret or not signature:
            return False
        sig = signature.strip().lower()
        key = secret.encode("utf-8")

        def matches(body: bytes) -> bool:
            digest = hmac.new(key, body, hashlib.sha512).hexdigest()
            return hmac.compare_digest(digest, sig)

        if matches(raw_body):
            return True
        try:
            compact = json.dumps(json.loads(raw_body.decode("utf-8")), separators=(",", ":")).encode("utf-8")
        except (ValueError, UnicodeDecodeError):
            return False
        return compact != raw_body and matches(compact)

    def signature_scheme(self, raw_body: bytes, signature: str) -> Optional[str]:
        """Which signing rule the delivery satisfies: 'v2' (whole body, Payments 2.0),
        'legacy' (v1 rule: HMAC-SHA512 of the compact JSON of body["data"] only), or None.

        Only 'v2' deliveries may ever change payment state; a legacy signature covers just
        the data object, not the event type/version, so legacy events are acknowledged only.
        """
        if self.verify_webhook_signature(raw_body, signature):
            return "v2"
        secret = self.creds.webhook_secret
        if not secret or not signature:
            return None
        try:
            body = json.loads(raw_body.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return None
        if not isinstance(body, dict) or "data" not in body:
            return None
        legacy = json.dumps(body["data"], separators=(",", ":")).encode("utf-8")
        digest = hmac.new(secret.encode("utf-8"), legacy, hashlib.sha512).hexdigest()
        return "legacy" if hmac.compare_digest(digest, signature.strip().lower()) else None


def summarize_tracker(data: Dict[str, Any]) -> Dict[str, Any]:
    """Normalise both reporter response shapes (flat and ``data.tracker``)."""
    t = data.get("tracker") if isinstance(data.get("tracker"), dict) else data
    totals = t.get("purchase_totals") or {}
    quote = totals.get("quote_amount") or {}
    base = totals.get("base_amount") or {}
    rate = (totals.get("conversion_rate") or {}).get("rate")
    order_id = None
    meta = t.get("metadata") or {}
    if isinstance(meta, dict):
        raw = meta.get("order_id")
        order_id = raw.get("value") if isinstance(raw, dict) else raw
    return {
        "token": str(t.get("token") or ""),
        "environment": str(t.get("environment") or ""),
        "state": str(t.get("state") or ""),
        "amount": _int_or_none(quote.get("amount")),
        "currency": str(quote.get("currency") or "").upper(),
        "base_amount": _int_or_none(base.get("amount")),
        "base_currency": str(base.get("currency") or "").upper() or None,
        "fx_rate": None if rate is None else str(rate),
        "order_id": None if order_id is None else str(order_id),
    }


def _int_or_none(value: Any) -> Optional[int]:
    try:
        return None if value is None else int(value)
    except (TypeError, ValueError):
        return None
