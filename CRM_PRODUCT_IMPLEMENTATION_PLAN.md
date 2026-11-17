# Infinity Leads CRM: product and implementation plan

**Status:** Design brief for owner and Claude review. No CRM code or database change is authorized by this document alone.  
**Base:** Implement after the approved user UX branch is complete; rebase or merge that branch into the CRM working branch first. Do not build against an obsolete Results or navigation screen.  
**Product aim:** Turn useful scraped businesses into an Odoo-inspired sales workspace where users can qualify, contact, follow up, and measure outcomes without losing the link to the search that found each business.

## 1. Product decisions, fixed for implementation

These decisions make the work actionable. If a constraint in the code makes one impossible, Claude should document the evidence and propose the smallest alternative before coding that part.

| Topic | Decision |
|---|---|
| CRM model | Native Infinity Leads CRM. Take workflow inspiration from Odoo; do not copy Odoo assets, code, wording, or visual design. |
| Source of CRM records | A scraped result is a **discovered business**, not automatically a qualified sales lead. Import is user initiated: one result, selected results, or all results of a search after an explicit review. Never auto-fill the pipeline with every scrape. |
| Navigation | Add **CRM** as a main destination after **My searches**. Within CRM: **Pipeline**, **All leads**, **Activities**, **Contacts**, **Reports**, **Settings** (Settings only to permitted users). The search page exposes **Add to CRM** and **View this search in CRM**. |
| Account boundaries | Each existing account receives one private CRM workspace. No account can see another account's CRM data. Product-admin status grants no implicit CRM access. Model memberships from day one so teams can be added later. |
| Default pipeline | **New → Contacted → Qualified → Proposal → Won**. **Lost** is a closed outcome with a required reason, not a column that hides old work permanently. **Archived** is a separate visibility flag. A workspace starts with one pipeline. |
| Leads and opportunities | Imported results start as `lead`. **Convert to opportunity** is an explicit action that preserves notes, history, source, assignee, and activities. A user can also create a lead or opportunity manually. |
| Stage customization | Workspace managers may rename, reorder, add, or deactivate open stages in a later phase. System outcome meanings `won` and `lost` are fixed. Deactivation requires moving records first. |
| Duplicates | Exact repeat imports of the same result are idempotent. Probable matches across searches show a review panel; never silently merge distinct contacts or businesses. A business may have more than one opportunity only by explicit user action. |
| Contact data | Scraped business phone, website, email, address, and Maps link are labelled **found online**. Do not invent a named person, verification badge, or consent. A user may add people and verified details manually. |
| Data durability | CRM keeps a snapshot independent of `results` and `jobs`; deleting a search must not delete CRM work. Source links may become unavailable and should say so. All persistent data goes to the configured remote `DATABASE_URL`, never the VM filesystem. |
| Credits | Importing or managing a result already delivered by a search has no extra credit charge. CRM monetary deal values are currency amounts, never scraping credits. |
| Notifications | In-app due and overdue reminders first. Email sending, inbox sync, and automatic outreach remain off until a provider, consent rules, and deliverability are configured. |
| Mobile | Pipeline is a stage-filtered list with a stage picker. Drag and drop is optional on desktop and must always have a keyboard-accessible stage menu. |
| Deletion | Archive and restore are the primary actions. Permanent delete is a separate confirmed action with a retention policy and an audit event. |
| Default currency | The workspace owner chooses an ISO currency when enabling deal values. A record may override it. Reports never convert currencies without an exchange-rate source. |
| Loss reasons | Seed `Not interested`, `No response`, `Not a fit`, `Duplicate`, and `Other`; permit a custom reason. A Lost record always has one reason. |
| Import size | Import requests process at most 200 source IDs per batch. `Add all` runs as a resumable server-side import with a status endpoint, bounded work, and the same idempotency rules. |

## 2. Why this fits the existing product

