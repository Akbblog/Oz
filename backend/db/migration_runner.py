"""
Database Migration Runner

Provides version-controlled database schema migrations with:
- Migration tracking in schema_migrations table
- Checksum validation to detect modified migrations
- Idempotent application (safe to run multiple times)
- Transaction-wrapped for atomicity
- Support for both SQLite and MySQL
"""

import os
import hashlib
import logging
from datetime import datetime
from typing import List, Dict, Optional, Tuple
from pathlib import Path
from urllib.parse import urlparse

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _get_db_type() -> str:
    explicit = os.getenv("DB_TYPE", "").strip().lower()
    if explicit in ("sqlite", "mysql"):
        return explicit

    database_url = os.getenv("DATABASE_URL", "sqlite:///scraper.db")
    scheme = (urlparse(database_url).scheme or "").lower()
    if scheme.startswith("mysql"):
        return "mysql"
    return "sqlite"


def _get_placeholder() -> str:
    return "%s" if _get_db_type() == "mysql" else "?"


def _convert_placeholders(query: str) -> str:
    """Convert sqlite-style '?' placeholders to '%s' for MySQL."""
    if _get_placeholder() == "%s":
        return query.replace("?", "%s")
    return query


def _ensure_schema_migrations_table(conn) -> None:
    """Create schema_migrations table (db-specific) if it doesn't exist."""
    cursor = conn.cursor()
    db_type = _get_db_type()

    if db_type == "mysql":
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


def get_db_connection():
    """Get database connection using existing database.py module"""
    import sys
    sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
    from database import get_db
    return get_db()


def calculate_checksum(sql_content: str) -> str:
    """Calculate MD5 checksum of SQL content for change detection"""
    return hashlib.md5(sql_content.encode('utf-8')).hexdigest()


def get_applied_migrations(conn) -> Dict[str, Dict]:
    """
    Get list of already applied migrations

    Returns:
        Dict mapping version -> {filename, applied_at, checksum}
    """
    cursor = conn.cursor()
    _ensure_schema_migrations_table(conn)

    # Fetch applied migrations
    cursor.execute("SELECT version, filename, applied_at, checksum FROM schema_migrations ORDER BY version")
    rows = cursor.fetchall()

    return {
        row[0]: {
            'filename': row[1],
            'applied_at': row[2],
            'checksum': row[3]
        }
        for row in rows
    }


def extract_version_from_filename(filename: str) -> Optional[str]:
    """
    Extract version number from migration filename

    Examples:
        '001_payment_tables.sql' -> '001'
        '004_user_enhancements.sql' -> '004'
        'invalid.sql' -> None
    """
    if not filename.endswith('.sql'):
        return None

    parts = filename.split('_')
    if not parts:
        return None

    version = parts[0]
    if version.isdigit():
        return version

    return None


def get_pending_migrations(migrations_dir: str) -> List[Tuple[str, str, str]]:
    """
    Find migration files that haven't been applied yet

    Returns:
        List of tuples: (version, filename, full_path)
        Sorted by version number
    """
    conn = get_db_connection()
    applied = get_applied_migrations(conn)
    conn.close()

    db_type = _get_db_type()

    # Find all .sql files in migrations directory
    migrations_path = Path(migrations_dir)
    if not migrations_path.exists():
        logger.warning(f"Migrations directory not found: {migrations_dir}")
        return []

    # Group by version so we can prefer DB-specific variants
    by_version: Dict[str, Dict[str, Path]] = {}
    for sql_file in sorted(migrations_path.glob('*.sql')):
        filename = sql_file.name
        version = extract_version_from_filename(filename)
        if version is None:
            logger.debug(f"Skipping non-migration file: {filename}")
            continue

        variant = "sqlite" if filename.lower().endswith("_sqlite.sql") else "default"
        by_version.setdefault(version, {})[variant] = sql_file

    pending: List[Tuple[str, str, str]] = []
    for version in sorted(by_version.keys()):
        variants = by_version[version]
        chosen: Optional[Path] = None

        if db_type == "sqlite":
            chosen = variants.get("sqlite") or variants.get("default")
        else:  # mysql
            chosen = variants.get("default")
            if chosen is None and "sqlite" in variants:
                logger.warning(f"No MySQL migration found for version {version}; skipping SQLite-only file.")
                continue

        if chosen is None:
            continue

        if version not in applied:
            pending.append((version, chosen.name, str(chosen)))

    return pending


def validate_migration_checksum(conn, version: str, sql_content: str) -> bool:
    """
    Validate that migration content hasn't changed since it was applied

    Returns:
        True if checksum matches or no checksum stored
        False if checksum mismatch (migration was modified)
    """
    cursor = conn.cursor()
    cursor.execute(_convert_placeholders("SELECT checksum FROM schema_migrations WHERE version = ?"), (version,))
    row = cursor.fetchone()

    if not row or not row[0]:
        # No checksum stored (legacy migration or first run)
        return True

    stored_checksum = row[0]
    current_checksum = calculate_checksum(sql_content)

    if stored_checksum != current_checksum:
        logger.warning(f"Checksum mismatch for migration {version}")
        logger.warning(f"  Stored: {stored_checksum}")
        logger.warning(f"  Current: {current_checksum}")
        return False

    return True


