# CRM Phase 1 — implementation contract (backend ⇄ frontend)

Spec: `CRM_PRODUCT_IMPLEMENTATION_PLAN.md` (product) and `docs/CRM_LEAD_SELECTION.md` (selection). This file fixes the
concrete API so backend and frontend can be built in parallel. Owner-approved decisions (2026-11-18):
private workspace per account; import is user-initiated and free; one / selected / all persisted results of a search;
the numeric `lead_id` (= `result_id`) is the source ID; exact repeats are idempotent; probable matches across searches
need review (never auto-merge); CRM keeps its own snapshot when a search is deleted; a running search can be imported
only for results already saved with an ID. No automated email.

## 0. Conventions

- Feature flag: backend env `CRM_ENABLED` (default **false**). When false every `/api/crm/*` route returns
  `404 {"detail": "CRM is not enabled", "code": "crm_disabled"}`. `GET /api/crm/status` always answers:
  `{"enabled": bool}` (auth required). Tests and the review harness set `CRM_ENABLED=true`.
- Auth: existing `get_current_user` (rejects suspended/unapproved). Product roles (owner/admin/support) grant **no** CRM
  access to other users' workspaces.
- Workspace: one per user, created lazily on first CRM call (get-or-create, unique `owner_user_id`, idempotent under
  races), with membership role `owner`, one default pipeline "Sales" and stages
  New(new) → Contacted(contacted) → Qualified(qualified) → Proposal(proposal) → Won(won, outcome_kind=won);
  seeded lost reasons: Not interested, No response, Not a fit, Duplicate, Other.
- IDs in URLs are opaque UUID strings (records, companies, people, activities, notes, tags, imports). Source result IDs
  are integers. Every query is workspace-scoped; another user's ID ⇒ `404 {"detail":"Not found"}` (never 403 that
  reveals existence).
- Timestamps stored and returned as UTC ISO-8601 with `Z`. Dates (`expected_close_date`) as `YYYY-MM-DD`.
- Errors: `{"detail": "<plain sentence>", "code": "<machine_code>"}`. Codes used below: `crm_disabled`,
  `validation_error` (422), `not_found` (404), `version_conflict` (409), `invalid_transition` (409),
  `rate_limited` (429), `result_not_persisted` (409).
- Pagination: keyset. List endpoints take `limit` (1–100, default 50) and `cursor` (opaque string) and return
  `{"items": [...], "next_cursor": str|null, "total": int}`.
- Concurrency: records carry `version` (int). `PATCH` and transition endpoints accept optional `version`; a mismatch ⇒
  409 `version_conflict` with the current record in `current`.
- Spreadsheet export escapes cells starting with `= + - @` (reuse existing helper).

## 1. Data model (migration `017_crm` + `017_crm_sqlite`)

Additive only; no change to existing tables. No FK from CRM tables to `results`/`jobs` (snapshots survive deletion).
Tables: `crm_workspaces`, `crm_memberships`, `crm_pipelines`, `crm_stages`, `crm_companies`, `crm_people`,
`crm_records`, `crm_source_links`, `crm_activities`, `crm_notes`, `crm_events`, `crm_tags`, `crm_record_tags`,
`crm_lost_reasons`, `crm_imports` (idempotency + resumable "all" imports). Fields per plan §5 with these specifics:
- `crm_companies`: `name`, `match_place_key` (from result `dedupe_key` when it starts with `id:`), `match_host`
  (normalized website host), `match_phone` (digits, ≥7), `match_name` (normalized), `source_snapshot` JSON (raw scraped
  fields: business_name, phone, website, email, address, city, state, category, google_maps_url), editable fields
  `phone`, `email`, `website`, `address`, `city`, `region`, `country`, `maps_url` (initialized from the snapshot,
  edited only by the user), `archived_at`.
- `crm_records`: `type` lead|opportunity, `outcome` open|won|lost, `stage_id`, `lost_reason_id`, `lost_note`,
  `value` DECIMAL(14,2) null, `currency` CHAR(3) null, `probability` 0–100 null, `expected_close_date` null,
  `assignee_user_id` null, `priority` 0–3, `archived_at`, `closed_at`, `version`, `last_activity_at`.
- `crm_source_links`: `source_job_id`, `source_result_id`, captured `category`, `city`, `region`, `country`,
  `job_created_at`, `imported_at`, `imported_by`. UNIQUE(`workspace_id`, `source_result_id`).
- `crm_imports`: `workspace_id`, `idempotency_key` UNIQUE per workspace, `job_id`, `mode` ids|all, `status`
  running|done, `cursor` (last processed result id), `totals` JSON, `response` JSON (for exact replay).

## 2. Endpoints

