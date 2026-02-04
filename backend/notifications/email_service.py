from __future__ import annotations

import os
import smtplib
from dataclasses import dataclass
from email.message import EmailMessage
from typing import Dict, List, Optional, Tuple

import config


@dataclass(frozen=True)
class EmailAttachment:
    filename: str
    content_type: str
    data: bytes


def _render_template(template_path: str, variables: Dict[str, str]) -> str:
    with open(template_path, "r", encoding="utf-8") as f:
        html = f.read()
    for k, v in variables.items():
        html = html.replace("{{" + k + "}}", v)
    return html


def send_email(
    *,
    to_email: str,
    subject: str,
    html_body: str,
    attachments: Optional[List[EmailAttachment]] = None,
) -> None:
    msg = EmailMessage()
    from_name = config.EMAIL_CONFIG.get("from_name", "Infinity Leads Pro")
    from_email = getattr(config, "FROM_EMAIL", None) or config.SMTP_USER

    msg["Subject"] = subject
    msg["From"] = f"{from_name} <{from_email}>"
    msg["To"] = to_email

    msg.set_content("This email requires an HTML-capable client.")
    msg.add_alternative(html_body, subtype="html")

    for att in attachments or []:
        maintype, subtype = (att.content_type.split("/", 1) + ["octet-stream"])[:2]
        msg.add_attachment(att.data, maintype=maintype, subtype=subtype, filename=att.filename)

    host = config.SMTP_HOST
    port = int(config.SMTP_PORT)
    user = config.SMTP_USER
    password = config.SMTP_PASSWORD

    with smtplib.SMTP(host, port, timeout=20) as smtp:
        smtp.ehlo()
        smtp.starttls()
        smtp.ehlo()
        if user and password and "your_" not in password:
            smtp.login(user, password)
        smtp.send_message(msg)


def send_invoice_email(
    *,
    to_email: str,
    invoice_number: str,
    invoice_pdf_bytes: bytes,
    amount_display: str,
    date_display: str,
) -> None:
    templates_dir = os.path.join(os.path.dirname(__file__), "templates")
    template_path = os.path.join(templates_dir, "invoice_email.html")
    html = _render_template(
        template_path,
        {
            "invoice_number": invoice_number,
            "support_email": config.EMAIL_CONFIG.get("support_email", ""),
        },
    )

    send_email(
        to_email=to_email,
        subject=f"Invoice {invoice_number}",
        html_body=html,
        attachments=[
            EmailAttachment(
                filename=f"{invoice_number}.pdf",
                content_type="application/pdf",
                data=invoice_pdf_bytes,
            )
        ],
    )

