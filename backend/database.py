"""
Database setup supporting SQLite (default) and MySQL (via PyMySQL) depending on env var DB_TYPE
"""
import os
import json
from datetime import datetime
from typing import Optional

DB_TYPE = os.getenv("DB_TYPE", "sqlite").lower()

# SQLite defaults
SQLITE_DB_PATH = os.getenv("SQLITE_DB", "scraper.db")

# MySQL defaults
MYSQL_HOST = os.getenv("MYSQL_HOST", "localhost")
MYSQL_PORT = int(os.getenv("MYSQL_PORT", 3306))
MYSQL_USER = os.getenv("MYSQL_USER", "scraper")
MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD", "scraper_pass")
MYSQL_DB = os.getenv("MYSQL_DB", "scraper_db")

# Lazily import pymysql if needed
pymysql = None
if DB_TYPE == "mysql":
    try:
        import pymysql
    except Exception as e:
        raise RuntimeError("PyMySQL is required for MySQL support. Install PyMySQL in requirements.")


def _get_placeholders():
    return "%s" if DB_TYPE == "mysql" else "?"


def init_database():
    """Initialize database with tables"""
    if DB_TYPE == "sqlite":
        import sqlite3
        conn = sqlite3.connect(SQLITE_DB_PATH)
        cursor = conn.cursor()

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                email TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                is_approved INTEGER DEFAULT 0,
                is_admin INTEGER DEFAULT 0,
                created_at TEXT NOT NULL,
                last_login TEXT
            )
        """)

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS jobs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id TEXT UNIQUE NOT NULL,
                user_id INTEGER NOT NULL,
                category TEXT NOT NULL,
                cities_data TEXT NOT NULL,
                max_results_per_city INTEGER DEFAULT 10,
                status TEXT NOT NULL,
                progress INTEGER DEFAULT 0,
                total_cities INTEGER DEFAULT 0,
                current_city TEXT,
                error TEXT,
                created_at TEXT NOT NULL,
                completed_at TEXT,
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        """)

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS results (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id TEXT NOT NULL,
                business_name TEXT,
                phone TEXT,
                website TEXT,
                address TEXT,
                category TEXT,
                city TEXT,
                state TEXT,
                google_maps_url TEXT,
                FOREIGN KEY (job_id) REFERENCES jobs(job_id)
            )
        """)

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS job_logs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id TEXT NOT NULL,
                log_message TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (job_id) REFERENCES jobs(job_id)
            )
        """)

        # Create default admin user (email: akb@tool.com, password: tool.com)
        cursor.execute("SELECT id FROM users WHERE email = ?", ("akb@tool.com",))
        if not cursor.fetchone():
            try:
                from passlib.context import CryptContext
                pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
                admin_password = "tool.com"
                admin_hash = pwd_context.hash(admin_password)

                cursor.execute("""
                    INSERT INTO users (username, email, password_hash, is_approved, is_admin, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, ("admin", "akb@tool.com", admin_hash, 1, 1, datetime.now().isoformat()))
            except Exception as e:
                print(f"Warning: Could not create admin user: {e}")
                print("Admin user can be created manually after first login")

        conn.commit()
        conn.close()

    elif DB_TYPE == "mysql":
        # Create tables using MySQL syntax
        import time
        conn = None
        for attempt in range(1, 11):
            try:
                conn = pymysql.connect(host=MYSQL_HOST, port=MYSQL_PORT, user=MYSQL_USER, password=MYSQL_PASSWORD, db=MYSQL_DB, autocommit=True)
                break
            except Exception as e:
                print(f"MySQL connection attempt {attempt} failed: {e}")
                time.sleep(2)
        if conn is None:
            raise RuntimeError("Could not connect to MySQL after multiple attempts")
        cursor = conn.cursor()

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INT PRIMARY KEY AUTO_INCREMENT,
                username VARCHAR(255) UNIQUE NOT NULL,
                email VARCHAR(255) UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                is_approved TINYINT(1) DEFAULT 0,
                is_admin TINYINT(1) DEFAULT 0,
                created_at TEXT NOT NULL,
                last_login TEXT
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """)

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS jobs (
                id INT PRIMARY KEY AUTO_INCREMENT,
                job_id VARCHAR(255) UNIQUE NOT NULL,
                user_id INT NOT NULL,
                category VARCHAR(255) NOT NULL,
                cities_data TEXT NOT NULL,
                max_results_per_city INT DEFAULT 10,
                status VARCHAR(50) NOT NULL,
                progress INT DEFAULT 0,
                total_cities INT DEFAULT 0,
                current_city VARCHAR(255),
                error TEXT,
                created_at TEXT NOT NULL,
                completed_at TEXT,
                FOREIGN KEY (user_id) REFERENCES users(id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """)

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS results (
                id INT PRIMARY KEY AUTO_INCREMENT,
                job_id VARCHAR(255) NOT NULL,
                business_name TEXT,
                phone TEXT,
                website TEXT,
                address TEXT,
                category VARCHAR(255),
                city VARCHAR(255),
                state VARCHAR(255),
                google_maps_url TEXT,
                FOREIGN KEY (job_id) REFERENCES jobs(job_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """)

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS job_logs (
                id INT PRIMARY KEY AUTO_INCREMENT,
                job_id VARCHAR(255) NOT NULL,
                log_message TEXT NOT NULL,
                created_at TEXT NOT NULL,
                FOREIGN KEY (job_id) REFERENCES jobs(job_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """)

        # Create default admin user (email: akb@tool.com, password: tool.com)
        cursor.execute("SELECT id FROM users WHERE email = %s", ("akb@tool.com",))
        if not cursor.fetchone():
            try:
                from passlib.context import CryptContext
                pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
                admin_password = "tool.com"
                admin_hash = pwd_context.hash(admin_password)

                cursor.execute("""
                    INSERT INTO users (username, email, password_hash, is_approved, is_admin, created_at)
                    VALUES (%s, %s, %s, %s, %s, %s)
                """, ("admin", "akb@tool.com", admin_hash, 1, 1, datetime.now().isoformat()))
            except Exception as e:
                print(f"Warning: Could not create admin user: {e}")
                print("Admin user can be created manually after first login")

        conn.commit()
        conn.close()

    else:
        raise RuntimeError(f"Unsupported DB_TYPE: {DB_TYPE}")


def get_db():
    """Return a DB connection for the configured DB_TYPE"""
    if DB_TYPE == "sqlite":
        import sqlite3
        return sqlite3.connect(SQLITE_DB_PATH)
    elif DB_TYPE == "mysql":
        return pymysql.connect(host=MYSQL_HOST, port=MYSQL_PORT, user=MYSQL_USER, password=MYSQL_PASSWORD, db=MYSQL_DB, autocommit=False)
    else:
        raise RuntimeError(f"Unsupported DB_TYPE: {DB_TYPE}")
