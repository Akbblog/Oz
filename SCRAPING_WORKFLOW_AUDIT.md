# Scraping workflow audit — 2026-11-16

Scope: the live job shown by the user, plus a read-only trace of the Flutter search screen, API, scraper, MySQL job state, logs, results, cancellation, and credits. **No product behavior was changed during this audit.** The job was left running.

## What happened in the live job

The UI showed **Failed**, 0%, 0 logs, 0 leads, and all cities pending. At the same time, MySQL showed the same job **running**, progressing through Qatar cities and persisting results and job logs. A later read found 16% progress and 38 result rows. Direct reads of `/api/jobs/{id}` through both localhost and the live frontend proxy returned 200 with the actual progress, results, and logs. The backend container continued scraping. This is a client/server state divergence, not a failed scrape.

The job stored category `ecommerce`, 30 cities, 10 results per city, and a 460-credit charge. The screen displayed `Software Companies` after the category field became empty; that text is the field's placeholder (`frontend/lib/screens/scraping_screen.dart:1129`), not the submitted category. The database balance was 690 while the page's top badge still showed 1150.

Eight additional read-only status requests through the Vercel proxy all returned 200, but latency ranged from 1.94 to 9.53 seconds. The browser's original failed request was not captured, so its immediate network/proxy error remains unproven.

## Critical findings

1. **A single status request failure permanently marks a running job as failed in the frontend.** `ScraperProvider._pollJobStatus` catches any request or parsing exception, sets both local job status and provider status to `failed`, and exits the polling loop (`frontend/lib/providers/scraper_provider.dart:107-145`). It does not verify backend state, retry, or reconnect. The live backend remained `running`. The exact browser-side failure (HTTP status, timeout, or parse error) was not captured, but no browser status polls for this job reached the backend; the two logged GETs were read-only audit probes. This is the direct explanation for the observed false Failed state.

2. **The UI hides the cause and prevents recovery.** The provider records `job.error`, but `ScrapingScreen` never renders it. Once local status is `failed`, polling stops and the cancel button is hidden because it is shown only for a locally running job (`frontend/lib/screens/scraping_screen.dart:2320-2374`). The Review & Start action becomes available again while the real job continues, creating a risk of a second charge and duplicate job.

3. **Job creation has no idempotency or atomic credit transaction.** The API deducts credits, then inserts the job in separate database operations (`backend/main.py:3610-3665`). A retry after an uncertain response can create and charge a second job. `deduct_credits` reads and updates balance in a separate connection, then writes the ledger in another (`backend/main.py:237-261`), so concurrent requests can race or leave billing and job state inconsistent.

4. **The worker lives inside the API process and cannot recover a running job.** `BackgroundTasks.add_task(run_scraping_job, ...)` starts scraping in the FastAPI process (`backend/main.py:3670-3685`). Startup marks all pending/running jobs failed instead of resuming them (`backend/main.py:340-379`). A Docker Desktop stop, host sleep, deploy, or process restart can lose work after the full charge. This setup also makes multiple API replicas unsafe for active jobs.

## High-priority UX and correctness findings

5. **The category field can lose the submitted value.** The screen controller is initialized from `widget.initialCategory` (`frontend/lib/screens/scraping_screen.dart:105`), but `HomeScreen` sets that initial category to empty when entering search (`frontend/lib/screens/home_screen.dart:154-160`). A recreated search screen also skips draft restoration when initial cities are present (`frontend/lib/screens/scraping_screen.dart:396-411`). No code directly clears the category on job start; the precise recreation event in the user's browser still needs a UI trace. The observed outcome is that the form displays its placeholder while the backend job retains `ecommerce`.

6. **Credit displays disagree after submission.** The API charged 460 credits, leaving 690 in MySQL, while the top badge displayed 1150. `HomeScreen` loads its balance on entry/authentication or after visiting the wallet, but does not subscribe to job charges (`frontend/lib/screens/home_screen.dart:96-129, 190-195`). Search and header maintain separate balances.