### Status, workspace, search-state
- `GET /api/crm/status` → `{"enabled": true}`.
- `GET /api/crm/workspace` → `{id, name, role, pipeline:{id,name,stages:[{id,key,name,position,outcome_kind}]},
  lost_reasons:[{id,name}], tags:[{id,name,color}], currency_default:null}`.
- `GET /api/crm/jobs/{job_id}/state` → for the caller's own job only (else 404):
  `{"job_id", "results": {"<result_id>": {"state": "not_added"|"added"|"possible_match", "record_id": str|null,
  "candidate_record_ids": [..], "reasons": [..]}}, "counts": {"not_added","added","possible_match"}}`.
  (Additive and separate from the results payload so search polling cost is unchanged.)

### Import
- `POST /api/crm/import` body `{"job_id": str, "result_ids": [int]?, "all": bool?, "idempotency_key": str(8–80)}`.
  - Exactly one of `result_ids` (1–200 unique ints) or `all: true`. Results must belong to the caller's job; unknown IDs
    or IDs from other jobs/users go to `rejected` with reason `not_found` (no details leaked). Result rows are read from
    the DB; client business data is never accepted. A running job is allowed; only rows that exist are importable.
  - Per item: `created` (new company + lead record + source link + `imported` event), `already_added` (same
    workspace+result_id), `possible_match` (candidates by place key, host+name, phone+name; name alone never matches),
    `rejected`.
  - `all: true` processes at most 200 rows per call ordered by result id; response has
    `"import_id", "done": bool, "processed": int, "remaining": int`; the client repeats the same request (same
    idempotency_key) until `done`. Replaying a finished key returns the stored response unchanged.
  - Response: `{"import_id","job_id","done","processed","remaining","created":[{"result_id","record_id"}],
    "already_added":[{"result_id","record_id"}],"possible_matches":[{"result_id","business_name","candidates":[{
    "record_id","name","stage","reasons":[...]}]}],"rejected":[{"result_id","reason"}],
    "summary":{"created","already_added","possible_match","rejected"}}`.
  - Rate limit: 30 import calls per user per minute (429).
- `POST /api/crm/import/resolve` body `{"job_id", "idempotency_key", "decisions":[{"result_id", "action":
  "add_new"|"link"|"skip", "record_id"?}]}` → same per-item shape (`created`, `linked`, `skipped`, `rejected`).
  `link` adds a source link to the existing record's company (record data unchanged) and a `source_linked` event.

### Records
- `GET /api/crm/records` filters: `q` (name, phone, email, website, tags, notes), `stage_id`, `outcome`
  (open|won|lost|all; default open), `archived` (false|true|all; default false), `type`, `tag_id`, `source_job_id`,
  `due` (overdue|today|none), `sort` (updated|created|name|next_activity), `limit`, `cursor`. Item:
  `{id, title, type, outcome, stage:{id,key,name}, company:{id,name,city,region,country,phone,email,website},
  tags:[..], next_activity:{id,type,subject,due_at,overdue:bool}|null, source_count, value, currency, archived,
  updated_at, created_at, version}`.
- `GET /api/crm/pipeline` (Kanban): `?q&tag_id&source_job_id&per_stage=20` → `{"stages":[{stage, count, values:
  [{currency,total}], items:[...first page...], next_cursor}], "summary":{"open","due_today","overdue",
  "no_next_activity"}}`; more cards per column via `GET /api/crm/records?stage_id=..&cursor=..`.
- `POST /api/crm/records` manual create `{title, company:{name,phone?,email?,website?,address?,city?,region?,
  country?}, type?, stage_id?}`.
- `GET /api/crm/records/{id}` detail: list item + `company` (editable fields + `source_snapshot` labelled found
  online), `people`, `sources:[{job_id, category, city, region, country, imported_at, available: bool}]`,
  `activities` (open first), `notes` (latest 50), `events` (latest 50, newest first), `lost_reason`, `lost_note`,
  `probability`, `expected_close_date`, `closed_at`.
- `PATCH /api/crm/records/{id}` allowlist: `title, value, currency, probability, expected_close_date, priority,
  company:{phone,email,website,address,city,region,country}` + `version`. Validates ISO currency (3 letters), URL
  scheme http/https, probability 0–100, lengths.
- Transitions (all accept optional `version`, each writes one event, idempotent when already in the target state):
  `POST …/{id}/stage {stage_id}` (open records only; stage of the record's pipeline), `…/convert` (lead→opportunity,
  once), `…/won`, `…/lost {reason_id, note?}` or `{custom_reason}` (creates a workspace reason), `…/reopen`
  (won/lost→open, keeps history; to the last open stage), `…/archive`, `…/restore`.
- `GET /api/crm/records/{id}/events?cursor` for older history.

