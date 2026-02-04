"""
Common database utilities for CRUD operations

Provides database-agnostic helper functions for:
- Connection management
- Query execution
- Placeholder handling (SQLite vs MySQL)
- Error handling and logging
"""

import os
import logging
from typing import Any, Dict, List, Optional, Tuple, Union
from contextlib import contextmanager

# Configure logging
logger = logging.getLogger(__name__)


def get_connection():
    """
    Get database connection using existing database.py module

    Returns:
        Database connection (sqlite3.Connection or pymysql.Connection)
    """
    import sys
    sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
    from database import get_db
    return get_db()


def get_db_type() -> str:
    """
    Get current database type

    Returns:
        'sqlite' or 'mysql'
    """
    return os.getenv("DB_TYPE", "sqlite").lower()


def get_placeholder() -> str:
    """
    Get SQL placeholder character for current database type

    Returns:
        '?' for SQLite, '%s' for MySQL
    """
    db_type = get_db_type()
    return "%s" if db_type == "mysql" else "?"


@contextmanager
def get_db_cursor(commit: bool = True):
    """
    Context manager for database operations

    Usage:
        with get_db_cursor() as cursor:
            cursor.execute("SELECT * FROM users")
            results = cursor.fetchall()

    Args:
        commit: Whether to commit on success (default True)

    Yields:
        Database cursor
    """
    conn = get_connection()
    cursor = conn.cursor()

    try:
        yield cursor
        if commit:
            conn.commit()
    except Exception as e:
        conn.rollback()
        logger.error(f"Database error: {str(e)}")
        raise
    finally:
        cursor.close()
        conn.close()


def execute_query(
    query: str,
    params: Optional[Union[Tuple, List]] = None,
    fetch_one: bool = False,
    fetch_all: bool = False,
    commit: bool = True
) -> Optional[Union[Any, List[Any]]]:
    """
    Execute a SQL query with error handling

    Args:
        query: SQL query string with placeholders
        params: Query parameters (tuple or list)
        fetch_one: If True, return single row
        fetch_all: If True, return all rows
        commit: Whether to commit changes (default True)

    Returns:
        - If fetch_one: Single row or None
        - If fetch_all: List of rows
        - Otherwise: lastrowid for INSERT, rowcount for UPDATE/DELETE

    Example:
        # Insert
        user_id = execute_query(
            "INSERT INTO users (username, email) VALUES (?, ?)",
            ("john", "john@example.com")
        )

        # Select one
        user = execute_query(
            "SELECT * FROM users WHERE id = ?",
            (1,),
            fetch_one=True
        )

        # Select all
        users = execute_query(
            "SELECT * FROM users",
            fetch_all=True
        )
    """
    placeholder = get_placeholder()

    # Convert ? to %s for MySQL
    if placeholder == "%s":
        query = query.replace("?", "%s")

    with get_db_cursor(commit=commit) as cursor:
        if params:
            cursor.execute(query, params)
        else:
            cursor.execute(query)

        if fetch_one:
            return cursor.fetchone()
        elif fetch_all:
            return cursor.fetchall()
        else:
            # For INSERT queries, return lastrowid
            if query.strip().upper().startswith('INSERT'):
                return cursor.lastrowid
            # For UPDATE/DELETE, return rowcount
            return cursor.rowcount


def execute_many(query: str, params_list: List[Tuple]) -> int:
    """
    Execute a query multiple times with different parameters (bulk insert)

    Args:
        query: SQL query string with placeholders
        params_list: List of parameter tuples

    Returns:
        Number of rows affected

    Example:
        rows = execute_many(
            "INSERT INTO logs (message, created_at) VALUES (?, ?)",
            [
                ("Log 1", "2026-02-04"),
                ("Log 2", "2026-02-04"),
                ("Log 3", "2026-02-04"),
            ]
        )
    """
    placeholder = get_placeholder()

    # Convert ? to %s for MySQL
    if placeholder == "%s":
        query = query.replace("?", "%s")

    with get_db_cursor(commit=True) as cursor:
        cursor.executemany(query, params_list)
        return cursor.rowcount


def table_exists(table_name: str) -> bool:
    """
    Check if a table exists in the database

    Args:
        table_name: Name of the table

    Returns:
        True if table exists, False otherwise
    """
    db_type = get_db_type()

    if db_type == "sqlite":
        query = """
            SELECT name FROM sqlite_master
            WHERE type='table' AND name=?
        """
    else:  # MySQL
        query = """
            SELECT TABLE_NAME FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s
        """

    result = execute_query(query, (table_name,), fetch_one=True)
    return result is not None


def column_exists(table_name: str, column_name: str) -> bool:
    """
    Check if a column exists in a table

    Args:
        table_name: Name of the table
        column_name: Name of the column

    Returns:
        True if column exists, False otherwise
    """
    db_type = get_db_type()

    if db_type == "sqlite":
        # SQLite: use PRAGMA table_info
        rows = execute_query(f"PRAGMA table_info({table_name})", fetch_all=True)
        if not rows:
            return False
        # Column name is at index 1 in PRAGMA result
        return any(row[1] == column_name for row in rows)
    else:  # MySQL
        query = """
            SELECT COLUMN_NAME FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = %s
            AND COLUMN_NAME = %s
        """
        result = execute_query(query, (table_name, column_name), fetch_one=True)
        return result is not None


def get_table_schema(table_name: str) -> List[Dict]:
    """
    Get schema information for a table

    Args:
        table_name: Name of the table

    Returns:
        List of column info dicts:
        [
            {'name': 'id', 'type': 'INTEGER', 'notnull': 1, 'pk': 1},
            ...
        ]
    """
    db_type = get_db_type()

    if db_type == "sqlite":
        rows = execute_query(f"PRAGMA table_info({table_name})", fetch_all=True)
        if not rows:
            return []
        # PRAGMA returns: (cid, name, type, notnull, dflt_value, pk)
        return [
            {
                'name': row[1],
                'type': row[2],
                'notnull': row[3],
                'default': row[4],
                'pk': row[5]
            }
            for row in rows
        ]
    else:  # MySQL
        query = """
            SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_KEY, COLUMN_DEFAULT
            FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s
            ORDER BY ORDINAL_POSITION
        """
        rows = execute_query(query, (table_name,), fetch_all=True)
        if not rows:
            return []

        return [
            {
                'name': row[0],
                'type': row[1],
                'notnull': 1 if row[2] == 'NO' else 0,
                'default': row[4],
                'pk': 1 if row[3] == 'PRI' else 0
            }
            for row in rows
        ]


def get_all_tables() -> List[str]:
    """
    Get list of all tables in the database

    Returns:
        List of table names
    """
    db_type = get_db_type()

    if db_type == "sqlite":
        query = """
            SELECT name FROM sqlite_master
            WHERE type='table' AND name NOT LIKE 'sqlite_%'
            ORDER BY name
        """
    else:  # MySQL
        query = """
            SELECT TABLE_NAME FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = DATABASE()
            ORDER BY TABLE_NAME
        """

    rows = execute_query(query, fetch_all=True)
    return [row[0] for row in rows] if rows else []


# Backwards compatibility with existing code
_get_placeholders = get_placeholder  # Alias for existing code
