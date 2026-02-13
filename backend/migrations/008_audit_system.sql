-- 008_audit_system.sql (MySQL variant)
-- Audit/activity logging system, role-based access, and 2-step approval

-- ============================================================================
-- STEP 1: Audit events table (append-only)
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(36) NOT NULL,
    actor_user_id INT,
    actor_username VARCHAR(255),
    action VARCHAR(100) NOT NULL,
    target_type VARCHAR(50),
    target_id VARCHAR(255),
    before_snapshot JSON,
    after_snapshot JSON,
    ip_address VARCHAR(45),
    user_agent VARCHAR(512),
    status VARCHAR(20) NOT NULL DEFAULT 'success',
    failure_reason TEXT,
    metadata JSON,
    prev_hash VARCHAR(64),
    record_hash VARCHAR(64),
    created_at VARCHAR(64) NOT NULL,
    INDEX idx_audit_events_actor (actor_user_id),
    INDEX idx_audit_events_action (action),
    INDEX idx_audit_events_target (target_type, target_id),
    INDEX idx_audit_events_created_at (created_at),
    INDEX idx_audit_events_request_id (request_id),
    INDEX idx_audit_events_status (status)
);

-- ============================================================================
-- STEP 2: Archived audit events (retention policy)
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_events_archive (
    id INT PRIMARY KEY,
    request_id VARCHAR(36) NOT NULL,
    actor_user_id INT,
    actor_username VARCHAR(255),
    action VARCHAR(100) NOT NULL,
    target_type VARCHAR(50),
    target_id VARCHAR(255),
    before_snapshot JSON,
    after_snapshot JSON,
    ip_address VARCHAR(45),
    user_agent VARCHAR(512),
    status VARCHAR(20) NOT NULL DEFAULT 'success',
    failure_reason TEXT,
    metadata JSON,
    prev_hash VARCHAR(64),
    record_hash VARCHAR(64),
    created_at VARCHAR(64) NOT NULL,
    archived_at VARCHAR(64) NOT NULL,
    INDEX idx_audit_archive_created_at (created_at),
    INDEX idx_audit_archive_actor (actor_user_id)
);

-- ============================================================================
-- STEP 3: Add role column to users table
-- ============================================================================

ALTER TABLE users ADD COLUMN role VARCHAR(20) DEFAULT 'user';

UPDATE users SET role = 'admin' WHERE is_admin = 1;
UPDATE users SET role = 'user' WHERE is_admin = 0 OR is_admin IS NULL;

-- ============================================================================
-- STEP 4: Pending approvals for destructive actions
-- ============================================================================

CREATE TABLE IF NOT EXISTS pending_approvals (
    id INT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(36) UNIQUE NOT NULL,
    requested_by INT NOT NULL,
    action VARCHAR(100) NOT NULL,
    target_type VARCHAR(50),
    target_id VARCHAR(255),
    payload JSON,
    status VARCHAR(20) DEFAULT 'pending',
    reviewed_by INT,
    reviewed_at VARCHAR(64),
    expires_at VARCHAR(64) NOT NULL,
    created_at VARCHAR(64) NOT NULL,
    INDEX idx_pending_approvals_status (status),
    INDEX idx_pending_approvals_requested_by (requested_by),
    FOREIGN KEY (requested_by) REFERENCES users(id),
    FOREIGN KEY (reviewed_by) REFERENCES users(id)
);
