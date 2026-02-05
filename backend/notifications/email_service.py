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


def send_welcome_email(
    *,
    to_email: str,
    username: str,
    email: str,
    starting_credits: int,
) -> None:
    """Send welcome email to auto-approved user"""
    templates_dir = os.path.join(os.path.dirname(__file__), "templates")
    template_path = os.path.join(templates_dir, "welcome_email.html")
    
    from datetime import datetime
    app_url = (getattr(config, "APP_URL", "") or "").strip() or "https://app.infinitleads.pro"
    support_email = config.EMAIL_CONFIG.get("support_email", "support@infinitleads.pro")
    
    html = _render_template(
        template_path,
        {
            "username": username,
            "email": email,
            "starting_credits": str(starting_credits),
            "current_year": str(datetime.now().year),
            "support_url": f"{app_url}/support",
            "help_url": f"{app_url}/help",
        },
    )

    send_email(
        to_email=to_email,
        subject="Welcome to Infinity Leads Pro! Your Account is Ready",
        html_body=html,
    )


def send_approval_email(
    *,
    to_email: str,
    username: str,
    starting_credits: int,
) -> None:
    """Send approval notification email when admin approves user"""
    templates_dir = os.path.join(os.path.dirname(__file__), "templates")
    template_path = os.path.join(templates_dir, "approval_email.html")
    
    from datetime import datetime
    app_url = (getattr(config, "APP_URL", "") or "").strip() or "https://app.infinitleads.pro"
    support_email = config.EMAIL_CONFIG.get("support_email", "support@infinitleads.pro")
    
    html = _render_template(
        template_path,
        {
            "username": username,
            "starting_credits": str(starting_credits),
            "current_year": str(datetime.now().year),
            "login_url": f"{app_url}/login",
            "support_email": support_email,
            "support_url": f"{app_url}/support",
            "help_url": f"{app_url}/help",
        },
    )

    send_email(
        to_email=to_email,
        subject="Your Account Has Been Approved!",
        html_body=html,
    )


def send_rejection_email(
    *,
    to_email: str,
    username: str,
    admin_note: Optional[str] = None,
) -> None:
    """Send rejection notification email when admin denies user"""
    templates_dir = os.path.join(os.path.dirname(__file__), "templates")
    template_path = os.path.join(templates_dir, "rejection_email.html")
    
    from datetime import datetime
    app_url = (getattr(config, "APP_URL", "") or "").strip() or "https://app.infinitleads.pro"
    support_email = config.EMAIL_CONFIG.get("support_email", "support@infinitleads.pro")
    
    html = _render_template(
        template_path,
        {
            "username": username,
            "admin_note": admin_note or "",
            "current_year": str(datetime.now().year),
            "support_url": f"{app_url}/support",
            "help_url": f"{app_url}/help",
        },
    )

    send_email(
        to_email=to_email,
        subject="Registration Application Status Update",
        html_body=html,
    )


def send_admin_new_signup_email(
    *,
    to_email: str,
    username: str,
    user_email: str,
    created_at_iso: str,
) -> None:
    """Send admin notification email when a new user registers (pending approval)."""
    templates_dir = os.path.join(os.path.dirname(__file__), "templates")
    template_path = os.path.join(templates_dir, "admin_new_signup_email.html")

    app_url = (getattr(config, "APP_URL", "") or "").strip() or "https://app.infinitleads.pro"
    from datetime import datetime

    html = _render_template(
        template_path,
        {
            "username": username,
            "user_email": user_email,
            "created_at": created_at_iso,
            "admin_url": f"{app_url}/admin",
            "current_year": str(datetime.now().year),
        },
    )

    send_email(
        to_email=to_email,
        subject=f"New signup pending approval: {username}",
        html_body=html,
    )
