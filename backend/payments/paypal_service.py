from __future__ import annotations

import base64
import logging
import time
from typing import Any, Dict, Optional, Tuple

import requests

import config

logger = logging.getLogger(__name__)


class PayPalService:
    """
    Minimal PayPal Orders API wrapper (server-side).

    This implementation is intentionally small:
    - Create an order (redirect approval URL)
    - Capture an approved order
    """

    def __init__(self) -> None:
        self._token: Optional[str] = None
        self._token_expires_at: float = 0.0

    def _base_url(self) -> str:
        env = (config.PAYPAL_ENV or "sandbox").lower()
        if env == "live":
            return "https://api-m.paypal.com"
        return "https://api-m.sandbox.paypal.com"

    def _is_configured(self) -> bool:
        return bool(config.PAYPAL_CLIENT_ID and config.PAYPAL_CLIENT_SECRET)

    def _get_access_token(self) -> str:
        if not self._is_configured():
            raise ValueError("PayPal is not configured (missing PAYPAL_CLIENT_ID/PAYPAL_CLIENT_SECRET)")

        now = time.time()
        if self._token and (now + 30) < self._token_expires_at:
            return self._token

        auth = f"{config.PAYPAL_CLIENT_ID}:{config.PAYPAL_CLIENT_SECRET}".encode("utf-8")
        basic = base64.b64encode(auth).decode("ascii")

        url = f"{self._base_url()}/v1/oauth2/token"
        resp = requests.post(
            url,
            headers={
                "Authorization": f"Basic {basic}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            data={"grant_type": "client_credentials"},
            timeout=20,
        )
        if resp.status_code not in (200, 201):
            raise ValueError(f"Failed to authenticate with PayPal ({resp.status_code})")

        data = resp.json()
        token = str(data.get("access_token") or "")
        expires_in = int(data.get("expires_in") or 0)
        if not token or expires_in <= 0:
            raise ValueError("Invalid PayPal auth response")

        self._token = token
        self._token_expires_at = now + float(expires_in)
        return token

    def create_order(
        self,
        *,
        amount_cents: int,
        currency: str,
        description: str,
        custom_id: str,
        return_url: str,
        cancel_url: str,
        brand_name: str = "Infinity Leads",
    ) -> Tuple[str, str]:
        """
        Returns (order_id, approve_url)
        """
        token = self._get_access_token()
        url = f"{self._base_url()}/v2/checkout/orders"

        value = f"{amount_cents / 100.0:.2f}"
        payload: Dict[str, Any] = {
            "intent": "CAPTURE",
            "purchase_units": [
                {
                    "custom_id": custom_id,
                    "description": description,
                    "amount": {
                        "currency_code": currency.upper(),
                        "value": value,
                    },
                }
            ],
            "application_context": {
                "brand_name": brand_name,
                "landing_page": "LOGIN",
                "user_action": "PAY_NOW",
                "return_url": return_url,
                "cancel_url": cancel_url,
            },
        }

        resp = requests.post(
            url,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=30,
        )
        if resp.status_code not in (200, 201):
            logger.warning("PayPal create order failed: %s %s", resp.status_code, resp.text[:500])
            raise ValueError("Failed to create PayPal order")

        data = resp.json()
        order_id = str(data.get("id") or "")
        links = data.get("links") or []
        approve_url = ""
        for link in links:
            if isinstance(link, dict) and link.get("rel") in ("approve", "payer-action"):
                approve_url = str(link.get("href") or "")
                break

        if not order_id or not approve_url:
            raise ValueError("PayPal order response missing approval link")

        return order_id, approve_url

    def capture_order(self, order_id: str) -> Dict[str, Any]:
        token = self._get_access_token()
        url = f"{self._base_url()}/v2/checkout/orders/{order_id}/capture"

        resp = requests.post(
            url,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            json={},
            timeout=30,
        )
        if resp.status_code not in (200, 201):
            logger.warning("PayPal capture failed: %s %s", resp.status_code, resp.text[:500])
            raise ValueError("Failed to capture PayPal order")

        return resp.json()

