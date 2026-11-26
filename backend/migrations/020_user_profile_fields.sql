-- 020_user_profile_fields.sql (MariaDB / MySQL)
-- Clean account data: real name, company, the phone's country, and where the
-- registration came from. Additive only: new nullable columns on users.

ALTER TABLE users ADD COLUMN full_name VARCHAR(120) NULL;
ALTER TABLE users ADD COLUMN company VARCHAR(120) NULL;
ALTER TABLE users ADD COLUMN phone_country VARCHAR(2) NULL;
ALTER TABLE users ADD COLUMN signup_ip VARCHAR(64) NULL;
ALTER TABLE users ADD COLUMN signup_country VARCHAR(8) NULL;
ALTER TABLE users ADD COLUMN signup_city VARCHAR(128) NULL;
ALTER TABLE users ADD COLUMN signup_device VARCHAR(128) NULL;
ALTER TABLE users ADD COLUMN signup_source VARCHAR(32) NULL;
ALTER TABLE users ADD COLUMN signup_referrer_host VARCHAR(255) NULL;
ALTER TABLE users ADD COLUMN signup_campaign VARCHAR(128) NULL;
ALTER TABLE users ADD COLUMN signup_visitor_id VARCHAR(64) NULL;

CREATE INDEX idx_users_phone_country ON users (phone_country);
