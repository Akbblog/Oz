from __future__ import annotations

import os
from typing import Any, Dict, Optional, Tuple


EU_COUNTRY_CODES = {
    "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR",
    "HU", "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK",
    "SI", "ES", "SE",
}


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except Exception:
        return default


def calculate_tax_cents(
    *,
    subtotal_cents: int,
    billing_address: Optional[Dict[str, Any]] = None,
) -> Tuple[int, str]:
    """
    Very small tax helper:
    - Applies VAT for EU addresses if VAT_RATE_EU is set (percentage)
    - Applies GST for AU addresses if GST_RATE_AU is set (percentage)
    - Otherwise 0

    Returns: (tax_cents, tax_label)
    """
    if subtotal_cents <= 0:
        return 0, "none"

    country = None
    if billing_address:
        country = billing_address.get("country") or billing_address.get("country_code")
    if not country:
        return 0, "none"

    country = str(country).upper()

    if country in EU_COUNTRY_CODES:
        rate = _env_float("VAT_RATE_EU", 0.0)
        if rate <= 0:
            return 0, "none"
        return int(round(subtotal_cents * (rate / 100.0))), f"vat_{rate:g}%"

    if country == "AU":
        rate = _env_float("GST_RATE_AU", 0.0)
        if rate <= 0:
            return 0, "none"
        return int(round(subtotal_cents * (rate / 100.0))), f"gst_{rate:g}%"

    return 0, "none"

