-- 013_user_suspension.sql
-- Add suspension lifecycle metadata to users (MySQL)

ALTER TABLE users ADD COLUMN is_suspended TINYINT(1) NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN suspended_at VARCHAR(64) NULL;
ALTER TABLE users ADD COLUMN suspended_by INT NULL;
ALTER TABLE users ADD COLUMN suspension_reason TEXT NULL;

CREATE INDEX idx_users_is_suspended ON users (is_suspended);
