-- 007_user_approval_metadata.sql
-- Add audit metadata for user approval/denial (MySQL)

ALTER TABLE users
  ADD COLUMN approved_at VARCHAR(64) NULL,
  ADD COLUMN approved_by INT NULL,
  ADD COLUMN denied_at VARCHAR(64) NULL,
  ADD COLUMN denied_by INT NULL,
  ADD COLUMN denied_reason TEXT NULL;

CREATE INDEX idx_users_is_approved ON users (is_approved);