7. **Elapsed time is about five hours too high in Pakistan.** Backend job timestamps are naive `datetime.now().isoformat()` values from a UTC Linux container (`backend/main.py:3640-3648`); Flutter parses them without a timezone and subtracts them from the browser's local `DateTime.now()` (`frontend/lib/providers/scraper_provider.dart:86`, `frontend/lib/screens/scraping_screen.dart:2565-2572`). The screenshot showed about 5h elapsed minutes after job creation.

8. **Progress reports a city before its scraping finishes.** The backend sets `(idx + 1) / total * 100` before calling `scrape_location` (`backend/main.py:3307-3345`). Thus 3% appears at the beginning of city 1 and 100% can appear while the final city is still processing. The browser then derives completed city count from `currentCity`, which can disagree with the percentage (`frontend/lib/screens/scraping_screen.dart:2565-2607`).

9. **Initial activity logs are discarded, and business-level progress never reaches the UI.** The create-job response contains two initial log messages (`backend/main.py:3690-3702`), but the provider creates `ScrapingJob` with its default empty `logs` and waits for polling (`frontend/lib/providers/scraper_provider.dart:80-100`). The backend emits per-business messages to container logs, while `job_logs` gets mainly city-level entries (`backend/main.py:3324-3338, 3395-3435`). The activity panel can therefore show 0 entries while work is active.

10. **Every two-second status poll transfers the full result set and all logs.** `GET /api/jobs/{id}` queries every result row and log (`backend/main.py:3820-3880`); the provider polls every two seconds (`frontend/lib/providers/scraper_provider.dart:107-145`). Payload size and database load grow with the job. A single slow or failed poll triggers finding 1.

11. **The current job is only in browser memory.** `ScraperProvider` initializes with no job and only checks API health (`frontend/lib/providers/scraper_provider.dart:38-68`); it never reattaches to a running job from `/api/jobs` after refresh or navigation. The history page may show the job, but the live activity view loses its connection and controls.

12. **Cancellation is delayed and does not settle credits.** The API marks a job cancelled immediately, but the scraper checks status only before the next city and again at the end (`backend/main.py:3311-3339, 3430-3465, 3700-3768`). It can continue the current city for up to three minutes and persist more results. No job failure/cancel refund path appears in `backend/main.py`; credits are charged up front. The UI's false Failed state removes its cancel button (finding 2).

13. **A timed-out city is silently skipped but the job can finish as successful.** Each city has a 180-second timeout; timeout becomes an empty result list and the loop proceeds (`backend/main.py:3343-3375`). There is no partial-completion status or per-city credit adjustment.

14. **Duplicate leads are persisted across cities.** The scraper deduplicates Maps URLs only within one city's link list (`backend/main.py:3070-3095`), then inserts every city's results (`backend/main.py:3380-3425`). During this job, 38 result rows had only 35 distinct Maps URLs. There is no cross-city job-level uniqueness rule.

15. **Lead completeness is variable and not reported.** At 30 result rows, 10 had no phone, 10 had no website, and 22 had no email. Missing contact data may reflect source availability, but users are charged for result targets without a visible completeness measure. The scraper does not validate category relevance or location after opening a Maps business page (`backend/main.py:3038-3200`). Relevance requires a sample-based accuracy review.

## Evidence still needed before implementation

- Browser Network record for the first failed `GET /api/jobs/{id}`: response status, timing, and any proxy error. This identifies the immediate trigger; the frontend's terminal handling of one failure is already confirmed.
- Reproduction of the category field reset with viewport changes, navigation, and refresh to pinpoint the exact widget recreation event.
- One complete job run to verify final status, export, billing settlement, and whether duplicate URLs persist in the final result set.
- Simulated process restart and cancellation on an isolated database to quantify lost work and credit behavior without interrupting this live job.

## Fix order after review

1. Make job creation return a durable job ID quickly and idempotently; charge and create in one transaction.
2. Treat network polling errors as connection problems, not job failure; retry and reattach by job ID after refresh.
3. Separate scraper execution from API process with a durable queue and restart/resume semantics.
4. Keep form and job details visible, surface the actual error, and refresh credit balance from one source.
5. Correct timezone, progress, logs, cancellation, refunds, deduplication, and result-quality reporting.
