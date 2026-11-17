# CRM Phase 1 — delivery report (branch `feat/crm-phase1`)

Base: release candidate `feat/user-ux-finishing` @ `9bb3e27`. **Not merged, not deployed.** No live database writes.
Spec: `CRM_PRODUCT_IMPLEMENTATION_PLAN.md`; selection contract `docs/CRM_LEAD_SELECTION.md`; concrete API/data contract
and every deviation: `docs/CRM_PHASE1_CONTRACT.md` (section 5 + "Frontend alignment").

## 1. What is complete (Phase 1)

| Area | Delivered |
|---|---|
| Workspace | One private workspace per account, created on first CRM use (race-safe unique key); owner membership; default Sales pipeline New → Contacted → Qualified → Proposal → Won; Lost is an outcome with a required reason; seeded lost reasons. Product admin/owner roles give no access to other workspaces. |
| Import | From the search page: per-lead state (Add to CRM / Already in CRM · View / Possible match · Review), Add one, Add selected (numeric `lead_id` only; disabled with a reason if any selected lead has no id), Add all (resumable server import in batches of 200). Free (no credits). Exact repeats idempotent; same-key retries replay; results read from the DB, never trusted from the client; running searches import only saved rows. |
| Duplicate review | Possible matches by same Maps place, website host + compatible name, or phone + compatible name (never name alone, never across workspaces, different Maps places never match, social/site-builder hosts ignored, different branch numbers never compatible). Review dialog: Link to existing (adds a source, keeps the record) / Add as new / Skip. No automatic merge. |
| Pipeline & list | Kanban (desktop) with counts, per-currency totals, drag & drop + "Move to stage" menu, optimistic move with rollback; stage-chip list on tablet/phone; All leads list with server search (name, phone, email, website, tags, notes), filters (stage, outcome, archived, type, tag, source search, due), sort, keyset "Load more", URL-addressable filters. |
| Record detail | Stage selector, Convert to opportunity, Mark won, Mark lost (reason/custom reason + note), Reopen (back to the stage it closed from), Archive/Restore; business details with "found online" snapshot kept separate from user edits; deal value/currency/probability/close date (value needs a currency); people/contacts; tags; notes with edit + unsaved-changes guard; activities schedule/done/reopen/reschedule; sources incl. "Original search no longer available"; history (one event per change, local times, older history paging); version-conflict handling. |
| Activities | Call/email/meeting/message/task with timezone-aware due dates stored UTC; agenda Overdue / Today / Upcoming / Done; due badge on the CRM nav item. Logging "email" never claims it was sent. |
| Contacts, reports, export | People search; reports with visible definitions (imported businesses, open leads, opportunities, by stage/source, won/lost, won rate with numerator/denominator, overdue, completed activities, lost reasons, value by currency — never summed across currencies), "No data yet"; CSV/XLSX export of the caller's records, formula-safe. |
| Durability | CRM tables have no foreign keys to `jobs`/`results`; deleting a search keeps records + captured source summary (`available: false`). |
| Flag | Backend `CRM_ENABLED` (default **false**): every `/api/crm/*` route except `/status` returns 404 `crm_disabled`; the CRM nav item appears only when enabled. |

## 2. Later phases (not built)

Phase 2: teams/members and roles, assignees and manager views, configurable pipelines/stages and settings screens,
saved views, list bulk actions (assign/tag/move/archive), duplicate comparison/merge, company view with multiple
opportunities, contact dedupe suggestions, "changed contact details" review on re-import, notification preferences,
richer reports/forecast, workspace default currency, permanent delete + retention + full-account deletion of CRM data.
Phase 3: email/calendar integrations, webhooks/API, automation. No automated outreach in any phase without consent work.

## 3. Deviations from the plan (all recorded in the contract)

- CRM status per lead comes from a separate `GET /api/crm/jobs/{id}/state`, not from `GET /api/jobs/{id}/results`
  (keeps search polling cost unchanged; results already carry `lead_id`).
