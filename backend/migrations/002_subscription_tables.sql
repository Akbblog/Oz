-- 002_subscription_tables.sql
-- Subscription system tables

CREATE TABLE IF NOT EXISTS subscription_plans (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    billing_interval ENUM('monthly', 'yearly') NOT NULL,
    credits_per_period INT NOT NULL,
    base_price_cents INT NOT NULL,
    stripe_price_id VARCHAR(255),
    rollover_credits BOOLEAN DEFAULT TRUE,
    max_rollover_credits INT DEFAULT 0,
    trial_days INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    is_featured BOOLEAN DEFAULT FALSE,
    features JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS user_subscriptions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    subscription_plan_id INT NOT NULL,
    stripe_subscription_id VARCHAR(255) UNIQUE,
    status ENUM('active', 'past_due', 'canceled', 'paused', 'expired', 'trialing') DEFAULT 'active',
    current_period_start TIMESTAMP NULL,
    current_period_end TIMESTAMP NULL,
    next_billing_date TIMESTAMP NULL,
    cancel_at_period_end BOOLEAN DEFAULT FALSE,
    credits_allocated_this_period INT DEFAULT 0,
    credits_used_this_period INT DEFAULT 0,
    credits_rolled_over INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (subscription_plan_id) REFERENCES subscription_plans(id)
);
