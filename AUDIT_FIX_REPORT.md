# Infinity Leads — audit, fixes and release plan (2026-11-16)

Branch `fix/job-durability-audit` (git worktree `F:\webTest\scraper\il-fix-worktree`), based on
`f60ec53` plus the uncommitted security fixes that were in the main checkout (commit `1434809`).
At the time of round 2, nothing was deployed or merged. The live database was not migrated or written: round 2 took one
read-only snapshot (approved by the owner) and tested only against isolated copies. `.env` was not
read; live credentials were never printed. Note: production runs **MariaDB 11.8**, not MySQL.
See section 0B for the later live QA setup.

Line numbers in the inventory refer to the **baseline** (`1434809`) unless marked "now".

---

## 0B. Live QA setup (2026-11-17)

The owner requested a pushed branch and a Vercel preview connected to the
backend running locally. Branch `fix/job-durability-audit` was pushed at
`ac682eb`. The current production frontend domain was **not** promoted to the
new build; use this Vercel preview for QA:

`https://frontend-69432nnim-akbs-projects-69c135c0.vercel.app`

The current backend/tunnel containers were replaced with the audited code on
the same local port and public tunnel. Because `backend/requirements.txt` did
not change, the local QA image layers the audited backend code on the tagged
previous image; the normal Dockerfile was not fully rebuilt in this session.
The previous image is tagged locally as
`infinity-leads-backend:pre-job-durability-20261117` for rollback.

Before the switch, a fresh live MariaDB dump was saved outside Git and
successfully restored into a temporary MariaDB 11.8 container: 29 tables,
22 jobs, 789 results, 46 ledger rows. The temporary restore container was
removed. The live backend applied migrations 014, 015 and 016 on startup;
read-only checks afterwards showed 4 users, 22 jobs, 789 results and 46 ledger
rows, with the new `billing_snapshot` column present and
`JOB_REFUND_POLICY=delivered`. The job runner started at concurrency 2.
Local and public API health checks returned HTTP 200. The Vercel preview's
home page, JavaScript bundle, login route and `/api/health` returned HTTP 200;
a headless browser load of `/login` reported 0 JavaScript errors and 0 failed
API requests.

**Your PC, Docker backend and Cloudflare tunnel must remain running during QA.**
The preview uses the live backend and database, so test jobs will consume and
then settle real account credits under the chosen refund policy. The branch is
not merged, the production frontend is unchanged, and manual QA is still
required before calling this a production release.

---

## 0A. Verification round 3 and QA handoff (2026-11-17)

This section supersedes the refund decision and open MariaDB test gate in round 2 below.
At the time of this verification, all changes remained on
`fix/job-durability-audit`; nothing was merged or deployed. The later live QA
setup is documented in section 0B.

### Billing decision

The owner chose to **return unused lead credits**. New jobs default to
`JOB_REFUND_POLICY=delivered`, and `docker-compose.worker.yml` sets it explicitly.
The maximum estimated cost is debited when the job starts. On settlement, the
user keeps the base job charge, completed-city charges, and charges for leads
actually delivered (subject to the existing minimum job charge); the rest is
returned once to the wallet. A failed job with no leads, or a cancellation
before any city completes and before any lead is saved, gets a full refund.
Historical jobs remain protected by `settled_at='pre-014'`: **no retroactive
refund is issued at deployment**. At the old fill rate, applying this policy
to future jobs could reduce net charges substantially; round 2 estimated
50.6% of historical charges would have been returned if it had applied then.

Examples with the test price (base 10, city 5, lead 1, minimum 15):

| Job | Charged | Returned | Kept |
|---|---:|---:|---:|
| 2 cities x 3 leads, all 6 delivered | 26 | 0 | 26 |
| 2 cities completed, zero leads | 26 | 6 | 20 |
| 3-city job cancelled while queued | 34 | 34 | 0 |
| Failed with no leads | 34 | 34 | 0 |

Migration 016 stores the prices at job creation so an admin price change during
a job cannot change that job's refund. Older active jobs without a snapshot use
the current prices; there were no active jobs in the isolated production copy.

### Final verification

| Check | Result |
|---|---|
| Full backend suite, temporary SQLite | **104 passed** |
| Full backend suite, isolated MariaDB 11.8 | **100 passed, 4 skipped** (the skips inspect SQLite-only catalog tables) |
| Billing matrix | 29 SQLite cases passed; pricing-change regression passed on MariaDB |
| 30-city x 10-lead scripted job | Passed on SQLite and MariaDB: 30 completed cities, 300 distinct saved leads, 460 charged, 0 refunded, balance and progress consistent |
| Settlement race | Regression passes on both engines: a completed job is settled even when ownership changes as the worker exits |
| Migration 016 on isolated MariaDB production copy | Applied once; users/jobs/results/ledger/balance totals stayed **5/25/802/50/10,838**; second startup applied 0 migrations |
| Flutter | 11 tests passed, analysis 0 errors (50 existing infos/warnings), cleaned Windows release web build succeeded and required bundle files were verified |
| Real Google Maps extraction and browser stress | Round 2 evidence still applies. Round 3 did not repeat those runs after the billing and settlement changes. |

The MariaDB run caught a real race: a heartbeat could see the just-completed
job as lost ownership and skip settlement. The worker now recognizes completed
status and always attempts the idempotent terminal settlement. The connection
pool also resets autocommit before reuse. The test fixture's MariaDB reset now
uses one transaction rather than many slow table-recreation operations.
The Windows build wrapper's asset paths were repaired.
After verification, the `il-qa-mariadb` and `il-qa-mysql8` containers holding
the production-data copy were removed. The live backend and tunnel stayed up.

