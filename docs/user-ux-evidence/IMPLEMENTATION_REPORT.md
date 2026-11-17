# User UX redesign — implementation report (branch `feat/user-ux-redesign`)

Base: `fix/job-durability-audit` @ `42603b7`. Implements USER_UX_AUDIT_PLAN.md P0 + P1 with owner decisions D1–D7
(approved 2026-11-17). **Not merged, not deployed.** Screenshots: `docs/user-ux-evidence/implemented/`.

## 1. Commits

| Commit | Scope |
|---|---|
| `833a5ca` | Approved plan, audit evidence, mockups |
| `69d1ca9` | API: paged job list + counts + derived country/region; partial downloads; formula-safe xlsx; refund policy + min cost in config; curated locations |
| `de82cb9` | Web: routes, new shell/navigation, live-search chip/banner, SearchSetupProvider, ActiveSearchesProvider, Home |
| `488565e` | API: `/api/locations/summary` (region term + counts) |
| `3f35e31` | Web: Find leads two-step setup (location picker, details & start); old Cities/Search screens removed |
| `7ac5722` | Web: search page (progress + results), My searches, results fixes, safe CSV/downloads, credit history, profile cleanup, concurrent searches allowed |
| `b3f1ccb` | Fixes from the browser walk-through (history UTC times, login Enter/label, top bar, Home live rows) |
| `43109fc` | API: explicit UTC in `GET /api/admin/jobs` (regression from the shared job card) |

## 2. Tests and checks (all run on this branch)

| Check | Result |
|---|---|
| Backend `pytest` (SQLite, full suite) | **132 passed** (was 95 before the branch; +37 incl. `tests/test_user_ux_api.py`) |
| Flutter `flutter test` | **75 passed** (new: search setup provider, find flow, search pages, shell/router) |
| `flutter analyze` | 48 issues — **all pre-existing** (admin, wallet, simple_buy, atlassian_shadows); none in new/changed files |
| `build_web.sh` (release, bundle completeness check) | passed |
| MySQL/MariaDB | **not run** for this branch (Docker not used); new SQL is portable (`LIMIT/OFFSET`, `COUNT`, `CASE`) |

## 3. Browser walk-throughs (isolated SQLite backend + fake scraper; never the live system)

Widths: **1440, 1024 (tablet), 820 (tablet), 430, 390, 360**. Real Chromium via Playwright, release build.

| Flow | 1440 | 1024 | 820 | 430 | 390 | 360 |
|---|---|---|---|---|---|---|
| Home (first visit / with history / live search) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Countries → regions → cities (split panel / phone drill-down via URL) | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| "Select N shown" keeps earlier picks (2 + 4 = 6) | ✓ | — | — | — | — | — |
| Region switch asks first; Stay keeps cities | ✓ | — | — | — | — | — |
| Details & start: cost breakdown, policy sentence, sticky start bar on phones | ✓ | — | ✓ | ✓ | ✓ | ✓ |
| Start → search page; live chip (≥768) / banner (phone) on other pages | ✓ | — | ✓ | ✓ | ✓ | ✓ |
| Reload during a running search stays on `/searches/<id>` | ✓ | — | — | — | ✓ | — |
| Cold deep link to `/searches/<id>`; browser Back | ✓ | — | — | ✓ | ✓ | ✓ |
| Completed search: Excel download opened with openpyxl, rows = saved leads | ✓ (8 = 8) | — | — | — | — | — |
| Cancel → Cancelled (grey) + partial Excel = saved leads | ✓ (10 = 10) | — | — | — | — | — |
| Failed search: plain reason + refund line (30 charged, 30 returned) | ✓ | — | — | — | — | — |
| Session expired → "Sign in" → login → back on the same search, polling resumes | ✓ | — | — | — | — | — |
| Low credits (12): Home message, Start disabled with reason, Get credits | ✓ | — | — | — | — | — |
| My searches tabs/counts, Credits history, Account (no fake badges) | ✓ | ✓ | ✓ | — | ✓ | ✓ |
| Admin "All jobs" + "View results" still work; times correct | ✓ | — | — | — | — | — |

