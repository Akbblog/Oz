-- 001_payment_tables_sqlite.sql
-- Core payment tables for Stripe and Coinbase integration (SQLite version)

-- ============================================================================
-- Credit Packages
-- ============================================================================

CREATE TABLE IF NOT EXISTS credit_packages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    credits INTEGER NOT NULL,
    base_price_cents INTEGER NOT NULL,
    display_price_cents INTEGER NOT NULL,
    discount_percentage REAL DEFAULT 0.00,
    tier_id INTEGER,
    is_active INTEGER DEFAULT 1,
    is_featured INTEGER DEFAULT 0,
    features TEXT,  -- JSON stored as TEXT
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- Payment Transactions
-- ============================================================================

CREATE TABLE IF NOT EXISTS payment_transactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_id TEXT UNIQUE NOT NULL,  -- UUID
    user_id INTEGER NOT NULL,
    payment_provider TEXT NOT NULL CHECK(payment_provider IN ('stripe', 'coinbase')),
    provider_transaction_id TEXT,
    amount_cents INTEGER NOT NULL,
    currency TEXT DEFAULT 'USD',
    credits_purchased INTEGER NOT NULL,
    status TEXT DEFAULT 'pending' CHECK(status IN ('pending', 'processing', 'completed', 'failed', 'refunded')),
    idempotency_key TEXT UNIQUE,
    package_id INTEGER,
    subscription_id INTEGER,
    promo_code_id INTEGER,
    invoice_id INTEGER,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (package_id) REFERENCES credit_packages(id),
    FOREIGN KEY (subscription_id) REFERENCES user_subscriptions(id),
    FOREIGN KEY (promo_code_id) REFERENCES promo_codes(id),
    FOREIGN KEY (invoice_id) REFERENCES invoices(id)
);

CREATE INDEX idx_payment_transactions_user ON payment_transactions(user_id);
CREATE INDEX idx_payment_transactions_status ON payment_transactions(status);
CREATE INDEX idx_payment_transactions_transaction_id ON payment_transactions(transaction_id);
CREATE INDEX idx_payment_transactions_created_at ON payment_transactions(created_at);

-- ============================================================================
-- Invoices
-- ============================================================================

CREATE TABLE IF NOT EXISTS invoices (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    invoice_number TEXT UNIQUE NOT NULL,
    user_id INTEGER NOT NULL,
    transaction_id INTEGER,
    subscription_id INTEGER,
    invoice_type TEXT NOT NULL CHECK(invoice_type IN ('purchase', 'subscription', 'refund')),
    amount_cents INTEGER NOT NULL,
    tax_amount_cents INTEGER DEFAULT 0,
    total_amount_cents INTEGER NOT NULL,
    status TEXT DEFAULT 'paid' CHECK(status IN ('draft', 'sent', 'paid', 'void')),
    pdf_path TEXT,
    line_items TEXT,  -- JSON stored as TEXT
    billing_name TEXT,
    billing_email TEXT,
    billing_address TEXT,  -- JSON stored as TEXT
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (transaction_id) REFERENCES payment_transactions(id),
    FOREIGN KEY (subscription_id) REFERENCES user_subscriptions(id)
);

CREATE INDEX idx_invoices_user ON invoices(user_id);
CREATE INDEX idx_invoices_invoice_number ON invoices(invoice_number);
CREATE INDEX idx_invoices_created_at ON invoices(created_at);

-- ============================================================================
-- Payment Methods
-- ============================================================================

CREATE TABLE IF NOT EXISTS payment_methods (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    stripe_payment_method_id TEXT UNIQUE NOT NULL,
    type TEXT DEFAULT 'card' CHECK(type IN ('card', 'bank_account')),
    is_default INTEGER DEFAULT 0,
    card_brand TEXT,
    card_last4 TEXT,
    card_exp_month INTEGER,
    card_exp_year INTEGER,
    billing_name TEXT,
    billing_email TEXT,
    billing_address TEXT,  -- JSON stored as TEXT
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_payment_methods_user ON payment_methods(user_id);
CREATE INDEX idx_payment_methods_stripe_id ON payment_methods(stripe_payment_method_id);

-- ============================================================================
-- Webhook Events
-- ============================================================================

CREATE TABLE IF NOT EXISTS webhook_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    webhook_id TEXT UNIQUE NOT NULL,
    provider TEXT NOT NULL CHECK(provider IN ('stripe', 'coinbase')),
    event_type TEXT NOT NULL,
    payload TEXT,  -- JSON stored as TEXT
    status TEXT DEFAULT 'pending' CHECK(status IN ('pending', 'processed', 'failed')),
    processed_at TEXT,
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_webhook_events_provider ON webhook_events(provider);
CREATE INDEX idx_webhook_events_status ON webhook_events(status);
CREATE INDEX idx_webhook_events_created_at ON webhook_events(created_at);
