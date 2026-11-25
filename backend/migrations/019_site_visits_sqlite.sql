-- 019_site_visits_sqlite.sql
-- Visitor tracking for the admin dashboard: one row per browser session, with
-- where it came from (IP, geo, referrer, UTM) and what it ran on (browser, OS).
-- Additive only: one new table, nothing existing is altered.

CREATE TABLE IF NOT EXISTS site_visits (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Identity
    session_id      TEXT NOT NULL UNIQUE,
    visitor_id      TEXT,
    user_id         INTEGER,

    -- Where the visitor is
    ip_address      TEXT,
    country         TEXT,
    region          TEXT,
    city            TEXT,

    -- Where the visitor came from
    referrer        TEXT,
    referrer_host   TEXT,
    source          TEXT,
    utm_source      TEXT,
    utm_medium      TEXT,
    utm_campaign    TEXT,

    -- What they looked at
    landing_path    TEXT,
    exit_path       TEXT,
    page_count      INTEGER NOT NULL DEFAULT 1,

    -- What they used
    browser         TEXT,
    os              TEXT,
    device_type     TEXT,
    is_bot          INTEGER NOT NULL DEFAULT 0,
    language        TEXT,
    timezone        TEXT,
    screen_w        INTEGER,
    screen_h        INTEGER,
    user_agent      TEXT,

    -- Time (UTC ISO strings, like the rest of the schema)
    first_seen_at   TEXT NOT NULL,
    last_seen_at    TEXT NOT NULL,
    date_bucket     TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_site_visits_visitor   ON site_visits(visitor_id);
CREATE INDEX IF NOT EXISTS idx_site_visits_user      ON site_visits(user_id);
CREATE INDEX IF NOT EXISTS idx_site_visits_ip        ON site_visits(ip_address);
CREATE INDEX IF NOT EXISTS idx_site_visits_date      ON site_visits(date_bucket);
CREATE INDEX IF NOT EXISTS idx_site_visits_last_seen ON site_visits(last_seen_at);
