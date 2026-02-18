-- 010_job_activity_tracking_sqlite.sql
-- Dedicated job activity timeline for "action -> result" drilldown in admin UI

CREATE TABLE IF NOT EXISTS job_activity_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_uuid TEXT NOT NULL UNIQUE,
    job_id TEXT NOT NULL,
    user_id INTEGER NOT NULL,
    event_type TEXT NOT NULL,
    job_status TEXT NOT NULL,
    job_type TEXT NOT NULL,
    result_count INTEGER NOT NULL DEFAULT 0,
    error_message TEXT,
    metadata_json TEXT,
    created_at TEXT NOT NULL,
    FOREIGN KEY (job_id) REFERENCES jobs(job_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_job_activity_created_at ON job_activity_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_job_activity_user_created_at ON job_activity_events(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_job_activity_type_status_created_at ON job_activity_events(job_type, job_status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_job_activity_job_created_at ON job_activity_events(job_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_job_activity_event_type ON job_activity_events(event_type);
