-- 013_user_suspension_sqlite.sql
-- Add suspension lifecycle metadata to users (SQLite)

ALTER TABLE users ADD COLUMN is_suspended INTEGER DEFAULT 0;
ALTER TABLE users ADD COLUMN suspended_at TEXT;
ALTER TABLE users ADD COLUMN suspended_by INTEGER;
ALTER TABLE users ADD COLUMN suspension_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_users_is_suspended ON users (is_suspended);
