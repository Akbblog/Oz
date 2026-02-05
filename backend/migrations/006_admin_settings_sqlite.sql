-- Admin Settings Table Migration (SQLite)
-- Provides centralized configuration for admin-controlled features

CREATE TABLE IF NOT EXISTS admin_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    description TEXT,
    updated_at TEXT,
    updated_by INTEGER REFERENCES users(id)
);

-- Default settings
INSERT OR IGNORE INTO admin_settings (key, value, description, updated_at) VALUES
    ('auto_approve_users', 'false', 'Auto-approve new user registrations', datetime('now')),
    ('send_approval_email', 'true', 'Send email when user is approved', datetime('now')),
    ('send_welcome_email', 'true', 'Send welcome email on auto-approval', datetime('now')),
    ('send_rejection_email', 'true', 'Send email when user registration is denied', datetime('now')),
    ('starting_credits', '100', 'Credits given to new approved users', datetime('now')),
    ('admin_notification_on_signup', 'true', 'Notify admin of new signups', datetime('now'));