The current `results` table already has a numeric `id`, `job_id`, business details, and a per-job dedupe key. However, `GET /api/jobs/{job_id}/results` currently returns business fields without the result ID, and `results` rows are removed when their parent job is deleted. The CRM therefore needs a stable result ID in the API and an independent record snapshot. `ResultsScreen` already supports row selection and exports, which can be extended with import actions. Existing job access verifies ownership; CRM endpoints must apply equally strict workspace checks.

The active user UX redesign changes Results, History, navigation, and direct job routes. CRM should consume those finished surfaces rather than introducing competing labels or a second results page. Admin work is separate; the live role-management issues in `ADMIN_UX_PLAN.md` should be resolved before team administration is exposed.

Odoo's relevant concepts are a pipeline, qualification before opportunity conversion, scheduled activities, lost reasons, duplicate review, and pipeline reports. These ideas are described in [Odoo CRM](https://www.odoo.com/documentation/19.0/applications/sales/crm.html), [lead conversion](https://www.odoo.com/documentation/19.0/applications/sales/crm/acquire_leads/convert.html), [activities](https://www.odoo.com/documentation/19.0/applications/sales/crm/optimize/utilize_activities.html), [duplicate handling](https://www.odoo.com/documentation/19.0/applications/sales/crm/pipeline/merge_similar.html), and [pipeline analysis](https://www.odoo.com/documentation/19.0/applications/sales/crm/performance/win_loss.html).

## 3. Main user journeys

### 3.1 From a completed search

1. Search detail and results show a CRM status on each business: **Add to CRM**, **Already in CRM · View**, or **Possible match · Review**.
2. User selects rows and chooses **Add selected to CRM**. Confirm the count and show exact matches, probable matches, and items without enough identity data. The user chooses Add new, Link to existing, or Skip for each probable match.
3. A successful import shows a clear summary: `18 added · 2 already in CRM · 1 needs review`. Partial failures remain selectable for retry. Retrying the same request cannot create duplicates.
4. **View this search in CRM** opens the pipeline or list filtered by source search. It must include records previously imported from that search, including records now in Won, Lost, or Archived when the relevant filter is enabled.
5. A running search may expose **Add to CRM** for already persisted results only. The action does not start or alter the scraper job.

### 3.2 Work a lead

1. Open a card to a full record page. Show business identity, source search, contact methods, stage and owner, next activity, notes, tags, and chronological history.
2. Record a call, email, meeting, message, or custom note. Mark an activity done and schedule the next one. Do not claim an email was sent merely because it was logged manually.
3. Change stage with drag and drop, a stage selector, or keyboard controls. Every change persists immediately, is reversible by another change, and appears once in history.
4. Convert a qualified lead to an opportunity. Add deal value/currency, probability, expected close date, and contact person if known. A user may skip these optional values; reports must label missing values clearly.
5. Mark Won or Lost. Lost asks for a reason and optional note. Both can be reopened, preserving their history and close timestamps.

### 3.3 Daily workflow

CRM Home/Activities starts with **Overdue**, **Due today**, **Upcoming**, and **No next activity**. Pipeline filters include My records, All workspace records, source search, stage, assigned person, tag, location, creation date, last activity, and contact availability. A manager sees unassigned and stale leads. A user can switch between Kanban and compact list/table without losing filters.

### 3.4 Search and contact history

The same business may appear in later scrapes. The existing CRM record remains the source of truth for stage and notes; the new search creates another source link. Show `Found in 3 searches` and the dates. Do not overwrite user-edited contact details with fresh scraped values. Present differences for review, e.g. `New website found`, before applying them.

## 4. Screen specifications

### 4.1 Pipeline

