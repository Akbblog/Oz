-- 009_paypal_provider.sql
-- Expand payment provider enums to include PayPal (MySQL)

ALTER TABLE payment_transactions
  MODIFY payment_provider ENUM('stripe', 'coinbase', 'paypal') NOT NULL;

ALTER TABLE webhook_events
  MODIFY provider ENUM('stripe', 'coinbase', 'paypal') NOT NULL;

