-- 003_promo_referral_tables_sqlite.sql
-- Promotional features, pricing tiers, and referral tracking (SQLite version)

-- ============================================================================
-- Pricing Tiers
-- ============================================================================

CREATE TABLE IF NOT EXISTS pricing_tiers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    min_monthly_credits INTEGER DEFAULT 0,
    max_monthly_credits INTEGER DEFAULT NULL,
    price_per_credit_cents REAL NOT NULL,  -- DECIMAL -> REAL in SQLite
    discount_percentage REAL DEFAULT 0.00,
    requires_approval INTEGER DEFAULT 0,
    is_active INTEGER DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- Promo Codes
-- ============================================================================

CREATE TABLE IF NOT EXISTS promo_codes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    type TEXT NOT NULL CHECK(type IN ('percentage_off', 'fixed_amount_off', 'bonus_credits')),
    discount_percentage REAL DEFAULT 0.00,
    discount_amount_cents INTEGER DEFAULT 0,
    bonus_credits INTEGER DEFAULT 0,
    max_uses INTEGER DEFAULT NULL,  -- NULL = unlimited
    uses_count INTEGER DEFAULT 0,
    max_uses_per_user INTEGER DEFAULT 1,
    min_purchase_cents INTEGER DEFAULT 0,
    valid_from TEXT,
    valid_until TEXT,
    applies_to TEXT DEFAULT 'all' CHECK(applies_to IN ('all', 'packages', 'subscriptions')),
    is_active INTEGER DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_promo_codes_code ON promo_codes(code);
CREATE INDEX idx_promo_codes_active ON promo_codes(is_active);

-- ============================================================================
-- Promo Code Usage
-- ============================================================================

CREATE TABLE IF NOT EXISTS promo_code_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    promo_code_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    transaction_id INTEGER,
    credits_awarded INTEGER DEFAULT 0,
    discount_amount_cents INTEGER DEFAULT 0,
    used_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (promo_code_id) REFERENCES promo_codes(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (transaction_id) REFERENCES payment_transactions(id)
);

CREATE INDEX idx_promo_code_usage_promo ON promo_code_usage(promo_code_id);
CREATE INDEX idx_promo_code_usage_user ON promo_code_usage(user_id);

-- ============================================================================
-- Referrals
-- ============================================================================

CREATE TABLE IF NOT EXISTS referrals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    referrer_user_id INTEGER NOT NULL,
    referred_user_id INTEGER NOT NULL,
    referral_code TEXT NOT NULL,
    status TEXT DEFAULT 'pending' CHECK(status IN ('pending', 'completed', 'rewarded')),
    referrer_credits_awarded INTEGER DEFAULT 0,
    referred_credits_awarded INTEGER DEFAULT 0,
    completed_at TEXT,  -- When first purchase is made
    rewarded_at TEXT,   -- When credits are granted
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (referrer_user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (referred_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX idx_referrals_unique ON referrals(referrer_user_id, referred_user_id);
CREATE INDEX idx_referrals_referrer ON referrals(referrer_user_id);
CREATE INDEX idx_referrals_code ON referrals(referral_code);

-- ============================================================================
-- Credit Expiry
-- ============================================================================

CREATE TABLE IF NOT EXISTS credit_expiry (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    credit_ledger_id INTEGER,  -- Link to origin transaction if applicable
    credits_granted INTEGER NOT NULL,
    credits_remaining INTEGER NOT NULL,
    expiry_type TEXT NOT NULL CHECK(expiry_type IN ('purchased', 'promotional', 'referral', 'bonus')),
    expires_at TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (credit_ledger_id) REFERENCES credit_ledger(id)
);

CREATE INDEX idx_credit_expiry_user ON credit_expiry(user_id);
CREATE INDEX idx_credit_expiry_expires_at ON credit_expiry(expires_at);
CREATE INDEX idx_credit_expiry_user_expires ON credit_expiry(user_id, expires_at);
