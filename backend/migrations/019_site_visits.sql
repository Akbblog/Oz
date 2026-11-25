-- 019_site_visits.sql (MariaDB / MySQL)
-- Visitor tracking for the admin dashboard: one row per browser session, with
-- where it came from (IP, geo, referrer, UTM) and what it ran on (browser, OS).
-- Additive only: one new table, nothing existing is altered.

CREATE TABLE IF NOT EXISTS site_visits (
    id              INT AUTO_INCREMENT PRIMARY KEY,

    -- Identity
    session_id      VARCHAR(64)  NOT NULL,
    visitor_id      VARCHAR(64),
    user_id         INT,

    -- Where the visitor is
    ip_address      VARCHAR(64),
    country         VARCHAR(8),
    region          VARCHAR(64),
    city            VARCHAR(128),

    -- Where the visitor came from
    referrer        VARCHAR(512),
    referrer_host   VARCHAR(255),
    source          VARCHAR(32),
    utm_source      VARCHAR(128),
    utm_medium      VARCHAR(128),
    utm_campaign    VARCHAR(128),

    -- What they looked at
    landing_path    VARCHAR(255),
    exit_path       VARCHAR(255),
    page_count      INT          NOT NULL DEFAULT 1,

    -- What they used
    browser         VARCHAR(64),
    os              VARCHAR(64),
    device_type     VARCHAR(16),
    is_bot          TINYINT      NOT NULL DEFAULT 0,
    language        VARCHAR(32),
    timezone        VARCHAR(64),
    screen_w        INT,
    screen_h        INT,
    user_agent      VARCHAR(512),

    -- Time (UTC ISO strings, like the rest of the schema)
    first_seen_at   VARCHAR(64)  NOT NULL,
    last_seen_at    VARCHAR(64)  NOT NULL,
    date_bucket     VARCHAR(10)  NOT NULL,

    UNIQUE KEY uq_site_visits_session (session_id),
    INDEX idx_site_visits_visitor   (visitor_id),
    INDEX idx_site_visits_user      (user_id),
    INDEX idx_site_visits_ip        (ip_address),
    INDEX idx_site_visits_date      (date_bucket),
    INDEX idx_site_visits_last_seen (last_seen_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