### Notes, people, tags, activities
- `POST /api/crm/records/{id}/notes {body}`; `PATCH /api/crm/notes/{note_id} {body}` (author only; keeps `edited_at`).
- `POST /api/crm/records/{id}/people {name, role?, phone?, email?, is_primary?}`; `PATCH/DELETE
  /api/crm/people/{person_id}`; `GET /api/crm/people?q&limit&cursor` (Contacts screen, with company + record id).
- `GET /api/crm/tags`, `POST /api/crm/tags {name,color?}`, `PUT /api/crm/records/{id}/tags {tag_ids:[..]}`.
- `POST /api/crm/records/{id}/activities {type: call|email|meeting|message|task, subject, due_at, notes?}`;
  `PATCH /api/crm/activities/{aid} {subject?, due_at?, notes?}` (reschedule); `POST /api/crm/activities/{aid}/done
  {outcome?}`; `POST …/reopen`. Due dates must parse as timezone-aware ISO; stored UTC.
- `GET /api/crm/agenda?bucket=overdue|today|upcoming|done&tz_offset_minutes=..&limit&cursor` → activities with record
  title; `today` is computed in the client's offset. `GET /api/crm/agenda/counts?tz_offset_minutes=..` →
  `{overdue, today, upcoming, no_next_activity}` (used for the nav badge).

### Reports and export
- `GET /api/crm/reports?from&to&tz_offset_minutes` → `{"definitions":{...},"imported_companies","open_leads",
  "opportunities","by_stage":[{stage,count}],"by_source":[{job_id,category,count}],"won","lost","won_rate":{value|null,
  numerator,denominator},"overdue_activities","activities_completed","lost_reasons":[{name,count}],
  "value_by_currency":[{currency,open_total,won_total}],"records_without_value"}`. No fake data; nulls when no data.
- `GET /api/crm/export?format=csv|xlsx&<same filters as records>` → base64 file like the job download
  (`{filename, content, content_type}`), formula-safe, workspace-scoped, includes source search and next activity.

## 3. Events (`crm_events.type`)
`imported`, `source_linked`, `created`, `updated`, `stage_changed`, `converted`, `won`, `lost`, `reopened`,
`archived`, `restored`, `note_added`, `note_edited`, `person_added`, `person_updated`, `person_removed`,
`tags_changed`, `activity_scheduled`, `activity_rescheduled`, `activity_done`, `activity_reopened`.
`before`/`after` JSON summaries only.

## 4. Frontend routes and entry points
- Nav: **CRM** after My searches (sidebar, rail, phone bar) — only when `/api/crm/status` says enabled.
- `/crm` pipeline (Kanban ≥1024 px; stage-chip list below), `/crm/leads` list, `/crm/activities` agenda,
  `/crm/contacts`, `/crm/reports`, `/crm/records/<id>` detail. Filters in the query string
  (`/crm?source=<job_id>&outcome=all&archived=all`).
- Search page / results: per-lead CRM state chip, **Add to CRM** (one), **Add selected to CRM**, **Add all to CRM**,
  review dialog for possible matches, summary snack `18 added · 2 already in CRM · 1 needs review`, and
  **View this search in CRM** (`/crm/leads?source=<job_id>&outcome=all`). Disabled with a reason for leads without
  `lead_id`.

## 5. Backend implementation notes and deviations (crm/backend)

Code: `backend/crm/` (router, workspace, importer, matching, records, activities, reports), wired by two lines at
the end of `backend/main.py`. Migration files: `backend/migrations/017_crm.sql` (MariaDB) and `017_crm_sqlite.sql`.
Where this section differs from sections 0–3, this section is what the backend does.