### Remaining before release

1. Run the manual staging QA in section 0.7 with **`delivered`** billing; verify
   a partial-result job shows the exact refund in the job panel and Wallet.
2. Sample result relevance and lead completeness. The historical 789 leads had
   phone/website/email on 711/667/259 rows respectively; the prior 38% result
   fill rate remains the main product-quality problem. A **real** 30-city
   Google Maps job has not been run; the 30-city test above uses a fake scraper.
3. Push the branch or open a PR to execute CI. The same backend and Flutter
   commands passed locally, but GitHub Actions has not run.
4. SMTP is not configured. The owner chose to leave email setup for later, so
   password reset remains unavailable until an email provider is configured.
5. Fresh MySQL 8 installs still fail on historical migration 004. Production
   runs MariaDB 11.8; document MySQL 8 as unsupported until that migration is fixed.

At the end of round 3 this was a **local QA candidate**. Section 0B records
the subsequent live QA setup; it is still not a fully production-ready release.

---

## 0. Verification round 2 — status before manual QA (2026-11-16)

**Not production-ready yet** — see 0.4 for the exact open gaps. Everything marked ✅ was executed and
observed; ⚠️ is partially verified; ❌ is a known gap or was blocked. Sections 3–5 further down are from round 1
and are superseded by this section where they differ.

### 0.1 Verified / unverified checklist

| # | Area | Status | Evidence |
|---|---|---|---|
| V1 | Production DB engine identified | ✅ | Read-only query: **MariaDB 11.8.9** (not MySQL 8), 29 tables, schema 013, 22 jobs (20 completed, 2 failed, 0 running) |
| V2 | Read-only production snapshot | ✅ | `mariadb-dump --single-transaction --skip-lock-tables` via a separate client container; credentials piped container→volume, never printed; volume deleted after use. 636 KB, 29 tables |
| V3 | Restore into isolated containers | ✅ | `il-qa-mariadb` (MariaDB 11.8, 127.0.0.1:13306) and `il-qa-mysql8` (MySQL 8.0.46, 127.0.0.1:13307); row counts match (4 users, 22 jobs, 789 results, 46 ledger rows) |
| V4 | Migration 014 on the production copy | ✅ 13/13 on MariaDB, 13/13 on MySQL 8 | Applies once; all columns/indexes present; no job, result, ledger or balance row changed; all 22 historical jobs marked `pre-014`; settlement sweep refunds 0; second start applies nothing; partially-applied 014 re-runs cleanly |
| V5 | Migration 015 on the production copy | ✅ | Applied by the new backend during V7 on both engines |
| V6 | Backend test suite on SQLite | ✅ 95/95 | `pytest tests` (final run, all fixes included) |
| V7a | Backend suite on **MariaDB 11.8** (production engine) | ⚠️ partial | `test_job_durability`: 27/28 — the 1 failure was a real bug (F11), fixed; the fix's regression test reproduces the failure on MariaDB without the fix (verified), but the post-fix MariaDB re-run was cut off by a Docker shutdown. Other modules: an earlier full MariaDB run (before F1/F11 fixes) passed 55 with 10 failures, all since diagnosed (F1 + harness). **A clean full MariaDB run is still owed** |
| V7b | Backend suite on **MySQL 8** | ❌ blocked | Fresh MySQL 8 databases cannot run the **pre-existing** migration 004 (F12). MySQL 8 was only exercised from the restored MariaDB snapshot (V4, V12–V14), not with a fresh schema |
| V8 | Real Google Maps scraping (MariaDB copy) | ✅ 41/41 | 3 real jobs, Qatar, headless Chromium — see 0.3 |
| V9 | Cancellation during a real job | ✅ | Settled 6 s after cancel; ≤1 lead written after cancel; no writes after settlement |
| V10 | Backend crash/restart during a real job | ✅ | Process tree killed after city 1; DB stayed `running`; restarted server resumed (attempt 2) and completed; 2 pre-crash leads kept, 6 total, no duplicates |
| V11 | DB ↔ API (=UI data) consistency | ✅ | For every real job: status, lead count, results list, completed cities, log lines, refund and ledger all equal |
| V12 | Rollback: live (old) backend on migrated schema | ✅ 25/25 | Old code starts on 015 schema, logs in, reads new jobs, creates/completes/cancels jobs (new unique index OK), accepts new tokens |
| V13 | Roll-forward after rollback | ✅ | Jobs billed by old code are not refunded retroactively (bug found and fixed, F2) |
| V14 | Deployed (current Vercel) frontend vs new backend | ✅ | Old client contract (create without key, default status payload, field types) + browser smoke of the old web build: loads signed in, History lists jobs, 0 API errors, 0 page errors |
| V15 | Browser: network outage, refresh, mobile↔desktop, reattach | ✅ 15/15 (round 1) | Unchanged since |
| V16 | Browser: double clicks, lost create response, slow/timeout responses, multiple tabs, session expiry + re-login, server-side failure | ✅ 17/17 | Run 5 (SQLite backend, fake scraper, new web build): one job/one charge on double-click; lost create response retried with one Idempotency-Key → one job/one charge; responses >20 s → connection notice; 2nd tab attaches, cancels, 1st tab shows Cancelled; 401 → sign-in notice, re-login reattaches; server crash → Failed + reason. Runs 2–4 failures were harness issues (timing, status parser, 5 jobs/hour limit correctly returning 429, stale test server on port) |
| V17 | "Never Failed unless the server says failed" | ✅ | UI sampled against the DB throughout runs 2–5: 0 violations; positive control (S6) shows Failed + server reason |
| V18 | Refund policies × job outcomes | ✅ 21/21 + default test | Exact outcomes in 0.5 |
| V19 | Security: roles/auth | ✅ | 12 security tests incl. support cannot mutate, password policy, reset revokes sessions, XFF rotation locked out, SECRET_KEY fail-fast, templates tracked |
| V20 | Flutter `analyze` / `test` / web build | ✅ | 0 errors (50 pre-existing infos/warnings) / 11/11 / bundle verified |
| V21 | CI | ✅ written, ❌ not executed | `.github/workflows/test.yml`: pytest on SQLite and MariaDB 11.8, Flutter analyze/test/build; `deploy.yml` test job runs pytest. Not run on GitHub (branch not pushed). MySQL 8 leg omitted until F12 is fixed |
| V22 | Production config: SMTP | ❌ not configured in live env | Live container has no SMTP user ⇒ forgot-password returns 503 (feature unavailable) |
| V23 | Load / concurrency at production scale | ❌ | Not tested beyond 2 concurrent jobs and 6 concurrent creates |
| V24 | Real email delivery, payments (Coinbase), PWA install | ❌ | Not exercised |

