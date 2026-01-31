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

COUNTRIES_DATA = {
    "USA": STATES_CITIES_DATA,
    "UK": UK_REGIONS_DATA,
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
    }


@app.get("/api/states/{state}/cities")
async def get_cities(state: str):
    from fastapi import HTTPException

    if state in STATES_CITIES_DATA:
        return {"country": "USA", "state": state, "cities": STATES_CITIES_DATA[state]}
    if state in UK_REGIONS_DATA:
        return {"country": "UK", "region": state, "cities": UK_REGIONS_DATA[state]}

    raise HTTPException(status_code=404, detail="State or region not found")


# Vercel serverless handler
handler = app
