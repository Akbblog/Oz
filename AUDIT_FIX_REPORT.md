# Infinity Leads — audit, fixes and release plan (2026-11-16)

Branch `fix/job-durability-audit` (git worktree `F:\webTest\scraper\il-fix-worktree`), based on
`f60ec53` plus the uncommitted security fixes that were in the main checkout (commit `1434809`).
Nothing was deployed. The live checkout, its containers, the Cloudflare tunnel, the live MySQL
database and `.env` were not read or modified. All testing used temporary SQLite files and
ports 8098/8099.

Line numbers in the inventory refer to the **baseline** (`1434809`) unless marked "now".

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
New env (all optional): `JOB_RUNNER_MODE` (`inprocess`|`external`|`off`), `JOB_WORKER_CONCURRENCY` (2), `JOB_STALE_SECONDS` (120), `JOB_HEARTBEAT_SECONDS` (20), `JOB_MAX_ATTEMPTS` (3), `JOB_MAX_HOURS` (12), `JOB_CITY_TIMEOUT_SECONDS` (180), `JOB_REFUND_POLICY` (`delivered`).
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
