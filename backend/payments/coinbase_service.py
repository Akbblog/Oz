from __future__ import annotations

import hashlib
import hmac
import json
import logging
import time
from typing import Any, Dict, Optional

import requests

import config

logger = logging.getLogger(__name__)


class CoinbaseServiceError(Exception):
    """Base exception for Coinbase Commerce integration failures."""


class CoinbaseProviderUnavailableError(CoinbaseServiceError):
    """Raised when Coinbase Commerce is temporarily unavailable."""


class CoinbaseCommerceService:
    """
    Minimal Coinbase Commerce integration via REST API.

    Docs: https://commerce.coinbase.com/docs/api/
    """

    API_BASE = "https://api.commerce.coinbase.com"
    API_VERSION = "2018-03-22"

    def __init__(self) -> None:
        self.api_key = config.COINBASE_API_KEY
        self.webhook_secret = config.COINBASE_WEBHOOK_SECRET

    @staticmethod
    def _looks_placeholder(value: Optional[str]) -> bool:
        v = (value or "").strip()
        if not v:
            return True
        if v in ("...", "your_coinbase_api_key", "your_coinbase_webhook_secret"):
            return True
        if v.startswith("your_"):
            return True
        if "..." in v:
            return True
        return False

    def _ensure_configured(self) -> None:
        if self._looks_placeholder(self.api_key):
            raise ValueError("Coinbase Commerce is not configured (missing COINBASE_API_KEY)")

    def _headers(self) -> Dict[str, str]:
        return {
            "X-CC-Api-Key": self.api_key,
            "X-CC-Version": self.API_VERSION,
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    def _request(self, method: str, path: str, **kwargs: Any) -> requests.Response:
        url = f"{self.API_BASE}{path}"
        max_attempts = 3
        backoff_seconds = 1.0
        last_error: Optional[Exception] = None

        for attempt in range(1, max_attempts + 1):
            try:
                resp = requests.request(
                    method,
                    url,
                    headers=self._headers(),
                    timeout=30,
                    **kwargs,
                )
            except requests.RequestException as exc:
                last_error = exc
                logger.warning(
                    "Coinbase Commerce request failed on attempt %s/%s for %s %s: %s",
                    attempt,
                    max_attempts,
                    method,
                    path,
                    exc,
                )
                if attempt == max_attempts:
                    raise CoinbaseProviderUnavailableError(
                        "Coinbase Commerce is temporarily unavailable. Please try again shortly."
                    ) from exc
                time.sleep(backoff_seconds)
                backoff_seconds *= 2
                continue

            if resp.status_code >= 500:
                last_error = requests.HTTPError(
                    f"Coinbase Commerce {resp.status_code} for {method} {url}",
                    response=resp,
                )
                logger.warning(
                    "Coinbase Commerce returned %s on attempt %s/%s for %s %s",
                    resp.status_code,
                    attempt,
                    max_attempts,
                    method,
                    path,
                )
                if attempt == max_attempts:
                    raise CoinbaseProviderUnavailableError(
                        "Coinbase Commerce is temporarily unavailable. Please try again shortly."
                    ) from last_error
                time.sleep(backoff_seconds)
                backoff_seconds *= 2
                continue

            try:
                resp.raise_for_status()
            except requests.HTTPError as exc:
                logger.error(
                    "Coinbase Commerce request failed with status %s for %s %s: %s",
                    resp.status_code,
                    method,
                    path,
                    resp.text[:500],
                )
                raise CoinbaseServiceError("Coinbase Commerce request failed.") from exc

            return resp

        raise CoinbaseProviderUnavailableError(
            "Coinbase Commerce is temporarily unavailable. Please try again shortly."
        ) from last_error

    def create_charge(
        self,
        *,
        name: str,
        description: str,
        amount: str,
        currency: str,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        self._ensure_configured()
        payload: Dict[str, Any] = {
            "name": name,
            "description": description,
            "pricing_type": "fixed_price",
            "local_price": {"amount": amount, "currency": currency.upper()},
        }
        if metadata:
            payload["metadata"] = metadata

        resp = self._request("POST", "/charges", data=json.dumps(payload))
        return resp.json()["data"]

    def get_charge(self, charge_id: str) -> Dict[str, Any]:
        self._ensure_configured()
        resp = self._request("GET", f"/charges/{charge_id}")
        return resp.json()["data"]

    def verify_webhook(self, raw_body: bytes, signature_header: str) -> bool:
        """
        Verify Coinbase Commerce webhook signature (HMAC SHA256).
        Header: X-CC-Webhook-Signature
        """
        if self._looks_placeholder(self.webhook_secret):
            return False

        expected = hmac.new(
            key=self.webhook_secret.encode("utf-8"),
            msg=raw_body,
            digestmod=hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(expected, signature_header or "")
