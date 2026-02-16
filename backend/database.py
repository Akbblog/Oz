import os
import json
from datetime import datetime
from typing import Optional
import queue
import threading
import time
from urllib.parse import urlparse
import config

# Lazily import pymysql only when MySQL is in use.
pymysql = None


def _infer_db_type_from_url(database_url: str) -> str:
    if not database_url:
        return "sqlite"

    parsed = urlparse(database_url)
    scheme = (parsed.scheme or "").lower()

    if scheme.startswith("mysql"):
        return "mysql"
    if scheme.startswith("sqlite") or scheme == "":
        return "sqlite"
    return "sqlite"


def _get_db_type() -> str:
    explicit = os.getenv("DB_TYPE", "").strip().lower()
    if explicit in ("sqlite", "mysql"):
        return explicit
    return _infer_db_type_from_url(config.DATABASE_URL)


def _ensure_pymysql():
    global pymysql
    if pymysql is not None:
        return pymysql
    try:
        import pymysql as _pymysql  # type: ignore
    except ImportError as exc:
        raise RuntimeError("PyMySQL is required for MySQL support. Install it with 'pip install PyMySQL'") from exc
    pymysql = _pymysql
    return pymysql


def _convert_qmark_placeholders(query: str) -> str:
    """Convert sqlite-style '?' placeholders to MySQL '%s' placeholders."""
    if "?" not in query:
        return query

    result = []
    in_single_quote = False
    in_double_quote = False
    in_backtick = False
    i = 0

    while i < len(query):
        char = query[i]

        if char == "'" and not in_double_quote and not in_backtick:
            # SQL escapes single quote in strings as doubled ''.
            if in_single_quote and i + 1 < len(query) and query[i + 1] == "'":
                result.append("''")
                i += 2
                continue
            in_single_quote = not in_single_quote
            result.append(char)
            i += 1
            continue

        if char == '"' and not in_single_quote and not in_backtick:
            in_double_quote = not in_double_quote
            result.append(char)
            i += 1
            continue

        if char == "`" and not in_single_quote and not in_double_quote:
            in_backtick = not in_backtick
            result.append(char)
            i += 1
            continue

        if char == "?" and not (in_single_quote or in_double_quote or in_backtick):
            result.append("%s")
        else:
            result.append(char)
        i += 1

    return "".join(result)


class _MySQLCursorAdapter:
    """DB-API cursor adapter that transparently converts qmark placeholders."""

    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, query, args=None):
        normalized_query = _convert_qmark_placeholders(query) if isinstance(query, str) else query
        if args is None:
            return self._cursor.execute(normalized_query)
        return self._cursor.execute(normalized_query, args)

    def executemany(self, query, args):
        normalized_query = _convert_qmark_placeholders(query) if isinstance(query, str) else query
        return self._cursor.executemany(normalized_query, args)

    def __iter__(self):
        return iter(self._cursor)

    def __enter__(self):
        self._cursor.__enter__()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        return self._cursor.__exit__(exc_type, exc_val, exc_tb)

    def __getattr__(self, item):
        return getattr(self._cursor, item)


class _MySQLConnectionAdapter:
    """Connection adapter that returns placeholder-normalizing cursors."""

    def __init__(self, conn):
        self._conn = conn

    def cursor(self, *args, **kwargs):
        return _MySQLCursorAdapter(self._conn.cursor(*args, **kwargs))

    def __enter__(self):
        self._conn.__enter__()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        return self._conn.__exit__(exc_type, exc_val, exc_tb)

    def __getattr__(self, item):
        return getattr(self._conn, item)


def _get_placeholders():
    return "%s" if _get_db_type() == "mysql" else "?"


_mysql_pool = None
_mysql_pool_lock = threading.Lock()


def _mysql_pool_config() -> tuple[int, int]:
    # Defaults are intentionally conservative to keep memory/connection pressure down.
    size_raw = os.getenv("MYSQL_POOL_SIZE", "5").strip()
    recycle_raw = os.getenv("MYSQL_POOL_RECYCLE_SECONDS", "1800").strip()  # 30 min

    try:
        size = max(1, int(size_raw))
    except Exception:
        size = 5

    try:
        recycle = max(0, int(recycle_raw))
    except Exception:
        recycle = 1800

    return size, recycle


def _get_mysql_pool():
    global _mysql_pool
    if _mysql_pool is not None:
        return _mysql_pool
    with _mysql_pool_lock:
        if _mysql_pool is None:
            size, _ = _mysql_pool_config()
            _mysql_pool = queue.LifoQueue(maxsize=size)
    return _mysql_pool


def _create_mysql_connection():
    # DATABASE_URL examples:
    # - mysql://user:password@host:port/db
    # - mysql+pymysql://user:password@host:port/db
    from urllib.parse import unquote

    mysql_client = _ensure_pymysql()
    parsed_url = urlparse(config.DATABASE_URL)

    # Keep timeouts low so "new connection per request" doesn't become catastrophic
    # when a remote DB is slow/unreachable.
    connect_timeout = float(os.getenv("MYSQL_CONNECT_TIMEOUT", "5") or "5")
    read_timeout = float(os.getenv("MYSQL_READ_TIMEOUT", "30") or "30")
    write_timeout = float(os.getenv("MYSQL_WRITE_TIMEOUT", "30") or "30")

    return mysql_client.connect(
        host=parsed_url.hostname,
        port=parsed_url.port or 3306,
        user=unquote(parsed_url.username or ""),
        password=unquote(parsed_url.password or ""),
        db=parsed_url.path.lstrip("/"),
        autocommit=False,
        connect_timeout=connect_timeout,
        read_timeout=read_timeout,
        write_timeout=write_timeout,
        charset="utf8mb4",
    )


