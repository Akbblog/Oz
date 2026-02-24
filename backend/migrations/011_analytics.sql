-- 011_analytics.sql (MySQL variant)
-- Behavioral analytics: event tracking, heatmaps, funnels, DAU/MAU

-- ============================================================================
-- TABLE 1: analytics_events
-- ============================================================================

CREATE TABLE IF NOT EXISTS analytics_events (
    id              INT AUTO_INCREMENT PRIMARY KEY,

    -- Identity
    user_id         INT,
    session_id      VARCHAR(36)  NOT NULL,

    -- What happened
    event_name      VARCHAR(100) NOT NULL,

    -- Denormalized hot dimensions
    page            VARCHAR(255),
    element         VARCHAR(255),
    feature         VARCHAR(100),

    -- Heatmap coordinates (% of viewport)
    click_x         FLOAT,
    click_y         FLOAT,
    viewport_w      SMALLINT UNSIGNED,
    viewport_h      SMALLINT UNSIGNED,

    -- Freeform payload
    extra_json      JSON,

    -- Time
    date_bucket     DATE         NOT NULL,
    created_at      VARCHAR(64)  NOT NULL,

    INDEX idx_ae_date_bucket     (date_bucket),
    INDEX idx_ae_user_date       (user_id, date_bucket),
    INDEX idx_ae_event_date      (event_name, date_bucket),
    INDEX idx_ae_session         (session_id),
    INDEX idx_ae_page_date       (page(64), date_bucket),
    INDEX idx_ae_feature_date    (feature, date_bucket),
    INDEX idx_ae_element_date    (element(64), date_bucket)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- TABLE 2: analytics_daily_stats
-- ============================================================================

CREATE TABLE IF NOT EXISTS analytics_daily_stats (
    date_bucket         DATE         PRIMARY KEY,
    dau                 INT          NOT NULL DEFAULT 0,
    new_users           INT          NOT NULL DEFAULT 0,
    total_sessions      INT          NOT NULL DEFAULT 0,
    total_events        INT          NOT NULL DEFAULT 0,
    searches_started    INT          NOT NULL DEFAULT 0,
    searches_completed  INT          NOT NULL DEFAULT 0,
    credits_consumed    INT          NOT NULL DEFAULT 0,
    credits_purchased   INT          NOT NULL DEFAULT 0,
    computed_at         VARCHAR(64)  NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
