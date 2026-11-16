-- 014_job_durability.sql
-- Durable, resumable, idempotent scraping jobs (MySQL)
-- See 014_job_durability_sqlite.sql for column meanings.
-- The migration runner tolerates "duplicate column/key" errors, so a
-- partially applied run of this file can be safely re-run.

ALTER TABLE jobs ADD COLUMN idempotency_key VARCHAR(64) NULL;
ALTER TABLE jobs ADD COLUMN completed_cities INT NOT NULL DEFAULT 0;
ALTER TABLE jobs ADD COLUMN failed_cities INT NOT NULL DEFAULT 0;
ALTER TABLE jobs ADD COLUMN heartbeat_at VARCHAR(64) NULL;
ALTER TABLE jobs ADD COLUMN worker_id VARCHAR(128) NULL;
ALTER TABLE jobs ADD COLUMN attempts INT NOT NULL DEFAULT 0;
ALTER TABLE jobs ADD COLUMN credit_refunded INT NOT NULL DEFAULT 0;
ALTER TABLE jobs ADD COLUMN settled_at VARCHAR(64) NULL;
ALTER TABLE results ADD COLUMN dedupe_key VARCHAR(191) NULL;

CREATE UNIQUE INDEX uq_jobs_user_idempotency ON jobs (user_id, idempotency_key);
CREATE UNIQUE INDEX uq_results_job_dedupe ON results (job_id, dedupe_key);
CREATE INDEX idx_jobs_status_heartbeat ON jobs (status, heartbeat_at);
CREATE INDEX idx_job_logs_job_id_id ON job_logs (job_id, id);
