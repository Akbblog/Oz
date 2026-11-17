"""Possible-match detection for imports (plan section 5, "Identity and dedupe rules").

A scraped result is a *possible match* of an existing workspace company when:

1. both have the same Google Maps place identity (``same_maps_place``), or
2. the normalized website host is equal and the names are compatible
   (``same_website_and_name``), or
3. the normalized phone is equal and the names are compatible
   (``same_phone_and_name``).

Name alone never matches. When both sides carry a Maps place identity and the
identities differ they are different places (e.g. two branches of a chain that
share a website), so rules 2 and 3 are not applied. Shared hosts such as social
networks or site builders are not used as a website signal. Matching is always
within one workspace; the caller scopes every query.
"""

from __future__ import annotations

import re
import unicodedata
from typing import Any, Dict, List, Optional, Set
from urllib.parse import urlparse

# Same patterns as job_service.dedupe_key_for (feature id / place id inside data=).
_CID_RE = re.compile(r"!1s(0x[0-9a-f]+:0x[0-9a-f]+)", re.IGNORECASE)
_PLACE_ID_RE = re.compile(r"!19s(ChIJ[\w-]+)")

_SHARED_HOSTS = {
    "facebook.com", "fb.com", "m.facebook.com", "instagram.com", "twitter.com", "x.com", "linkedin.com",
    "youtube.com", "tiktok.com", "linktr.ee", "wa.me", "whatsapp.com", "api.whatsapp.com", "google.com",
    "maps.google.com", "goo.gl", "g.page", "business.site", "sites.google.com", "wixsite.com", "wix.com",
    "squarespace.com", "wordpress.com", "blogspot.com", "weebly.com", "godaddysites.com", "yelp.com",
    "tripadvisor.com", "booking.com", "t.me", "bit.ly", "linktree.com", "carrd.co", "jimdosite.com",
}

_LEGAL_WORDS = {
    "the", "llc", "l.l.c", "ltd", "limited", "inc", "incorporated", "co", "company", "corp", "corporation",
    "plc", "gmbh", "sarl", "sa", "bv", "pty", "pvt", "fze", "fzco", "fz", "est", "wll", "and", "&",
}


def place_key(maps_url: Any) -> Optional[str]:
    """``id:<feature id or place id>`` from a Google Maps URL, else None."""
    url = str(maps_url or "")
    m = _CID_RE.search(url) or _PLACE_ID_RE.search(url)
    return ("id:" + m.group(1).lower()) if m else None


def website_host(website: Any) -> Optional[str]:
    text = str(website or "").strip()
    if not text:
        return None
    if "://" not in text:
        text = "http://" + text
    try:
        host = (urlparse(text).hostname or "").lower().strip(".")
    except ValueError:
        return None
    if host.startswith("www."):
        host = host[4:]
    if not host or "." not in host:
        return None
    for shared in _SHARED_HOSTS:
        if host == shared or host.endswith("." + shared):
            return None
    return host[:191]


def phone_key(phone: Any) -> Optional[str]:
    digits = re.sub(r"\D", "", str(phone or ""))
    if len(digits) < 7:
        return None
    # Compare national significant digits so "+974 4444 5555" equals "4444 5555"-style
    # variants with/without a country code.
    return digits[-9:] if len(digits) > 9 else digits


def _strip_accents(text: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c))


def name_key(name: Any) -> Optional[str]:
    text = _strip_accents(str(name or "")).casefold()
    text = re.sub(r"[^\w\s&]", " ", text)
    tokens = [t for t in text.split() if t and t not in _LEGAL_WORDS]
    key = " ".join(tokens)
    return key[:191] or None


def names_compatible(a: Optional[str], b: Optional[str]) -> bool:
    if not a or not b:
        return False
    if a == b:
        return True
    ta: Set[str] = set(a.split())
    tb: Set[str] = set(b.split())
    if not ta or not tb:
        return False
    small, big = (ta, tb) if len(ta) <= len(tb) else (tb, ta)
    if small <= big and sum(len(t) for t in small) >= 3:
        return True
    return len(ta & tb) / len(ta | tb) >= 0.6


def keys_for(name: Any, phone: Any, website: Any, maps_url: Any) -> Dict[str, Optional[str]]:
    return {
        "match_place_key": place_key(maps_url),
        "match_host": website_host(website),
        "match_phone": phone_key(phone),
        "match_name": name_key(name),
    }


def match_reasons(keys: Dict[str, Optional[str]], company: Dict[str, Any]) -> List[str]:
    """Reasons why ``keys`` (a new result) may be the same business as ``company``."""
    a_place, b_place = keys.get("match_place_key"), company.get("match_place_key")
    if a_place and b_place:
        return ["same_maps_place"] if a_place == b_place else []
    reasons: List[str] = []
    compatible = names_compatible(keys.get("match_name"), company.get("match_name"))
    if not compatible:
        return reasons
    if keys.get("match_host") and keys.get("match_host") == company.get("match_host"):
        reasons.append("same_website_and_name")
    if keys.get("match_phone") and keys.get("match_phone") == company.get("match_phone"):
        reasons.append("same_phone_and_name")
    return reasons
