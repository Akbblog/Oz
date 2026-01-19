"""
FastAPI Backend for Google Business Scraper
Provides REST API for scraping functionality with authentication
"""

from fastapi import FastAPI, HTTPException, BackgroundTasks, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr
from typing import List, Dict, Optional
import pandas as pd
import os
import uuid
import json
import logging
from datetime import datetime, timedelta
from enum import Enum
import asyncio
from playwright.async_api import async_playwright

from database import init_database, get_db
from auth import (
    verify_password, get_password_hash, 
    create_access_token, decode_access_token
)

# Initialize database
init_database()

app = FastAPI(title="Google Business Scraper API", version="2.0.0")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Security
security = HTTPBearer()

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

# Results directory
RESULTS_DIR = "results"
os.makedirs(RESULTS_DIR, exist_ok=True)

# ==================== MODELS ====================

class ScrapingStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"

class UserRegister(BaseModel):
    username: str
    email: EmailStr
    password: str

class UserLogin(BaseModel):
    username: str
    password: str

class ScrapingRequest(BaseModel):
    category: str
    cities_data: List[str]
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

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: dict

# ==================== AUTHENTICATION ====================

async def get_current_user(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Get current authenticated user"""
    token = credentials.credentials
    payload = decode_access_token(token)
    
    if payload is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials"
        )
    
    username = payload.get("sub")
    if username is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials"
        )
    
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("SELECT id, username, email, is_approved, is_admin FROM users WHERE username = ?", (username,))
    user = cursor.fetchone()
    conn.close()
    
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found"
        )
    
    if not user[3]:  # is_approved
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account pending approval"
        )
    
    return {
        "id": user[0],
        "username": user[1],
        "email": user[2],
        "is_admin": bool(user[4])
    }

async def get_admin_user(current_user: dict = Depends(get_current_user)):
    """Get current admin user"""
    if not current_user.get("is_admin"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required"
        )
    return current_user

# ==================== AUTH ENDPOINTS ====================

@app.post("/api/auth/register", status_code=status.HTTP_201_CREATED)
async def register(user_data: UserRegister):
    """Register a new user (requires approval)"""
    conn = get_db()
    cursor = conn.cursor()
    
    # Check if username exists
    cursor.execute("SELECT id FROM users WHERE username = ?", (user_data.username,))
    if cursor.fetchone():
        conn.close()
        raise HTTPException(status_code=400, detail="Username already exists")
    
    # Check if email exists
    cursor.execute("SELECT id FROM users WHERE email = ?", (user_data.email,))
    if cursor.fetchone():
        conn.close()
        raise HTTPException(status_code=400, detail="Email already exists")
    
    # Create user (not approved by default)
    password_hash = get_password_hash(user_data.password)
    cursor.execute("""
        INSERT INTO users (username, email, password_hash, is_approved, created_at)
        VALUES (?, ?, ?, ?, ?)
    """, (user_data.username, user_data.email, password_hash, 0, datetime.now().isoformat()))
    
    conn.commit()
    user_id = cursor.lastrowid
    conn.close()
    
    return {"message": "Registration successful. Please wait for admin approval."}

@app.post("/api/auth/login", response_model=TokenResponse)
async def login(credentials: UserLogin):
    """Login and get access token"""
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute("SELECT id, username, email, password_hash, is_approved, is_admin FROM users WHERE username = ?", (credentials.username,))
    user = cursor.fetchone()
    conn.close()
    
    if not user or not verify_password(credentials.password, user[3]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password"
        )
    
    if not user[4]:  # is_approved
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account pending approval"
        )
    
    # Update last login
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE users SET last_login = ? WHERE id = ?", (datetime.now().isoformat(), user[0]))
    conn.commit()
    conn.close()
    
    # Create token
    access_token = create_access_token(data={"sub": user[1]})
    
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "user": {
            "id": user[0],
            "username": user[1],
            "email": user[2],
            "is_admin": bool(user[5])
        }
    }

@app.get("/api/auth/me")
async def get_current_user_info(current_user: dict = Depends(get_current_user)):
    """Get current user information"""
    return current_user

# ==================== ADMIN ENDPOINTS ====================

@app.get("/api/admin/users")
async def get_all_users(admin: dict = Depends(get_admin_user)):
    """Get all users (admin only)"""
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, username, email, is_approved, is_admin, created_at, last_login
        FROM users ORDER BY created_at DESC
    """)
    users = cursor.fetchall()
    conn.close()
    
    return {
        "users": [
            {
                "id": u[0],
                "username": u[1],
                "email": u[2],
                "is_approved": bool(u[3]),
                "is_admin": bool(u[4]),
                "created_at": u[5],
                "last_login": u[6]
            }
            for u in users
        ]
    }

