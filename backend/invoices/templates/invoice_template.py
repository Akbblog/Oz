from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional


@dataclass(frozen=True)
class InvoiceCompanyInfo:
    name: str
    address: str
    support_email: str


def build_default_line_items(invoice: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    Fallback when invoices.line_items is NULL.
    """
    return [
        {
            "description": f"{invoice.get('invoice_type', 'purchase').title()}",
            "quantity": 1,
            "unit_price_cents": int(invoice.get("total_amount_cents") or 0),
            "total_cents": int(invoice.get("total_amount_cents") or 0),
        }
    ]