- Header: **CRM / Pipeline**, pipeline switcher (when more than one), **+ New lead**, search, saved filters, Kanban/List toggle.
- Summary line: number of open records, due today, overdue, unassigned. If deal values exist, show currency-specific totals only; never sum different currencies into one number.
- Columns: New, Contacted, Qualified, Proposal, Won. Lost is accessible by filter/tab, not silently discarded. Each column shows count; value appears only when populated and in one currency.
- Card: business name, city/region, source category or tag, assigned user, next activity with due state, and one meaningful contact hint. Status and due state must use text and icon as well as color. No raw UUID.
- Dragging is optimistic only with rollback and an error message if the save fails. Provide `Move to stage` menu and keyboard action. Large columns paginate or virtualize; do not render thousands of cards.
- Empty state offers **Add from a search** and **Create manually**. No fake metrics or sample records in a real account.

### 4.2 All leads / list

- Search name, phone, email, website, tags, and notes with server-side pagination.
- Columns: business, contact, stage, type, owner, next activity, source, city, updated; configurable visible columns can follow later.
- Bulk actions: assign, tag, move stage, archive, export, with confirmation and per-item failure reporting. Bulk Won/Lost still records an outcome reason or requires explicit choice.
- Saved views: My leads, All, Due today, Overdue, Unassigned, Recently added, Won, Lost, Archived. User filters persist in the URL and can be shared only within an authorized workspace.

### 4.3 Lead/opportunity detail

- Clear top actions: **Convert to opportunity** (lead only), **Mark won**, **Mark lost**, stage selector, archive, more menu. Destructive actions are separated.
- Business section: name, address, category, website, phone, email, Maps link; distinguish sourced details from manually entered contacts. Offer safe copy/open links.
- Opportunity section: expected revenue, currency, probability, expected close date. Keep blank values blank; no fabricated forecast.
- Activities and notes: next action at top, timeline below with author and local display time; timeline timestamps stored UTC.
- Source section: original search and all later source searches. If the source job is deleted, keep a readable captured source summary and show `Original search no longer available`.
- Duplicate banner: reasons for possible match and actions to compare/link/merge. Merge preview shows the survivor and what happens to each field, contact, note, task, and source link.
- Mobile: header and next action first, tabs or sections for Details, Activity, and History. No horizontal overflow.

### 4.4 Activities

- My agenda and workspace agenda (where permitted): Overdue, Today, Upcoming, Done.
- Activity kinds: call, email to send, meeting, message, task. Fields: subject, due time/date, assignee, optional notes, completion time and outcome.
- Reminder badge and in-app notification link directly to the record. Deduplicate alerts and respect timezone and user notification settings.
- No outbound email or calendar event is created in the first release. A manual `Email sent` activity records the user's assertion only.

### 4.5 Contacts and companies

- Imported result represents a company/business. A person is a separate contact linked to it. Users can add multiple people, roles, emails, phones, and a primary contact.
- Contacts list supports search and dedupe suggestions. Do not treat a generic business email as a person's email.
- Allow a company to have one active imported lead by default, but explicit new opportunities for separate deals. Show all linked opportunities and source searches on the company view.

### 4.6 Reports

- Initial: lead counts by stage/source/search, conversion from imported lead to opportunity, Won/Lost outcomes, overdue activities, time in stage, and follow-up completion. Date range and assignee filters must apply consistently.
- Later: expected revenue by currency and close month, forecast weighted by an explicitly entered probability, performance by team, and lost reasons.
- Definitions visible beside each metric. `Imported`, `contacted`, `qualified`, `won`, and `lost` are distinct. A scraped result is not a conversion. Revenue is not scraping credits.
- No fake chart series; return `No data yet` when absent. Server-side aggregates and pagination for scale.

### 4.7 Settings

- Pipeline/stage configuration, tags, lost reasons, activity types, workspace members, notification preferences, import defaults, and data export/retention.
- Lock system meanings of Won/Lost while allowing display labels where safe. Never remove a stage with records until they are moved.
- Invitations/team administration appear only after the live admin role bugs are fixed and workspace authorization is tested.

## 5. Data model and migration contract

