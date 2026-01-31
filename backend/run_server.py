"""
Server startup script that sets Windows event loop policy before starting uvicorn
"""
import asyncio
import sys
import os

# CRITICAL: Set Windows event loop policy BEFORE importing anything else
if sys.platform == 'win32':
    asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())

# Set Playwright browser path to use system-installed browsers
os.environ['PLAYWRIGHT_BROWSERS_PATH'] = r'C:\Users\Computer Max\AppData\Local\ms-playwright'

if __name__ == "__main__":
    import uvicorn
    # Use reload=False to avoid subprocess issues with event loop policy
    uvicorn.run("main:app", host="0.0.0.0", port=8001, reload=False, log_level="info")
