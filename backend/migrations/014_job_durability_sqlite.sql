-- 014_job_durability_sqlite.sql
-- Durable, resumable, idempotent scraping jobs (SQLite)
--   idempotency_key   client-supplied key; (user_id, idempotency_key) is unique
--   completed_cities  number of cities fully processed (resume point)
--   failed_cities     cities that timed out or errored
--   heartbeat_at      last liveness write by the worker that owns the job
--   worker_id         worker that currently owns the job
--   attempts          how many times a worker has started/resumed the job
--   credit_refunded   credits returned to the user when the job settled
--   settled_at        set exactly once when credits are settled (idempotency guard)
--   results.dedupe_key  stable per-business key; unique per job

ALTER TABLE jobs ADD COLUMN idempotency_key TEXT;
ALTER TABLE jobs ADD COLUMN completed_cities INTEGER DEFAULT 0;
ALTER TABLE jobs ADD COLUMN failed_cities INTEGER DEFAULT 0;
ALTER TABLE jobs ADD COLUMN heartbeat_at TEXT;
ALTER TABLE jobs ADD COLUMN worker_id TEXT;
ALTER TABLE jobs ADD COLUMN attempts INTEGER DEFAULT 0;
ALTER TABLE jobs ADD COLUMN credit_refunded INTEGER DEFAULT 0;
ALTER TABLE jobs ADD COLUMN settled_at TEXT;
ALTER TABLE results ADD COLUMN dedupe_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS uq_jobs_user_idempotency ON jobs (user_id, idempotency_key);
CREATE UNIQUE INDEX IF NOT EXISTS uq_results_job_dedupe ON results (job_id, dedupe_key);
CREATE INDEX IF NOT EXISTS idx_jobs_status_heartbeat ON jobs (status, heartbeat_at);
CREATE INDEX IF NOT EXISTS idx_job_logs_job_id_id ON job_logs (job_id, id);
