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

# Credit system configuration
CREDITS_BASE = int(os.getenv("CREDITS_BASE", "2"))
CREDITS_PER_CITY = int(os.getenv("CREDITS_PER_CITY", "1"))
CREDITS_PER_RESULT = int(os.getenv("CREDITS_PER_RESULT", "1"))
CREDITS_MIN_JOB = int(os.getenv("CREDITS_MIN_JOB", "3"))
CREDITS_STARTING = int(os.getenv("CREDITS_STARTING", "100"))
MAX_JOBS_PER_HOUR = int(os.getenv("MAX_JOBS_PER_HOUR", "5"))
MAX_CONCURRENT_JOBS = int(os.getenv("MAX_CONCURRENT_JOBS", "2"))

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
                credit_balance INTEGER DEFAULT 0,
                credit_updated_at TEXT,
                created_at TEXT NOT NULL,
                last_login TEXT
            )
        """)

        # Add credit columns to existing users table if they don't exist
        try:
            cursor.execute("ALTER TABLE users ADD COLUMN credit_balance INTEGER DEFAULT 0")
        except:
            pass
        try:
            cursor.execute("ALTER TABLE users ADD COLUMN credit_updated_at TEXT")
        except:
            pass

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
                credit_estimate INTEGER DEFAULT 0,
                credit_charged INTEGER DEFAULT 0,
                credit_refund INTEGER DEFAULT 0,
                created_at TEXT NOT NULL,
                completed_at TEXT,
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        """)

        # Add credit columns to existing jobs table if they don't exist
        try:
            cursor.execute("ALTER TABLE jobs ADD COLUMN credit_estimate INTEGER DEFAULT 0")
        except:
            pass
        try:
            cursor.execute("ALTER TABLE jobs ADD COLUMN credit_charged INTEGER DEFAULT 0")
        except:
            pass
        try:
            cursor.execute("ALTER TABLE jobs ADD COLUMN credit_refund INTEGER DEFAULT 0")
        except:
            pass

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

        # Credit ledger table for audit trail
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS credit_ledger (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                job_id TEXT,
                amount INTEGER NOT NULL,
                balance_after INTEGER NOT NULL,
                transaction_type TEXT NOT NULL,
                reason TEXT,
                created_at TEXT NOT NULL,
                created_by INTEGER,
                FOREIGN KEY (user_id) REFERENCES users(id),
                FOREIGN KEY (job_id) REFERENCES jobs(job_id),
                FOREIGN KEY (created_by) REFERENCES users(id)
            )
        """)

        # Rate limit tracking table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS rate_limits (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL UNIQUE,
                window_start TEXT NOT NULL,
                jobs_in_window INTEGER DEFAULT 0,
                last_job_at TEXT,
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        """)

        # Credit requests table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS credit_requests (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                amount_requested INTEGER NOT NULL,
                reason TEXT,
                status TEXT DEFAULT 'pending',
                admin_note TEXT,
                reviewed_by INTEGER,
                created_at TEXT NOT NULL,
                reviewed_at TEXT,
                FOREIGN KEY (user_id) REFERENCES users(id),
                FOREIGN KEY (reviewed_by) REFERENCES users(id)
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
                    INSERT INTO users (username, email, password_hash, is_approved, is_admin, credit_balance, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, ("admin", "akb@tool.com", admin_hash, 1, 1, 999999, datetime.now().isoformat()))
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
                credit_balance INT DEFAULT 0,
                credit_updated_at TEXT,
                created_at TEXT NOT NULL,
                last_login TEXT
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """)

        # Add credit columns to existing users table if they don't exist
        try:
            cursor.execute("ALTER TABLE users ADD COLUMN credit_balance INT DEFAULT 0")
        except:
            pass
        try:
            cursor.execute("ALTER TABLE users ADD COLUMN credit_updated_at TEXT")
        except:
            pass

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
                credit_estimate INT DEFAULT 0,
                credit_charged INT DEFAULT 0,
                credit_refund INT DEFAULT 0,
                created_at TEXT NOT NULL,
                completed_at TEXT,
                FOREIGN KEY (user_id) REFERENCES users(id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """)

        # Add credit columns to existing jobs table if they don't exist
        try:
            cursor.execute("ALTER TABLE jobs ADD COLUMN credit_estimate INT DEFAULT 0")
        except:
            pass
        try:
            cursor.execute("ALTER TABLE jobs ADD COLUMN credit_charged INT DEFAULT 0")
        except:
            pass
        try:
            cursor.execute("ALTER TABLE jobs ADD COLUMN credit_refund INT DEFAULT 0")
        except:
            pass

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

        # Credit ledger table for audit trail
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS credit_ledger (
                id INT PRIMARY KEY AUTO_INCREMENT,
                user_id INT NOT NULL,
                job_id VARCHAR(255),
                amount INT NOT NULL,
                balance_after INT NOT NULL,
                transaction_type VARCHAR(50) NOT NULL,
                reason TEXT,
                created_at TEXT NOT NULL,
                created_by INT,
                FOREIGN KEY (user_id) REFERENCES users(id),
                FOREIGN KEY (job_id) REFERENCES jobs(job_id),
                FOREIGN KEY (created_by) REFERENCES users(id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """)

        # Rate limit tracking table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS rate_limits (
                id INT PRIMARY KEY AUTO_INCREMENT,
                user_id INT NOT NULL UNIQUE,
                window_start TEXT NOT NULL,
                jobs_in_window INT DEFAULT 0,
                last_job_at TEXT,
                FOREIGN KEY (user_id) REFERENCES users(id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        """)

        # Credit requests table
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS credit_requests (
                id INT PRIMARY KEY AUTO_INCREMENT,
                user_id INT NOT NULL,
                amount_requested INT NOT NULL,
                reason TEXT,
                status VARCHAR(50) DEFAULT 'pending',
                admin_note TEXT,
                reviewed_by INT,
                created_at TEXT NOT NULL,
                reviewed_at TEXT,
                FOREIGN KEY (user_id) REFERENCES users(id),
                FOREIGN KEY (reviewed_by) REFERENCES users(id)
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
                    INSERT INTO users (username, email, password_hash, is_approved, is_admin, credit_balance, created_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                """, ("admin", "akb@tool.com", admin_hash, 1, 1, 999999, datetime.now().isoformat()))
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


def get_credit_config():
    """Return credit system configuration"""
    return {
        "base": CREDITS_BASE,
        "per_city": CREDITS_PER_CITY,
        "per_result": CREDITS_PER_RESULT,
        "min_job": CREDITS_MIN_JOB,
        "starting": CREDITS_STARTING,
        "max_jobs_per_hour": MAX_JOBS_PER_HOUR,
        "max_concurrent_jobs": MAX_CONCURRENT_JOBS,
    }