Use additive versioned migrations for **MariaDB 11.8** and SQLite test parity. Confirm the migration number at implementation time; do not assume 017 is still free. Back up and rehearse on an isolated MariaDB copy before production. Prefer normalized tables with indexes and foreign keys where they will not cascade away CRM history.

| Entity | Required fields and relationships |
|---|---|
| `crm_workspaces` | id, owner_user_id, name, created_at. One private workspace per existing user initially. Backfill idempotently. |
| `crm_memberships` | workspace_id, user_id, role (`owner`, `manager`, `member`, optional `viewer`), joined_at, status. Unique workspace/user. Do not infer membership from product-admin role. |
| `crm_pipelines` | id, workspace_id, name, is_default, active, created_at. One default Sales pipeline per workspace. |
| `crm_stages` | id, pipeline_id, stable key, display name, position, outcome kind (`open`, `won`), active, color. Lost is a separate closed outcome on a record. |
| `crm_companies` | id, workspace_id, business name, normalized matching key, sourced contact snapshot, editable contact fields, country/region/city, address, maps URL, website, phone, email, created/updated timestamps, archived_at. Raw scraped snapshot retained separately from user edits. |
| `crm_people` | id, workspace_id, company_id, name, role/title, phone, email, primary flag, created/updated timestamps. These are user-entered unless a real person was explicitly sourced. |
| `crm_records` | id, workspace_id, company_id, pipeline_id, stage_id, type (`lead`/`opportunity`), title, assignee_user_id nullable, outcome (`open`/`won`/`lost`), lost_reason_id nullable, value DECIMAL nullable, ISO currency nullable, probability nullable 0–100, expected_close_date nullable, priority, archived_at, created/updated/closed timestamps, version for concurrency. |
| `crm_source_links` | id, workspace_id, company_id, record_id nullable, source_job_id text, source_result_id nullable integer, captured job category and location, imported_at, imported_by. Unique `(workspace_id, source_result_id)` while result ID exists. Do not cascade delete on source job/result deletion. |
| `crm_activities` | id, workspace_id, record_id, type, subject, description, due_at UTC, assignee_user_id, status, completed_at UTC, outcome text, created/updated timestamps. Index due/status/assignee. |
| `crm_notes` | id, workspace_id, record_id, author_user_id, body, created/edited timestamps. Soft-delete or edit history according to workspace policy. |
| `crm_events` | id, workspace_id, record_id, actor_user_id, event type, structured before/after summary, occurred_at UTC. Append-only; redact secrets and sensitive tokens. Index record/time. |
| `crm_tags`, `crm_record_tags`, `crm_lost_reasons` | Workspace-scoped dictionaries and join table. |

Implementation may consolidate tables if it preserves the same behavior and constraints. All primary record IDs should be opaque in URLs. Enforce ownership with workspace-scoped queries on **every** read and write, including search, exports, sources, attachments, activities, and bulk actions. Use transactions for import, merge, stage changes, and activity completion. Set `created_at`/`updated_at` consistently in UTC.

### Identity and dedupe rules

1. Exact source result ID in same workspace: return the existing CRM link/record (`already_added`).
2. Stable Google Place identity when present: high-confidence possible match; exact matching business ID may link automatically only if user previously opted into `Link repeats automatically`, default off.
3. Otherwise normalized website host plus compatible business name/location, or normalized phone plus compatible name/location: possible match, not automatic merge.
4. Name alone is insufficient. Generic shared phone numbers/domains are weak signals. Never dedupe across workspaces.
5. Merge is explicit, transactional, reversible only by an audit-backed restore process; retain all sources, contacts, notes, and activities. No silent field overwrite.

### Search deletion and retention

Search deletion currently cascades to `results`. CRM company/record and source snapshots stay. If a user requests full account data deletion, the CRM workspace and associated PII must be included in that workflow; retention and export policies must cover CRM data. Archived is searchable and restorable. Permanent delete uses an explicit confirmation and audit metadata; a future retention setting can govern purge timing.