**Conventions**
- The flag check runs before authentication: with `CRM_ENABLED` off, every `/api/crm/*` route except `/status`
  answers `404 crm_disabled` even without a token. Unexpected failures answer `500 {"code": "server_error"}`; body /
  query validation failures answer `422 {"code": "validation_error"}` with a plain sentence (never FastAPI's list).
- Code `result_not_persisted` is not used: a row that is not saved yet has no ID, so it is `rejected: not_found`.
- Money (`value`, totals) is a JSON number with 2 decimals. A value needs a currency (the record's, or the workspace
  default); otherwise `422`. `tz_offset_minutes` = minutes east of UTC (UTC+3 ⇒ `180`), range ±840.
- Time buckets (agenda, `due` filter, pipeline summary): **overdue** = open activity due before now; **today** =
  due from now until the end of the client's local day; **upcoming** = due after the end of the local day. They do
  not overlap. Activities of archived records are not in the agenda.

**Data model**
- `crm_companies.match_place_key` is `id:<Maps feature/place id>` parsed from `google_maps_url` with the same
  patterns as `job_service.dedupe_key_for` (`results.dedupe_key` is a SHA-1 hash, so it can't be read back).
- Extra columns: `crm_records.last_open_stage_id` (reopen target), `converted_at` (also set for records created as
  opportunities), `next_activity_at` (denormalized earliest open activity, used for sort/filters);
  `crm_source_links.snapshot` (the raw row at import); `crm_people.record_id`; `crm_imports.request_hash`,
  `user_id`; `crm_imports.cursor` is named `cursor_result_id` (`cursor` is reserved in MariaDB). `crm_stages.key`
  is `stage_key` for the same reason (the API still says `key`). Events use an auto-increment id (strict order).
- Source links belong to a record (`record_id`); `source_job_id` filters and detail `sources` use the record's links.

**Import / resolve**
- Possible match: same place key; or same website host + compatible name; or same phone (last 8 digits) +
  compatible name. Names are compatible when equal after normalization (case, accents, punctuation, legal words
  such as LLC/Ltd removed), one's words contain the other's, or word overlap ≥ 60 %. If both sides have a place key
  and they differ, they are different places (chain branches) and nothing else is checked. Social / site-builder
  hosts (facebook.com, wixsite.com, …) are not a website signal. Reasons: `same_maps_place`,
  `same_website_and_name`, `same_phone_and_name`. Candidate items also carry `outcome` and `archived`; `stage` is
  `{id, key, name}`.
- Reusing an `idempotency_key` with a different request ⇒ `422 validation_error` (a finished identical request is
  replayed byte-for-byte).
- `all: true`: `created/already_added/possible_matches/rejected` list **this batch**; `processed` and `summary`
  are cumulative for the whole import; `remaining` counts saved rows after the cursor at that moment (a running
  search may add more later — a new import picks them up). Retrying an unfinished `all` call continues with the next
  batch; only a finished import is replayed.
- Resolve keys are stored separately from import keys (the same key may be reused). The response also has
  `already_added`; a `link` to a record outside the workspace is `rejected` with reason `record_not_found`.
  `skip` writes nothing, so the job state keeps showing `possible_match` for that result.
- Rate limit: 30 calls/min/user across import + resolve, in-process (per worker), env `CRM_IMPORT_RATE_PER_MIN`.

**Records**
- `GET /records?stage_id=<won stage>` without `outcome` lists won records (so the Won column paginates);
  `tz_offset_minutes` is accepted by `/records` and `/pipeline` for `due=today` / `due_today`.
- PATCH and every transition return the **detail** shape (a superset of the list item; list items also carry
  `priority`). Detail adds `converted_at`, `assignee_user_id`, `last_activity_at`, `events_next_cursor`, and each
  source has `result_id`, `job_created_at`, `snapshot`. Events: `{id, type, actor_user_id, before, after,
  occurred_at}`; `/events` returns `{items, next_cursor, total}` newest first.
- PATCH with an unknown field (including company `name`) ⇒ 422. A no-op PATCH writes nothing.
- `version` changes only when the record's own fields/stage/outcome change; notes, people, tags and activities
  update `updated_at` but not `version`. An idempotent transition (already in the target state) succeeds even with an
  old `version`.
- `POST …/stage` to the Won stage performs Mark won (`won` event). Stage/convert/won/lost/reopen on an archived
  record ⇒ `409 invalid_transition`; won→lost and lost→won need a reopen first (`409`). Reopen returns to the stage
  the record was in when it closed and clears `closed_at`, `lost_reason`, `lost_note` (the `won`/`lost` events keep
  them). `custom_reason` reuses an existing reason with the same name (case-insensitive).

**Notes, people, tags, activities**
- Editing another member's note ⇒ 404. `DELETE /people/{id}` ⇒ `{"deleted": true}`. `GET /tags` ⇒ `{"items": [...]}`;
  `POST /tags` with an existing name (case-insensitive) returns that tag with `"created": false`;
  `PUT …/tags` ⇒ `{record_id, tags}`; an unknown tag id ⇒ 404. People/activities/PATCH reject unknown fields.
- Activity responses: `{id, record_id, type, subject, notes, due_at, status, completed_at, outcome, overdue,
  assignee_user_id, created_at, updated_at}`; agenda items add `record_title`; agenda returns
  `{bucket, items, next_cursor, total}` (default bucket `today`). `done` / `reopen` are idempotent.

**Reports / export**
- `from`/`to` are local calendar dates (inclusive, in `tz_offset_minutes`); without them the period is all time.
  The response adds `period`. `open_leads`, `by_stage`, `overdue_activities`, `records_without_value` and
  `value_by_currency.open_total` describe **now**; the other metrics use their event date in the period (see
  `definitions`). `won_rate` counts all records closed in the period (leads and opportunities).
  `records_without_value` = open opportunities without a value.
- Export adds `encoding: "base64"` and `count`, is capped at 10 000 rows, CSV cells starting with `= + - @ \t \r`
  get a leading apostrophe, XLSX cells use the job-download text helper (never formulas). Timestamps in the file
  are UTC.