def apply_migration(conn, migration_path: str, version: str, filename: str) -> bool:
    """
    Apply a single migration file

    Args:
        conn: Database connection
        migration_path: Full path to migration SQL file
        version: Migration version number
        filename: Migration filename

    Returns:
        True if successful, False otherwise
    """
    try:
        # Read migration SQL
        with open(migration_path, 'r', encoding='utf-8') as f:
            sql_content = f.read()

        # Calculate checksum
        checksum = calculate_checksum(sql_content)

        logger.info(f"Applying migration {version}: {filename}")

        # Begin transaction
        cursor = conn.cursor()

        # Split SQL into individual statements (SQLite doesn't support executescript in transactions well)
        # Remove comments and empty lines
        statements = []
        current_statement = []

        for line in sql_content.split('\n'):
            # Skip comment lines
            if line.strip().startswith('--') or not line.strip():
                continue

            current_statement.append(line)

            # Check if statement is complete (ends with semicolon)
            if line.strip().endswith(';'):
                statement = '\n'.join(current_statement)
                if statement.strip():
                    statements.append(statement)
                current_statement = []

        # Execute each statement
        for statement in statements:
            try:
                cursor.execute(statement)
            except Exception as e:
                logger.error(f"Error executing statement in {filename}:")
                logger.error(f"Statement: {statement[:200]}...")
                raise

        # Record migration in schema_migrations table
        applied_at = datetime.now().isoformat()
        cursor.execute(_convert_placeholders("""
            INSERT INTO schema_migrations (version, filename, applied_at, checksum)
            VALUES (?, ?, ?, ?)
        """), (version, filename, applied_at, checksum))

        # Commit transaction
        conn.commit()

        logger.info(f"✓ Successfully applied migration {version}")
        return True

    except Exception as e:
        logger.error(f"✗ Failed to apply migration {version}: {str(e)}")
        conn.rollback()
        return False


def run_pending_migrations(migrations_dir: str) -> int:
    """
    Apply all pending migrations in order

    Args:
        migrations_dir: Directory containing migration SQL files

    Returns:
        Number of migrations applied
    """
    pending = get_pending_migrations(migrations_dir)

    if not pending:
        logger.info("No pending migrations")
        return 0

    logger.info(f"Found {len(pending)} pending migration(s)")

    conn = get_db_connection()
    applied_count = 0

    try:
        for version, filename, full_path in pending:
            success = apply_migration(conn, full_path, version, filename)
            if success:
                applied_count += 1
            else:
                logger.error(f"Migration {version} failed. Stopping migration process.")
                break
    finally:
        conn.close()

    logger.info(f"Applied {applied_count} migration(s)")
    return applied_count


def get_migration_status() -> List[Dict]:
    """
    Get status of all migrations (applied and pending)

    Returns:
        List of dicts with migration info:
        [
            {
                'version': '001',
                'filename': '001_payment_tables.sql',
                'status': 'applied' | 'pending',
                'applied_at': '2026-02-04T...' or None
            }
        ]
    """
    conn = get_db_connection()
    applied = get_applied_migrations(conn)
    conn.close()

    # Find migrations directory
    backend_dir = os.path.dirname(os.path.dirname(__file__))
    migrations_dir = os.path.join(backend_dir, 'migrations')

    # Get all migration files
    migrations_path = Path(migrations_dir)
    all_migrations: Dict[str, Dict] = {}
    db_type = _get_db_type()

    if migrations_path.exists():
        # Same selection logic as get_pending_migrations: prefer sqlite variants in sqlite mode.
        by_version: Dict[str, Dict[str, Path]] = {}
        for sql_file in sorted(migrations_path.glob('*.sql')):
            filename = sql_file.name
            version = extract_version_from_filename(filename)
            if version is None:
                continue
            variant = "sqlite" if filename.lower().endswith("_sqlite.sql") else "default"
            by_version.setdefault(version, {})[variant] = sql_file

        for version in sorted(by_version.keys()):
            variants = by_version[version]
            chosen: Optional[Path]
            if db_type == "sqlite":
                chosen = variants.get("sqlite") or variants.get("default")
            else:
                chosen = variants.get("default")
            if chosen is None:
                continue

            all_migrations[version] = {
                'version': version,
                'filename': chosen.name,
                'status': 'applied' if version in applied else 'pending',
                'applied_at': applied[version]['applied_at'] if version in applied else None
            }

    # Sort by version
    return sorted(all_migrations.values(), key=lambda x: x['version'])


def rollback_migration(version: str) -> bool:
    """
    Rollback a specific migration (if rollback SQL exists)

    Note: This is a placeholder for future rollback support.
    Implement rollback SQL files as needed (e.g., 001_payment_tables_rollback.sql)
    """
    logger.warning("Migration rollback not yet implemented")
    logger.info("To rollback, restore database from backup or manually drop tables")
    return False


if __name__ == '__main__':
    # Allow running migration runner directly
    import sys

    if len(sys.argv) > 1:
        if sys.argv[1] == 'status':
            # Show migration status
            status = get_migration_status()
            print("\nMigration Status:")
            print("-" * 60)
            for migration in status:
                print(f"{migration['version']}: {migration['filename']}")
                print(f"  Status: {migration['status']}")
                if migration['applied_at']:
                    print(f"  Applied: {migration['applied_at']}")
                print()
        elif sys.argv[1] == 'run':
            # Run pending migrations
            backend_dir = os.path.dirname(os.path.dirname(__file__))
            migrations_dir = os.path.join(backend_dir, 'migrations')
            run_pending_migrations(migrations_dir)
    else:
        print("Usage:")
        print("  python migration_runner.py status  - Show migration status")
        print("  python migration_runner.py run     - Run pending migrations")
