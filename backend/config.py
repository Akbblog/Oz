"""
Configuration for the Google Business Scraper API
"""

import os
import logging
from dotenv import load_dotenv

# Load environment variables from a local .env file (kept out of git)
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), ".env"))

# General
# Set to True for production, False for development
DEBUG = os.getenv("DEBUG", "False").lower() in ("true", "1", "t")
# Change this in production
SECRET_KEY = os.getenv("SECRET_KEY", "a_secure_secret_key")

# Database
# Use in-memory SQLite for testing
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///scraper.db")

# Playwright
PLAYWRIGHT_HEADLESS = os.getenv("PLAYWRIGHT_HEADLESS", "True").lower() in ("true", "1", "t")
PLAYWRIGHT_USER_AGENT = os.getenv("PLAYWRIGHT_USER_AGENT", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

# Directories
RESULTS_DIR = "results"

# Logging
LOG_LEVEL = logging.DEBUG if DEBUG else logging.INFO
LOG_FORMAT = '%(asctime)s - %(levelname)s - %(message)s'
LOG_FILE = "scraper.log"

# CORS
# Adjust for your frontend URL in production
ALLOWED_ORIGINS = ["*"]

# Data files
USA_DATA_FILE = "states_cities_data.json"
UK_DATA_FILE = "uk_regions_cities.json"
UAE_DATA_FILE = "uae_cities_data.json"
KSA_DATA_FILE = "ksa_cities_data.json"
AUSTRALIA_DATA_FILE = "australia_cities_data.json"

# JWT Settings
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 days
ALGORITHM = "HS256"

# Password Reset
PASSWORD_RESET_TOKEN_EXPIRE_HOURS = 24

# Credit System
# These settings can be overridden by the database `credit_config` table
DEFAULT_CREDIT_CONFIG = {
    "starting_credits": 100,           # Initial credits given to new users
    "base": 10,                        # Base cost per job
    "per_city": 5,                     # Cost per city searched
    "per_result": 1,                   # Cost per result returned
    "min_job": 15,                     # Minimum job cost
    "max_concurrent_jobs": 2,          # Maximum concurrent jobs per user
    "max_jobs_per_hour": 5,            # Maximum jobs per hour per user
    "credit_expiry_days": 365,         # Days until purchased credits expire (0 = never)
    "promotional_expiry_days": 90,     # Days until promotional credits expire
    "bonus_expiry_days": 90,           # Days until bonus credits expire
}

# Stripe Settings
STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY", "sk_test_...")
STRIPE_PUBLISHABLE_KEY = os.getenv("STRIPE_PUBLISHABLE_KEY", "pk_test_...")
STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET", "whsec_...")

# Coinbase Commerce Settings
COINBASE_API_KEY = os.getenv("COINBASE_API_KEY", "your_coinbase_api_key")
COINBASE_WEBHOOK_SECRET = os.getenv("COINBASE_WEBHOOK_SECRET", "your_coinbase_webhook_secret")

# SMTP Email Settings
SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "your_email@gmail.com")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "your_app_password")
FROM_EMAIL = os.getenv("FROM_EMAIL", "noreply@business-scraper.com")

# Public app URL (used in emails). Example: https://app.infinityleadspro.com
APP_URL = os.getenv("APP_URL", "").strip()

# Optional override for who receives admin notifications.
# Comma-separated list of emails (e.g. "admin@a.com,ops@a.com").
ADMIN_NOTIFICATION_EMAILS = [
    e.strip()
    for e in os.getenv("ADMIN_NOTIFICATION_EMAILS", "").split(",")
    if e.strip()
]

# Redis Settings (for Celery)
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")

# Payment Configuration
PAYMENT_CONFIG = {
    "currency": "USD",                         # Default currency
    "invoice_prefix": "INV",                   # Invoice number prefix
    "invoice_dir": "invoices",                 # Directory for PDF invoices
    "tax_rate": 0.0,                          # Default tax rate (location-based in Phase 2)
    "min_purchase_cents": 500,                # Minimum purchase amount ($5.00)
    "max_purchase_cents": 1000000,            # Maximum purchase amount ($10,000.00)
    "enable_crypto": True,                    # Enable cryptocurrency payments
    "enable_subscriptions": True,             # Enable subscription plans
}

# Referral Configuration
REFERRAL_CONFIG = {
    "enabled": True,                          # Enable referral program
    "referrer_bonus_credits": 50,             # Credits awarded to referrer
    "referred_bonus_credits": 25,             # Credits awarded to referred user
    "min_purchase_for_reward": 1000,          # Minimum purchase (cents) to trigger reward
    "referral_code_length": 8,                # Length of referral codes
}

# Subscription Configuration
SUBSCRIPTION_CONFIG = {
    "trial_enabled": True,                    # Enable trial periods
    "default_trial_days": 14,                 # Default trial length
    "grace_period_days": 3,                   # Days before subscription cancellation
    "allow_downgrade": True,                  # Allow users to downgrade plans
    "prorate_upgrades": True,                 # Prorate charges on upgrades
}

# Celery Configuration (for background tasks)
CELERY_CONFIG = {
    "broker_url": REDIS_URL,                  # Redis broker URL
    "result_backend": REDIS_URL,              # Redis result backend
    "task_serializer": "json",
    "result_serializer": "json",
    "accept_content": ["json"],
    "timezone": "UTC",
    "enable_utc": True,
    "task_track_started": True,
    "task_time_limit": 3600,                  # 1 hour max per task
}

# Email Templates Configuration
EMAIL_CONFIG = {
    "from_name": "Infinity Leads Pro",
    "support_email": "support@infinityleadspro.com",
    "company_name": "Infinity Leads Pro",
    "company_address": "123 Business St, City, State 12345",
}
