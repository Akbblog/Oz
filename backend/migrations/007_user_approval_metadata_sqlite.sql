-- 007_user_approval_metadata_sqlite.sql
-- Add audit metadata for user approval/denial (SQLite)

ALTER TABLE users ADD COLUMN approved_at TEXT;
ALTER TABLE users ADD COLUMN approved_by INTEGER;
ALTER TABLE users ADD COLUMN denied_at TEXT;
ALTER TABLE users ADD COLUMN denied_by INTEGER;
ALTER TABLE users ADD COLUMN denied_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_users_is_approved ON users (is_approved);
