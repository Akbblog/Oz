-- 000_base_schema.sql
-- Base schema required for core application tables (MySQL)

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
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
    FOREIGN KEY (job_id) REFERENCES jobs(job_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS job_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    job_id VARCHAR(255) NOT NULL,
    log_message TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (job_id) REFERENCES jobs(job_id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE INDEX idx_jobs_user_id ON jobs(user_id);
CREATE INDEX idx_jobs_job_id ON jobs(job_id);
CREATE INDEX idx_results_job_id ON results(job_id);
CREATE INDEX idx_job_logs_job_id ON job_logs(job_id);

