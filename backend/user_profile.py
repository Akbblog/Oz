"""
user_profile.py - clean, comparable account data.

* Phone numbers are validated against the real numbering plan of their
  country and stored in one format (E.164, "+923001234567") with the country
  in its own column, so "which country is this user from" is a column, not a
  guess.
* Emails are trimmed and lower-cased; throwaway inbox domains are refused.
* The sign-up context (IP, country, device, where the visitor came from) is
  captured once, at registration.

Nothing here talks to the network.
"""

from __future__ import annotations

import logging
import re
from typing import Any, Dict, Mapping, Optional

logger = logging.getLogger(__name__)

try:  # The library is small and pure Python; degrade to "store as typed" without it.
    import phonenumbers
    from phonenumbers import NumberParseException, PhoneNumberFormat
except Exception:  # pragma: no cover - only when the dependency is missing
    phonenumbers = None  # type: ignore[assignment]

_ISO2 = re.compile(r"^[A-Za-z]{2}$")
MAX_NAME = 120


class PhoneError(ValueError):
    """The number cannot be a real number for the chosen country."""


def clean_text(value: Any, max_len: int = MAX_NAME) -> Optional[str]:
    """Trim, collapse inner whitespace, cap the length; '' -> None."""
    if value is None:
        return None
    text = re.sub(r"\s+", " ", str(value)).strip()
    return text[:max_len] or None


def clean_country(value: Any) -> Optional[str]:
    text = (str(value).strip() if value is not None else "")
    return text.upper() if _ISO2.match(text) else None


def normalize_email(value: Any) -> str:
    return str(value or "").strip().lower()


def normalize_phone(raw: Any, country: Any = None, *, strict: bool = True) -> Dict[str, Optional[str]]:
    """Return {"phone", "country", "national"}.

    * With a country, or a number typed in international form ("+..."), the
      number must be valid: otherwise PhoneError (strict) or the text as typed
      with no country (strict=False).
    * A bare local number with no country cannot be interpreted: it is kept as
      typed with country None. Older app versions send exactly that.
    """
    text = clean_text(raw, 40)
    if not text:
        return {"phone": None, "country": None, "national": None}
    region = clean_country(country)
    as_typed = {"phone": text, "country": None, "national": None}
    if phonenumbers is None:
        return as_typed
    international = text.startswith("+") or text.startswith("00")
    if not region and not international:
        return as_typed
    try:
        candidate = "+" + text[2:] if text.startswith("00") else text
        parsed = phonenumbers.parse(candidate, None if candidate.startswith("+") else region)
        if not phonenumbers.is_valid_number(parsed):
            raise PhoneError("That phone number is not valid for the selected country.")
    except NumberParseException:
        if strict:
            raise PhoneError("That phone number is not valid for the selected country.") from None
        return as_typed
    except PhoneError:
        if strict:
            raise
        return as_typed
    # Several countries share a dial code (+44: UK, Guernsey, Jersey...; +1: US,
    # Canada...). Keep the country the person chose when the number fits it.
    detected = phonenumbers.region_code_for_number(parsed)
    if region and phonenumbers.country_code_for_region(region) == parsed.country_code:
        chosen = region if (detected is None or phonenumbers.is_possible_number(parsed)) else detected
    else:
        chosen = detected or region
    return {
        "phone": phonenumbers.format_number(parsed, PhoneNumberFormat.E164),
        "country": chosen,
        "national": phonenumbers.format_number(parsed, PhoneNumberFormat.INTERNATIONAL),
    }


# Throwaway inbox providers. Deliberately short and conservative: only domains
# whose whole purpose is a disposable address.
_DISPOSABLE = frozenset({
    "mailinator.com", "guerrillamail.com", "guerrillamail.net", "guerrillamail.org", "sharklasers.com",
    "grr.la", "10minutemail.com", "10minutemail.net", "tempmail.com", "temp-mail.org", "temp-mail.io",
    "tempmail.net", "tempmailo.com", "tempmail.plus", "throwawaymail.com", "yopmail.com", "yopmail.net",
    "yopmail.fr", "getnada.com", "nada.email", "trashmail.com", "trashmail.net", "dispostable.com",
    "maildrop.cc", "mailnesia.com", "fakeinbox.com", "mohmal.com", "emailondeck.com", "moakt.com",
    "mintemail.com", "mytemp.email", "spamgourmet.com", "tempail.com", "tempr.email", "discard.email",
    "mailcatch.com", "inboxkitten.com", "burnermail.io", "temp-inbox.com", "minuteinbox.com",
    "1secmail.com", "1secmail.net", "1secmail.org", "emltmp.com", "tmpmail.org",
    "tmpmail.net", "tmpeml.com", "dropmail.me", "mail.tm", "mailto.plus", "fexpost.com", "rteet.com",
})


