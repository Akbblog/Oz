-- 003_promo_referral_tables.sql
-- Promotional features, pricing tiers, and referral tracking

CREATE TABLE IF NOT EXISTS pricing_tiers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    min_monthly_credits INT DEFAULT 0,
    max_monthly_credits INT DEFAULT NULL,
    price_per_credit_cents DECIMAL(10, 4) NOT NULL, -- Detailed precision for bulk rates
    discount_percentage DECIMAL(5, 2) DEFAULT 0.00,
    requires_approval BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS promo_codes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    type ENUM('percentage_off', 'fixed_amount_off', 'bonus_credits') NOT NULL,
    discount_percentage DECIMAL(5, 2) DEFAULT 0.00,
    discount_amount_cents INT DEFAULT 0,
    bonus_credits INT DEFAULT 0,
    max_uses INT DEFAULT NULL, -- NULL = unlimited
    uses_count INT DEFAULT 0,
    max_uses_per_user INT DEFAULT 1,
    min_purchase_cents INT DEFAULT 0,
    valid_from TIMESTAMP NULL,
    valid_until TIMESTAMP NULL,
    applies_to ENUM('all', 'packages', 'subscriptions') DEFAULT 'all',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_code (code)
);

CREATE TABLE IF NOT EXISTS promo_code_usage (
    id INT AUTO_INCREMENT PRIMARY KEY,
    promo_code_id INT NOT NULL,
    user_id INT NOT NULL,
    transaction_id INT,
    credits_awarded INT DEFAULT 0,
    discount_amount_cents INT DEFAULT 0,
    used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (promo_code_id) REFERENCES promo_codes(id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS referrals (
    id INT AUTO_INCREMENT PRIMARY KEY,
    referrer_user_id INT NOT NULL,
    referred_user_id INT NOT NULL,
    referral_code VARCHAR(50) NOT NULL,
    status ENUM('pending', 'completed', 'rewarded') DEFAULT 'pending',
    referrer_credits_awarded INT DEFAULT 0,
    referred_credits_awarded INT DEFAULT 0,
    completed_at TIMESTAMP NULL, -- When first purchase is made
    rewarded_at TIMESTAMP NULL,  -- When credits are granted
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY unique_referral (referrer_user_id, referred_user_id),
    INDEX idx_referrer (referrer_user_id),
    INDEX idx_referral_code (referral_code),
    FOREIGN KEY (referrer_user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (referred_user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS credit_expiry (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    credit_ledger_id INT, -- Link to origin transaction if applicable
    credits_granted INT NOT NULL,
    credits_remaining INT NOT NULL,
    expiry_type ENUM('purchased', 'promotional', 'referral', 'bonus') NOT NULL,
    expires_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_expiry (user_id, expires_at),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
