from __future__ import annotations

import io
from datetime import datetime
from typing import Any, Dict, List, Optional

from reportlab.lib import colors
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.lib.units import inch
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle

import config
from invoices.templates.invoice_template import InvoiceCompanyInfo, build_default_line_items


def _money(cents: int) -> str:
    return f"${cents / 100.0:,.2f}"


def generate_invoice_pdf_bytes(
    *,
    invoice: Dict[str, Any],
    user: Dict[str, Any],
    line_items: Optional[List[Dict[str, Any]]] = None,
) -> bytes:
    buf = io.BytesIO()

    doc = SimpleDocTemplate(
        buf,
        pagesize=LETTER,
        leftMargin=0.75 * inch,
        rightMargin=0.75 * inch,
        topMargin=0.75 * inch,
        bottomMargin=0.75 * inch,
        title=f"Invoice {invoice.get('invoice_number')}",
    )

    styles = getSampleStyleSheet()
    story: List[Any] = []

    company = InvoiceCompanyInfo(
        name=config.EMAIL_CONFIG.get("company_name", "Infinity Leads Pro"),
        address=config.EMAIL_CONFIG.get("company_address", ""),
        support_email=config.EMAIL_CONFIG.get("support_email", ""),
    )

    story.append(Paragraph(company.name, styles["Title"]))
    if company.address:
        story.append(Paragraph(company.address.replace("\n", "<br/>"), styles["Normal"]))
    if company.support_email:
        story.append(Paragraph(f"Support: {company.support_email}", styles["Normal"]))
    story.append(Spacer(1, 0.25 * inch))

    invoice_number = str(invoice.get("invoice_number") or "")
    created_at = str(invoice.get("created_at") or "")
    bill_to = user.get("billing_name") or user.get("username") or "Customer"
    bill_email = user.get("billing_email") or user.get("email") or ""

    story.append(Paragraph(f"<b>Invoice:</b> {invoice_number}", styles["Heading2"]))
    if created_at:
        story.append(Paragraph(f"<b>Date:</b> {created_at}", styles["Normal"]))
    story.append(Paragraph(f"<b>Billed To:</b> {bill_to}", styles["Normal"]))
    if bill_email:
        story.append(Paragraph(f"<b>Email:</b> {bill_email}", styles["Normal"]))
    story.append(Spacer(1, 0.2 * inch))

    items = line_items or build_default_line_items(invoice)

    data = [["Description", "Qty", "Unit Price", "Total"]]
    for it in items:
        qty = int(it.get("quantity") or 1)
        unit = int(it.get("unit_price_cents") or 0)
        total = int(it.get("total_cents") or (unit * qty))
        data.append([str(it.get("description") or ""), str(qty), _money(unit), _money(total)])

    tbl = Table(data, hAlign="LEFT", colWidths=[3.5 * inch, 0.6 * inch, 1.2 * inch, 1.2 * inch])
    tbl.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#111827")),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#E5E7EB")),
                ("BACKGROUND", (0, 1), (-1, -1), colors.white),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("PADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    story.append(tbl)
    story.append(Spacer(1, 0.2 * inch))

    subtotal_cents = int(invoice.get("amount_cents") or 0)
    tax_cents = int(invoice.get("tax_amount_cents") or 0)
    total_cents = int(invoice.get("total_amount_cents") or 0)

    totals = Table(
        [
            ["Subtotal", _money(subtotal_cents)],
            ["Tax", _money(tax_cents)],
            ["Total", _money(total_cents)],
        ],
        hAlign="RIGHT",
        colWidths=[1.2 * inch, 1.2 * inch],
    )
    totals.setStyle(
        TableStyle(
            [
                ("FONTNAME", (0, 0), (-1, -2), "Helvetica"),
                ("FONTNAME", (0, -1), (-1, -1), "Helvetica-Bold"),
                ("LINEABOVE", (0, -1), (-1, -1), 1, colors.HexColor("#111827")),
                ("ALIGN", (0, 0), (-1, -1), "RIGHT"),
                ("PADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    story.append(totals)
    story.append(Spacer(1, 0.3 * inch))

    story.append(Paragraph("Thank you for your business.", styles["Italic"]))

    doc.build(story)
    return buf.getvalue()