def countries_differ(phone_country: Any, signup_country: Any) -> bool:
    """True when the phone's country and the sign-up country are both known
    and do not share a dial code (UK vs Guernsey, or US vs Canada, is not a
    mismatch worth flagging)."""
    a, b = clean_country(phone_country), clean_country(signup_country)
    if not a or not b or a == b:
        return False
    if phonenumbers is None:
        return True
    ca, cb = phonenumbers.country_code_for_region(a), phonenumbers.country_code_for_region(b)
    return not (ca and ca == cb)


def is_disposable_email(email: Any) -> bool:
    domain = normalize_email(email).rpartition("@")[2]
    return bool(domain) and domain in _DISPOSABLE


def signup_context(headers: Mapping[str, str], client_host: Optional[str],
                   visitor_id: Any = None, session_id: Any = None,
                   reported_geo: Any = None) -> Dict[str, Optional[str]]:
    """Where a registration came from. Every value may be None; never raises."""
    out: Dict[str, Optional[str]] = {
        "signup_ip": None, "signup_country": None, "signup_city": None, "signup_device": None,
        "signup_source": None, "signup_referrer_host": None, "signup_campaign": None,
        "signup_visitor_id": None,
    }
    try:
        from analytics import visits

        out["signup_ip"] = visits.resolve_client_ip(headers, client_host)
        geo = visits.best_geo(headers, reported_geo)
        out["signup_country"] = geo.get("country")
        out["signup_city"] = geo.get("city")
        ua = visits.parse_user_agent(headers.get("user-agent"))
        parts = [p for p in (ua.get("browser"), ua.get("os"), ua.get("device_type")) if p]
        out["signup_device"] = " · ".join(parts)[:128] or None

        vid = visits._clean_id(visitor_id)
        sid = visits._clean_id(session_id)
        out["signup_visitor_id"] = vid
        row = None
        from db.base import execute_query

        # The visit that led here: this browser session if known, else the
        # visitor's first recorded visit (how they originally found the site).
        if sid:
            row = execute_query(
                "SELECT source, referrer_host, utm_campaign FROM site_visits WHERE session_id = ?",
                (sid,), fetch_one=True, commit=False)
        if vid:
            first = execute_query(
                "SELECT source, referrer_host, utm_campaign FROM site_visits WHERE visitor_id = ? "
                "ORDER BY first_seen_at ASC, id ASC LIMIT 1",
                (vid,), fetch_one=True, commit=False)
            # Prefer the first touch when it says more than "direct"/"internal".
            if first and (not row or (first[0] or "") not in ("", "direct", "internal")):
                row = first
        if row:
            out["signup_source"] = row[0]
            out["signup_referrer_host"] = row[1]
            out["signup_campaign"] = row[2]
    except Exception:
        logger.exception("signup context failed (non-fatal)")
    return out


def backfill_phone_countries() -> int:
    """Give existing accounts a country where the stored number is unambiguous
    (typed in international form and valid). Local-format numbers are left
    exactly as typed: guessing a country would be inventing data. Idempotent."""
    if phonenumbers is None:
        return 0
    from db.base import execute_query

    rows = execute_query(
        "SELECT id, phone FROM users WHERE phone IS NOT NULL AND phone_country IS NULL",
        fetch_all=True, commit=False) or []
    done = 0
    for user_id, phone in rows:
        text = (phone or "").strip()
        if not (text.startswith("+") or text.startswith("00")):
            continue
        result = normalize_phone(text, None, strict=False)
        if not result["country"]:
            continue
        execute_query("UPDATE users SET phone = ?, phone_country = ? WHERE id = ?",
                      (result["phone"], result["country"], user_id))
        done += 1
    return done
