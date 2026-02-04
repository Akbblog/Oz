import os
import json
from datetime import datetime
from typing import Optional
import config

# Lazily import pymysql if needed
pymysql = None
try:
    if os.getenv("DB_TYPE", "sqlite").lower() == "mysql":
        import pymysql  # type: ignore
except ImportError:
    raise RuntimeError("PyMySQL is required for MySQL support. Install it with 'pip install PyMySQL'")


def _get_db_type() -> str:
    return os.getenv("DB_TYPE", "sqlite").lower()

def _get_placeholders():
    return "%s" if _get_db_type() == "mysql" else "?"

def init_database():
    """Initialize database with base schema and run pending migrations"""
    import logging

    logger = logging.getLogger(__name__)
    logger.info("Initializing database...")

    # Create schema_migrations tracking table
    conn = get_db()
    cursor = conn.cursor()

    if _get_db_type() == "mysql":
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id INT AUTO_INCREMENT PRIMARY KEY,
                version VARCHAR(20) UNIQUE NOT NULL,
                filename VARCHAR(255) NOT NULL,
                applied_at VARCHAR(64) NOT NULL,
                checksum VARCHAR(32)
            )
        """)
    else:
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                version TEXT UNIQUE NOT NULL,
                filename TEXT NOT NULL,
                applied_at TEXT NOT NULL,
                checksum TEXT
            )
        """)
    conn.commit()
    conn.close()

    # Run all pending migrations
    from db.migration_runner import run_pending_migrations
    migrations_dir = os.path.join(os.path.dirname(__file__), "migrations")

    try:
        applied_count = run_pending_migrations(migrations_dir)
        logger.info(f"✓ Database initialized successfully. Applied {applied_count} migration(s).")
        try:
            _ensure_default_admin_user(logger=logger)
        except Exception as e:
            logger.warning(f"Default admin bootstrap skipped/failed: {e}")
        return applied_count
    except Exception as e:
        logger.error(f"✗ Database initialization failed: {str(e)}")
        raise

def _ensure_default_admin_user(logger=None) -> None:
    """
    Ensure at least one admin exists.

    Repo docs expect a default admin for new/dev installs. This only creates (or
    promotes) the configured DEFAULT_ADMIN_* identity, and only if no admin user
    currently exists.
    """
    default_username = os.getenv("DEFAULT_ADMIN_USERNAME", "admin").strip()
    default_email = os.getenv("DEFAULT_ADMIN_EMAIL", "admin@tool.com").strip()
    default_password = os.getenv("DEFAULT_ADMIN_PASSWORD", "tool.com")

    if not default_username or not default_email:
        return

    # Allow disabling this behavior explicitly (recommended for production).
    if os.getenv("DISABLE_DEFAULT_ADMIN", "false").lower() in ("true", "1", "t", "yes", "y"):
        return

    conn = get_db()
    try:
        cursor = conn.cursor()

        # If any admin exists, do nothing.
        cursor.execute("SELECT id FROM users WHERE is_admin = 1 LIMIT 1")
        if cursor.fetchone():
            return

        ph = _get_placeholders()
        cursor.execute(
            f"SELECT id FROM users WHERE username = {ph} OR email = {ph} LIMIT 1",
            (default_username, default_email),
        )
        existing = cursor.fetchone()
        now = datetime.now().isoformat()

        if existing:
            user_id = int(existing[0])
            cursor.execute(
                f"UPDATE users SET is_admin = 1, is_approved = 1 WHERE id = {ph}",
                (user_id,),
            )
            conn.commit()
            if logger:
                logger.info(f"✓ Promoted existing user id={user_id} to admin (username/email match).")
            return

        from auth import get_password_hash

        cursor.execute(
            f"""
            INSERT INTO users (username, email, password_hash, is_approved, is_admin, created_at)
            VALUES ({ph}, {ph}, {ph}, 1, 1, {ph})
            """,
            (default_username, default_email, get_password_hash(default_password), now),
        )
        conn.commit()
        if logger:
            logger.info(f"✓ Created default admin user '{default_username}' ({default_email}).")
            logger.info("  Set DISABLE_DEFAULT_ADMIN=true to disable this auto-bootstrap.")
    finally:
        conn.close()


def get_db():
    """Return a DB connection for the configured DB_TYPE"""
    db_type = _get_db_type()
    if db_type == "sqlite":
        import sqlite3
        conn = sqlite3.connect(config.DATABASE_URL.split("///")[1])
        try:
            conn.execute("PRAGMA foreign_keys = ON")
        except Exception:
            pass
        return conn
    elif db_type == "mysql":
        # Assumes DATABASE_URL is in the format: mysql+pymysql://user:password@host:port/db
        from urllib.parse import urlparse
        parsed_url = urlparse(config.DATABASE_URL)
        return pymysql.connect(
            host=parsed_url.hostname,
            port=parsed_url.port or 3306,
            user=parsed_url.username,
            password=parsed_url.password,
            db=parsed_url.path.lstrip('/'),
            autocommit=False
        )
    else:
        raise RuntimeError(f"Unsupported DB_TYPE: {db_type}")

def get_credit_config():
    """Return credit system configuration"""
    return config.DEFAULT_CREDIT_CONFIG

# Credit system configuration - for use within this module if needed, e.g., for migrations
CREDITS_STARTING = config.DEFAULT_CREDIT_CONFIG["starting_credits"]