## 6. API contract

Use versioned, additive responses; do not break the current frontend. Extend `GET /api/jobs/{job_id}/results` with `result_id`, stable source metadata, and `crm_state` (`not_added`, `added`, `possible_match`) only for the authenticated user's workspace. Confirm how live in-memory results acquire a persisted `result_id`; disable import until persistence is confirmed.

| Endpoint (illustrative) | Behavior |
|---|---|
| `POST /api/crm/import` | Body `{job_id, result_ids[], idempotency_key}`. Validate job ownership and result IDs belong to job. Transactional import with per-item outcomes: created, already_added, possible_match, rejected. Avoid importing arbitrary client-supplied business data as trusted source. |
| `POST /api/crm/import/resolve` | Explicit decisions for possible matches: add new, link to existing, skip. Check target record belongs to same workspace. |
| `GET /api/crm/records` | Cursor/keyset pagination, server-side filters and sort; include total/has_more as needed. Default excludes archived and lost. |
| `POST /api/crm/records`, `GET/PATCH /api/crm/records/{id}` | Manual create, detail, partial update. Field allowlist and version check; no role fields accepted. |
| `POST /api/crm/records/{id}/convert` | Convert lead to opportunity once; preserve history, source, and related data. |
| `POST /api/crm/records/{id}/stage`, `/won`, `/lost`, `/reopen`, `/archive`, `/restore` | Validated transitions with events. Lost requires reason. Stage belongs to record pipeline. |
| `GET/POST/PATCH /api/crm/records/{id}/activities` | Schedule, complete, reschedule; validate assignee membership and due time. |
| `GET/POST/PATCH /api/crm/records/{id}/notes` | Notes and edit history with author attribution. |
| `GET/POST /api/crm/records/{id}/people` | Manage people/contact methods. |
| `GET /api/crm/pipeline`, `GET /api/crm/agenda`, `GET /api/crm/reports` | Counts, paged cards, due tasks, and server-side aggregates scoped to workspace. |
| `POST /api/crm/records/bulk`, `GET /api/crm/export` | Bounded bulk actions and CSV/XLSX export of authorized records; report item-level results. Escape spreadsheet formulas. |
| `GET/POST/PATCH /api/crm/settings/*` | Pipeline, stages, tags, lost reasons, preferences; manager/owner only. |

Use the application's existing auth mechanism. For all endpoints: reject suspended/unapproved users; check workspace membership and role; validate field lengths, URL schemes, phones, currency codes, and dates; use parameterized SQL; rate-limit expensive search/export/import paths; avoid echoing raw database errors. `GET` requests must be read-only. Bulk import and stage updates must be retry safe. Document OpenAPI schemas and example responses. Test authorization by trying another user's IDs and source result IDs.

### Example import response

```json
{
  "job_id": "...",
  "created": [{"result_id": 101, "crm_record_id": "..."}],
  "already_added": [{"result_id": 102, "crm_record_id": "..."}],
  "possible_matches": [{"result_id": 103, "candidate_ids": ["..."], "reasons": ["same Maps place"]}],
  "rejected": []
}
```

## 7. Access and team rules

Phase 1 is private workspace use. In Phase 2, invite existing approved users (or add a reviewed invitation flow) as members. A product owner/admin is not automatically a member of customers' CRM workspaces. Support access, if ever needed, requires a logged, time-limited support mechanism with customer authorization.

**Team policy for implementation:** all active members may view workspace records and activities; owners/managers may edit any record, manage settings, and assign work; members may create records and edit records assigned to them or unassigned records they claim; viewers may only read. Only owners invite/remove members, change roles, export the whole workspace, or permanently delete records. A member may export only records they can edit. Every endpoint applies the rule server-side; hiding a button is insufficient. Team invitations stay disabled until the permission matrix is tested and the separate admin role defects are fixed.

