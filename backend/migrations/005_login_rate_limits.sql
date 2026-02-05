-- 005_login_rate_limits.sql
-- Add login rate limiting table (MySQL)

-- ============================================================================
-- STEP 1: Create login_rate_limits table
-- ============================================================================

CREATE TABLE IF NOT EXISTS login_rate_limits (
    id INT AUTO_INCREMENT PRIMARY KEY,
    scope VARCHAR(16) NOT NULL,
    identifier VARCHAR(255) NOT NULL,
    window_start TEXT NOT NULL,
    attempts_in_window INT DEFAULT 0,
    locked_until TEXT,
    last_attempt_at TEXT,
    last_success_at TEXT,
    UNIQUE KEY unique_login_rate_limit (scope, identifier),
    INDEX idx_login_rate_locked_until (locked_until(64)),
    INDEX idx_login_rate_window_start (window_start(64))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

