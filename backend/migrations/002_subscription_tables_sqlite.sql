-- 002_subscription_tables_sqlite.sql
-- Subscription system tables (SQLite version)

-- ============================================================================
-- Subscription Plans
-- ============================================================================

CREATE TABLE IF NOT EXISTS subscription_plans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    billing_interval TEXT NOT NULL CHECK(billing_interval IN ('monthly', 'yearly')),
    credits_per_period INTEGER NOT NULL,
    base_price_cents INTEGER NOT NULL,
    stripe_price_id TEXT,
    rollover_credits INTEGER DEFAULT 1,
    max_rollover_credits INTEGER DEFAULT 0,
    trial_days INTEGER DEFAULT 0,
    is_active INTEGER DEFAULT 1,
    is_featured INTEGER DEFAULT 0,
    features TEXT,  -- JSON stored as TEXT
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- User Subscriptions
-- ============================================================================

CREATE TABLE IF NOT EXISTS user_subscriptions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    subscription_plan_id INTEGER NOT NULL,
    stripe_subscription_id TEXT UNIQUE,
    status TEXT DEFAULT 'active' CHECK(status IN ('active', 'past_due', 'canceled', 'paused', 'expired', 'trialing')),
    current_period_start TEXT,
    current_period_end TEXT,
    next_billing_date TEXT,
    cancel_at_period_end INTEGER DEFAULT 0,
    credits_allocated_this_period INTEGER DEFAULT 0,
    credits_used_this_period INTEGER DEFAULT 0,
    credits_rolled_over INTEGER DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (subscription_plan_id) REFERENCES subscription_plans(id)
);

CREATE INDEX idx_user_subscriptions_user ON user_subscriptions(user_id);
CREATE INDEX idx_user_subscriptions_status ON user_subscriptions(status);
CREATE INDEX idx_user_subscriptions_stripe_id ON user_subscriptions(stripe_subscription_id);