### 0.2 Failures found in this round (all fixed on the branch)

**F1 — On MySQL/MariaDB a healthy worker could think it lost its job (critical).**
*Repro:* `IL_TEST_MYSQL_URL=…13306… pytest tests/test_job_durability.py::test_runner_dedupes_across_cities_and_keeps_timeout_partials` → job left `running`, only first lead saved.
*Root cause:* PyMySQL reports rows **changed**, SQLite reports rows **matched**. Ownership/heartbeat/settlement checks use `rowcount == 1`; an UPDATE writing an identical value (two heartbeats within one clock tick) returns 0 on MySQL ⇒ `_LostOwnership`.
*Fix:* `client_flag=CLIENT.FOUND_ROWS` on every MySQL connection (`backend/database.py`).
*Evidence:* `test_heartbeat_with_identical_timestamp_keeps_ownership` **fails on MariaDB without the fix, passes with it** (verified both ways).

**F2 — Roll-forward after a rollback could refund old jobs retroactively (high, money).**
*Repro:* deploy new → roll back (old code finishes jobs: `settled_at NULL`, `attempts 0`) → deploy new again → settlement sweep refunds those jobs.
*Fix:* sweep only settles jobs the durable runner ran (`attempts > 0`).
*Evidence:* `test_sweep_never_refunds_jobs_finished_by_old_code`; V13 on MySQL 8 (balance 938 → 938).

