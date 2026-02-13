"""
Vercel Serverless Function Entry Point
Serves only static data endpoints (no Playwright/scraping)
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
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

# Load states/cities data from local JSON files
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "backend")
with open(os.path.join(DATA_DIR, "states_cities_data.json"), "r", encoding="utf-8") as f:
    STATES_CITIES_DATA = json.load(f)
with open(os.path.join(DATA_DIR, "uk_regions_cities.json"), "r", encoding="utf-8") as f:
    UK_REGIONS_DATA = json.load(f)
with open(os.path.join(DATA_DIR, "uae_cities_data.json"), "r", encoding="utf-8") as f:
    UAE_CITIES_DATA = json.load(f)
with open(os.path.join(DATA_DIR, "ksa_cities_data.json"), "r", encoding="utf-8") as f:
    KSA_CITIES_DATA = json.load(f)
with open(os.path.join(DATA_DIR, "australia_cities_data.json"), "r", encoding="utf-8") as f:
    AUSTRALIA_CITIES_DATA = json.load(f)
with open(os.path.join(DATA_DIR, "canada_cities_data.json"), "r", encoding="utf-8") as f:
    CANADA_CITIES_DATA = json.load(f)
with open(os.path.join(DATA_DIR, "india_cities_data.json"), "r", encoding="utf-8") as f:
    INDIA_CITIES_DATA = json.load(f)
with open(os.path.join(DATA_DIR, "qatar_cities_data.json"), "r", encoding="utf-8") as f:
    QATAR_CITIES_DATA = json.load(f)
with open(os.path.join(DATA_DIR, "indonesia_cities_data.json"), "r", encoding="utf-8") as f:
    INDONESIA_CITIES_DATA = json.load(f)
with open(os.path.join(DATA_DIR, "finland_cities_data.json"), "r", encoding="utf-8") as f:
    FINLAND_CITIES_DATA = json.load(f)
with open(os.path.join(DATA_DIR, "germany_cities_data.json"), "r", encoding="utf-8") as f:
    GERMANY_CITIES_DATA = json.load(f)
with open(os.path.join(DATA_DIR, "france_cities_data.json"), "r", encoding="utf-8") as f:
    FRANCE_CITIES_DATA = json.load(f)

COUNTRIES_DATA = {
    "USA": STATES_CITIES_DATA,
    "UK": UK_REGIONS_DATA,
    "UAE": UAE_CITIES_DATA,
    "KSA": KSA_CITIES_DATA,
    "Australia": AUSTRALIA_CITIES_DATA,
    "Canada": CANADA_CITIES_DATA,
    "India": INDIA_CITIES_DATA,
    "Qatar": QATAR_CITIES_DATA,
    "Indonesia": INDONESIA_CITIES_DATA,
    "Finland": FINLAND_CITIES_DATA,
    "Germany": GERMANY_CITIES_DATA,
    "France": FRANCE_CITIES_DATA,
}


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
    return {"countries": list(COUNTRIES_DATA.keys())}


@app.get("/api/states")
async def get_states():
    return {
        "USA": list(STATES_CITIES_DATA.keys()),
        "UK": list(UK_REGIONS_DATA.keys()),
        "UAE": list(UAE_CITIES_DATA.keys()),
        "KSA": list(KSA_CITIES_DATA.keys()),
        "Australia": list(AUSTRALIA_CITIES_DATA.keys()),
        "Canada": list(CANADA_CITIES_DATA.keys()),
        "India": list(INDIA_CITIES_DATA.keys()),
        "Qatar": list(QATAR_CITIES_DATA.keys()),
        "Indonesia": list(INDONESIA_CITIES_DATA.keys()),
        "Finland": list(FINLAND_CITIES_DATA.keys()),
        "Germany": list(GERMANY_CITIES_DATA.keys()),
        "France": list(FRANCE_CITIES_DATA.keys()),
    }


@app.get("/api/states/{state}/cities")
async def get_cities(state: str):
    from fastapi import HTTPException

    if state in STATES_CITIES_DATA:
        return {"country": "USA", "state": state, "cities": STATES_CITIES_DATA[state]}
    if state in UK_REGIONS_DATA:
        return {"country": "UK", "region": state, "cities": UK_REGIONS_DATA[state]}
    if state in UAE_CITIES_DATA:
        return {"country": "UAE", "emirate": state, "cities": UAE_CITIES_DATA[state]}
    if state in KSA_CITIES_DATA:
        return {"country": "KSA", "region": state, "cities": KSA_CITIES_DATA[state]}
    if state in AUSTRALIA_CITIES_DATA:
        return {"country": "Australia", "state": state, "cities": AUSTRALIA_CITIES_DATA[state]}
    if state in CANADA_CITIES_DATA:
        return {"country": "Canada", "province": state, "cities": CANADA_CITIES_DATA[state]}
    if state in INDIA_CITIES_DATA:
        return {"country": "India", "state": state, "cities": INDIA_CITIES_DATA[state]}
    if state in QATAR_CITIES_DATA:
        return {"country": "Qatar", "region": state, "cities": QATAR_CITIES_DATA[state]}
    if state in INDONESIA_CITIES_DATA:
        return {"country": "Indonesia", "province": state, "cities": INDONESIA_CITIES_DATA[state]}
    if state in FINLAND_CITIES_DATA:
        return {"country": "Finland", "region": state, "cities": FINLAND_CITIES_DATA[state]}
    if state in GERMANY_CITIES_DATA:
        return {"country": "Germany", "state": state, "cities": GERMANY_CITIES_DATA[state]}
    if state in FRANCE_CITIES_DATA:
        return {"country": "France", "region": state, "cities": FRANCE_CITIES_DATA[state]}

    raise HTTPException(status_code=404, detail="State or region not found")


# Vercel serverless handler
handler = app
