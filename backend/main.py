"""
FastAPI Backend for Google Business Scraper
Provides REST API for scraping functionality
"""

from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Dict, Optional
import pandas as pd
import time
import os
import uuid
import json
import logging
from datetime import datetime
from enum import Enum
import asyncio
from playwright.async_api import async_playwright

app = FastAPI(title="Google Business Scraper API", version="1.0.0")

# CORS middleware for frontend access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler("scraper.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Load states and cities data
with open('states_cities_data.json', 'r', encoding='utf-8') as f:
    STATES_CITIES_DATA = json.load(f)

# In-memory storage for jobs (replace with database in production)
jobs = {}

class ScrapingStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"

class ScrapingRequest(BaseModel):
    category: str
    cities_data: List[str]  # List of "city, state" strings
    max_results_per_city: int = 10

class ScrapingJob(BaseModel):
    job_id: str
    status: ScrapingStatus
    progress: int = 0
    total_cities: int = 0
    current_city: str = ""
    results: List[Dict] = []
    error: Optional[str] = None
    created_at: str
    completed_at: Optional[str] = None
    logs: List[str] = []

class GoogleBusinessScraper:
    def __init__(self):
        self.browser = None
        self.page = None
    
    async def init_browser(self):
        """Initialize Playwright browser"""
        playwright = await async_playwright().start()
        self.browser = await playwright.chromium.launch(headless=True)
        self.page = await self.browser.new_page()
        
        # Block images for faster loading
        await self.page.route("**/*.{png,jpg,jpeg,gif,webp}", lambda route: route.abort())
    
    async def scrape_location(self, category: str, city: str, state: str, max_results: int = 10) -> List[Dict]:
        """Scrape businesses for a specific location"""
        if not self.page:
            await self.init_browser()
        
        results = []
        search_term = f"{category} in {city}, {state}"
        
        try:
            logger.info(f"Starting scraping for {city}, {state}")
            
            # Search for businesses
            await self.page.goto("https://www.google.com/maps", timeout=60000)
            await self.page.wait_for_selector("input#searchboxinput", timeout=10000)
            await self.page.fill("input#searchboxinput", search_term)
            await self.page.keyboard.press("Enter")
            
            try:
                await self.page.wait_for_selector('div[role="feed"]', timeout=15000)
            except:
                logger.warning(f"No results feed found for {city}, {state}")
                return []

            # Scroll to load results
            feed_selector = 'div[role="feed"]'
            for i in range(10):  # Reduced scrolls for performance
                await self.page.evaluate(f'''
                    const feed = document.querySelector('{feed_selector}');
                    if (feed) feed.scrollTo(0, feed.scrollHeight);
                ''')
                
                if await self.page.locator("text=You've reached the end of the list").count() > 0:
                    break
                await asyncio.sleep(1)

            # Extract URLs
            listing_elements = await self.page.locator(f'{feed_selector} > div > div > a[href*="/maps/place/"]').all()
            urls_to_visit = []
            
            for listing in listing_elements:
                href = await listing.get_attribute("href")
                if href:
                    urls_to_visit.append(href.split('?')[0])

            urls_to_visit = list(set(urls_to_visit))[:max_results]  # Limit results
            logger.info(f"Found {len(urls_to_visit)} businesses to scrape for {city}, {state}")
            
            # Visit each URL
            for url in urls_to_visit:
                try:
                    await self.page.goto(url, timeout=30000)
                    await self.page.wait_for_selector("h1", timeout=10000)
                    
                    name = await self.page.locator("h1").first.inner_text()
                    website = "N/A"
                    phone = "N/A"
                    address = "N/A"

                    # Extract website
                    try:
                        website_loc = self.page.locator('a[data-item-id="authority"]')
                        if await website_loc.count() > 0:
                            website = await website_loc.get_attribute("href")
                    except: pass

                    # Extract phone
                    try:
                        phone_loc = self.page.locator('button[data-item-id^="phone:"]')
                        if await phone_loc.count() > 0:
                            phone = await phone_loc.get_attribute("aria-label")
                            if phone: phone = phone.replace("Phone: ", "").strip()
                    except: pass
                    
                    # Extract address
                    try:
                        address_loc = self.page.locator('button[data-item-id="address"]')
                        if await address_loc.count() > 0:
                            address = await address_loc.get_attribute("aria-label")
                            if address: address = address.replace("Address: ", "").strip()
                    except: pass

                    data = {
                        'business_name': name,
                        'phone': phone,
                        'website': website,
                        'address': address,
                        'category': category,
                        'city': city,
                        'state': state,
                        'google_maps_url': url
                    }
                    results.append(data)
                    logger.info(f"Scraped business: {name}")
                    
                    await asyncio.sleep(0.5)

                except Exception as e:
                    logger.error(f"Error scraping business URL {url}: {e}")
                    continue

            logger.info(f"Completed scraping for {city}, {state}. Found {len(results)} businesses")
            return results

        except Exception as e:
            logger.error(f"Scraping error for {city}, {state}: {e}")
            return []
    
    async def close(self):
        """Close browser"""
        if self.browser:
            await self.browser.close()

