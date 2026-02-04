-- 004_user_enhancements_sqlite.sql
-- Fix existing database issues and add missing tables referenced in code (SQLite)

-- ============================================================================
-- STEP 1: Add missing columns to existing tables
-- ============================================================================

-- Add credit/payment columns to users table
ALTER TABLE users ADD COLUMN credit_balance INTEGER DEFAULT 100;
ALTER TABLE users ADD COLUMN credit_updated_at TEXT;
ALTER TABLE users ADD COLUMN referral_code TEXT;
ALTER TABLE users ADD COLUMN pricing_tier_id INTEGER;
ALTER TABLE users ADD COLUMN lifetime_credits_purchased INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN lifetime_spent_cents INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN low_balance_threshold INTEGER DEFAULT 10;
ALTER TABLE users ADD COLUMN email_notifications_enabled INTEGER DEFAULT 1;
ALTER TABLE users ADD COLUMN billing_name TEXT;
ALTER TABLE users ADD COLUMN billing_email TEXT;
-- JSON stored as TEXT
ALTER TABLE users ADD COLUMN billing_address TEXT;
ALTER TABLE users ADD COLUMN tax_id TEXT;
ALTER TABLE users ADD COLUMN stripe_customer_id TEXT;

-- SQLite cannot add UNIQUE constraints via ALTER TABLE; use indexes instead.
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_referral_code_unique ON users(referral_code);

-- Add credit tracking columns to jobs table
ALTER TABLE jobs ADD COLUMN credit_estimate INTEGER DEFAULT 0;
ALTER TABLE jobs ADD COLUMN credit_charged INTEGER DEFAULT 0;

-- ============================================================================
-- STEP 2: Create credit_ledger table (referenced extensively in main.py)
-- ============================================================================

CREATE TABLE IF NOT EXISTS credit_ledger (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    job_id TEXT,
    amount INTEGER NOT NULL,
    balance_after INTEGER NOT NULL,
    transaction_type TEXT NOT NULL CHECK(transaction_type IN ('credit', 'debit', 'refund', 'bonus', 'promotional')),
    reason TEXT,
    created_at TEXT NOT NULL,
    created_by INTEGER,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_credit_ledger_user ON credit_ledger(user_id);
CREATE INDEX IF NOT EXISTS idx_credit_ledger_created_at ON credit_ledger(created_at);
CREATE INDEX IF NOT EXISTS idx_credit_ledger_transaction_type ON credit_ledger(transaction_type);

-- ============================================================================
-- STEP 3: Create credit_requests table
-- ============================================================================

CREATE TABLE IF NOT EXISTS credit_requests (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    amount_requested INTEGER NOT NULL,
    reason TEXT,
    status TEXT DEFAULT 'pending' CHECK(status IN ('pending', 'approved', 'denied')),
    admin_note TEXT,
    reviewed_by INTEGER,
    reviewed_at TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (reviewed_by) REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_credit_requests_user ON credit_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_credit_requests_status ON credit_requests(status);

-- ============================================================================
-- STEP 4: Create password_reset_tokens table
-- ============================================================================

CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    token_hash TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    used INTEGER DEFAULT 0,
    used_at TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_password_reset_token ON password_reset_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_password_reset_user ON password_reset_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_password_reset_expires ON password_reset_tokens(expires_at);

-- ============================================================================
-- STEP 5: Create rate_limits table (for API rate limiting)
-- ============================================================================

CREATE TABLE IF NOT EXISTS rate_limits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    window_start TEXT NOT NULL,
    jobs_in_window INTEGER DEFAULT 0,
    concurrent_jobs INTEGER DEFAULT 0,
    last_job_at TEXT,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_rate_limit_user ON rate_limits(user_id);
CREATE INDEX IF NOT EXISTS idx_rate_limit_window ON rate_limits(window_start);
