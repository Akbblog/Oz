from __future__ import annotations

import hashlib
import hmac
import json
import logging
from typing import Any, Dict, Optional

import requests

import config

logger = logging.getLogger(__name__)


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

    def _headers(self) -> Dict[str, str]:
        return {
            "X-CC-Api-Key": self.api_key,
            "X-CC-Version": self.API_VERSION,
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

    def create_charge(
        self,
        *,
        name: str,
        description: str,
        amount: str,
        currency: str,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        payload: Dict[str, Any] = {
            "name": name,
            "description": description,
            "pricing_type": "fixed_price",
            "local_price": {"amount": amount, "currency": currency.upper()},
        }
        if metadata:
            payload["metadata"] = metadata

        resp = requests.post(
            f"{self.API_BASE}/charges",
            headers=self._headers(),
            data=json.dumps(payload),
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()["data"]

    def get_charge(self, charge_id: str) -> Dict[str, Any]:
        resp = requests.get(
            f"{self.API_BASE}/charges/{charge_id}",
            headers=self._headers(),
            timeout=30,
        )
        resp.raise_for_status()
        return resp.json()["data"]

    def verify_webhook(self, raw_body: bytes, signature_header: str) -> bool:
        """
        Verify Coinbase Commerce webhook signature (HMAC SHA256).
        Header: X-CC-Webhook-Signature
        """
        if not self.webhook_secret:
            return False

        expected = hmac.new(
            key=self.webhook_secret.encode("utf-8"),
            msg=raw_body,
            digestmod=hashlib.sha256,
        ).hexdigest()
        return hmac.compare_digest(expected, signature_header or "")

