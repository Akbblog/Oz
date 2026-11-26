-- 020_user_profile_fields_sqlite.sql (SQLite)
-- Clean account data: real name, company, the phone's country, and where the
-- registration came from. Additive only: new nullable columns on users.

ALTER TABLE users ADD COLUMN full_name TEXT;
ALTER TABLE users ADD COLUMN company TEXT;
ALTER TABLE users ADD COLUMN phone_country TEXT;
ALTER TABLE users ADD COLUMN signup_ip TEXT;
ALTER TABLE users ADD COLUMN signup_country TEXT;
ALTER TABLE users ADD COLUMN signup_city TEXT;
ALTER TABLE users ADD COLUMN signup_device TEXT;
ALTER TABLE users ADD COLUMN signup_source TEXT;
ALTER TABLE users ADD COLUMN signup_referrer_host TEXT;
ALTER TABLE users ADD COLUMN signup_campaign TEXT;
ALTER TABLE users ADD COLUMN signup_visitor_id TEXT;

CREATE INDEX idx_users_phone_country ON users (phone_country);
