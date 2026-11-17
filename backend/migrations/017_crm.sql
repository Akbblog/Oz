-- 017_crm.sql
-- CRM Phase 1 (MariaDB 11.8 / MySQL). See docs/CRM_PHASE1_CONTRACT.md.
-- Additive only: new crm_* tables, no change to any existing table.
-- No foreign keys to jobs/results: CRM snapshots must survive search deletion.
-- Every statement is CREATE TABLE IF NOT EXISTS with inline indexes, so a
-- partially applied run can be re-run safely.
-- All timestamps are UTC (DATETIME(6)); the application writes them.

CREATE TABLE IF NOT EXISTS crm_workspaces (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    owner_user_id INT NOT NULL,
    name VARCHAR(200) NOT NULL,
    currency_default CHAR(3) NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    UNIQUE KEY uq_crm_workspaces_owner (owner_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_memberships (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    user_id INT NOT NULL,
    role VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    joined_at DATETIME(6) NOT NULL,
    UNIQUE KEY uq_crm_memberships_ws_user (workspace_id, user_id),
    KEY idx_crm_memberships_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_pipelines (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(120) NOT NULL,
    is_default TINYINT NOT NULL DEFAULT 0,
    active TINYINT NOT NULL DEFAULT 1,
    created_at DATETIME(6) NOT NULL,
    KEY idx_crm_pipelines_ws (workspace_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_stages (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    pipeline_id VARCHAR(36) NOT NULL,
    stage_key VARCHAR(40) NOT NULL,
    name VARCHAR(120) NOT NULL,
    position INT NOT NULL,
    outcome_kind VARCHAR(10) NOT NULL DEFAULT 'open',
    active TINYINT NOT NULL DEFAULT 1,
    color VARCHAR(20) NULL,
    created_at DATETIME(6) NOT NULL,
    UNIQUE KEY uq_crm_stages_pipeline_key (pipeline_id, stage_key),
    KEY idx_crm_stages_ws (workspace_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_lost_reasons (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(120) NOT NULL,
    is_system TINYINT NOT NULL DEFAULT 0,
    active TINYINT NOT NULL DEFAULT 1,
    position INT NOT NULL DEFAULT 0,
    created_at DATETIME(6) NOT NULL,
    UNIQUE KEY uq_crm_lost_reasons_ws_name (workspace_id, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_tags (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(60) NOT NULL,
    color VARCHAR(20) NULL,
    created_at DATETIME(6) NOT NULL,
    UNIQUE KEY uq_crm_tags_ws_name (workspace_id, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_companies (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    name VARCHAR(300) NOT NULL,
    match_place_key VARCHAR(191) NULL,
    match_host VARCHAR(191) NULL,
    match_phone VARCHAR(32) NULL,
    match_name VARCHAR(191) NULL,
    source_snapshot TEXT NULL,
    phone VARCHAR(64) NULL,
    email VARCHAR(254) NULL,
    website TEXT NULL,
    address TEXT NULL,
    city VARCHAR(191) NULL,
    region VARCHAR(191) NULL,
    country VARCHAR(100) NULL,
    maps_url TEXT NULL,
    category VARCHAR(255) NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    archived_at DATETIME(6) NULL,
    KEY idx_crm_companies_ws_place (workspace_id, match_place_key),
    KEY idx_crm_companies_ws_host (workspace_id, match_host),
    KEY idx_crm_companies_ws_phone (workspace_id, match_phone)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_people (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    company_id VARCHAR(36) NOT NULL,
    record_id VARCHAR(36) NULL,
    name VARCHAR(200) NOT NULL,
    role VARCHAR(120) NULL,
    phone VARCHAR(64) NULL,
    email VARCHAR(254) NULL,
    is_primary TINYINT NOT NULL DEFAULT 0,
    created_by INT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    KEY idx_crm_people_ws_company (workspace_id, company_id),
    KEY idx_crm_people_ws_name (workspace_id, name, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_records (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    company_id VARCHAR(36) NOT NULL,
    pipeline_id VARCHAR(36) NOT NULL,
    stage_id VARCHAR(36) NOT NULL,
    last_open_stage_id VARCHAR(36) NULL,
    type VARCHAR(20) NOT NULL DEFAULT 'lead',
    title VARCHAR(300) NOT NULL,
    assignee_user_id INT NULL,
    outcome VARCHAR(10) NOT NULL DEFAULT 'open',
    lost_reason_id VARCHAR(36) NULL,
    lost_note TEXT NULL,
    value DECIMAL(14,2) NULL,
    currency CHAR(3) NULL,
    probability INT NULL,
    expected_close_date DATE NULL,
    priority INT NOT NULL DEFAULT 0,
    archived_at DATETIME(6) NULL,
    closed_at DATETIME(6) NULL,
    converted_at DATETIME(6) NULL,
    created_by INT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    version INT NOT NULL DEFAULT 1,
    last_activity_at DATETIME(6) NULL,
    next_activity_at DATETIME(6) NULL,
    KEY idx_crm_records_ws_updated (workspace_id, updated_at, id),
    KEY idx_crm_records_ws_created (workspace_id, created_at, id),
    KEY idx_crm_records_ws_stage (workspace_id, stage_id),
    KEY idx_crm_records_ws_company (workspace_id, company_id),
    KEY idx_crm_records_ws_next (workspace_id, next_activity_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_source_links (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    company_id VARCHAR(36) NOT NULL,
    record_id VARCHAR(36) NULL,
    source_job_id VARCHAR(255) NOT NULL,
    source_result_id INT NULL,
    category VARCHAR(255) NULL,
    city VARCHAR(191) NULL,
    region VARCHAR(191) NULL,
    country VARCHAR(100) NULL,
    job_created_at DATETIME(6) NULL,
    snapshot TEXT NULL,
    imported_at DATETIME(6) NOT NULL,
    imported_by INT NULL,
    UNIQUE KEY uq_crm_source_links_ws_result (workspace_id, source_result_id),
    KEY idx_crm_source_links_ws_job (workspace_id, source_job_id),
    KEY idx_crm_source_links_ws_record (workspace_id, record_id),
    KEY idx_crm_source_links_ws_company (workspace_id, company_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_activities (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    record_id VARCHAR(36) NOT NULL,
    type VARCHAR(20) NOT NULL,
    subject VARCHAR(300) NOT NULL,
    notes TEXT NULL,
    due_at DATETIME(6) NOT NULL,
    assignee_user_id INT NULL,
    status VARCHAR(10) NOT NULL DEFAULT 'open',
    completed_at DATETIME(6) NULL,
    outcome TEXT NULL,
    created_by INT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    KEY idx_crm_activities_ws_status_due (workspace_id, status, due_at, id),
    KEY idx_crm_activities_ws_record (workspace_id, record_id),
    KEY idx_crm_activities_ws_assignee (workspace_id, assignee_user_id, status),
    KEY idx_crm_activities_ws_completed (workspace_id, status, completed_at, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_notes (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    record_id VARCHAR(36) NOT NULL,
    author_user_id INT NULL,
    body TEXT NOT NULL,
    created_at DATETIME(6) NOT NULL,
    edited_at DATETIME(6) NULL,
    KEY idx_crm_notes_ws_record (workspace_id, record_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_events (
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    record_id VARCHAR(36) NULL,
    actor_user_id INT NULL,
    type VARCHAR(40) NOT NULL,
    before_json TEXT NULL,
    after_json TEXT NULL,
    occurred_at DATETIME(6) NOT NULL,
    KEY idx_crm_events_ws_record (workspace_id, record_id, id),
    KEY idx_crm_events_ws_type_time (workspace_id, type, occurred_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_record_tags (
    workspace_id VARCHAR(36) NOT NULL,
    record_id VARCHAR(36) NOT NULL,
    tag_id VARCHAR(36) NOT NULL,
    created_at DATETIME(6) NOT NULL,
    PRIMARY KEY (record_id, tag_id),
    KEY idx_crm_record_tags_ws_tag (workspace_id, tag_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS crm_imports (
    id VARCHAR(36) NOT NULL PRIMARY KEY,
    workspace_id VARCHAR(36) NOT NULL,
    user_id INT NOT NULL,
    idempotency_key VARCHAR(100) NOT NULL,
    request_hash VARCHAR(64) NOT NULL,
    job_id VARCHAR(255) NOT NULL,
    mode VARCHAR(10) NOT NULL,
    status VARCHAR(10) NOT NULL DEFAULT 'running',
    cursor_result_id INT NOT NULL DEFAULT 0,
    totals TEXT NULL,
    response TEXT NULL,
    created_at DATETIME(6) NOT NULL,
    updated_at DATETIME(6) NOT NULL,
    UNIQUE KEY uq_crm_imports_ws_key (workspace_id, idempotency_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