Every change has an actor. A reassignment keeps all history. On member removal, records stay with the workspace and become unassigned or are reassigned by the owner. Shared CRM notifications should never reveal records to a removed member. Team-facing features remain gated until role and authorization tests pass, particularly given the separate live admin role defects.

## 8. UX details and accessibility

- Fit the approved Infinity Leads user design system and naming. No second sidebar or unrelated Odoo chrome.
- Desktop Kanban supports drag and drop, but each card also has a `Move to stage` action. Mobile uses a list with stage chips, compact cards, and a clear detail route.
- Provide explicit loading, empty, offline, unauthorized, conflict, and save-failed states. Never show an empty pipeline when loading actually failed.
- Optimistic changes roll back on failed API calls. Unsaved notes are guarded on navigation. Refresh or another tab must show persisted state.
- Search and filters are URL-addressable, browser Back works, direct record URLs reopen after login, and a removed/archived record has an informative state.
- Keyboard path covers import, filter, card, stage change, activity completion, and dialogs. Screen readers receive labels, status text, and live updates. Meet WCAG 2.2 AA contrast and focus requirements. Respect reduced motion.
- Large data sets use pagination/virtualization. Do not fetch all leads, notes, or timeline events to render one screen.
- Times display in the user's local timezone with an unambiguous full timestamp on hover/detail; store UTC. Keep currencies distinct and format by ISO code.

## 9. Reporting definitions

| Metric | Definition |
|---|---|
| Imported businesses | Unique companies added to the workspace from search results during the selected period. Repeat source links are not new imports. |
| Open leads | CRM records of type lead and outcome open at period end. |
| Opportunities | CRM records converted or manually created as opportunities. |
| Contacted | Records with a logged completed contact activity or moved to Contacted; report which definition is used. |
| Won rate | Won opportunities divided by opportunities closed Won or Lost during the period; show denominator. |
| Overdue follow-ups | Open activities with due_at before now, scoped to selected assignee/workspace. |
| Time in stage | Duration between stage-change events; exclude archived intervals or state the rule. |
| Expected revenue | Sum of explicit value × explicit probability for open opportunities, grouped by currency and close period. Unknown values excluded and counted separately. |

Reports must not claim that scraping itself generated a sale. Make period filters apply to the relevant event date (imported, converted, closed, or due) and show that definition in the UI.

## 10. Build phases and release gates

### Phase 0 — dependency review and prototype

- Wait for the user UX branch to finish and inspect its routes, Results component, and tests. Identify conflicts and incorporate the CRM entry points in that design.
- Confirm actual MariaDB schema and migration number. Rehearse migrations on an isolated copy; no production-data write during design/test.
- Build clickable desktop and mobile CRM mockups for owner approval. Include imported-result state, pipeline, detail, activities, and empty states. Preserve all existing search/export functionality.
- Decide workspace/team policy using the rules above. No email-provider dependency for initial release.

### Phase 1 — usable single-user CRM

- Add additive DB migrations, workspace backfill, API schemas, ownership checks, and result IDs.
- Import one/selected/all from a search with idempotency and duplicate review. Snapshot source data.
- Pipeline Kanban and list; record detail, stage changes, Won/Lost/reopen, notes, manual contacts, tags, activity scheduling/completion, source links, archive/restore.
- Search-detail `View in CRM` and global CRM navigation. Desktop, tablet, and mobile layouts.
- In-app agenda and due badges. Basic reports with honest metrics. Export authorized CRM data.
- Tests and isolated browser QA. No deployment until owner checks it.

### Phase 2 — Odoo-like depth

- Workspace teams, assignment, manager views, permissions, configurable pipelines/stages, saved filters, bulk actions, lost reasons, duplicate comparison/merge, company view, multiple opportunities per company, richer reports and forecast.
- Notifications and reminders with per-user preferences. Activity plans/templates, but no automated outbound messages.
- Import from later searches can link to existing businesses, show changed contact fields, and preserve manually edited data.

