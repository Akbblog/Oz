-- 001_payment_tables.sql
-- Core payment tables for Stripe and Coinbase integration

CREATE TABLE IF NOT EXISTS credit_packages (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    credits INT NOT NULL,
    base_price_cents INT NOT NULL,
    display_price_cents INT NOT NULL,
    discount_percentage DECIMAL(5, 2) DEFAULT 0.00,
    tier_id INT,
    is_active BOOLEAN DEFAULT TRUE,
    is_featured BOOLEAN DEFAULT FALSE,
    features JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS payment_transactions (
    id INT AUTO_INCREMENT PRIMARY KEY,
    transaction_id VARCHAR(36) UNIQUE NOT NULL, -- UUID
    user_id INT NOT NULL,
    payment_provider ENUM('stripe', 'coinbase') NOT NULL,
    provider_transaction_id VARCHAR(255),
    amount_cents INT NOT NULL,
    currency VARCHAR(10) DEFAULT 'USD',
    credits_purchased INT NOT NULL,
    status ENUM('pending', 'processing', 'completed', 'failed', 'refunded') DEFAULT 'pending',
    idempotency_key VARCHAR(255) UNIQUE,
    package_id INT,
    subscription_id INT,
    promo_code_id INT,
    invoice_id INT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_status (status),
    INDEX idx_transaction_id (transaction_id)
);

CREATE TABLE IF NOT EXISTS invoices (
    id INT AUTO_INCREMENT PRIMARY KEY,
    invoice_number VARCHAR(50) UNIQUE NOT NULL,
    user_id INT NOT NULL,
    transaction_id INT,
    subscription_id INT,
    invoice_type ENUM('purchase', 'subscription', 'refund') NOT NULL,
    amount_cents INT NOT NULL,
    tax_amount_cents INT DEFAULT 0,
    total_amount_cents INT NOT NULL,
    status ENUM('draft', 'sent', 'paid', 'void') DEFAULT 'paid',
    pdf_path VARCHAR(255),
    line_items JSON,
    billing_name VARCHAR(255),
    billing_email VARCHAR(255),
    billing_address JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_invoice_number (invoice_number)
);

CREATE TABLE IF NOT EXISTS payment_methods (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    stripe_payment_method_id VARCHAR(255) UNIQUE NOT NULL,
    type ENUM('card', 'bank_account') DEFAULT 'card',
    is_default BOOLEAN DEFAULT FALSE,
    card_brand VARCHAR(50),
    card_last4 VARCHAR(4),
    card_exp_month INT,
    card_exp_year INT,
    billing_name VARCHAR(255),
    billing_email VARCHAR(255),
    billing_address JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id)
);

CREATE TABLE IF NOT EXISTS webhook_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    webhook_id VARCHAR(255) UNIQUE NOT NULL,
    provider ENUM('stripe', 'coinbase') NOT NULL,
    event_type VARCHAR(100) NOT NULL,
    payload JSON,
    status ENUM('pending', 'processed', 'failed') DEFAULT 'pending',
    processed_at TIMESTAMP NULL,
    error_message TEXT,
    retry_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
