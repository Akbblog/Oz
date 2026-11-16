-- Preserve the prices in effect when a job was charged.
ALTER TABLE jobs ADD COLUMN billing_snapshot TEXT;