def _acquire_mysql_connection():
    pool = _get_mysql_pool()
    _, recycle_seconds = _mysql_pool_config()
    now = time.time()

    try:
        raw_conn, created_at = pool.get_nowait()
    except queue.Empty:
        return _create_mysql_connection(), now

    if recycle_seconds and (now - float(created_at)) > float(recycle_seconds):
        try:
            raw_conn.close()
        except Exception:
            pass
        return _create_mysql_connection(), now

    try:
        # ping(reconnect=True) keeps pooled connections from going stale (common with remote DBs).
        raw_conn.ping(reconnect=True)
    except Exception:
        try:
            raw_conn.close()
        except Exception:
            pass
        return _create_mysql_connection(), now

    return raw_conn, created_at


def _release_mysql_connection(raw_conn, created_at: float) -> None:
    pool = _get_mysql_pool()

    try:
        # Ensure we don't leak an open transaction into the next borrower.
        raw_conn.rollback()
    except Exception:
        pass

    try:
        if hasattr(raw_conn, "open") and not raw_conn.open:
            return
    except Exception:
        return

    try:
        pool.put_nowait((raw_conn, float(created_at)))
    except queue.Full:
        try:
            raw_conn.close()
        except Exception:
            pass


class _MySQLPooledConnection:
    """Pooled connection wrapper that returns placeholder-normalizing cursors and releases on close()."""

    def __init__(self, raw_conn, created_at: float):
        self._raw_conn = raw_conn
        self._created_at = float(created_at)
        self._closed = False

    def cursor(self, *args, **kwargs):
        return _MySQLCursorAdapter(self._raw_conn.cursor(*args, **kwargs))

    def close(self):
        if self._closed:
            return
        self._closed = True
        _release_mysql_connection(self._raw_conn, self._created_at)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
        return False

    def __getattr__(self, item):
        return getattr(self._raw_conn, item)

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
            _ensure_users_phone_column(logger=logger)
        except Exception as e:
            logger.warning(f"Users.phone ensure step skipped/failed: {e}")
        try:
            _ensure_results_email_column(logger=logger)
        except Exception as e:
            logger.warning(f"Results.email ensure step skipped/failed: {e}")
        try:
            _ensure_default_admin_user(logger=logger)
        except Exception as e:
            logger.warning(f"Default admin bootstrap skipped/failed: {e}")
        return applied_count
    except Exception as e:
        logger.error(f"✗ Database initialization failed: {str(e)}")
        raise


def _ensure_users_phone_column(logger=None) -> None:
    """Ensure users.phone exists across supported databases."""
    conn = get_db()
    try:
        cursor = conn.cursor()
        if _get_db_type() == "mysql":
            cursor.execute(
                """
                SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'users'
                  AND COLUMN_NAME = 'phone'
                """
            )
            exists = int((cursor.fetchone() or [0])[0] or 0) > 0
            if not exists:
                cursor.execute("ALTER TABLE users ADD COLUMN phone VARCHAR(64) NULL")
                conn.commit()
                if logger:
                    logger.info("✓ Added missing users.phone column (MySQL).")
            return

        cursor.execute("PRAGMA table_info(users)")
        columns = [str(row[1]).lower() for row in (cursor.fetchall() or []) if row and len(row) > 1]
        if "phone" not in columns:
            cursor.execute("ALTER TABLE users ADD COLUMN phone TEXT")
            conn.commit()
            if logger:
                logger.info("✓ Added missing users.phone column (SQLite).")
    finally:
        conn.close()


def _ensure_results_email_column(logger=None) -> None:
    """Ensure results.email exists across supported databases."""
    conn = get_db()
    try:
        cursor = conn.cursor()
        if _get_db_type() == "mysql":
            cursor.execute(
                """
                SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = 'results'
                  AND COLUMN_NAME = 'email'
                """
            )
            exists = int((cursor.fetchone() or [0])[0] or 0) > 0
            if not exists:
                cursor.execute("ALTER TABLE results ADD COLUMN email TEXT NULL")
                conn.commit()
                if logger:
                    logger.info("Added missing results.email column (MySQL).")
            return

        cursor.execute("PRAGMA table_info(results)")
        columns = [str(row[1]).lower() for row in (cursor.fetchall() or []) if row and len(row) > 1]
        if "email" not in columns:
            cursor.execute("ALTER TABLE results ADD COLUMN email TEXT")
            conn.commit()
            if logger:
                logger.info("Added missing results.email column (SQLite).")
    finally:
        conn.close()


def _ensure_default_admin_user(logger=None) -> None:
    """
    Ensure at least one admin exists.

    Repo docs expect a default admin for new/dev installs. This only creates (or
    promotes) the configured DEFAULT_ADMIN_* identity, and only if no admin user
    currently exists.
    """
    default_username = os.getenv("DEFAULT_ADMIN_USERNAME", "admin").strip()
    default_email = os.getenv("DEFAULT_ADMIN_EMAIL", "akb@tool.com").strip()
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
    """Return a DB connection for the configured database backend."""
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
        raw_conn, created_at = _acquire_mysql_connection()
        return _MySQLPooledConnection(raw_conn, created_at)
    else:
        raise RuntimeError(f"Unsupported DB_TYPE: {db_type}")

def get_credit_config():
    """Return credit system configuration"""
    return config.DEFAULT_CREDIT_CONFIG

# Credit system configuration - for use within this module if needed, e.g., for migrations
CREDITS_STARTING = config.DEFAULT_CREDIT_CONFIG["starting_credits"]
