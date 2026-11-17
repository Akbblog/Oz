"""Country / region / city reference data.

Owns the registry of per-country data files (``config.*_DATA_FILE``) and the
lookups built on them. Kept free of FastAPI / database imports so both
``main`` and ``job_service`` can use it without import cycles.

Location strings are always ``"City, Region"``. Historical jobs keep the
strings they were created with; ``derive_job_location`` resolves them at read
time and never writes anything back.
"""

from __future__ import annotations

import json
import os
from functools import lru_cache
from typing import Dict, Iterable, List, Optional, Tuple

import config

BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
REMOVED_LOCATIONS_FILE = os.path.join(BACKEND_DIR, "data", "removed_locations.json")

COUNTRY_DATA_FILES: Dict[str, str] = {
    "USA": config.USA_DATA_FILE,
    "UK": config.UK_DATA_FILE,
    "UAE": config.UAE_DATA_FILE,
    "KSA": config.KSA_DATA_FILE,
    "Australia": config.AUSTRALIA_DATA_FILE,
    "Canada": config.CANADA_DATA_FILE,
    "India": config.INDIA_DATA_FILE,
    "Qatar": config.QATAR_DATA_FILE,
    "Indonesia": config.INDONESIA_DATA_FILE,
    "Malaysia": config.MALAYSIA_DATA_FILE,
    "Singapore": config.SINGAPORE_DATA_FILE,
    "China": config.CHINA_DATA_FILE,
    "Finland": config.FINLAND_DATA_FILE,
    "Germany": config.GERMANY_DATA_FILE,
    "France": config.FRANCE_DATA_FILE,
}

COUNTRY_REGION_FIELD: Dict[str, str] = {
    "USA": "state",
    "UK": "region",
    "UAE": "emirate",
    "KSA": "region",
    "Australia": "state",
    "Canada": "province",
    "India": "state",
    "Qatar": "region",
    "Indonesia": "province",
    "Malaysia": "state",
    "Singapore": "region",
    "China": "province",
    "Finland": "region",
    "Germany": "state",
    "France": "region",
}


@lru_cache(maxsize=None)
def load_country_data(country: str) -> dict:
    filename = COUNTRY_DATA_FILES.get(country)
    if not filename:
        raise KeyError(f"Unknown country: {country}")
    path = os.path.join(BACKEND_DIR, filename)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def find_country_for_region(region: str) -> Optional[str]:
    for country in COUNTRY_DATA_FILES.keys():
        data = load_country_data(country)
        if region in data:
            return country
    return None


@lru_cache(maxsize=1)
def load_removed_locations() -> Dict[str, Dict[str, List[str]]]:
    """``{country: {region: [strings no longer listed]}}`` (see data/CURATION.md)."""
    try:
        with open(REMOVED_LOCATIONS_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


@lru_cache(maxsize=1)
def _entry_index() -> Dict[str, Tuple[str, str]]:
    """Exact location string -> (country, region), including removed entries,
    so historical jobs that used a since-removed string still resolve."""
    index: Dict[str, Tuple[str, str]] = {}
    for country in COUNTRY_DATA_FILES.keys():
        for region, items in load_country_data(country).items():
            for item in items or []:
                if isinstance(item, str):
                    index.setdefault(item.strip(), (country, region))
    for country, regions in load_removed_locations().items():
        if country not in COUNTRY_DATA_FILES or not isinstance(regions, dict):
            continue
        for region, items in regions.items():
            for item in items or []:
                if isinstance(item, str):
                    index.setdefault(item.strip(), (country, region))
    return index


@lru_cache(maxsize=1)
def _country_names() -> Dict[str, str]:
    return {c.lower(): c for c in COUNTRY_DATA_FILES.keys()}


def resolve_location(entry: str) -> Tuple[Optional[str], Optional[str]]:
    """``(country, region)`` for one stored location string; ``None`` when unknown.

    1. exact match against the data files (and the removed list), so entries such
       as ``"Al Hamra, Jeddah"`` resolve to their listed region;
    2. otherwise the text after the last comma, when it is a known region;
    3. otherwise that text when it names a country (``"Doha, Qatar"``): region unknown.
    """
    if not isinstance(entry, str) or not entry.strip():
        return None, None
    text = entry.strip()
    hit = _entry_index().get(text)
    if hit:
        return hit
    if "," not in text:
        return None, None
    suffix = text.rsplit(",", 1)[1].strip()
    if not suffix:
        return None, None
    country = find_country_for_region(suffix)
    if country:
        return country, suffix
    named = _country_names().get(suffix.lower())
    if named:
        return named, None
    return None, None


def derive_job_location(cities: Iterable[str]) -> Dict[str, object]:
    """Read-time ``country`` / ``region`` / ``regions`` for a job's stored city strings."""
    country: Optional[str] = None
    regions: List[str] = []
    for entry in cities or []:
        c, r = resolve_location(entry)
        if c and country is None:
            country = c
        if r and r not in regions:
            regions.append(r)
    return {"country": country, "region": regions[0] if regions else None, "regions": regions}
