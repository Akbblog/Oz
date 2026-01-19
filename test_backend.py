#!/usr/bin/env python3
"""
Test script for the Business Scraper API backend
"""

import requests
import json

BASE_URL = "http://localhost:8000"

def test_health_check():
    """Test API health endpoint"""
    try:
        response = requests.get(f"{BASE_URL}/api/health")
        print(f"✅ Health check: {response.status_code}")
        return response.status_code == 200
    except Exception as e:
        print(f"❌ Health check failed: {e}")
        return False

def test_create_job():
    """Test creating a scraping job"""
    try:
        test_data = {
            "category": "restaurants",
            "cities_data": ["Los Angeles, California", "San Diego, California"],
            "max_results_per_city": 5
        }
        
        response = requests.post(
            f"{BASE_URL}/api/jobs",
            headers={"Content-Type": "application/json"},
            data=json.dumps(test_data)
        )
        
        if response.status_code == 200:
            job_data = response.json()
            print(f"✅ Job created: {job_data['job_id']}")
            return job_data['job_id']
        else:
            print(f"❌ Job creation failed: {response.status_code}")
            return None
            
    except Exception as e:
        print(f"❌ Job creation error: {e}")
        return None

def test_job_status(job_id):
    """Test getting job status"""
    try:
        response = requests.get(f"{BASE_URL}/api/jobs/{job_id}")
        
        if response.status_code == 200:
            job_data = response.json()
            print(f"✅ Job status: {job_data['status']}")
            return True
        else:
            print(f"❌ Status check failed: {response.status_code}")
            return False
            
    except Exception as e:
        print(f"❌ Status check error: {e}")
        return False

if __name__ == "__main__":
    print("Testing Business Scraper API Backend...")
    print("=" * 50)
    
    # Test 1: Health check
    if not test_health_check():
        print("\n⚠️  Make sure the backend is running:")
        print("cd backend && uvicorn main:app --host 0.0.0.0 --port 8000 --reload")
        exit(1)
    
    # Test 2: Create job
    job_id = test_create_job()
    
    if job_id:
        # Test 3: Check job status
        test_job_status(job_id)
    
    print("\n" + "=" * 50)
    print("✅ Backend tests completed successfully!")
    print("\nNext steps:")
    print("1. Start Flutter app: cd frontend && flutter run")
    print("2. Open web app: cd web && python -m http.server 8080")
    print("3. Visit http://localhost:8080 in your browser")