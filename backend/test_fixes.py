"""
Test script to verify Playwright fixes
"""
import asyncio
import sys
import os

# Add parent directory to path to import from main.py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from main import GoogleBusinessScraper


async def test_scraper():
    """Test the scraper with a simple query"""
    print("=" * 60)
    print("Testing Google Business Scraper with Playwright fixes")
    print("=" * 60)

    scraper = GoogleBusinessScraper(headless=False)  # Set to False to see the browser

    try:
        print("\n1. Initializing browser...")
        await scraper.init_browser()
        print("   [OK] Browser initialized successfully!")

        print("\n2. Scraping test location (Restaurants in San Francisco, CA)...")
        results = await scraper.scrape_location(
            category="restaurants",
            city="San Francisco",
            state="CA",
            max_results=3  # Just get 3 results for testing
        )

        print(f"\n3. Results found: {len(results)} businesses")
        print("=" * 60)

        if results:
            for idx, business in enumerate(results, 1):
                print(f"\nBusiness {idx}:")
                print(f"  Name: {business.get('business_name', 'N/A')}")
                print(f"  Phone: {business.get('phone', 'N/A')}")
                print(f"  Website: {business.get('website', 'N/A')}")
                print(f"  Address: {business.get('address', 'N/A')}")
                print(f"  Google Maps URL: {business.get('google_maps_url', 'N/A')}")
        else:
            print("\n[WARNING] No results found. This might indicate an issue with selectors.")

        print("\n" + "=" * 60)
        print("[OK] Test completed successfully!")
        print("=" * 60)

    except Exception as e:
        print(f"\n[ERROR] Test failed with error: {e}")
        import traceback
        traceback.print_exc()

    finally:
        print("\n4. Closing browser...")
        await scraper.close()
        print("   [OK] Browser closed!")


if __name__ == "__main__":
    # Run the test
    asyncio.run(test_scraper())