- Workspaces are created lazily on first use instead of a migration backfill (same outcome, no bulk write at deploy).
- Place identity is read from the Maps URL (the stored `dedupe_key` is a hash). Phone matching uses the last 8 digits.
- "All" imports: each response lists that batch's items; totals are running. Only a finished import replays exactly.
- `version` changes only with the record's own fields/stage; adding notes/activities doesn't conflict with edits.
- Import rate limit (30/min/user) is per server process.

## 4. Tests (exact merged branch)

See section 7 for the final numbers recorded after the last commit.

Browser journey (isolated SQLite + fake scraper, CRM enabled; `docs/crm-evidence/phase1/journey_results.txt`):
search → Add all → state chips → View this search in CRM; retry with the same key (no duplicates); another user's
job/result/record/export (404/none); stage change + stale version 409; Lost needs a reason; Lost → Reopen to the
previous stage; notes, two contacts, tag; timezone-aware activities (naive date refused, +05:00 stored as UTC),
overdue count clears on done; one history event per change; second search of the same places → 3 possible matches,
0 created; Link adds a second source; deleting a source search keeps the record with that source unavailable;
CRM screens at 1440/1024/820/430/390/360 with no page errors. 27/28 automated checks passed; the 28th (import
summary) exposed a real defect, fixed in `8fcf70e` and re-verified by screenshot
(`02b_1440_import_summary_and_review.png`).

Defects found and fixed during integration: import summary/review dialog skipped after Add all (`8fcf70e`); names
with different branch numbers suggested as the same business, apostrophes split names (`a0575b9`).

## 5. Migration and rollback

- Migration: `backend/migrations/017_crm.sql` (MariaDB) + `017_crm_sqlite.sql`; 15 new `crm_*` tables, additive only,
  `CREATE TABLE IF NOT EXISTS`, InnoDB/utf8mb4. Applied automatically at backend start by the existing runner.
- Rehearsal on MariaDB 11.8.9 (`docs/crm-evidence/migration_rehearsal_mariadb.txt`): upgrade from the release
  candidate's schema with data applied only `017`; `CHECKSUM TABLE` of users/jobs/results/credit_ledger/job_logs
  unchanged; second start applied nothing; the previous (release-candidate) backend starts on the upgraded schema and
  its health/login/searches calls work; fresh install applies 000–017.
- Release order: back up the production DB → deploy backend with `CRM_ENABLED=false` (migration runs, CRM hidden) →
  smoke test → deploy frontend → set `CRM_ENABLED=true` → smoke test CRM.
- Rollback: set `CRM_ENABLED=false` (CRM disappears; data kept). If the backend itself must go back, redeploy the
  previous backend — it runs on the upgraded schema (rehearsed). Leave the `crm_*` tables in place. Only if the owner
  decides to discard CRM data entirely: after a backup, drop the 15 `crm_*` tables and delete the
  `schema_migrations` row for `017` (never needed for a normal rollback).

## 6. Owner QA checklist

1. Real phone (360–430 px): search → Add selected → CRM → record → schedule activity → Mark done; Back/refresh on
   `/crm/records/<id>`.
2. NVDA/VoiceOver: import dialog, Move to stage menu, Mark lost dialog, agenda Mark done (not verified with a real
   screen reader).
3. Desktop drag and drop between columns (only the menu path is tested automatically).
4. Export CSV/XLSX opens in Excel; formulas shown as text.
5. Decide Phase 2 order and whether to enable the flag for all users or a few accounts first.

## 7. Final test results

| Check | Result |
|---|---|
| Backend pytest, SQLite (3 groups) | **224 passed** (95 + 77 + 52), incl. 40 CRM tests |
| Backend pytest, MariaDB 11.8.9 (isolated, READ-COMMITTED) | **219 passed, 4 skipped** (SQLite-catalogue tests) after fixing one flaky pre-existing test (`17a5fe5`, random job id containing the query) |
| Migration rehearsal, MariaDB 11.8.9 | upgrade / repeat / previous backend / fresh install all pass (section 5) |
| Flutter test | **192 passed** |
| flutter analyze | 48 issues, all pre-existing (none in CRM code) |
| `build_web.sh` release build | passed at the branch head (one earlier run failed transiently and passed on rerun) |
| Browser journey | 27/28 automated + the 28th fixed and re-verified (section 4) |
