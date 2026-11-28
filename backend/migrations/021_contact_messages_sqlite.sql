-- 021_contact_messages_sqlite.sql (SQLite)
-- Messages sent through the contact form (signed-in users and visitors).

CREATE TABLE IF NOT EXISTS contact_messages (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id       INTEGER,
    name          TEXT NOT NULL,
    email         TEXT NOT NULL,
    phone         TEXT,
    topic         TEXT,
    message       TEXT NOT NULL,
    status        TEXT NOT NULL DEFAULT 'new',
    admin_note    TEXT,
    handled_by    INTEGER,
    handled_at    TEXT,
    ip_address    TEXT,
    country       TEXT,
    city          TEXT,
    device        TEXT,
    page          TEXT,
    visitor_id    TEXT,
    created_at    TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_contact_status  ON contact_messages(status);
CREATE INDEX IF NOT EXISTS idx_contact_created ON contact_messages(created_at);
CREATE INDEX IF NOT EXISTS idx_contact_user    ON contact_messages(user_id);