**F3 — Silent billing change (high, business).** Round 1 defaulted `JOB_REFUND_POLICY` to `delivered`, which on historical data refunds ~51 % of revenue (0.5). *Fix:* default `none` (today's billing) + startup warning when unset/invalid; refunds are an explicit choice. *Evidence:* `test_refund_policy_default_is_none`.

**F4 — Password reset did not end existing sessions (high, audit M-9).** *Fix:* migration 015 `users.password_changed_at`; tokens carry `iat`; tokens issued before the change are rejected; the admin reset script stamps it too. *Evidence:* `test_password_reset_revokes_existing_sessions`.

**F5 — Login lockout bypass by rotating `X-Forwarded-For` (high, audit H-6).** *Fix:* second lockout scope keyed on Cloudflare's `CF-Connecting-IP` (not settable through the tunnel; API is bound to 127.0.0.1). *Evidence:* `test_rotating_x_forwarded_for_does_not_bypass_lockout`. *Residual:* traffic proxied by Vercel shares Vercel egress IPs, so this scope uses a higher threshold (`LOGIN_EDGE_MAX_ATTEMPTS`, default 60/10 min); a spray attack through Vercel could temporarily block logins from that egress IP.

**F6 — No password policy (high, audit H-5).** *Fix:* ≥ 8 chars, ≤ 72 bytes (bcrypt limit), not blank — on register and reset (API 422) and in the register/reset forms. Existing passwords are unaffected. *Evidence:* `test_password_policy_on_register_and_reset`.

**F7 — Weak/missing `SECRET_KEY` silently fell back to a public constant (high, audit M-10).** *Fix:* `auth.py` loads config first and refuses to start with an empty, short (<16) or placeholder key. Live env checked (boolean only): key set, ≥ 32 chars, not a placeholder. *Evidence:* `test_missing_or_placeholder_secret_key_refuses_to_start`.

**F8 — Email templates were git-ignored (high, audit H-7).** *Fix:* `.gitignore` exception + 6 templates committed (contain only placeholders, no secrets). *Evidence:* `test_every_email_template_referenced_by_code_is_tracked_in_git`.

**F9 — CI never ran the tests (audit L-2).** *Fix:* see V21.

**F10 — Admin password-reset script left sessions valid.** *Fix:* stamps `password_changed_at`.

**F11 — On MariaDB's default isolation, the heartbeat could make a healthy job fail (high).**
*Repro:* MariaDB 11.8 with default `REPEATABLE READ` + `innodb_snapshot_isolation=ON`; worker reads the job row, heartbeat thread updates it, worker updates it → `1020 Record has changed since last read`; three retries then the job errors (seen in `test_runner_dedupes_across_cities_and_keeps_timeout_partials`).
*Production impact:* none today — a read-only check shows production runs `READ-COMMITTED` globally (`innodb_snapshot_isolation=1`), where this cannot happen. Any MariaDB left at defaults would fail jobs.
*Fix:* every MySQL/MariaDB connection sets `SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED` (matches production).
*Evidence:* `test_job_row_update_after_concurrent_heartbeat_does_not_conflict` raises 1020 on MariaDB 11.8 **without** the fix (verified). Post-fix MariaDB run: owed (V7a).

**F12 — Fresh MySQL 8 install cannot initialise (pre-existing, not fixed).**
*Repro:* empty MySQL 8.0 database → `init_database()` → migration `004_user_enhancements.sql` fails: `1170 BLOB/TEXT column 'created_at' used in key specification without a key length`. Many MySQL migrations declare timestamps as `TEXT` and index them.
*Impact:* production (MariaDB, already past 004) unaffected; `docker-compose.yml`'s `mysql:8.0` stack and any new MySQL 8 deployment fail at startup.
*Not fixed* because the change (TEXT→VARCHAR in historical MySQL migrations) needs a fresh-install run on MySQL 8 to verify and Docker went down. Next step: change indexed `TEXT` columns in the MySQL `.sql` files to `VARCHAR(64)`/`VARCHAR(255)`, then run the fresh-install probe until all 15 migrations apply.

Test-harness-only problems fixed (not product bugs): MySQL test mode needed autocommit on the long-lived test connection (REPEATABLE READ snapshot hid app writes), tuple-vs-list comparisons, SQLite-catalog tests skipped on MySQL, test helper typo, too-tight timeout for Docker-hosted DB, browser status parser.

### 0.3 Real scraping run (MariaDB copy of production, headless Chromium, Google Maps)

| Job | Scenario | Result |
|---|---|---|
| A | "coffee shop", Doha + Lusail, 3/city | completed in 63 s; 6 leads (6 with phone, 4 with website); 15 log lines; charged 26, refunded 0 |
| B | "restaurant", 3 cities, cancel after first lead | cancelled; settled 6 s after cancel; 1 lead; charged 34, refunded 19 (run used the then-default `delivered`) |
| C | "pharmacy", 3 cities, process tree killed after city 1 | resumed on attempt 2, completed; 6 leads (2 pre-crash kept); charged 31, refunded 0 |
| — | User balance vs ledger | 928 = 1000 + (−72) ✅; balance API = DB ✅ |

### 0.4 Gaps that block "production ready"

1. **Clean full backend suite on MariaDB 11.8 after F1/F11** (V7a). Command in 0.6; needs Docker.
2. **MySQL 8 fresh install** (F12) — only matters if MySQL 8 will ever be used; otherwise document MariaDB as the supported engine.
3. **Refund policy decision** (0.5) — set `JOB_REFUND_POLICY` explicitly.
4. **Real scraping at production scale** — verified with 3 small Qatar jobs (≤ 3 cities × 3 results); a 30-city × 10 job and concurrent users were not run.
5. **SMTP not configured in production** (V22) — password reset is unavailable until it is.
6. **CI never executed** (V21) — push the branch to see it run.
7. **Manual QA** (0.7) on a staging copy.
8. **Data hygiene:** the snapshot file was deleted, but the stopped QA containers `il-qa-mariadb` and
   `il-qa-mysql8` still hold a **copy of production data** (users, emails, leads). Re-use them for gap 1,
   then remove them: `docker rm -f il-qa-mariadb il-qa-mysql8`.

Environment note: during this round Docker Desktop stopped several times by itself (each time the
session was interrupted). Every restart also restarted the **live** backend and tunnel containers
(restart policy `unless-stopped`) on the old code; the live database showed 0 running jobs, so the old
startup recovery had nothing to fail. No live container was started, stopped or rebuilt by this work.

### 0.5 Refund policy — exact outcomes and recommendation

Credit config: base 10, per city 5, per result 1, minimum 15. Every case runs the real runner + settlement
(`backend/tests/test_refund_policy_matrix.py`); ledger == balance and exactly-once settlement asserted in all 21.

| Scenario (cities × max results) | Leads | Charged | `delivered` refund | `unattempted` refund | `none` refund |
|---|---|---|---|---|---|
| Completed, full (2×3) | 6 | 26 | 0 | 0 | 0 |
| Completed, partial: one city short, one city timed out (3×3) | 5 | 34 | 4 | 0 | 0 |
| Cancelled during city 2 (3×3) | 4 | 34 | 15 | 16 | 0 |
| Failed, no leads (3×3) | 0 | 34 | 34 | 34 | 0 |
| Failed after city 1 (3×3) | 3 | 34 | 16 | 16 | 0 |
| Every city timed out → failed (3×3) | 0 | 34 | 34 | 34 | 0 |
| Retried after crash, completed (2×3) | 6 | 26 | 0 | 0 | 0 |

Applied to the **22 real historical jobs** in the production snapshot (2,890 credits charged; 789 leads
delivered against 2,060 requested result slots = 38 % fill):

| Policy | Would have refunded | Share of charges |
|---|---|---|
| `delivered` | 1,461 | 50.6 % |
| `unattempted` | 375 | 13.0 % |
| `none` (today) | 0 | 0 % |

Largest cases: the live-incident job (460 charged, failed after 6 of 30 cities, 56 leads) → 364 / 360;
a completed 7-city × 50 job with 81 leads → 269 / 0; 3 completed jobs delivered **zero** leads (e.g. 55
charged) → refunded under `delivered`, kept under `unattempted`.

**Recommendation (your decision):** launch with **`unattempted`** — it fixes the clearly unfair cases
(failed/cancelled jobs, cities never searched) at ~13 % of historical revenue — and treat the 38 % fill
rate as the real problem: either price per delivered lead (`delivered`, ~51 % less revenue at today's
fill rate) together with a price change, or improve fill. Note `unattempted` still charges in full for a
*completed* job that found nothing; if that is unacceptable, ask for a small policy change
("refund fully when zero leads"), which is not implemented. Set `JOB_REFUND_POLICY` explicitly; unset
means `none`.

### 0.6 Exact commands used (reproducible)

```bash
# Isolated DBs (never the live one)
docker run -d --name il-qa-mariadb -e MARIADB_ROOT_PASSWORD=qa_root_only -e MARIADB_DATABASE=il_qa -p 127.0.0.1:13306:3306 mariadb:11.8
docker run -d --name il-qa-mysql8  -e MYSQL_ROOT_PASSWORD=qa_root_only   -e MYSQL_DATABASE=il_qa   -p 127.0.0.1:13307:3306 mysql:8.0
docker exec -i il-qa-mariadb mariadb -uroot -pqa_root_only il_qa < prod_snapshot.sql
sed 's/utf8mb4_uca1400_ai_ci/utf8mb4_unicode_ci/g' prod_snapshot.sql | docker exec -i il-qa-mysql8 mysql -uroot -pqa_root_only il_qa

# Backend tests
cd backend
SECRET_KEY=test-secret-key-0123456789 python -m pytest tests -q                       # SQLite
IL_TEST_MYSQL_URL=mysql://root:qa_root_only@127.0.0.1:13306/il_test_mariadb \
SECRET_KEY=test-secret-key-0123456789 python -m pytest tests/<module>.py -q          # MariaDB, per module
# MySQL 8: blocked by F12 for fresh databases

# Frontend
cd frontend && flutter analyze && flutter test && bash build_web.sh
```
The migration-verification, real-scrape, rollback/compatibility and browser harnesses
(`verify_migration.py`, `e2e_real.py`, `e2e_compat.py`, `e2e_browser.py`, `e2e_browser2.py`) live in the
session scratchpad, not in the repo; they target only 127.0.0.1:13306/13307, temp SQLite, and ports 8098/8099.

### 0.7 Manual QA plan (≈45 min, on a staging copy — not production)

Setup: backend from this branch against an **isolated staging database**, `JOB_REFUND_POLICY=delivered`,
frontend built with `API_URL` pointing at it. Use a test account with ~500 credits.

1. **Sign in / refresh** — sign in, refresh twice. Expect: still signed in, balance identical in top bar,
   Credit Balance card and Wallet.
2. **Small real job** — Cities → Qatar → Doha + Lusail → category "coffee shop", 3 results → Review & Start
   (double-click it). Expect: one job in History, one debit in Wallet history, panel shows Queued→Running,
   one log line per lead, Elapsed counts from 0s (not hours).
3. **Refresh mid-job** — press F5. Expect: app returns to the live job panel, form shows "coffee shop".
4. **Network cut** — DevTools → Network → Offline for 20 s, then Online. Expect: amber "Connection
   problem… job keeps running" banner, never "Failed"; recovers within ~10 s; Cancel stays visible.
5. **Mobile ↔ desktop** — DevTools device toolbar to 390 px and back. Expect: same tab, job panel and
   category text unchanged.
6. **Second tab** — open the app in a 2nd tab. Expect: same running job. Cancel it there. Expect: first tab
   shows Cancelled within ~10 s; leads found so far downloadable; refund shown per chosen policy.
7. **Completion and refund** — run another 1-city job to completion. Expect: Completed, Download Excel
   works, lead count in panel = History = Results page = rows in the file. If fewer leads than requested
   arrive, the unused lead credits return once; the job panel and Wallet agree on the exact amount.
8. **Backend restart** — start a 3-city job; restart the backend container after the first city. Expect:
   UI shows "Connection problem" while down, then the job resumes ("Resuming job at city 2" in the log)
   and completes; no duplicate leads.
9. **Password reset — deferred** until SMTP is configured. Do not mark this feature as passing yet;
   after configuration, request reset, set an 8+ char password and verify another session is signed out.
10. **Roles** — sign in as a support user: admin lists visible; granting credits / deleting users fails.
11. **Wallet** — after all of the above, sum of Wallet ledger = shown balance.
Record any step that deviates, with a screenshot and the job id.

---

## 1. Issue inventory

Severity: **C**ritical / **H**igh / **M**edium / **L**ow. Status: **Fixed** (with test),
**Open** (not changed), **Hypothesis** (not reproduced).

### 1.1 Scraping workflow (highest priority)

| # | Sev | Status | Where | Root cause → user impact | Fix |
|---|---|---|---|---|---|
| S1 | C | Fixed | `frontend/lib/providers/scraper_provider.dart:136-142` | One failed `GET /api/jobs/{id}` (timeout, 5xx, proxy blip) set the job **and** the provider to `failed` and stopped polling. → The live case: UI showed *Failed, 0 %, 0 leads* while the backend kept scraping and saving. | Polling errors set a `reconnecting` sync state with backoff (≤10 s) and a *Retry now* button; job status changes only from server responses. 404 and 401 handled separately. |
| S2 | C | Fixed | `scraper_provider.dart:38-105` | Current job lived only in browser memory; never re-read after refresh/navigation. → Running job vanished from the live view after a refresh. | Active job id persisted; `GET /api/jobs/active` (new) reattaches on sign-in/refresh; Home switches to the live job automatically. |
| S3 | C | Fixed | `backend/main.py:3604-3699`, `235-262` | Credit check, debit, job insert, ledger insert and ledger→job link ran on 5-6 separate connections; read-modify-write balance (`max(0, cur-amount)`). → Double-spend under concurrency; a retried request after an uncertain response created and charged a second job. | `job_service.create_job_atomic`: one transaction, user row locked (`FOR UPDATE` / `BEGIN IMMEDIATE`), conditional debit, limits checked under the lock. `Idempotency-Key` header: retries return the original job, never charge twice. Client retries with the same key and reattaches if still unsure. |
| S4 | C | Fixed | `main.py:349-375` (startup), `468-517` (watchdog), `3678` | Scraping ran in `BackgroundTasks` in the API process; any restart marked every running job **failed** (credits kept); watchdog failed any job older than 2 h even when healthy. | DB-backed runner (`job_runner.py`): atomic claim, worker lease + heartbeat, stale jobs requeued and **resumed from the last completed city**; max attempts / max hours then fail + refund. `JOB_RUNNER_MODE=external` + `job_worker.py` moves scraping out of the API process. |
| S5 | H | Fixed | `home_screen.dart:982-1004`, `:156`, `:293`; `scraping_screen.dart:105`, `:391-412` | Desktop tabs were rebuilt on every switch and the mobile/desktop trees swap at 768 px; the screen re-initialised with `initialCategory: ''` while cities were re-passed, and the draft restore was skipped whenever cities were present. → **Category text disappeared** (placeholder "Software Companies" shown while an `ecommerce` job ran). | Desktop tabs kept alive (lazy `IndexedStack`); form state survives widget recreation; draft restore fills whichever field is empty; an attached job fills an empty form with its own category/cities. Verified in a browser across the breakpoint. |
| S6 | H | Fixed | `home_screen.dart:110-134`, `scraping_screen.dart:244-260`, `wallet_screen.dart` | Three independent balance copies; none updated on job charge or refund. → Top bar showed 1150 while DB had 690. | `CreditProvider` single source; set from the create response, refreshed on job settle, wallet load and refresh. |
| S7 | H | Fixed | `main.py:3640-3648`, `scraper_provider.dart:86`, `scraping_screen.dart:2568-2570` | Naive server timestamps (UTC container) parsed as browser-local. → Elapsed time ~5 h too high in Pakistan; same shift in History/Admin/Wallet times. | API returns explicit UTC (`…Z`) plus `server_time`; client uses UTC instants and the server clock offset; one `parseServerTime` helper used in History, Admin, Admin Jobs, Dashboard, Wallet. |
| S8 | H | Fixed | `main.py:3308` | Progress `(idx+1)/n` written **before** scraping a city; 100 % during the last city. | Progress = completed cities + fraction of current city, capped at 99 until completed. |
| S9 | H | Fixed | `scraper_provider.dart:80-100`, `main.py:3324-3435` | Create response logs discarded; only city-level logs stored. → Activity log showed 0 entries while working. | Initial logs persisted at creation and shown immediately; one log line per lead; resume/timeout/refund lines. |
| S10 | H | Fixed | `main.py:3820-3880` | Every 2 s poll returned all results and all logs. | `include_results=false` + `logs_after=<cursor>` (default stays backward compatible); full results fetched once at the end. |
| S11 | H | Fixed | `main.py:3311-3339`, `3702-3770`; `scraping_screen.dart:2361` | Cancellation checked only between cities (up to 3 min more scraping); no refund anywhere; cancel button hidden once UI wrongly said Failed. | Stop checked between businesses and on heartbeat; worker writes guarded by ownership; cancel of a pending job settles immediately; button follows server state. E2E: no writes after cancel. |
| S12 | H | Fixed | (no refund path existed) | Failed / cancelled / empty jobs kept the full charge. | Exactly-once settlement guarded by `jobs.settled_at`; ledger `refund` row. Policy `JOB_REFUND_POLICY` (default `delivered`: pay base + per attempted city + per delivered lead, nothing if zero leads; `unattempted`; `none`). **Product decision — see §4.** |
| S13 | H | Fixed | `main.py:3343-3381` | City timeout dropped everything found in that city and the job still reported plain success. | Leads persisted as found (kept on timeout); `failed_cities` counted, shown, logged; all cities failing with 0 leads → `failed` + full refund. |
| S14 | M | Fixed | `main.py:3084-3097`, `3380-3425` | De-dup only within one city's link list. → 38 rows / 35 unique in the live job. | `results.dedupe_key` (Maps feature/place id, else name+coords, else name/address/phone) unique per job; known businesses skipped before visiting. |
| S15 | M | Fixed | `scraping_screen.dart:2572-2579` | Completed-city count derived by string-matching `currentCity` against user input. | Server `completed_cities`. City list shows *Done / Scraping…* until per-city counts load. |
| S16 | M | Fixed | `main.py:3719`, `3790` | `current_user.get("is_admin") is not True` — admins could not cancel/delete others' jobs. | Role-based check. |
| S17 | M | Fixed | `main.py:172` (`ensure_default_admin_settings`) | Settings attributed to user id 1 → FK violation → **API fails to start on a fresh DB with `DISABLE_DEFAULT_ADMIN=true`** (found by E2E). | Bootstrap rows use `NULL`. |
| S18 | M | Fixed | `scraping_screen.dart:169-199` | Job listener never removed (leak, calls after dispose). | Removed in `dispose`. |
| S19 | L | Open | `main.py:3038-3200` | Category/location relevance of scraped places not validated; completeness (phone/web/email) not reported. | Needs a sample-based accuracy review; consider per-result completeness flags. |
| S20 | L | Hypothesis | — | Exact first network error in the original browser session (status/proxy) was never captured. | No longer matters for correctness: any client error is now non-terminal. |

### 1.2 Other pages

| # | Sev | Status | Where | Issue | Fix |
|---|---|---|---|---|---|
| P1 | H | Fixed | `auth_provider.dart:28-46` | Any error while restoring the session (incl. network) deleted the token → users logged out on a flaky refresh. | Retries; token cleared only on 401/403. |
| P2 | M | Fixed | `job_history_screen.dart`, `dashboard_screen.dart`, `results_screen.dart` | Lists loaded once; running jobs went stale; a failed reload replaced the list with an error. (Keeping tabs alive would also have stopped the old "reload on revisit".) | `RefreshBus`: reload on tab visit and job create/finish; History polls every 10 s while jobs are active; last good list kept on transient errors. |
| P3 | M | Fixed | `home_screen.dart:293-326` | Entering the mobile layout reopened the PageView at Cities, hiding the current tab (e.g. the running job). | Current tab restored after the switch. |
| P4 | M | Fixed | `sidebar_navigation.dart:324` | Collapsed rail (tablet) overflowed by 19 px. | Compact spacing when collapsed. |
| P5 | M | Fixed | `api_service.dart` `getUserJobs`, `getCreditBalance` | No timeouts → spinners forever on a dead connection. | 30 s timeouts. |
| P6 | M | Fixed | `frontend/build_web.sh/.bat` | Incremental `flutter build web` intermittently reported success with no asset manifests → blank app (reproduced twice). | Scripts fail if `main.dart.js`, `AssetManifest.bin.json` or `FontManifest.json` is missing. |
| P7 | L | Open | `frontend/lib/config/environment.dart:22-24` | Debug builds without `API_URL` default to `http://localhost:8001` — the **live** backend's port on this machine. | Always pass `--dart-define=API_URL=…` for local runs. |
| P8 | L | Open | 50 analyzer infos/warnings (unused code, `print`, async context use) in admin/wallet screens | Cosmetic. | Clean up separately. |

### 1.3 Deep-audit findings re-verified (`CLAUDE_DEEP_AUDIT.md`)

| ID | Status now | Notes |
|---|---|---|
| C-1 debug user dump | **Fixed** | Route removed; `/docs`, `/redoc`, `/openapi.json` only when `DEBUG`; `debug=False`. |
| C-2 default admin | **Fixed** | No built-in password (needs 12+ char `DEFAULT_ADMIN_PASSWORD`), never promotes an existing account, creates `owner`; credential removed from scripts, AGENTS.md, `.env.example`, local compose. **Rotate the live admin password anyway.** |
| C-3 reset token in logs | Fixed earlier (baseline) | Email via SMTP; 503 when SMTP unset. Token lifetime still 24 h; reset does not revoke JWTs (M-9). |
| C-4 support → owner | **Fixed** | Role changes owner-only (baseline); now all 24 mutating `/api/admin/*` routes require admin; `support` no longer gets `is_admin=1`. |
| H-1 negative cost | Fixed | Pydantic bounds (baseline) + clamped cost + per-city length check. |
| H-2 subscription IDOR | Fixed earlier (baseline) | — |
| H-3 no refunds | **Fixed** | S12. |
| H-4 webhook retries | **Fixed** | Idempotent ingestion (`begin_webhook_event`); processed redelivery acknowledged without re-processing; failed events retry on the same row. |
| H-5 password policy, H-6 XFF lockout bypass | Open | — |
| H-7 email templates gitignored | Open | `*.html` still ignored; templates must be force-added before a clean-clone build sends email. |
| H-8 migrations swallow failure | **Fixed** | Failure raises (startup stops); duplicate column/index errors tolerated so a partial MySQL run can be re-applied. Checksums still not validated. |
| H-9 SQLite-only SQL on MySQL purchase path | **Fixed** (pricing) / Open (`event_queries.py` `CAST(... AS TEXT)`) | — |
| H-10 prod on a workstation | Open | Architecture/ops decision. |
| M-1 credit race | **Fixed** | S3; `add_credits`/`deduct_credits` atomic single-statement updates with ledger in the same transaction. |
| M-3 tests can hit real DB | **Fixed** | DB URL resolved lazily; session-wide guard; the one test without a fixture fixed (it was creating `backend/scraper.db`). |
| M-2, M-6–M-10, M-13–M-17, M-19, M-20, L-1–L-4 | Open | Not changed in this branch. M-19 (Coinbase `charge:resolved` credits full amount when underpaid) needs a review state in the schema. |
| HYP-1 `UPDATE … ORDER BY LIMIT` | Removed | The statement no longer exists (ledger row written with the job id in the same transaction). |

---

## 2. Changes (commits on `fix/job-durability-audit`)

1. `1434809` baseline — carried the uncommitted security fixes and local-run docs from the main checkout.
2. `f80eb94` durable/resumable/idempotent jobs, atomic credits, migration 014, status API, runner + standalone worker.
3. `15e04e8` web: server-truth job state, CreditProvider, form persistence, UTC parsing, refresh bus, auth retry, sidebar.
4. `e062af2` fresh-DB startup crash, auto-reattach to live job, mobile tab restore, backoff cap, build guard.
5. `13ed464` test isolation guard.
6. `ac9c3da` admin/payment security (C-1, C-2, C-4, H-4, H-9).
7. `18868ce` migration 014 marks historical terminal jobs settled (prevents **retroactive mass refunds** on first start).

New backend files: `job_service.py`, `job_runner.py`, `job_worker.py`, `migrations/014_job_durability*.sql`.
New API: `GET /api/jobs/active`; `POST /api/jobs` accepts `Idempotency-Key`; `GET /api/jobs/{id}` accepts `include_results`, `logs_after`.
New env (all optional): `JOB_RUNNER_MODE` (`inprocess`|`external`|`off`), `JOB_WORKER_CONCURRENCY` (2), `JOB_STALE_SECONDS` (120), `JOB_HEARTBEAT_SECONDS` (20), `JOB_MAX_ATTEMPTS` (3), `JOB_MAX_HOURS` (12), `JOB_CITY_TIMEOUT_SECONDS` (180), `JOB_REFUND_POLICY` (default `none` since round 2 — set it explicitly), `LOGIN_EDGE_MAX_ATTEMPTS` (60). Required: `SECRET_KEY` (≥16 chars, not a placeholder) — the app refuses to start without it.
Removed env: `JOB_WATCHDOG_HOURS`, `JOB_WATCHDOG_INTERVAL_SECS` (replaced by heartbeat recovery).

---

## 3. Test results (final run)

| Suite | Result |
|---|---|
| Backend `pytest tests` (temp SQLite) | **64 passed** (baseline: 21 passed, 1 failed, 10 errors — all from broken test isolation) |
| Flutter `flutter test` | **11 passed** (baseline smoke test failed) |
| Flutter `flutter analyze` | **0 errors**; 50 pre-existing warnings/infos |
| `flutter build web --release` | Succeeds; output verified complete |
| HTTP E2E (real uvicorn, kill -9 mid-job, restart) | **24/24**: idempotent retry charged once; job stays `running` after crash; resumes on attempt 2 from city 2 keeping 3 pre-crash leads; 10/10 unique leads, no duplicates; UTC times; settled once; ledger == balance; cancel stops writes and refunds 11/26 |
| Browser E2E (Playwright + built app) | **15/15**: boots signed in; reattaches after refresh and opens the live job; light polling; 12 s network cut → *Connection problem*, never *Failed*, keeps retrying, cancel visible; recovers to *Completed*, fetches results once; mobile↔desktop keeps the job panel and the typed category (category persistence verified by screenshot) |

The E2E runs use a deterministic fake scraper (no Google traffic). **Not tested:** real Google Maps scraping with Playwright, and MySQL (Docker was down for the whole session).

---

## 4. Remaining risks

1. **MySQL not exercised.** Migration 014 and the locking/`INSERT IGNORE`/`FOR UPDATE` paths were reviewed but only run on SQLite. Run §5 step 2 before release.
2. **Refund policy changes revenue.** Default `delivered` refunds undelivered results on every job (e.g. a 460-credit job that delivers 38 leads over 4 cities refunds ~392). Choose `JOB_REFUND_POLICY` deliberately; `unattempted` is closer to the old billing, `none` restores it.
3. **Leaked secrets in git history.** The Cloudflare tunnel token was committed (`docker-compose.yml` at `f60ec53`); the default admin password was public. Rotate both.
4. **Single process.** In-process mode still scrapes inside the API container (now resumable). For isolation run `JOB_RUNNER_MODE=external` and one or more `python job_worker.py` containers.
5. **Docker was down during this session**, so the live backend/tunnel were likely offline; the old image's startup recovery will mark any interrupted job `failed` with no refund. Those jobs can be refunded manually (ledger `refund` row + balance) — the new code does not refund pre-014 jobs.
6. Open audit items in §1.3 (password policy, XFF lockout bypass, email templates, JWT revocation, CI not running tests, promo reservation, Coinbase underpayment).

---

## 5. Releasing safely

1. **Back up MySQL** (`mysqldump --single-transaction`) and keep the current image tag for rollback.
2. **Rehearse on a copy:** restore the dump into a throwaway MySQL 8 (e.g. `docker run -p 13306:3306 mysql:8.0`), point `DATABASE_URL` at it, run `python -c "from database import init_database; init_database()"` from `backend/`. Verify `schema_migrations` has `014`, no error, and `SELECT COUNT(*) FROM jobs WHERE settled_at='pre-014'` equals the number of finished jobs. Run `pytest` with that `DATABASE_URL` only if you accept test rows in the copy.
3. Rotate the Cloudflare tunnel token and the admin password; confirm `DISABLE_DEFAULT_ADMIN=true` and `SECRET_KEY` are set in `backend/.env`. Set `JOB_REFUND_POLICY`.
4. **Deploy the backend first** (it is backward compatible with the current Vercel frontend; the new frontend is *not* compatible with the old backend because the old backend ignores `logs_after`). Merge the branch, then `docker compose --env-file backend/.env -f docker-compose.worker.yml up -d --build backend` at a quiet time. The migration runs on start; a running job is requeued and resumed within ~2 minutes.
5. Smoke test: `/api/health`; sign in; start a 1-city, 3-result job; watch it complete; check the balance badge, History, and the credit ledger; cancel a second job and confirm the refund; restart the backend container mid-job and confirm it resumes.
6. **Then deploy the frontend:** `cd frontend && ./build_web.sh` (or the Vercel build) — the script now refuses an incomplete bundle. Verify on desktop and phone widths.
7. Rollback: redeploy the previous image (migration 014 only adds columns; old code ignores them) and the previous frontend. Do not drop the new columns.
8. Follow-ups: add a MySQL leg and `pytest`/`flutter test` to CI; consider external workers; address §1.3 open items.
