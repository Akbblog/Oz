-- Admin Settings Table Migration (MySQL)
-- Provides centralized configuration for admin-controlled features

CREATE TABLE IF NOT EXISTS admin_settings (
    `key` VARCHAR(100) PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at VARCHAR(64),
    updated_by INT REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Default settings
INSERT IGNORE INTO admin_settings (`key`, value, description, updated_at) VALUES
    ('auto_approve_users', 'false', 'Auto-approve new user registrations', NOW()),
    ('send_approval_email', 'true', 'Send email when user is approved', NOW()),
    ('send_welcome_email', 'true', 'Send welcome email on auto-approval', NOW()),
    ('send_rejection_email', 'true', 'Send email when user registration is denied', NOW()),
    ('starting_credits', '100', 'Credits given to new approved users', NOW()),
    ('admin_notification_on_signup', 'true', 'Notify admin of new signups', NOW());
