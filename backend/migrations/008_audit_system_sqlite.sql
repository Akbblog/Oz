-- 008_audit_system_sqlite.sql
-- Audit/activity logging system, role-based access, and 2-step approval

-- ============================================================================
-- STEP 1: Audit events table (append-only)
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id TEXT NOT NULL,
    actor_user_id INTEGER,
    actor_username TEXT,
    action TEXT NOT NULL,
    target_type TEXT,
    target_id TEXT,
    before_snapshot TEXT,
    after_snapshot TEXT,
    ip_address TEXT,
    user_agent TEXT,
    status TEXT NOT NULL DEFAULT 'success',
    failure_reason TEXT,
    metadata TEXT,
    prev_hash TEXT,
    record_hash TEXT,
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_events_actor ON audit_events(actor_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_action ON audit_events(action);
CREATE INDEX IF NOT EXISTS idx_audit_events_target ON audit_events(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_created_at ON audit_events(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_events_request_id ON audit_events(request_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_status ON audit_events(status);

-- ============================================================================
-- STEP 2: Archived audit events (retention policy)
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_events_archive (
    id INTEGER PRIMARY KEY,
    request_id TEXT NOT NULL,
    actor_user_id INTEGER,
    actor_username TEXT,
    action TEXT NOT NULL,
    target_type TEXT,
    target_id TEXT,
    before_snapshot TEXT,
    after_snapshot TEXT,
    ip_address TEXT,
    user_agent TEXT,
    status TEXT NOT NULL DEFAULT 'success',
    failure_reason TEXT,
    metadata TEXT,
    prev_hash TEXT,
    record_hash TEXT,
    created_at TEXT NOT NULL,
    archived_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_archive_created_at ON audit_events_archive(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_archive_actor ON audit_events_archive(actor_user_id);

-- ============================================================================
-- STEP 3: Add role column to users table
-- ============================================================================

ALTER TABLE users ADD COLUMN role TEXT DEFAULT 'user';

UPDATE users SET role = 'admin' WHERE is_admin = 1;
UPDATE users SET role = 'user' WHERE is_admin = 0 OR is_admin IS NULL;

-- ============================================================================
-- STEP 4: Pending approvals for destructive actions
-- ============================================================================

CREATE TABLE IF NOT EXISTS pending_approvals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    request_id TEXT UNIQUE NOT NULL,
    requested_by INTEGER NOT NULL,
    action TEXT NOT NULL,
    target_type TEXT,
    target_id TEXT,
    payload TEXT,
    status TEXT DEFAULT 'pending',
    reviewed_by INTEGER,
    reviewed_at TEXT,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    FOREIGN KEY (requested_by) REFERENCES users(id),
    FOREIGN KEY (reviewed_by) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_pending_approvals_status ON pending_approvals(status);
CREATE INDEX IF NOT EXISTS idx_pending_approvals_requested_by ON pending_approvals(requested_by);