### Phase 3 — optional integrations

- Email integration and two-way activity capture only after provider setup, security review, user consent, unsubscribe/opt-out handling, and a clear distinction between logged versus actually sent messages.
- Calendar sync, quotations, webhooks/API access, and automation rules only if real customer workflows justify them. Integrations must be opt-in and workspace scoped.

The implementation branch should be pushed for review with migrations, tests, screenshots, feature flags, and rollback notes. Do not merge or deploy as part of the planning work. If Phase 2 is too large for one safe review, split it into reviewable PRs without reducing Phase 1's functional acceptance bar.

## 11. Acceptance tests

### Source and import

- Import one result, 50 selected, and an entire small search; refresh and confirm the same records remain. Repeat the request and verify no duplicate records or source links.
- Attempt import with another user's job ID or result ID: 404/403 without revealing record details.
- Re-scrape the same business in another search: show candidate/link behavior; existing stage, notes, and manual contact fields survive.
- Delete a source job in a test database: CRM record and captured source summary survive; direct source link becomes unavailable gracefully.
- A running job exposes import only for persisted results; a network retry cannot import the same row twice.

### Pipeline and activities

- Move a card by drag, menu, and keyboard; refresh and verify persisted stage and one history event. Simulate API failure and verify rollback.
- Convert a lead, add value and currency, mark Won/Lost, require lost reason, reopen, archive/restore. Verify event order and timestamps.
- Add a note and two contacts; schedule an activity, mark done, reschedule another; due/overdue counts agree with the detail view.
- Another user cannot read a direct record URL, timeline, contact, export, or notification from a private workspace.

### Layout, data, and scale

- Browser walk at 1440, 1024, 820, 430, 390, and 360 px, including empty, 1 record, 100 records, and a long pipeline column. No clipped actions or horizontal overflow on phones.
- Screen-reader labels and keyboard focus order for import, stage changes, dialogs, and activities. Contrast and reduced-motion checks.
- Verify counts and report definitions with known fixtures, including multiple currencies, no values, partial activities, and a source found in multiple jobs.
- Test MariaDB 11.8 and SQLite migration up/down or documented rollback, fresh install, repeated startup, old frontend against additive API, and previous backend against additive schema.
- Run backend unit/integration tests, Flutter tests/analyzer, production web build, and browser end-to-end tests on the exact pushed branch. Keep remote Hostinger data untouched during tests.

## 12. Operational and release requirements

- Database backup and restore rehearsal before production migration. Prefer additive schema; avoid table rewrites or long locks on live MariaDB.
- Feature flag CRM navigation and APIs until migration and smoke test pass. Deploy compatible backend first, then frontend.
- Log import, merge, stage, and deletion actions without storing credentials. Monitor API error rate, import failures, slow queries, activity backlog, and migration state.
- Define export/retention and full account deletion behavior before public release. Provide a user export of CRM records and activities.
- Do not create a second database on the VM. The configured `DATABASE_URL` remains the source of persistent CRM data. Local files may hold only ephemeral build/runtime artifacts.
- Rollback must leave new CRM tables intact and allow the prior backend to continue operating. Roll back the frontend feature flag first if CRM-specific problems appear.

## 13. What Claude should hand back after coding

1. Branch and commit IDs, migration number, API contract/OpenAPI changes, and exact feature scope by phase.
2. Screenshots or short recordings of desktop and mobile flows, including the result-to-CRM handoff and daily agenda.
3. Test command outputs, MariaDB migration rehearsal evidence, authorization/duplicate tests, and known gaps.
4. List of any feature explicitly deferred to Phase 2/3 and why.
5. Release order, rollback steps, feature flag default, and manual QA checklist for the owner.

The owner and Codex will review the delivered implementation together before merge or deployment.