@app.post("/api/admin/users/{user_id}/approve")
async def approve_user(user_id: int, admin: dict = Depends(get_admin_user)):
    """Approve a user (admin only)"""
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("UPDATE users SET is_approved = 1 WHERE id = ?", (user_id,))
    conn.commit()
    conn.close()
    return {"message": "User approved successfully"}

@app.delete("/api/admin/users/{user_id}")
async def delete_user(user_id: int, admin: dict = Depends(get_admin_user)):
    """Delete a user (admin only)"""
    conn = get_db()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM users WHERE id = ?", (user_id,))
    conn.commit()
    conn.close()
    return {"message": "User deleted successfully"}

@app.get("/api/admin/stats")
async def get_admin_stats(admin: dict = Depends(get_admin_user)):
    """Get admin dashboard statistics"""
    conn = get_db()
    cursor = conn.cursor()
    
    # Total users
    cursor.execute("SELECT COUNT(*) FROM users")
    total_users = cursor.fetchone()[0]
    
    # Approved users
    cursor.execute("SELECT COUNT(*) FROM users WHERE is_approved = 1")
    approved_users = cursor.fetchone()[0]
    
    # Pending users
    cursor.execute("SELECT COUNT(*) FROM users WHERE is_approved = 0")
    pending_users = cursor.fetchone()[0]
    
    # Total jobs
    cursor.execute("SELECT COUNT(*) FROM jobs")
    total_jobs = cursor.fetchone()[0]
    
    # Completed jobs
    cursor.execute("SELECT COUNT(*) FROM jobs WHERE status = 'completed'")
    completed_jobs = cursor.fetchone()[0]
    
    # Total results
    cursor.execute("SELECT COUNT(*) FROM results")
    total_results = cursor.fetchone()[0]
    
    # Recent jobs
    cursor.execute("""
        SELECT j.job_id, j.category, j.status, j.created_at, u.username
        FROM jobs j
        JOIN users u ON j.user_id = u.id
        ORDER BY j.created_at DESC
        LIMIT 10
    """)
    recent_jobs = [
        {
            "job_id": j[0],
            "category": j[1],
            "status": j[2],
            "created_at": j[3],
            "username": j[4]
        }
        for j in cursor.fetchall()
    ]
    
    conn.close()
    
    return {
        "total_users": total_users,
        "approved_users": approved_users,
        "pending_users": pending_users,
        "total_jobs": total_jobs,
        "completed_jobs": completed_jobs,
        "total_results": total_results,
        "recent_jobs": recent_jobs
    }

# ==================== SCRAPER ====================

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
            for i in range(10):
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
                    full_url = href if href.startswith("http") else f"https://www.google.com{href}"
                    urls_to_visit.append(full_url.split('?')[0])

            urls_to_visit = list(set(urls_to_visit))[:max_results]
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
                            website = await website_loc.get_attribute("href") or "N/A"
                    except: pass

                    # Extract phone
                    try:
                        phone_loc = self.page.locator('button[data-item-id^="phone:"]')
                        if await phone_loc.count() > 0:
                            phone = await phone_loc.get_attribute("aria-label") or "N/A"
                            if phone != "N/A": 
                                phone = phone.replace("Phone: ", "").strip()
                    except: pass
                    
                    # Extract address
                    try:
                        address_loc = self.page.locator('button[data-item-id="address"]')
                        if await address_loc.count() > 0:
                            address = await address_loc.get_attribute("aria-label") or "N/A"
                            if address != "N/A":
                                address = address.replace("Address: ", "").strip()
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

