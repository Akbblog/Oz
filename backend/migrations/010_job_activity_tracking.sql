-- 010_job_activity_tracking.sql
-- Dedicated job activity timeline for "action -> result" drilldown in admin UI

CREATE TABLE IF NOT EXISTS job_activity_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    event_uuid VARCHAR(36) NOT NULL UNIQUE,
    job_id VARCHAR(255) NOT NULL,
    user_id INT NOT NULL,
    event_type VARCHAR(64) NOT NULL,
    job_status VARCHAR(50) NOT NULL,
    job_type VARCHAR(255) NOT NULL,
    result_count INT NOT NULL DEFAULT 0,
    error_message TEXT,
    metadata_json TEXT,
    created_at TEXT NOT NULL,
    INDEX idx_job_activity_created_at (created_at(64)),
    INDEX idx_job_activity_user_created_at (user_id, created_at(64)),
    INDEX idx_job_activity_type_status_created_at (job_type, job_status, created_at(64)),
    INDEX idx_job_activity_job_created_at (job_id, created_at(64)),
    INDEX idx_job_activity_event_type (event_type),
    FOREIGN KEY (job_id) REFERENCES jobs(job_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
