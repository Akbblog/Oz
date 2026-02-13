-- 009_paypal_provider_sqlite.sql
-- Expand provider CHECK constraints to include PayPal (SQLite)

PRAGMA foreign_keys=OFF;
BEGIN TRANSACTION;

-- payment_transactions: widen payment_provider CHECK constraint
CREATE TABLE IF NOT EXISTS payment_transactions_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    transaction_id TEXT UNIQUE NOT NULL,
    user_id INTEGER NOT NULL,
    payment_provider TEXT NOT NULL CHECK(payment_provider IN ('stripe', 'coinbase', 'paypal')),
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

INSERT INTO payment_transactions_new (
    id, transaction_id, user_id, payment_provider, provider_transaction_id,
    amount_cents, currency, credits_purchased, status, idempotency_key,
    package_id, subscription_id, promo_code_id, invoice_id, created_at, updated_at
)
SELECT
    id, transaction_id, user_id, payment_provider, provider_transaction_id,
    amount_cents, currency, credits_purchased, status, idempotency_key,
    package_id, subscription_id, promo_code_id, invoice_id, created_at, updated_at
FROM payment_transactions;

DROP TABLE payment_transactions;
ALTER TABLE payment_transactions_new RENAME TO payment_transactions;

CREATE INDEX IF NOT EXISTS idx_payment_transactions_user ON payment_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_status ON payment_transactions(status);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_transaction_id ON payment_transactions(transaction_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_created_at ON payment_transactions(created_at);

-- webhook_events: widen provider CHECK constraint
CREATE TABLE IF NOT EXISTS webhook_events_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    webhook_id TEXT UNIQUE NOT NULL,
    provider TEXT NOT NULL CHECK(provider IN ('stripe', 'coinbase', 'paypal')),
    event_type TEXT NOT NULL,
    payload TEXT,
    status TEXT DEFAULT 'pending' CHECK(status IN ('pending', 'processed', 'failed')),
    processed_at TEXT,
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO webhook_events_new (
    id, webhook_id, provider, event_type, payload, status, processed_at, error_message, retry_count, created_at
)
SELECT
    id, webhook_id, provider, event_type, payload, status, processed_at, error_message, retry_count, created_at
FROM webhook_events;

DROP TABLE webhook_events;
ALTER TABLE webhook_events_new RENAME TO webhook_events;

CREATE INDEX IF NOT EXISTS idx_webhook_events_provider ON webhook_events(provider);
CREATE INDEX IF NOT EXISTS idx_webhook_events_status ON webhook_events(status);
CREATE INDEX IF NOT EXISTS idx_webhook_events_created_at ON webhook_events(created_at);

COMMIT;
PRAGMA foreign_keys=ON;

