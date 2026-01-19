"""
Database models and setup using SQLite
"""
import sqlite3
import json
from datetime import datetime
from typing import List, Dict, Optional
import os

DB_PATH = "scraper.db"

def init_database():
    """Initialize database with tables"""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    
    # Users table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            email TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            is_approved BOOLEAN DEFAULT 0,
            is_admin BOOLEAN DEFAULT 0,
            created_at TEXT NOT NULL,
            last_login TEXT
        )
    """)
    
    # Jobs table
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
    
    # Results table
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
    
    # Logs table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS job_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            job_id TEXT NOT NULL,
            log_message TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (job_id) REFERENCES jobs(job_id)
        )
    """)
    
    # Create default admin user (password: admin123)
    from passlib.context import CryptContext
    pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    # Truncate password to ensure it's within bcrypt's 72-byte limit
    admin_password = "admin123"
    admin_password_bytes = admin_password.encode('utf-8')
    if len(admin_password_bytes) > 72:
        admin_password_bytes = admin_password_bytes[:72]
        admin_password = admin_password_bytes.decode('utf-8')
    admin_hash = pwd_context.hash(admin_password)
    
    cursor.execute("""
        INSERT OR IGNORE INTO users (username, email, password_hash, is_approved, is_admin, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
    """, ("admin", "admin@example.com", admin_hash, 1, 1, datetime.now().isoformat()))
    
    conn.commit()
    conn.close()

def get_db():
    """Get database connection"""
    return sqlite3.connect(DB_PATH)
