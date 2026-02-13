"""
Copy data from a SQLite database into the MySQL database defined by DATABASE_URL.

This script is intended for one-time migration before switching production from
SQLite to MySQL.

Usage examples:
  python scripts/migrate_sqlite_to_mysql.py --sqlite-db scraper.db
  DATABASE_URL=mysql://user:pass@host:3306/db python scripts/migrate_sqlite_to_mysql.py --sqlite-db scraper.db

Behavior:
  - Reads from SQLite tables (except sqlite_* internal tables).
  - Inserts into MySQL tables with matching names and columns.
  - Aborts if destination tables are non-empty (unless --force is supplied).
  - Preserves explicit IDs and timestamps from SQLite.
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from typing import Dict, List, Sequence, Tuple
from urllib.parse import unquote, urlparse

try:
    import pymysql
except ImportError as exc:
    raise RuntimeError("PyMySQL is required. Install with: pip install PyMySQL") from exc


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Migrate SQLite data to MySQL.")
    parser.add_argument(
        "--sqlite-db",
        default="scraper.db",
        help="Path to SQLite DB file (default: scraper.db)",
    )
    parser.add_argument(
        "--mysql-url",
        default=os.getenv("DATABASE_URL", ""),
        help="MySQL URL. Defaults to DATABASE_URL env var.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Allow migration even if destination has rows; destination tables will be cleared first.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=1000,
        help="Rows per batch insert (default: 1000)",
    )
    return parser.parse_args()


def parse_mysql_url(mysql_url: str) -> Dict[str, object]:
    parsed = urlparse((mysql_url or "").strip())
    scheme = (parsed.scheme or "").lower()
    if not scheme.startswith("mysql"):
        raise ValueError("mysql-url must use mysql:// or mysql+pymysql://")
    if not parsed.hostname or not parsed.path.strip("/"):
        raise ValueError("mysql-url is missing host or database name")
    return {
        "host": parsed.hostname,
        "port": parsed.port or 3306,
        "user": unquote(parsed.username or ""),
        "password": unquote(parsed.password or ""),
        "db": parsed.path.lstrip("/"),
    }


def get_sqlite_tables(sqlite_conn: sqlite3.Connection) -> List[str]:
    cur = sqlite_conn.cursor()
    cur.execute(
        """
        SELECT name
        FROM sqlite_master
        WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
        ORDER BY name
        """
    )
    return [row[0] for row in (cur.fetchall() or [])]


def get_mysql_tables(mysql_conn) -> List[str]:
    cur = mysql_conn.cursor()
    cur.execute("SHOW TABLES")
    return [row[0] for row in (cur.fetchall() or [])]


def get_sqlite_columns(sqlite_conn: sqlite3.Connection, table: str) -> List[str]:
    cur = sqlite_conn.cursor()
    cur.execute(f"PRAGMA table_info({table})")
    return [row[1] for row in (cur.fetchall() or [])]


def get_mysql_columns(mysql_conn, table: str) -> List[str]:
    cur = mysql_conn.cursor()
    cur.execute(
        """
        SELECT COLUMN_NAME
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = %s
        ORDER BY ORDINAL_POSITION
        """,
        (table,),
    )
    return [row[0] for row in (cur.fetchall() or [])]


def count_rows(mysql_conn, table: str) -> int:
    cur = mysql_conn.cursor()
    cur.execute(f"SELECT COUNT(*) FROM `{table}`")
    row = cur.fetchone()
    return int(row[0] or 0) if row else 0


def chunked(rows: Sequence[Tuple], size: int):
    for i in range(0, len(rows), size):
        yield rows[i : i + size]


def migrate_table(
    sqlite_conn: sqlite3.Connection,
    mysql_conn,
    table: str,
    common_columns: List[str],
    batch_size: int,
) -> int:
    if not common_columns:
        return 0

    sqlite_cur = sqlite_conn.cursor()
    mysql_cur = mysql_conn.cursor()

    select_sql = f"SELECT {', '.join(common_columns)} FROM {table}"
    sqlite_cur.execute(select_sql)
    rows = sqlite_cur.fetchall() or []
    if not rows:
        return 0

    cols = ", ".join([f"`{c}`" for c in common_columns])
    placeholders = ", ".join(["%s"] * len(common_columns))
    insert_sql = f"INSERT INTO `{table}` ({cols}) VALUES ({placeholders})"

    inserted = 0
    for batch in chunked(rows, batch_size):
        mysql_cur.executemany(insert_sql, batch)
        inserted += len(batch)

    return inserted


def main() -> int:
    args = parse_args()

    mysql_url = (args.mysql_url or "").strip()
    if not mysql_url:
        print("Missing MySQL URL. Set DATABASE_URL or pass --mysql-url.")
        return 1

    mysql_cfg = parse_mysql_url(mysql_url)

    if not os.path.exists(args.sqlite_db):
        print(f"SQLite database not found: {args.sqlite_db}")
        return 1

    sqlite_conn = sqlite3.connect(args.sqlite_db)
    mysql_conn = pymysql.connect(
        host=mysql_cfg["host"],
        port=int(mysql_cfg["port"]),
        user=str(mysql_cfg["user"]),
        password=str(mysql_cfg["password"]),
        db=str(mysql_cfg["db"]),
        autocommit=False,
        charset="utf8mb4",
    )

    try:
        sqlite_tables = get_sqlite_tables(sqlite_conn)
        mysql_tables = set(get_mysql_tables(mysql_conn))
        target_tables = [t for t in sqlite_tables if t in mysql_tables]

        if not target_tables:
            print("No matching tables found between SQLite and MySQL.")
            return 1

        if not args.force:
            non_empty = []
            for table in target_tables:
                if count_rows(mysql_conn, table) > 0:
                    non_empty.append(table)
            if non_empty:
                print("Destination MySQL is not empty for these tables:")
                for table in non_empty:
                    print(f"  - {table}")
                print("Re-run with --force to clear destination tables and continue.")
                return 1

        mysql_cur = mysql_conn.cursor()
        mysql_cur.execute("SET FOREIGN_KEY_CHECKS=0")

        if args.force:
            for table in target_tables:
                mysql_cur.execute(f"DELETE FROM `{table}`")
            mysql_conn.commit()

        summary: List[Tuple[str, int]] = []
        for table in target_tables:
            sqlite_columns = get_sqlite_columns(sqlite_conn, table)
            mysql_columns = set(get_mysql_columns(mysql_conn, table))
            common_columns = [col for col in sqlite_columns if col in mysql_columns]

            inserted = migrate_table(
                sqlite_conn=sqlite_conn,
                mysql_conn=mysql_conn,
                table=table,
                common_columns=common_columns,
                batch_size=max(1, int(args.batch_size)),
            )
            summary.append((table, inserted))
            mysql_conn.commit()

        mysql_cur.execute("SET FOREIGN_KEY_CHECKS=1")
        mysql_conn.commit()

        print("Migration completed.")
        for table, inserted in summary:
            print(f"{table}: {inserted} row(s)")
        return 0
    finally:
        sqlite_conn.close()
        mysql_conn.close()


if __name__ == "__main__":
    raise SystemExit(main())
