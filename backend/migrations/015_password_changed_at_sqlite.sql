-- 015_password_changed_at_sqlite.sql
-- Tokens issued before users.password_changed_at are rejected (sessions end on password reset).
ALTER TABLE users ADD COLUMN password_changed_at TEXT;