async def run_scraping_job(job_id: str, request: ScrapingRequest, user_id: int):
    """Background task for running scraping jobs"""
    scraper = GoogleBusinessScraper()
    conn = get_db()
    
    try:
        logger.info(f"Starting scraping job {job_id}")
        
        # Update job status
        cursor = conn.cursor()
        cursor.execute("UPDATE jobs SET status = ? WHERE job_id = ?", ("running", job_id))
        conn.commit()
        
        # Add log
        cursor.execute("INSERT INTO job_logs (job_id, log_message, created_at) VALUES (?, ?, ?)",
                      (job_id, f"Starting scraping job for category: {request.category}", datetime.now().isoformat()))
        conn.commit()
        
        all_results = []
        
        for idx, city_state in enumerate(request.cities_data):
            # Check if job was cancelled
            cursor.execute("SELECT status FROM jobs WHERE job_id = ?", (job_id,))
            job_status = cursor.fetchone()
            if job_status and job_status[0] == "failed":
                break
            
            # Parse city and state
            parts = city_state.split(",")
            if len(parts) >= 2:
                city = parts[0].strip()
                state = parts[1].strip()
                
                current_city = f"{city}, {state}"
                progress = int((idx + 1) / len(request.cities_data) * 100)
                
                # Update job progress
                cursor.execute("""
                    UPDATE jobs SET current_city = ?, progress = ?
                    WHERE job_id = ?
                """, (current_city, progress, job_id))
                conn.commit()
                
                # Add log
                cursor.execute("INSERT INTO job_logs (job_id, log_message, created_at) VALUES (?, ?, ?)",
                              (job_id, f"Processing city {idx + 1}/{len(request.cities_data)}: {city}, {state}", datetime.now().isoformat()))
                conn.commit()
                
                logger.info(f"Processing city {idx + 1}/{len(request.cities_data)}: {city}, {state}")
                
                # Scrape this location
                results = await scraper.scrape_location(
                    request.category, 
                    city, 
                    state, 
                    request.max_results_per_city
                )
                
                all_results.extend(results)
                
                # Save results to database
                for result in results:
                    cursor.execute("""
                        INSERT INTO results (job_id, business_name, phone, website, address, category, city, state, google_maps_url)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, (
                        job_id, result['business_name'], result['phone'], result['website'],
                        result['address'], result['category'], result['city'], result['state'],
                        result['google_maps_url']
                    ))
                conn.commit()
                
                # Add log
                cursor.execute("INSERT INTO job_logs (job_id, log_message, created_at) VALUES (?, ?, ?)",
                              (job_id, f"Found {len(results)} businesses in {city}, {state}", datetime.now().isoformat()))
                conn.commit()
                
                logger.info(f"Found {len(results)} businesses in {city}, {state}")
                
                await asyncio.sleep(1)
        
        # Save results to CSV file
        if all_results:
            filename = f"{RESULTS_DIR}/results_{job_id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
            df = pd.DataFrame(all_results)
            df.to_csv(filename, index=False)
            logger.info(f"Saved {len(all_results)} results to {filename}")
        
        # Update job as completed
        cursor.execute("""
            UPDATE jobs SET status = ?, progress = ?, completed_at = ?
            WHERE job_id = ?
        """, ("completed", 100, datetime.now().isoformat(), job_id))
        conn.commit()
        
        # Add completion log
        cursor.execute("INSERT INTO job_logs (job_id, log_message, created_at) VALUES (?, ?, ?)",
                      (job_id, f"Job completed successfully. Total businesses found: {len(all_results)}", datetime.now().isoformat()))
        conn.commit()
        
        logger.info(f"Job {job_id} completed successfully. Total businesses found: {len(all_results)}")
        
    except Exception as e:
        logger.error(f"Job {job_id} failed with error: {str(e)}")
        cursor = conn.cursor()
        cursor.execute("""
            UPDATE jobs SET status = ?, error = ?, completed_at = ?
            WHERE job_id = ?
        """, ("failed", str(e), datetime.now().isoformat(), job_id))
        conn.commit()
        
        cursor.execute("INSERT INTO job_logs (job_id, log_message, created_at) VALUES (?, ?, ?)",
                      (job_id, f"Job failed with error: {str(e)}", datetime.now().isoformat()))
        conn.commit()
    
    finally:
        conn.close()
        await scraper.close()
        logger.info(f"Closed browser for job {job_id}")

# ==================== JOB ENDPOINTS ====================

@app.post("/api/jobs", response_model=ScrapingJob)
async def create_scraping_job(
    request: ScrapingRequest, 
    background_tasks: BackgroundTasks,
    current_user: dict = Depends(get_current_user)
):
    """Create a new scraping job"""
    job_id = str(uuid.uuid4())
    
    conn = get_db()
    cursor = conn.cursor()
    
    # Create job in database
    cursor.execute("""
        INSERT INTO jobs (job_id, user_id, category, cities_data, max_results_per_city, status, total_cities, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        job_id, current_user["id"], request.category, 
        json.dumps(request.cities_data), request.max_results_per_city,
        "pending", len(request.cities_data), datetime.now().isoformat()
    ))
    conn.commit()
    conn.close()
    
    # Start background task
    background_tasks.add_task(run_scraping_job, job_id, request, current_user["id"])
    
    # Return job
    return ScrapingJob(
        job_id=job_id,
        status=ScrapingStatus.PENDING,
        created_at=datetime.now().isoformat(),
        logs=[f"Job created for category: {request.category}"]
    )