**Credits verified against the database** (delivered policy): e.g. 4 cities × 10, 15 leads → charged 70, returned 25,
ledger −70/+25, balance 500 → 455, UI "45 (25 returned)"; cancelled search charged 85 / returned 50 = UI line;
failed search 30 / 30. Backend integration test covers cancel-with-leads settlement + partial download.

## 4. Capability-preservation matrix (plan §7) — status

Kept or moved: rows 1–39, 41, 42. Notable moves: free-text cities → "Add a city not listed" (validated); logs (search,
filters, auto-scroll, copy, export) → "Technical log" on the search page; completion stats → search summary;
results (filters, sort, cards/table, bulk CSV/JSON, lead actions) → embedded on the search page (bulk export now at
all widths); History details panel (≥1440) → replaced by the search page; wallet/profile embedded in the shell.
Intentionally removed (approved): 40 mobile swipe (D7), 43 Include Suburbs (D2), 44 API Status card.

## 5. Deviations from the plan (deliberate)

- **Condition 3:** all speculative copy dropped — no "about N cities", ETAs, "usually starts within a minute",
  duration predictions. Home shows the factual minimum cost instead.
- A new search may start while another runs (backend limit of 2 applies and its message is shown).
- Curation: Finland — 65 former municipalities removed (many are still real towns; restorable one line each, see
  `backend/data/CURATION.md`); Qatar "Doha" — 22 real neighbourhoods were hidden by a duplicate key and are now
  listed; UK/Indonesia entries normalised to "Name, Region" (same strings the app already sent).
- Login: Enter submits; "Remember me for 30 days" → "Keep me signed in" (tokens last 7 days).

## 6. Shared code touching admin (condition 6) — flagged

- `GET /api/admin/jobs`: timestamps now explicit UTC (formatting only). No permission/role code changed.
- `ResultsScreen` and `JobCompletionCard` are reused by the admin "All jobs" screen; re-verified in the browser.
- **Not addressed here:** the two live admin permission bugs (A1 role rewrite on profile save, A2 admin can delete an
  owner). No code they depend on was changed. They remain urgent and should be fixed on their own branch.

## 7. Known issues / remaining risks

1. **Accessibility-mode typing (needs real screen-reader QA):** with Flutter semantics enabled, after reaching the city
   list by tapping (stacked `/find` routes) *and* ticking a checkbox, typed text in the city search may not register.
   Not reproducible with semantics off, via deep link, or without ticking first. Likely a Flutter web semantics quirk.
2. Phone city header truncates ("Canada · ste…") at 360 px; My searches tabs scroll horizontally on phones.
3. Home "This month" line can lag behind a running search's live counts until the next list refresh.
4. Android Excel download ("corrupted file") fixed at the suspected causes (delayed object-URL revoke, text cells,
   sanitised titles) but **not tested on a real Android device**.
5. Vercel: if the repo is Git-connected, pushing this branch may create a **preview** deployment automatically.
6. MySQL/MariaDB not exercised for the new queries; CI MariaDB leg will run them once CI runs.
7. Fake scraper only — real Google Maps timing and fill rates not exercised on this branch.

## 8. Manual QA for the owner (≈ 30 min, on a staging copy)

1. Desktop: Find leads → Canada → Quebec → tick 2 → search "saint" → "Select 4 shown" → expect 6 selected.
2. Switch to Ontario → dialog → Stay; then Switch and remove → selection cleared.
3. Details: check the cost lines and the refund sentence match your configured `JOB_REFUND_POLICY`.
4. Start a real 2-city search → search page → Home shows chip + Running now → reload → still on the search.
5. Cancel a running search → Cancelled + refund line → Download Excel opens (desktop Excel **and Android**).
6. Phone (real device, 360–430 px): full journey; Back between country/region/city levels; sticky bars visible.
7. Let your session expire during a search (or sign out in another tab) → "Sign in" → returns to the search.
8. A 12-credit account: Home warning, Start disabled with reason, Get credits opens Credits.
9. Credits page: history shows charges and refunds with correct local times.
10. Screen reader (NVDA/VoiceOver): complete one search; check known issue 1.
11. Admin: All jobs list times and View results.
