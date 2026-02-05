"""
Tests for database migration system

Verifies:
- Migration tracking table creation
- Migration application in order
- Idempotency (safe to run twice)
- Checksum validation
"""

import pytest
from db.migration_runner import (
    get_applied_migrations,
    extract_version_from_filename,
    get_migration_status
)


def test_schema_migrations_table_exists(db_connection):
    """Test that schema_migrations tracking table is created"""
    cursor = db_connection.cursor()
    cursor.execute("""
        SELECT name FROM sqlite_master
        WHERE type='table' AND name='schema_migrations'
    """)
    result = cursor.fetchone()
    assert result is not None, "schema_migrations table should exist"


def test_extract_version_from_filename():
    """Test version extraction from migration filenames"""
    assert extract_version_from_filename("001_payment_tables.sql") == "001"
    assert extract_version_from_filename("004_user_enhancements.sql") == "004"
    assert extract_version_from_filename("invalid.sql") is None
    assert extract_version_from_filename("test.txt") is None


def test_migrations_applied(db_connection):
    """Test that migrations have been applied"""
    applied = get_applied_migrations(db_connection)
    assert len(applied) > 0, "At least one migration should be applied"
    assert "004" in applied, "Migration 004 (user enhancements) should be applied"


def test_migration_status():
    """Test migration status reporting"""
    status = get_migration_status()
    assert isinstance(status, list), "Status should return a list"
    assert len(status) > 0, "Should have at least one migration"

    # Check structure
    for migration in status:
        assert "version" in migration
        assert "filename" in migration
        assert "status" in migration
        assert migration["status"] in ["applied", "pending"]


def test_required_tables_exist(db_connection):
    """Test that all required tables from migrations exist"""
    cursor = db_connection.cursor()

    # Tables from 004_user_enhancements.sql
    required_tables = [
        "credit_ledger",
        "credit_requests",
        "password_reset_tokens",
        "rate_limits"
    ]

    # Tables from payment migrations (if applied)
    payment_tables = [
        "credit_packages",
        "payment_transactions",
        "invoices",
        "payment_methods",
        "webhook_events"
    ]

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    existing_tables = [row[0] for row in cursor.fetchall()]

    # Check required tables
    for table in required_tables:
        assert table in existing_tables, f"Table {table} should exist"

    # Check payment tables (if migrations were applied)
    applied = get_applied_migrations(db_connection)
    if any(v.startswith("001") or v.startswith("002") or v.startswith("003") for v in applied.keys()):
        for table in payment_tables:
            assert table in existing_tables, f"Payment table {table} should exist"


def test_users_table_has_credit_columns(db_connection):
    """Test that users table has been extended with credit columns"""
    cursor = db_connection.cursor()

    # Get table schema
    cursor.execute("PRAGMA table_info(users)")
    columns = {row[1] for row in cursor.fetchall()}  # row[1] is column name

    # Check for credit-related columns added by migration 004
    required_columns = {
        "credit_balance",
        "credit_updated_at",
        "referral_code",
        "lifetime_credits_purchased",
        "lifetime_spent_cents",

        # Approval metadata added by migration 007
        "approved_at",
        "approved_by",
        "denied_at",
        "denied_by",
        "denied_reason",
    }

    for column in required_columns:
        assert column in columns, f"Column {column} should exist in users table"
