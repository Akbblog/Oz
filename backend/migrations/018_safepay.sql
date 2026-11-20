-- 018_safepay.sql
-- Safepay (Payments 2.0) as the payment provider for new credit purchases (MariaDB / MySQL).
-- Additive: widens the provider ENUMs (existing coinbase/stripe/paypal rows are untouched)
-- and adds nullable columns used to reconcile a Safepay tracker against the transaction.

ALTER TABLE payment_transactions
  MODIFY payment_provider ENUM('stripe', 'coinbase', 'paypal', 'safepay') NOT NULL;

ALTER TABLE webhook_events
  MODIFY provider ENUM('stripe', 'coinbase', 'paypal', 'safepay') NOT NULL;

ALTER TABLE payment_transactions ADD COLUMN provider_environment VARCHAR(16) NULL;
ALTER TABLE payment_transactions ADD COLUMN provider_status VARCHAR(40) NULL;
ALTER TABLE payment_transactions ADD COLUMN status_detail VARCHAR(255) NULL;
ALTER TABLE payment_transactions ADD COLUMN provider_base_amount BIGINT NULL;
ALTER TABLE payment_transactions ADD COLUMN provider_base_currency VARCHAR(10) NULL;
ALTER TABLE payment_transactions ADD COLUMN provider_fx_rate VARCHAR(32) NULL;
ALTER TABLE payment_transactions ADD COLUMN completed_at DATETIME NULL;

CREATE INDEX idx_payment_transactions_provider_txn ON payment_transactions(provider_transaction_id);
