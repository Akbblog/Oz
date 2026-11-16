"""
Pytest configuration and fixtures for testing

Provides:
- Test database setup/teardown
- Sample data fixtures
- Common test utilities
"""

import os
import sys
import pytest
from datetime import datetime
from pathlib import Path

# Add backend to path
backend_dir = Path(__file__).parent.parent
sys.path.insert(0, str(backend_dir))


@pytest.fixture(scope="session", autouse=True)
def _never_touch_real_databases(tmp_path_factory):
    """Point every test - even ones without a DB fixture - at a temp SQLite file.

    config.py loads backend/.env at import time; without this a test that
    forgets the fixture would read/write the developer's (or production) DB.
    """
    guard_db = tmp_path_factory.mktemp("guard") / "guard.db"
    saved = {k: os.environ.get(k) for k in ("DATABASE_URL", "DB_TYPE")}
    os.environ["DATABASE_URL"] = f"sqlite:///{guard_db}"
    os.environ["DB_TYPE"] = "sqlite"
    yield
    for k, v in saved.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v


requires_sqlite = pytest.mark.skipif(bool(os.getenv("IL_TEST_MYSQL_URL", "").strip()),
                                     reason="inspects SQLite catalog (sqlite_master / PRAGMA)")


@pytest.fixture(scope="session")
def test_db_path(tmp_path_factory):
    """Create a temporary database file for testing"""
    db_path = tmp_path_factory.mktemp("data") / "test_scraper.db"
    return str(db_path)


# Opt-in: run the suite against an ISOLATED MySQL/MariaDB test server, e.g.
#   IL_TEST_MYSQL_URL=mysql://root:qa_root_only@127.0.0.1:13306/il_test_suite
# Hard guards: loopback host only, database name must start with "il_test".
# The database is dropped and recreated for every test.
_MYSQL_URL = os.getenv("IL_TEST_MYSQL_URL", "").strip()


def _mysql_target():
    from urllib.parse import urlparse

    u = urlparse(_MYSQL_URL)
    db = u.path.lstrip("/")
    if u.hostname not in ("127.0.0.1", "localhost") or not db.startswith("il_test"):
        raise RuntimeError("IL_TEST_MYSQL_URL must point at 127.0.0.1 and a database named il_test*")
    return u, db


_MYSQL_SEED = None  # {table: (columns, rows)} captured right after the first migration run


def _mysql_admin_conn(db=None):
    import pymysql

    u, _ = _mysql_target()
    return pymysql.connect(host=u.hostname, port=u.port or 3306, user=u.username or "root",
                           password=u.password or "", db=db, autocommit=True)


def _reset_mysql_database(init_database):
    """First call: drop/create + run all migrations, then snapshot seed rows.
    Later calls: truncate every table and restore that snapshot (DDL replay
    on Docker storage costs ~60s per test)."""
    global _MYSQL_SEED
    _, db = _mysql_target()
    if _MYSQL_SEED is None:
        conn = _mysql_admin_conn()
        with conn.cursor() as cur:
            cur.execute(f"DROP DATABASE IF EXISTS `{db}`")
            cur.execute(f"CREATE DATABASE `{db}` CHARACTER SET utf8mb4")
        conn.close()
        init_database()
        conn = _mysql_admin_conn(db)
        seed = {}
        with conn.cursor() as cur:
            cur.execute("SHOW TABLES")
            for (table,) in cur.fetchall():
                cur.execute(f"SELECT * FROM `{table}`")
                cols = [d[0] for d in cur.description]
                seed[table] = (cols, cur.fetchall())
        conn.close()
        _MYSQL_SEED = seed
        return
    conn = _mysql_admin_conn(db)
    with conn.cursor() as cur:
        cur.execute("SET FOREIGN_KEY_CHECKS = 0")
        for table, (cols, rows) in _MYSQL_SEED.items():
            cur.execute(f"TRUNCATE TABLE `{table}`")
            if rows:
                col_sql = ", ".join(f"`{c}`" for c in cols)
                ph = ", ".join(["%s"] * len(cols))
                cur.executemany(f"INSERT INTO `{table}` ({col_sql}) VALUES ({ph})", rows)
        cur.execute("SET FOREIGN_KEY_CHECKS = 1")
    conn.close()


@pytest.fixture(scope="function")
def test_db(test_db_path, monkeypatch):
    """
    Provide a fresh test database for each test function (temp SQLite by
    default; an isolated MySQL/MariaDB when IL_TEST_MYSQL_URL is set).
    """
    monkeypatch.setenv("DISABLE_DEFAULT_ADMIN", "true")
    monkeypatch.setenv("JOB_RUNNER_MODE", "off")
    # Durability tests assert refund behaviour, so they pin a policy explicitly.
    # (Production default when unset is "none" - see test_refund_policy_default_is_none.)
    monkeypatch.setenv("JOB_REFUND_POLICY", "delivered")

    import database
    from database import init_database, get_db

    if _MYSQL_URL:
        _mysql_target()
        monkeypatch.setenv("DATABASE_URL", _MYSQL_URL)
        monkeypatch.setenv("DB_TYPE", "mysql")
        # Drop pooled connections from the previous test's database.
        while True:
            try:
                raw, _ = database._get_mysql_pool().get_nowait()
                raw.close()
            except Exception:
                break
        _reset_mysql_database(init_database)
        yield
        return

    db_url = f"sqlite:///{test_db_path}"
    monkeypatch.setenv("DATABASE_URL", db_url)
    monkeypatch.setenv("DB_TYPE", "sqlite")

    # Safety guard: never let the suite touch a real database (CLAUDE_DEEP_AUDIT M-3).
    assert database._get_db_type() == "sqlite"
    assert os.path.abspath(database._sqlite_path(database._database_url())) == os.path.abspath(test_db_path), (
        "Test DB resolution escaped the temp directory"
    )

    # Initialize database with migrations
    init_database()

    yield

    # Cleanup: remove test database file
    if os.path.exists(test_db_path):
        # Close any open connections first
        try:
            conn = get_db()
            conn.close()
        except:
            pass
        os.remove(test_db_path)


@pytest.fixture
def db_connection(test_db):
    """Provide a database connection for tests"""
    from database import get_db
    conn = get_db()
    if _MYSQL_URL:
        # Without autocommit this long-lived connection keeps a REPEATABLE READ
        # snapshot and never sees rows the application writes on its own connections.
        conn.autocommit(True)
    yield conn
    conn.close()


@pytest.fixture
def sample_user(db_connection):
    """Create a test user and return user ID"""
    cursor = db_connection.cursor()

    cursor.execute("""
        INSERT INTO users (username, email, password_hash, is_approved, created_at, credit_balance)
        VALUES (?, ?, ?, ?, ?, ?)
    """, ("testuser", "test@example.com", "hashed_password", 1, datetime.now().isoformat(), 100))

    db_connection.commit()
    user_id = cursor.lastrowid

    yield user_id

    # Cleanup happens automatically when db_connection closes


@pytest.fixture
def sample_credit_package(db_connection):
    """Create a test credit package and return package ID"""
    from db.payment_crud import create_credit_package

    package_id = create_credit_package(
        name="Test Package",
        credits=100,
        base_price_cents=1000,
        display_price_cents=1000,
        is_active=True
    )

    yield package_id


@pytest.fixture
def sample_promo_code(db_connection):
    """Create a test promo code and return promo ID"""
    from db.payment_crud import create_promo_code

    promo_id = create_promo_code(
        code="TEST20",
        promo_type="percentage_off",
        discount_percentage=20.0,
        is_active=True
    )

    yield promo_id
