-- Preserve the prices in effect when a job was charged, so changing the
-- pricing table during a long-running job cannot change its refund.
ALTER TABLE jobs ADD COLUMN billing_snapshot TEXT NULL;