async def run_scraping_job(job_id: str, request: ScrapingRequest):
    """Background task for running scraping jobs"""
    scraper = GoogleBusinessScraper()
    
    try:
        logger.info(f"Starting scraping job {job_id}")
        jobs[job_id].status = ScrapingStatus.RUNNING
        jobs[job_id].total_cities = len(request.cities_data)
        jobs[job_id].logs.append(f"Starting scraping job for category: {request.category}")
        
        all_results = []
        
        for idx, city_state in enumerate(request.cities_data):
            if jobs[job_id].status == ScrapingStatus.FAILED:
                break
                
            # Parse city and state
            parts = city_state.split(",")
            if len(parts) >= 2:
                city = parts[0].strip()
                state = parts[1].strip()
                
                jobs[job_id].current_city = f"{city}, {state}"
                jobs[job_id].progress = int((idx + 1) / len(request.cities_data) * 100)
                jobs[job_id].logs.append(f"Processing city {idx + 1}/{len(request.cities_data)}: {city}, {state}")
                logger.info(f"Processing city {idx + 1}/{len(request.cities_data)}: {city}, {state}")
                
                # Scrape this location
                results = await scraper.scrape_location(
                    request.category, 
                    city, 
                    state, 
                    request.max_results_per_city
                )
                
                all_results.extend(results)
                jobs[job_id].results = all_results
                jobs[job_id].logs.append(f"Found {len(results)} businesses in {city}, {state}")
                logger.info(f"Found {len(results)} businesses in {city}, {state}")
                
                # Small delay between cities
                await asyncio.sleep(1)
        
        jobs[job_id].status = ScrapingStatus.COMPLETED
        jobs[job_id].progress = 100
        jobs[job_id].completed_at = datetime.now().isoformat()
        jobs[job_id].logs.append(f"Job completed successfully. Total businesses found: {len(all_results)}")
        logger.info(f"Job {job_id} completed successfully. Total businesses found: {len(all_results)}")
        
    except Exception as e:
        jobs[job_id].status = ScrapingStatus.FAILED
        jobs[job_id].error = str(e)
        jobs[job_id].completed_at = datetime.now().isoformat()
        jobs[job_id].logs.append(f"Job failed with error: {str(e)}")
        logger.error(f"Job {job_id} failed with error: {str(e)}")
    
    finally:
        await scraper.close()
        logger.info(f"Closed browser for job {job_id}")

@app.post("/api/jobs", response_model=ScrapingJob)
async def create_scraping_job(request: ScrapingRequest, background_tasks: BackgroundTasks):
    """Create a new scraping job"""
    job_id = str(uuid.uuid4())
    
    job = ScrapingJob(
        job_id=job_id,
        status=ScrapingStatus.PENDING,
        created_at=datetime.now().isoformat(),
        logs=[f"Job created for category: {request.category}"]
    )
    
    jobs[job_id] = job
    
    # Start background task
    background_tasks.add_task(run_scraping_job, job_id, request)
    
    return job

@app.get("/api/jobs/{job_id}", response_model=ScrapingJob)
async def get_job_status(job_id: str):
    """Get scraping job status"""
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    
    logger.info(f"Retrieved status for job {job_id}")
    return jobs[job_id]

@app.get("/api/jobs/{job_id}/results")
async def get_job_results(job_id: str):
    """Get scraping results"""
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    
    job = jobs[job_id]
    if job.status != ScrapingStatus.COMPLETED:
        raise HTTPException(status_code=400, detail="Job not completed")
    
    return {
        "job_id": job_id,
        "total_results": len(job.results),
        "results": job.results
    }

@app.get("/api/jobs/{job_id}/download")
async def download_results(job_id: str):
    """Download results as CSV"""
    if job_id not in jobs:
        raise HTTPException(status_code=404, detail="Job not found")
    
    job = jobs[job_id]
    if job.status != ScrapingStatus.COMPLETED:
        raise HTTPException(status_code=400, detail="Job not completed")
    
    # Create CSV
    df = pd.DataFrame(job.results)
    csv_content = df.to_csv(index=False)
    
    return {
        "filename": f"business_results_{job_id}.csv",
        "content": csv_content,
        "content_type": "text/csv"
    }

@app.get("/api/health")
async def health_check():
    """Health check endpoint"""
    logger.info("Health check endpoint called")
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

@app.get("/api/states")
async def get_states():
    """Get list of all available states"""
    logger.info("Get states endpoint called")
    return {"states": list(STATES_CITIES_DATA.keys())}

@app.get("/api/states/{state}/cities")
async def get_cities(state: str):
    """Get list of cities for a specific state"""
    logger.info(f"Get cities for state {state} endpoint called")
    
    if state not in STATES_CITIES_DATA:
        raise HTTPException(status_code=404, detail="State not found")
    
    return {"state": state, "cities": STATES_CITIES_DATA[state]}

if __name__ == "__main__":
    import uvicorn
    import asyncio
    
    async def main():
        config = uvicorn.Config(app, host="0.0.0.0", port=8000)
        server = uvicorn.Server(config)
        await server.serve()
    
    asyncio.run(main())