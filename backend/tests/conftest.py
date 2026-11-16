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


@pytest.fixture(scope="session")
def test_db_path(tmp_path_factory):
    """Create a temporary database file for testing"""
    db_path = tmp_path_factory.mktemp("data") / "test_scraper.db"
    return str(db_path)


@pytest.fixture(scope="function")
def test_db(test_db_path, monkeypatch):
    """
    Provide a fresh test database for each test function

    This fixture:
    1. Sets DATABASE_URL to test database
    2. Initializes database with migrations
    3. Yields to test
    4. Cleans up after test
    """
    # Set environment to use test database
    db_url = f"sqlite:///{test_db_path}"
    monkeypatch.setenv("DATABASE_URL", db_url)
    monkeypatch.setenv("DB_TYPE", "sqlite")

    monkeypatch.setenv("DISABLE_DEFAULT_ADMIN", "true")
    monkeypatch.setenv("JOB_RUNNER_MODE", "off")
    monkeypatch.delenv("JOB_REFUND_POLICY", raising=False)

    # Import after setting environment
    import database
    from database import init_database, get_db

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
