-- 005_login_rate_limits_sqlite.sql
-- Add login rate limiting table (SQLite)

-- ============================================================================
-- STEP 1: Create login_rate_limits table
-- ============================================================================

CREATE TABLE IF NOT EXISTS login_rate_limits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    scope TEXT NOT NULL,
    identifier TEXT NOT NULL,
    window_start TEXT NOT NULL,
    attempts_in_window INTEGER DEFAULT 0,
    locked_until TEXT,
    last_attempt_at TEXT,
    last_success_at TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_login_rate_unique ON login_rate_limits(scope, identifier);
CREATE INDEX IF NOT EXISTS idx_login_rate_locked_until ON login_rate_limits(locked_until);
CREATE INDEX IF NOT EXISTS idx_login_rate_window_start ON login_rate_limits(window_start);

