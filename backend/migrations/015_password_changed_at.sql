-- 015_password_changed_at.sql
-- Tokens issued before users.password_changed_at are rejected (sessions end on password reset).
ALTER TABLE users ADD COLUMN password_changed_at VARCHAR(64) NULL;
