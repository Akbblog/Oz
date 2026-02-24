-- 011_analytics_sqlite.sql
-- Behavioral analytics: event tracking, heatmaps, funnels, DAU/MAU
-- Separate from audit_events (compliance) and job_activity_events (operational).

-- ============================================================================
-- TABLE 1: analytics_events
-- One row per tracked frontend event (page view, click, feature use, etc.)
-- Hot columns are denormalized for index efficiency — no json_extract in queries.
-- ============================================================================

CREATE TABLE IF NOT EXISTS analytics_events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Identity
    user_id         INTEGER,            -- NULL = anonymous/pre-login
    session_id      TEXT NOT NULL,      -- UUID per browser tab (sessionStorage)

    -- What happened
    event_name      TEXT NOT NULL,      -- 'page_view' | 'click' | 'feature_use' |
                                        -- 'search_start' | 'search_complete' |
                                        -- 'credit_purchase' | 'register' | 'login' |
                                        -- 'page_exit'

    -- Where it happened (denormalized hot dimensions)
    page            TEXT,               -- hash route: '#/dashboard', '#/admin', '#/'
    element         TEXT,               -- data-track value: 'nav-activity', 'btn-run-job'
    feature         TEXT,               -- for feature_use events: 'Stats','Users','Credits','Settings'

    -- Heatmap coordinates (% of viewport, 0.00–100.00, device-agnostic)
    click_x         REAL,
    click_y         REAL,
    viewport_w      INTEGER,
    viewport_h      INTEGER,

    -- Freeform payload for everything else
    extra_json      TEXT,               -- JSON: {duration_ms, job_type, credits, label, ...}

    -- Time (date_bucket is the critical indexed partition key)
    date_bucket     TEXT NOT NULL,      -- 'YYYY-MM-DD' — makes GROUP BY DAU/MAU fast
    created_at      TEXT NOT NULL       -- full ISO timestamp
);

-- Index strategy: cover the analytics query patterns exactly
CREATE INDEX IF NOT EXISTS idx_ae_date_bucket     ON analytics_events(date_bucket);
CREATE INDEX IF NOT EXISTS idx_ae_user_date       ON analytics_events(user_id, date_bucket);
CREATE INDEX IF NOT EXISTS idx_ae_event_date      ON analytics_events(event_name, date_bucket);
CREATE INDEX IF NOT EXISTS idx_ae_session         ON analytics_events(session_id);
CREATE INDEX IF NOT EXISTS idx_ae_page_date       ON analytics_events(page, date_bucket);
CREATE INDEX IF NOT EXISTS idx_ae_feature_date    ON analytics_events(feature, date_bucket);
CREATE INDEX IF NOT EXISTS idx_ae_element_date    ON analytics_events(element, date_bucket);

-- ============================================================================
-- TABLE 2: analytics_daily_stats
-- Pre-aggregated daily snapshot — updated on-demand or nightly.
-- Reading DAU/MAU charts from this is O(days) not O(events).
-- ============================================================================

CREATE TABLE IF NOT EXISTS analytics_daily_stats (
    date_bucket         TEXT PRIMARY KEY,   -- 'YYYY-MM-DD'
    dau                 INTEGER NOT NULL DEFAULT 0,   -- distinct user_ids with events
    new_users           INTEGER NOT NULL DEFAULT 0,   -- event_name='register' users
    total_sessions      INTEGER NOT NULL DEFAULT 0,   -- distinct session_ids
    total_events        INTEGER NOT NULL DEFAULT 0,   -- all events
    searches_started    INTEGER NOT NULL DEFAULT 0,   -- event_name='search_start'
    searches_completed  INTEGER NOT NULL DEFAULT 0,   -- event_name='search_complete'
    credits_consumed    INTEGER NOT NULL DEFAULT 0,   -- from credit_ledger (debit sum)
    credits_purchased   INTEGER NOT NULL DEFAULT 0,   -- from credit_ledger (credit sum)
    computed_at         TEXT NOT NULL                 -- when this row was last refreshed
);