@app.get("/api/jobs/{job_id}", response_model=ScrapingJob)
async def get_job_status(job_id: str, current_user: dict = Depends(get_current_user)):
    """Get scraping job status"""
    conn = get_db()
    cursor = conn.cursor()
    
    # Get job
    cursor.execute("""
        SELECT job_id, status, progress, total_cities, current_city, error, created_at, completed_at
        FROM jobs WHERE job_id = ? AND user_id = ?
    """, (job_id, current_user["id"]))
    
    job_data = cursor.fetchone()
    if not job_data:
        conn.close()
        raise HTTPException(status_code=404, detail="Job not found")
    
    # Get logs
    cursor.execute("SELECT log_message FROM job_logs WHERE job_id = ? ORDER BY created_at", (job_id,))
    logs = [row[0] for row in cursor.fetchall()]
    
    # Get results count
    cursor.execute("SELECT COUNT(*) FROM results WHERE job_id = ?", (job_id,))
    results_count = cursor.fetchone()[0]
    
    # Get results
    cursor.execute("""
        SELECT business_name, phone, website, address, category, city, state, google_maps_url
        FROM results WHERE job_id = ?
    """, (job_id,))
    
    results = []
    for row in cursor.fetchall():
        results.append({
            "business_name": row[0],
            "phone": row[1],
            "website": row[2],
            "address": row[3],
            "category": row[4],
            "city": row[5],
            "state": row[6],
            "google_maps_url": row[7]
        })
    
    conn.close()
    
    return ScrapingJob(
        job_id=job_data[0],
        status=ScrapingStatus(job_data[1]),
        progress=job_data[2],
        total_cities=job_data[3],
        current_city=job_data[4] or "",
        results=results,
        error=job_data[5],
        created_at=job_data[6],
        completed_at=job_data[7],
        logs=logs
    )

@app.get("/api/jobs")
async def get_user_jobs(current_user: dict = Depends(get_current_user)):
    """Get all jobs for current user"""
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT job_id, category, status, progress, created_at, completed_at
        FROM jobs WHERE user_id = ? ORDER BY created_at DESC
    """, (current_user["id"],))
    
    jobs = []
    for row in cursor.fetchall():
        jobs.append({
            "job_id": row[0],
            "category": row[1],
            "status": row[2],
            "progress": row[3],
            "created_at": row[4],
            "completed_at": row[5]
        })
    
    conn.close()
    return {"jobs": jobs}

@app.get("/api/jobs/{job_id}/results")
async def get_job_results(job_id: str, current_user: dict = Depends(get_current_user)):
    """Get scraping results"""
    conn = get_db()
    cursor = conn.cursor()
    
    # Verify job ownership
    cursor.execute("SELECT user_id FROM jobs WHERE job_id = ?", (job_id,))
    job = cursor.fetchone()
    if not job or job[0] != current_user["id"]:
        conn.close()
        raise HTTPException(status_code=404, detail="Job not found")
    
    # Get results
    cursor.execute("""
        SELECT business_name, phone, website, address, category, city, state, google_maps_url
        FROM results WHERE job_id = ?
    """, (job_id,))
    
    results = []
    for row in cursor.fetchall():
        results.append({
            "business_name": row[0],
            "phone": row[1],
            "website": row[2],
            "address": row[3],
            "category": row[4],
            "city": row[5],
            "state": row[6],
            "google_maps_url": row[7]
        })
    
    conn.close()
    
    return {
        "job_id": job_id,
        "total_results": len(results),
        "results": results
    }

@app.get("/api/jobs/{job_id}/download")
async def download_results(job_id: str, current_user: dict = Depends(get_current_user)):
    """Download results as CSV"""
    conn = get_db()
    cursor = conn.cursor()
    
    # Verify job ownership
    cursor.execute("SELECT status FROM jobs WHERE job_id = ? AND user_id = ?", (job_id, current_user["id"]))
    job = cursor.fetchone()
    if not job:
        conn.close()
        raise HTTPException(status_code=404, detail="Job not found")
    
    if job[0] != "completed":
        conn.close()
        raise HTTPException(status_code=400, detail="Job not completed")
    
    # Get results
    cursor.execute("""
        SELECT business_name, phone, website, address, category, city, state, google_maps_url
        FROM results WHERE job_id = ?
    """, (job_id,))
    
    results = []
    for row in cursor.fetchall():
        results.append({
            "business_name": row[0],
            "phone": row[1],
            "website": row[2],
            "address": row[3],
            "category": row[4],
            "city": row[5],
            "state": row[6],
            "google_maps_url": row[7]
        })
    
    conn.close()
    
    # Create CSV
    df = pd.DataFrame(results)
    csv_content = df.to_csv(index=False)
    
    return {
        "filename": f"business_results_{job_id}.csv",
        "content": csv_content,
        "content_type": "text/csv"
    }

# ==================== UTILITY ENDPOINTS ====================

@app.get("/api/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

@app.get("/api/states")
async def get_states():
    """Get list of all available states"""
    return {"states": list(STATES_CITIES_DATA.keys())}

@app.get("/api/states/{state}/cities")
async def get_cities(state: str):
    """Get list of cities for a specific state"""
    if state not in STATES_CITIES_DATA:
        raise HTTPException(status_code=404, detail="State not found")
    
    return {"state": state, "cities": STATES_CITIES_DATA[state]}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
