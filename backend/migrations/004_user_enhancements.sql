-- 004_user_enhancements.sql
-- Fix existing database issues and add missing tables referenced in code (MySQL)

-- NOTE: These statements assume MySQL 5.7+ / 8.0+.
-- If your MySQL version lacks JSON, change JSON columns to TEXT.

-- ============================================================================
-- STEP 1: Add missing columns to existing tables
-- ============================================================================

ALTER TABLE users ADD COLUMN credit_balance INT DEFAULT 100;
ALTER TABLE users ADD COLUMN credit_updated_at TEXT;
ALTER TABLE users ADD COLUMN referral_code VARCHAR(50) UNIQUE;
ALTER TABLE users ADD COLUMN pricing_tier_id INT;
ALTER TABLE users ADD COLUMN lifetime_credits_purchased INT DEFAULT 0;
ALTER TABLE users ADD COLUMN lifetime_spent_cents INT DEFAULT 0;
ALTER TABLE users ADD COLUMN low_balance_threshold INT DEFAULT 10;
ALTER TABLE users ADD COLUMN email_notifications_enabled TINYINT(1) DEFAULT 1;
ALTER TABLE users ADD COLUMN billing_name VARCHAR(255);
ALTER TABLE users ADD COLUMN billing_email VARCHAR(255);
ALTER TABLE users ADD COLUMN billing_address JSON;
ALTER TABLE users ADD COLUMN tax_id VARCHAR(100);
ALTER TABLE users ADD COLUMN stripe_customer_id VARCHAR(255);

ALTER TABLE jobs ADD COLUMN credit_estimate INT DEFAULT 0;
ALTER TABLE jobs ADD COLUMN credit_charged INT DEFAULT 0;

-- ============================================================================
-- STEP 2: Create credit_ledger table
-- ============================================================================

CREATE TABLE IF NOT EXISTS credit_ledger (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    job_id VARCHAR(255),
    amount INT NOT NULL,
    balance_after INT NOT NULL,
    transaction_type ENUM('credit', 'debit', 'refund', 'bonus', 'promotional') NOT NULL,
    reason TEXT,
    created_at TEXT NOT NULL,
    created_by INT,
    INDEX idx_credit_ledger_user (user_id),
    INDEX idx_credit_ledger_created_at (created_at),
    INDEX idx_credit_ledger_transaction_type (transaction_type),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- STEP 3: Create credit_requests table
-- ============================================================================

CREATE TABLE IF NOT EXISTS credit_requests (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    amount_requested INT NOT NULL,
    reason TEXT,
    status ENUM('pending', 'approved', 'denied') DEFAULT 'pending',
    admin_note TEXT,
    reviewed_by INT,
    reviewed_at TEXT,
    created_at TEXT NOT NULL,
    INDEX idx_credit_requests_user (user_id),
    INDEX idx_credit_requests_status (status),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (reviewed_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- STEP 4: Create password_reset_tokens table
-- ============================================================================

CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    token_hash VARCHAR(64) NOT NULL,
    expires_at TEXT NOT NULL,
    used TINYINT(1) DEFAULT 0,
    used_at TEXT,
    created_at TEXT NOT NULL,
    INDEX idx_password_reset_token (token_hash),
    INDEX idx_password_reset_user (user_id),
    INDEX idx_password_reset_expires (expires_at),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- STEP 5: Create rate_limits table
-- ============================================================================

CREATE TABLE IF NOT EXISTS rate_limits (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    endpoint VARCHAR(255) NOT NULL,
    requests_count INT DEFAULT 0,
    window_start TEXT NOT NULL,
    window_end TEXT NOT NULL,
    last_request_at TEXT,
    UNIQUE KEY unique_rate_limit (user_id, endpoint, window_start),
    INDEX idx_rate_limit_window (window_start(64), window_end(64)),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

