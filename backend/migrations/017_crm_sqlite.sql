-- 017_crm_sqlite.sql
-- CRM Phase 1 (SQLite test/dev parity). See 017_crm.sql and docs/CRM_PHASE1_CONTRACT.md.
-- Additive only, no foreign keys to jobs/results, safe to re-run (IF NOT EXISTS).
-- Timestamps are UTC text 'YYYY-MM-DD HH:MM:SS.ffffff' written by the application.

CREATE TABLE IF NOT EXISTS crm_workspaces (
    id TEXT NOT NULL PRIMARY KEY,
    owner_user_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    currency_default TEXT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_crm_workspaces_owner ON crm_workspaces (owner_user_id);

CREATE TABLE IF NOT EXISTS crm_memberships (
    id TEXT NOT NULL PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    user_id INTEGER NOT NULL,
    role TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'active',
    joined_at TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_crm_memberships_ws_user ON crm_memberships (workspace_id, user_id);
CREATE INDEX IF NOT EXISTS idx_crm_memberships_user ON crm_memberships (user_id);

CREATE TABLE IF NOT EXISTS crm_pipelines (
    id TEXT NOT NULL PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    name TEXT NOT NULL,
    is_default INTEGER NOT NULL DEFAULT 0,
    active INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_crm_pipelines_ws ON crm_pipelines (workspace_id);

CREATE TABLE IF NOT EXISTS crm_stages (
    id TEXT NOT NULL PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    pipeline_id TEXT NOT NULL,
    stage_key TEXT NOT NULL,
    name TEXT NOT NULL,
    position INTEGER NOT NULL,
    outcome_kind TEXT NOT NULL DEFAULT 'open',
    active INTEGER NOT NULL DEFAULT 1,
    color TEXT NULL,
    created_at TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_crm_stages_pipeline_key ON crm_stages (pipeline_id, stage_key);
CREATE INDEX IF NOT EXISTS idx_crm_stages_ws ON crm_stages (workspace_id);

CREATE TABLE IF NOT EXISTS crm_lost_reasons (
    id TEXT NOT NULL PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    name TEXT NOT NULL COLLATE NOCASE,
    is_system INTEGER NOT NULL DEFAULT 0,
    active INTEGER NOT NULL DEFAULT 1,
    position INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_crm_lost_reasons_ws_name ON crm_lost_reasons (workspace_id, name);

CREATE TABLE IF NOT EXISTS crm_tags (
    id TEXT NOT NULL PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    name TEXT NOT NULL COLLATE NOCASE,
    color TEXT NULL,
    created_at TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_crm_tags_ws_name ON crm_tags (workspace_id, name);

CREATE TABLE IF NOT EXISTS crm_companies (
    id TEXT NOT NULL PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    name TEXT NOT NULL,
    match_place_key TEXT NULL,
    match_host TEXT NULL,
    match_phone TEXT NULL,
    match_name TEXT NULL,
    source_snapshot TEXT NULL,
    phone TEXT NULL,
    email TEXT NULL,
    website TEXT NULL,
    address TEXT NULL,
    city TEXT NULL,
    region TEXT NULL,
    country TEXT NULL,
    maps_url TEXT NULL,
    category TEXT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    archived_at TEXT NULL
);
CREATE INDEX IF NOT EXISTS idx_crm_companies_ws_place ON crm_companies (workspace_id, match_place_key);
CREATE INDEX IF NOT EXISTS idx_crm_companies_ws_host ON crm_companies (workspace_id, match_host);
CREATE INDEX IF NOT EXISTS idx_crm_companies_ws_phone ON crm_companies (workspace_id, match_phone);

CREATE TABLE IF NOT EXISTS crm_people (
    id TEXT NOT NULL PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    company_id TEXT NOT NULL,
    record_id TEXT NULL,
    name TEXT NOT NULL,
    role TEXT NULL,
    phone TEXT NULL,
    email TEXT NULL,
    is_primary INTEGER NOT NULL DEFAULT 0,
    created_by INTEGER NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_crm_people_ws_company ON crm_people (workspace_id, company_id);
CREATE INDEX IF NOT EXISTS idx_crm_people_ws_name ON crm_people (workspace_id, name, id);

CREATE TABLE IF NOT EXISTS crm_records (
    id TEXT NOT NULL PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    company_id TEXT NOT NULL,
    pipeline_id TEXT NOT NULL,
    stage_id TEXT NOT NULL,
    last_open_stage_id TEXT NULL,
    type TEXT NOT NULL DEFAULT 'lead',
    title TEXT NOT NULL,
    assignee_user_id INTEGER NULL,
    outcome TEXT NOT NULL DEFAULT 'open',
    lost_reason_id TEXT NULL,
    lost_note TEXT NULL,
    value NUMERIC NULL,
    currency TEXT NULL,
    probability INTEGER NULL,
    expected_close_date TEXT NULL,
    priority INTEGER NOT NULL DEFAULT 0,
    archived_at TEXT NULL,
    closed_at TEXT NULL,
    converted_at TEXT NULL,
    created_by INTEGER NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    last_activity_at TEXT NULL,
    next_activity_at TEXT NULL
);
CREATE INDEX IF NOT EXISTS idx_crm_records_ws_updated ON crm_records (workspace_id, updated_at, id);
CREATE INDEX IF NOT EXISTS idx_crm_records_ws_created ON crm_records (workspace_id, created_at, id);
CREATE INDEX IF NOT EXISTS idx_crm_records_ws_stage ON crm_records (workspace_id, stage_id);
CREATE INDEX IF NOT EXISTS idx_crm_records_ws_company ON crm_records (workspace_id, company_id);
CREATE INDEX IF NOT EXISTS idx_crm_records_ws_next ON crm_records (workspace_id, next_activity_at);

CREATE TABLE IF NOT EXISTS crm_source_links (
    id TEXT NOT NULL PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    company_id TEXT NOT NULL,
    record_id TEXT NULL,
    source_job_id TEXT NOT NULL,
    source_result_id INTEGER NULL,
    category TEXT NULL,
    city TEXT NULL,
    region TEXT NULL,
    country TEXT NULL,
    job_created_at TEXT NULL,
    snapshot TEXT NULL,
    imported_at TEXT NOT NULL,
    imported_by INTEGER NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_crm_source_links_ws_result ON crm_source_links (workspace_id, source_result_id);
CREATE INDEX IF NOT EXISTS idx_crm_source_links_ws_job ON crm_source_links (workspace_id, source_job_id);
CREATE INDEX IF NOT EXISTS idx_crm_source_links_ws_record ON crm_source_links (workspace_id, record_id);
CREATE INDEX IF NOT EXISTS idx_crm_source_links_ws_company ON crm_source_links (workspace_id, company_id);

CREATE TABLE IF NOT EXISTS crm_activities (
    id TEXT NOT NULL PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    record_id TEXT NOT NULL,
    type TEXT NOT NULL,
    subject TEXT NOT NULL,
    notes TEXT NULL,
    due_at TEXT NOT NULL,
    assignee_user_id INTEGER NULL,
    status TEXT NOT NULL DEFAULT 'open',
    completed_at TEXT NULL,
    outcome TEXT NULL,
    created_by INTEGER NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_crm_activities_ws_status_due ON crm_activities (workspace_id, status, due_at, id);
CREATE INDEX IF NOT EXISTS idx_crm_activities_ws_record ON crm_activities (workspace_id, record_id);
CREATE INDEX IF NOT EXISTS idx_crm_activities_ws_assignee ON crm_activities (workspace_id, assignee_user_id, status);
CREATE INDEX IF NOT EXISTS idx_crm_activities_ws_completed ON crm_activities (workspace_id, status, completed_at, id);

CREATE TABLE IF NOT EXISTS crm_notes (
    id TEXT NOT NULL PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    record_id TEXT NOT NULL,
    author_user_id INTEGER NULL,
    body TEXT NOT NULL,
    created_at TEXT NOT NULL,
    edited_at TEXT NULL
);
CREATE INDEX IF NOT EXISTS idx_crm_notes_ws_record ON crm_notes (workspace_id, record_id, created_at);

CREATE TABLE IF NOT EXISTS crm_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workspace_id TEXT NOT NULL,
    record_id TEXT NULL,
    actor_user_id INTEGER NULL,
    type TEXT NOT NULL,
    before_json TEXT NULL,
    after_json TEXT NULL,
    occurred_at TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_crm_events_ws_record ON crm_events (workspace_id, record_id, id);
CREATE INDEX IF NOT EXISTS idx_crm_events_ws_type_time ON crm_events (workspace_id, type, occurred_at);

CREATE TABLE IF NOT EXISTS crm_record_tags (
    workspace_id TEXT NOT NULL,
    record_id TEXT NOT NULL,
    tag_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    PRIMARY KEY (record_id, tag_id)
);
CREATE INDEX IF NOT EXISTS idx_crm_record_tags_ws_tag ON crm_record_tags (workspace_id, tag_id);

CREATE TABLE IF NOT EXISTS crm_imports (
    id TEXT NOT NULL PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    user_id INTEGER NOT NULL,
    idempotency_key TEXT NOT NULL,
    request_hash TEXT NOT NULL,
    job_id TEXT NOT NULL,
    mode TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'running',
    cursor_result_id INTEGER NOT NULL DEFAULT 0,
    totals TEXT NULL,
    response TEXT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_crm_imports_ws_key ON crm_imports (workspace_id, idempotency_key);
