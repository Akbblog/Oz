from __future__ import annotations

import base64
import json
import os
from typing import Any, Dict, Optional, Tuple

import config
from db.base import execute_query
from db.payment_crud import get_invoice_by_id, update_invoice_pdf_path
from invoices.invoice_generator import generate_invoice_pdf_bytes


def _invoice_dir() -> str:
    base = os.path.dirname(__file__)
    out_dir = os.path.join(os.path.dirname(base), str(config.PAYMENT_CONFIG.get("invoice_dir", "invoices")))
    os.makedirs(out_dir, exist_ok=True)
    return out_dir


def _load_user_for_invoice(user_id: int) -> Dict[str, Any]:
    row = execute_query(
        "SELECT id, username, email, billing_name, billing_email, billing_address, tax_id FROM users WHERE id = ?",
        (user_id,),
        fetch_one=True,
        commit=False,
    )
    if not row:
        return {"id": user_id}
    return {
        "id": row[0],
        "username": row[1],
        "email": row[2],
        "billing_name": row[3],
        "billing_email": row[4],
        "billing_address": row[5],
        "tax_id": row[6],
    }


def ensure_invoice_pdf(invoice_id: int) -> Tuple[str, bytes]:
    """
    Ensure invoice has a generated PDF on disk.
    Returns: (pdf_path, pdf_bytes)
    """
    inv = get_invoice_by_id(invoice_id)
    if not inv:
        raise ValueError("Invoice not found")

    # invoices schema: id, invoice_number, user_id, transaction_id, subscription_id, invoice_type,
    # amount_cents, tax_amount_cents, total_amount_cents, status, pdf_path, line_items, billing_name,
    # billing_email, billing_address, created_at, updated_at
    invoice = {
        "id": inv[0],
        "invoice_number": inv[1],
        "user_id": inv[2],
        "transaction_id": inv[3],
        "subscription_id": inv[4],
        "invoice_type": inv[5],
        "amount_cents": inv[6],
        "tax_amount_cents": inv[7],
        "total_amount_cents": inv[8],
        "status": inv[9],
        "pdf_path": inv[10],
        "line_items": inv[11],
        "billing_name": inv[12],
        "billing_email": inv[13],
        "billing_address": inv[14],
        "created_at": inv[15],
        "updated_at": inv[16],
    }

    existing_path = invoice.get("pdf_path")
    if existing_path and os.path.exists(existing_path):
        with open(existing_path, "rb") as f:
            return existing_path, f.read()

    user = _load_user_for_invoice(int(invoice["user_id"]))

    line_items = None
    if invoice.get("line_items"):
        try:
            line_items = json.loads(invoice["line_items"])
        except Exception:
            line_items = None

    pdf_bytes = generate_invoice_pdf_bytes(invoice=invoice, user=user, line_items=line_items)
    filename = f"{invoice['invoice_number']}.pdf"
    out_path = os.path.join(_invoice_dir(), filename)
    with open(out_path, "wb") as f:
        f.write(pdf_bytes)

    update_invoice_pdf_path(invoice_id, out_path)
    return out_path, pdf_bytes

