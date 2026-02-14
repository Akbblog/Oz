"""
Vercel Serverless Function Entry Point
Serves only static data endpoints (no Playwright/scraping)
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from functools import lru_cache
import json
import os

app = FastAPI(title="Business Scraper API", version="2.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "backend")

_COUNTRY_DATA_FILES = {
    "USA": "states_cities_data.json",
    "UK": "uk_regions_cities.json",
    "UAE": "uae_cities_data.json",
    "KSA": "ksa_cities_data.json",
    "Australia": "australia_cities_data.json",
    "Canada": "canada_cities_data.json",
    "India": "india_cities_data.json",
    "Qatar": "qatar_cities_data.json",
    "Indonesia": "indonesia_cities_data.json",
    "Finland": "finland_cities_data.json",
    "Germany": "germany_cities_data.json",
    "France": "france_cities_data.json",
}

_COUNTRY_REGION_FIELD = {
    "USA": "state",
    "UK": "region",
    "UAE": "emirate",
    "KSA": "region",
    "Australia": "state",
    "Canada": "province",
    "India": "state",
    "Qatar": "region",
    "Indonesia": "province",
    "Finland": "region",
    "Germany": "state",
    "France": "region",
}


@lru_cache(maxsize=None)
def _load_country_data(country: str) -> dict:
    filename = _COUNTRY_DATA_FILES.get(country)
    if not filename:
        raise KeyError(f"Unknown country: {country}")
    path = os.path.join(DATA_DIR, filename)
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _find_country_for_region(region: str):
    for country in _COUNTRY_DATA_FILES.keys():
        if region in _load_country_data(country):
            return country
    return None


@app.get("/")
@app.get("/api")
async def root():
    return {
        "message": "Business Scraper API",
        "version": "2.0.0",
        "note": "Scraping disabled on Vercel",
    }


@app.get("/api/health")
async def health_check():
    from datetime import datetime

    return {"status": "healthy", "timestamp": datetime.now().isoformat()}


@app.get("/api/countries")
async def get_countries():
    return {"countries": list(_COUNTRY_DATA_FILES.keys())}


@app.get("/api/states")
async def get_states():
    return {country: list(_load_country_data(country).keys()) for country in _COUNTRY_DATA_FILES.keys()}


@app.get("/api/states/{state}/cities")
async def get_cities(state: str):
    from fastapi import HTTPException

    country = _find_country_for_region(state)
    if not country:
        raise HTTPException(status_code=404, detail="State or region not found")

    data = _load_country_data(country)
    payload = {"country": country, "cities": data[state]}
    payload[_COUNTRY_REGION_FIELD.get(country, "region")] = state
    return payload


# Vercel serverless handler
handler = app
