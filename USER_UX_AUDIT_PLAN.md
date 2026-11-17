# Infinity Leads — User Experience Audit & Redesign Plan

**Status: proposal for approval. Nothing has been implemented, committed, deployed or changed.**
Written 2026-11-17 against branch `fix/job-durability-audit` (head `42603b7`). Companion to `ADMIN_UX_PLAN.md`
(shared visual language; that file was not edited). Evidence and mockups: `docs/user-ux-evidence/`.

---

## 0. Method, evidence and limits

| Source | What it covered |
|---|---|
| Code | Every user-facing screen and widget: `home_screen`, `dashboard_screen`, `state_selection_screen` (2,189 lines), `scraping_screen` (3,365), `results_screen`, `job_history_screen`, wallet/profile entry points, `scraper_provider`, `credit_provider`, `api_service`, plus the backend handlers they call (`/api/countries`, `/api/states`, `/api/jobs*`, `/api/credits/*`). Two read-only subagents produced line-level inventories; every high-impact claim used below was re-checked by hand. |
| Browser | The current branch head was built and served against an **isolated** backend (SQLite, fake scraper returning 0–6 leads per city, test accounts with 500, 4,200 and 12 credits). Playwright walked the full journey at **1440, 1024, 820, 430, 390 and 360 px**: Home → country → region → cities → filter/select-all → change region → criteria → review → start → running → reload mid-job → completion → results → History, plus a low-credit user. 27 screenshots are in `docs/user-ux-evidence/current/`. No live service, data or credential was touched. |
| Data | Counted the backend location files: USA 50 states / 9,555 cities (largest state 201), Canada 13 × 30, India 34 regions / 1,020, Qatar 8 × 30 (many are landmarks, e.g. "Hamad International Airport, Doha"), Singapore 1 region. |
| Accessibility | WCAG 2.2 AA. Contrast **computed** from hex values; semantics/roles read from Flutter's web semantics tree; keyboard behaviour inferred from code (no screen-reader session was run). |
| Skills/tools | `dataviz` skill principles (stat tiles vs charts, status colour + icon + label), Playwright, a WCAG contrast script, two `general-purpose` inventory subagents. |

**Limits — read before approving**
1. **No screenshots came with your messages.** The "supplied screenshots" you refer to never arrived in this conversation (the only image in the repo is a February Android photo of a "corrupted" spreadsheet). The visual evidence is from the current branch build. Production may differ where code changed since the deployed build; where that matters it is marked *needs testing*.
2. Real Google Maps behaviour (lead counts, timings) was not exercised here; the fake scraper only reproduces the UI states.
3. Not tested in a browser: Android download of the Excel file, a real screen reader, iOS Safari, browser-back on pushed screens, two jobs running at once.

**Confidence labels**: **C-code** (provable from source), **C-visual** (reproduced in the browser run), **Needs test** (plausible, unproven).

---

## 1. What a user experiences today (summary)

- **The main action has three names and no home.** Desktop calls it "Cities", tablet shows an unlabelled building icon, phones call it "New". Home has no primary "start" button for anyone who already has a job.
- **Home shows four large, bright lifetime counters** (Credits, Total Jobs + "1 done", Completed, Running) and a "Recent Activity" list of raw UUIDs with *gross* credits; refunds are invisible (Home said "40 credits" for a job that cost 27).
- **The location picker fights the user.** 170 px country tiles; on a 1440 px screen Quebec's 30 cities are 178 px-tall cards in **one column** (≈5,600 px of scrolling) with Continue at the very bottom; a filtered "Select All" **replaces** earlier picks; "Change region" **silently wipes** the selected cities; region badges are wrong ("NO" Nova Scotia, "NE" for both New Brunswick and Newfoundland).
- **Two percentage bars** show "0%" and "67%" at once and reach **100% before the search is even configured**.
- **Criteria accept impossible input**: the leads-per-city slider goes to 500, the backend caps at 100; above 100 the cost shows "—" and starting fails with raw JSON.
- **After Start on a phone, progress is below the fold**; the job page is a log console. Completion time shows in **UTC** on the card but **local** in History (08:00 vs 13:00 for the same job).
- **Results are a dead end.** Opening results pushes a full-screen page with no back button and, inside the app shell, no download. Cancelled/failed jobs promise "leads can be downloaded" but there is no button, and the backend refuses the export.
- **Low credits are discovered at the last step** as small red text with no way to get credits.

What already works well and must be kept: idempotent job creation with safe retry, reattach to a running job after refresh (C-visual), heartbeat-based elapsed time, cancel with confirmation, refund calculation and display when settled, location and search drafts, category suggestions, city chips with remove, log search/filter/copy/export, Excel download for completed jobs, guest exploration before sign-in.

---

## 2. Issue inventory

Severity: **Critical** = money or data wrong / user blocked with no workaround; **High** = user likely to fail, be misled or lose work; **Medium** = slows or confuses; **Low** = polish.

### 2.1 Navigation and information architecture

| ID | Sev | Issue | Evidence | Root cause | User impact | Recommendation | Conf. |
|---|---|---|---|---|---|---|---|
| N1 | High | Starting a search is called "Cities" (desktop), an unlabelled icon (tablet rail) and "New" (phone). The top-bar title reads "Cities" even on the criteria, progress and results steps. | `current/01,02,03`; `home_screen.dart:47-72, 744-788, 236` | Nav was built around the first wizard screen, not the task | Users don't recognise where to start or where they are | One task name everywhere: **Find leads** (§3) | C-visual |
| N2 | High | No way back to a running search on desktop/tablet except reloading the page from Home; no nav item points to the progress page. | `home_screen.dart:58-65, 114-121` | Progress lives on an unnamed tab (index 2) | User loses the job while it runs; thinks it vanished | Persistent "Searching…" chip in the top bar + a search detail page with its own URL | C-code |
| N3 | High | Results are reached three different ways; pushed results screens have **no shell and no back button**; the in-shell Results tab hides the **Excel** button; the post-completion "View Results" opens a page with no title, back or download. | `current/24,25`; `results_screen.dart:599, 637-679`; `scraping_screen.dart:252-255` | `showHeader:false` in the shell, header-only actions | Dead ends; users can't download from where they are | Results live inside the search detail page with the download as its primary action | C-visual |
| N4 | Medium | The URL never changes inside the journey; refreshing returns to Home; no shareable link to a search. | `main.dart`, `home_screen.dart` (IndexedStack/PageView) | Tabs instead of routes | Refresh loses context; no bookmarks | Routes: `/find`, `/find/details`, `/searches`, `/searches/<id>`, `/credits`, `/account` | C-visual |
| N5 | Low | Brand varies: "Leads Pro" (sidebar), "Leads v2.0" (phone), "v2.4.1" (activity panel). Notifications bell does nothing. | `current/01,03`; `top_bar.dart:77-81` | Leftovers | Looks unfinished | One wordmark; remove bell until notifications exist | C-code |

### 2.2 Home

| ID | Sev | Issue | Evidence | Root cause | Impact | Recommendation | Conf. |
|---|---|---|---|---|---|---|---|
| H1 | High | No primary action for a returning user; four large gradient tiles dominate. "Total Jobs" shows "1 done" which repeats "Completed"; "Running" excludes queued jobs; the Completed tile opens the *latest* job's results, not completed jobs. | `current/01-04`; `dashboard_screen.dart:286-323` | Dashboard built as a stats page | User doesn't know what to do next | Hero with **Find leads**; running card; one-line monthly summary (§6.1) | C-visual |
| H2 | High | "Recent Activity" rows show `Job <full UUID> · status · N credits`; no location, date or lead count; credits are **gross** (ignores refund); cancelled uses the failure icon; only completed rows have an action. | `current/01`; `dashboard_screen.dart:484-661` | Row template shows DB fields | Can't tell searches apart or what they cost | "Recent searches" rows: business type, location, date, leads, net credits, status, next action | C-visual |
| H3 | Medium | Tile colours fail contrast with white text: ochre 2.2–2.6:1, lavender 2.6–3.2:1, rose 2.9–3.8:1. | computed | Decorative gradients | Hard to read | Neutral surfaces; status colour only on badges | C-code |
| H4 | Medium | First-load error is invisible (fade only starts on success); Home fetches its own balance that can disagree with the pill; an unknown balance renders "0 Cr" in the low-balance style. | `dashboard_screen.dart:96-118`; `credit_provider.dart:148-150` | Separate fetches, optimistic defaults | False "0 credits" alarm; silent failures | One credit source; explicit loading/error states | C-code |

### 2.3 Location picker (country → region → cities)

| ID | Sev | Issue | Evidence | Root cause | Impact | Recommendation | Conf. |
|---|---|---|---|---|---|---|---|
| L1 | High | Country step: 15 countries as large empty tiles (2 × 170 px at 1024 px; 6 columns at 1440; 2 tall columns on phones). No search, no recents. | `current/05,06` | Grid aspect ratio tuned for marketing look | Slow scanning; most of the screen is empty | Compact searchable list/grid with recents and region counts | C-visual |
| L2 | High | Cities on desktop are **178 px-tall cards in one column** (two visible per screen); Quebec needs ≈5,600 px of scroll; **Continue/Save draft sit at y≈6,260** and are not sticky. | `current/08`; `state_selection_screen.dart:1505-1513, 1906-1996` | Grid aspect ratio on a narrow pane; footer in scroll content | Selections and the next step are lost while scrolling | Dense checkbox rows (44 px) in 1–3 columns + sticky selection bar | C-visual |
| L3 | High | **Filtered "Select All" replaces the selection** (Montreal + Quebec City selected → filter "saint" → Select All → 4 selected, the first two dropped). Un-ticking clears *everything*. The checkbox compares counts, not membership. | `current/09`; `state_selection_screen.dart:1456-1460, 1526-1527, 1582-1586` | `_selectedCities = List.from(_filteredCities)` | Users lose picks silently | "Select N shown" adds; "Clear shown" removes only shown; separate "Clear all" (§6.3) | C-visual |
| L4 | High | **"Change region" wipes selected cities immediately**, before a new region is chosen, without warning; tapping another region card also clears. | `current/10`; `state_selection_screen.dart:353-364, 1257-1264` | Single-region model | Lost work | Keep selections per region; ask before discarding (§6.3) | C-visual |
| L5 | High | "Include Suburbs — Expand search radius by 25 miles" (on by default) **does nothing**: never sent, not read by the backend. | `state_selection_screen.dart:40, 1742-1809`; backend query `f"{category} in {city}, {state}"` | Unfinished feature | Misleading promise | Remove (owner decision D2) | C-code |
| L6 | Medium | Region abbreviations are the first two letters (NO, NE×2, BR, AL, SA, YU); city counts appear only for the first five regions. | `current/07,10`; `state_selection_screen.dart:181, 301-315` | Derived codes; preload without rebuild | Confusing labels | Drop codes; show counts for all (data is already loaded by `/api/states`) | C-visual |
| L7 | Medium | On load error the picker silently falls back to a hard-coded country list and **fake US regions for any country**; city-load errors show raw exceptions. | `state_selection_screen.dart:196-236, 347-349` | Defensive fallback | User picks nonexistent places | Error state with Retry | C-code |
| L8 | Medium | Phone: city list is a 220 px box scrolling inside the page; selected cities are only a count; draft "Clear" deletes the stored draft but keeps the selection. | `current/12` | Nested scroll | Hard to use with a thumb | Full-height list with sticky bar and "Review list" sheet | C-visual |
| L9 | Medium | Location data quality: Qatar "cities" are districts/landmarks; Finland includes merged municipalities; 60+ duplicate strings; free-text entries without a comma are charged but skipped. | data count; `main.py:3422-3430` | Generated lists | Low fill rate (38 % in production) and wasted credits | Curate lists; dedupe; validate free text (D6) | C-code; impact needs test |

### 2.4 Setup progress vs job progress

| ID | Sev | Issue | Evidence | Root cause | Impact | Recommendation | Conf. |
|---|---|---|---|---|---|---|---|
| P1 | High | The location screen shows a 4-step stepper **and** a percentage bar: "0%" and "67%" at once; the bar hits **100% once a city is ticked**, before criteria. The stepper disappears on later steps; the Results page shows it at 100% even for old jobs. On phones the pinned stepper + bars use ~215 px. | `current/06,08,12,24` | Two widgets (`WorkflowStepper`, `_buildWizardProgress`) | Users read "100%" as job progress | Setup = named steps, no %; job = cities done / total (§6.5) | C-visual |
| P2 | High | Job progress on **phones is below the fold** after Start; the panel leads with a log console; "99% Processing" while 2/2 cities show Done; completed shows "100% Idle"; failed/cancelled final stage shows a green check. | `current/17,18,19`; `scraping_screen.dart:1741-1779, 2577-2701` | Form and progress share one page | Users can't see that anything happened | Navigate to the search detail page on Start | C-visual |
| P3 | High | **Session expired during a job**: copy says "Sign in again…" but there is no button and polling stops. | `scraper_provider.dart:431-435, 341` | Missing action | User stuck | "Sign in to keep following" button, resume after login | C-code |
| P4 | Medium | Elapsed time includes queue time; no explicit "Queued" explanation; "Est. Remaining 0s" while still running. | `current/17` | Derived from `created_at` | Wrong expectations | "Queued · waiting for a free slot" + "Started 13:04" | C-visual |

### 2.5 Criteria, cost and starting

| ID | Sev | Issue | Evidence | Root cause | Impact | Recommendation | Conf. |
|---|---|---|---|---|---|---|---|
| S1 | **Critical** | Leads-per-city slider is 10–**500**; backend accepts ≤100. Above 100: estimate 422 → cost "—", the insufficient-credit check is skipped, and starting fails showing the raw `{"detail":[…]}` JSON. | `scraping_screen.dart:1439-1452`; API probe returned 422 for 200 | Frontend/backend limits diverged | Users cannot start and don't know why | Choices 10 / 20 / 50 / 100 (+ custom ≤100) | C-code + API |
| S2 | High | Low credits are found only after Review: "Insufficient credits. Required: 25, Available: 12" in small red text, **no link** to Credits; the minimum job (25) exceeds the balance from the start. | `current/26` | Validation at submit | Wasted setup; dead end | Pre-flight balance check, cost panel with "Get credits", disable Start with reason | C-visual |
| S3 | Medium | Default leads/city is 10 or 50 depending on entry path; session memory overrides it. | `home_screen.dart:45`; `state_selection_screen.dart:1922`; `scraping_screen.dart:120-121` | Three defaults | Unexpected cost | One default (10) shown explicitly | C-code |
| S4 | Medium | "API Status ONLINE" card (checked once at start-up) and a duplicate "Results/City" card occupy the top of the criteria screen; "Est. Cost" has an unlabelled bar. | `current/13` | Debug-style dashboard | Noise above the form | Remove; cost lives in the cost panel | C-visual |
| S5 | Medium | Cost re-estimated twice per keystroke without debounce; free-text "Target Cities" accepts any text, is editable while a job runs, and is not validated. | `scraping_screen.dart:143, 1355, 1232-1237` | Listener + onChanged | Flicker, stale cost, charged invalid cities | Debounce; chips only (free text behind "Add a city not listed" with validation) | C-code |
| S6 | Medium | Review sheet omits the country; refund copy is static while the policy is configurable; "After Charge" reads like the final cost. | `current/15` | Static copy | Credit confusion | Cost breakdown with job fee / cities / leads and plain refund rule | C-visual |

### 2.6 Running, finished and failed searches

| ID | Sev | Issue | Evidence | Root cause | Impact | Recommendation | Conf. |
|---|---|---|---|---|---|---|---|
| R1 | High | Cancelled/failed: "N leads were saved and can be downloaded" — **no download button**, and `GET /api/jobs/{id}/download` returns 400 "Job not completed". | `scraping_screen.dart:2480-2490, 1705`; `main.py:4174-4176` | Completed-only export | User paid for leads they can't get | Allow download of any saved leads (BE + FE) | C-code |
| R2 | Medium | Completion card shows time in **UTC**; History shows local — same job 08:00 vs 13:00. | `current/20,22`; `job_completion_card.dart:695-701` | `parseServerTime` vs `parseServerTimeLocal` | Distrust | Always local, with relative time | C-visual |
| R3 | Medium | Reload just after completion lands on Home with no summary (the active-job key is cleared at completion). | `current/21` | Reattach only for active jobs | "Did it finish?" | Home "Recent searches" shows it first with **Open results**; search URL survives reload | C-visual |
| R4 | Medium | "Settling any refund…" can stay until reload; refund shown only on the progress page, not on Home or History. | `scraper_provider.dart:388, 416-419` | Polling stops at terminal | Refund invisible | Net credits on every search row; refresh until `settled_at` | C-code / needs test |
| R5 | Medium | Search form and drafts survive logout; a second user in the same browser inherits them. | `scraping_screen.dart:77-79`; `auth_provider.dart:118-122` | Static memory | Privacy leak | Clear on logout | C-code |
| R6 | Low | Kebab icon copies the job ID; "Repeat last job" uses the current slider value instead of the job's. | `scraping_screen.dart:2206-2214, 225-230` | Mislabelled control; bug | Small surprises | Explicit "Copy ID"; rerun uses job settings | C-code |
| R7 | Medium | Only the newest active job is reattached although two may run concurrently. | `scraper_provider.dart:345-356` | Single-job provider | Second job invisible | "My searches" lists all running searches | C-code |

### 2.7 History, results and download

| ID | Sev | Issue | Evidence | Root cause | Impact | Recommendation | Conf. |
|---|---|---|---|---|---|---|---|
| D1 | High | History table "Results" column, detail panel and **"Most Results" sort read `job['results']`**, which the API never sends (`result_count`) → 0 everywhere in the table. | `job_history_screen.dart:186-188, 788, 952`; `main.py:3952` | Field-name drift | Wrong lead counts | Use `result_count` | C-code |
| D2 | Medium | History filter has no Cancelled or Queued; "Delete Job" is a full-width filled red button on every cancelled/failed card; failed jobs show "View Logs" which opens results. | `current/22,23`; `job_history_screen.dart:567-593, 1386` | | Destructive action too prominent | Status tabs incl. Cancelled; Delete in a menu with confirmation | C-visual |
| D3 | Medium | Results: every card says **"Verified Lead"**; the phone shows the first lead at ~540 px under header, stepper, search, filters and counters; default contact filters (all four, ANY) hide leads with no contact data; "Newest" is storage order; phone/email only actionable in the desktop table; no copy actions. | `current/24,25`; `results_screen.dart:317-338, 1935-1941` | | Misleading badge; slow to reach data | Remove badge; compact header; filters off by default; copy/call/email/maps per lead | C-visual |
| D4 | High | **Android "corrupted spreadsheet"** (Feb 2026 photo): candidates — web download revokes the blob URL right after `click()`; scraped strings beginning with `=` become formulas in the xlsx; categories with `/ : ? * [ ]` crash the sheet title (500). | `current/27`; `download_helper.dart:24-32`; `main.py:~4006-4153` | Download/export hardening | Users can't open what they paid for | Delay revoke and attach the link; escape formulas; sanitise titles; test on Android | Needs test |
| D5 | Medium | Bulk CSV/JSON export exists only on desktop table selection; CSV quoting bug (quotes without commas not escaped) and no formula protection. | `results_screen.dart:1204-1361` | | Broken files | Shared, tested export helper | C-code |
| D6 | Needs test | Desktop Results **table** may not scroll vertically (DataTable in a non-scrolling column). | `results_screen.dart:1410-1480` | Layout | Rows clipped | Verify; use a scrolling table | Needs test |

### 2.8 Credits, account, sign-in

| ID | Sev | Issue | Evidence | Root cause | Impact | Recommendation | Conf. |
|---|---|---|---|---|---|---|---|
| C1 | Medium | With live payments off (production state), users have **no credit history** in the app (the ledger tab exists only in the full wallet); refunds are visible nowhere except the progress page. `/api/credits/history` already exists. | `wallet_screen.dart:742-858`; `main.py:2466` | Gate hides the ledger | "Where did my credits go?" | Credits page with history in both payment modes | C-code |
| C2 | Medium | Low-balance alert exists only inside the full wallet; the pill is a pulsing colour with an arbitrary fill (balance/100). | `low_balance_alert.dart`; `credit_pill.dart:246` | | No guidance | Balance meaning ("≈ N cities at 10 leads"), low-balance banner on Home and in setup | C-code |
| C3 | Medium | Profile shows invented content ("Pro Member", "Top 5% of users", "Weekly goal 1000"); Edit disabled; phone logout has no confirmation, desktop Profile has no logout. | `profile_screen.dart:274-546, 671-727` | Placeholder | Erodes trust | Remove fakes; account menu with Profile, Sign out (confirm) | C-code |
| C4 | Low | "Remember me for 30 days" while tokens last 7 days; after login the user always lands on `/home` (intended destination lost). | `login_screen.dart:128, 443`; `auth.py:28` | | Expectation gap | "Keep me signed in"; return to the intended page | C-code |

### 2.9 Accessibility (WCAG 2.2 AA)

| ID | Criterion | Issue | Conf. |
|---|---|---|---|
| A1 | 2.1.1, 4.1.2 | Country, region and city cards, Select All, the **Review & Start** CTA, log chips, history/results chips and the credit pill are `GestureDetector`s: not focusable, no button role. `Semantics` is used only on flags. | C-code |
| A2 | 2.5.8 | Targets below 24 px: city-chip remove (14–16 px), pill refresh (~18 px), results table actions (28 px is OK; 22 px checkbox is borderline). | C-code |
| A3 | 1.4.3 | White on Home tiles 2.2–3.8:1; `#2C5F6D` text on `#171717` 2.53:1 ("Running", "Pro Member"); white at 24 % for "Edit" 2.19:1; many 10–11 px labels. | computed |
| A4 | 1.4.1 | Colour-only: selected city tint, log severity, stage dots, credit pill state. | C-code |
| A5 | 1.4.10 | Phone chrome (~315 px of 844) and the nested city list; long UUID wraps over four lines at 390 px (`current/20`). | C-visual |
| A6 | 2.4.3, 3.3.1 | No `textInputAction`/`onSubmitted`; Enter does nothing in search fields; errors appear as transient snackbars only. | C-code |

---

## 3. Navigation model (proposal)

**Principle:** users do three things — *find leads*, *check on searches*, *manage credits*. Name the nav after those tasks, not after wizard steps.

| Destination | Label (exact) | Desktop ≥1024 | Tablet 768–1023 | Phone <768 | Route |
|---|---|---|---|---|---|
| Overview | **Home** | sidebar | labelled rail | bottom bar 1 | `/home` |
| Start a search | **Find leads** | sidebar (emphasised, filled) | rail | bottom bar 2 (centre) | `/find`, `/find/details` |
| Running, past searches, results | **My searches** (phone: **Searches**) | sidebar + "1 live" count | rail | bottom bar 3 | `/searches`, `/searches/<id>` |
| Balance, buy/request, history | **Credits** | sidebar | rail | bottom bar 4 | `/credits` |
| Profile, sign out | **Account** | sidebar bottom + avatar menu | rail bottom | bottom bar 5 | `/account` |

- **Monitoring a running search:** every page shows a top-bar chip **"Searching · plumbers · 2 of 4 cities"** (phone: a slim banner under the top bar) that opens `/searches/<id>`. "My searches" shows a "1 live" count.
- **Opening previous results:** Home → Recent searches → **Open results**, or My searches → row. Results always live on the search's own page (`/searches/<id>`), which has the download, so there is exactly one results destination.
- **Credits:** pill in the top bar on every page → `/credits` (balance, what it buys, get/request credits, history with refunds).
- **Profile:** avatar menu (desktop/tablet) and the Account tab (phone). "Sign out" always confirms.
- Page titles match the nav label ("Find leads", "My searches"); a search page is titled "Search · plumbers".

**Challenging the "Find Leads" idea:** it is the right *action* label, but making it the label for everything (location → results) repeats today's mistake ("Cities" for the whole flow). Results belong to a search, so they live under **My searches**. "Recent Searches" on Home is right; avoid "Activity" and "Jobs" in user copy ("job" is our word, not theirs).

**Alternative considered:** a single "Searches" area with a "New search" button inside it (2 fewer nav items). Rejected for now: starting a search is the product's core action and deserves a top-level, always-visible entry, especially on phones.

---

## 4. Find Leads journey (end to end)

```
Home ──Find leads──▶ 1 Location ─────────────────▶ 2 Details & start ──Start search──▶ /searches/<id>
                     country → region → cities      business type, leads/city,         Queued → Searching → Completed
                     (sticky selection bar)         cost panel, Start button           (or Cancelled / Failed)
                                                                                         └─ results, download, run again
```

Setup has **two steps** (was four). The old "Review" sheet merges into step 2: the cost panel and the labelled button "Start search · 70 credits" are the confirmation. *Search* and *Results* are not setup steps; they are states of the search page.

---

## 5. Responsive strategy (per layout)

| Width | Shell | Location picker | Details & start | Search page |
|---|---|---|---|---|
| ≥1200 desktop | 232 px sidebar, top bar with live chip + credits + avatar | **Split panel**: regions list (300 px) + cities grid (3 columns of 44 px rows) + sticky selection bar | Form (left) + sticky cost panel (right) | Summary card, cities list + credits/latest leads side by side, log collapsed |
| 1024–1199 | same, 2 city columns | Split panel, 2 city columns | Same, narrower | Same |
| 768–1023 tablet | 88 px **labelled** rail (icons + text) | Split panel: regions 240 px + 1–2 city columns; sticky bar | Form + cost stacked if <900 px | Single column |
| <768 phone | top bar (title + credits) + 5-item bottom bar; live banner | **Drill-down**: Country list → Region list → City list, each full height; sticky bar above bottom nav | Single column; sticky "Start search" bar | Single column; cancel at bottom; back to My searches |

Problems specific to each layout today (from the walk-through):
- **Desktop 1440**: 178 px city cards in one column; Continue far below; 4 stat cards on criteria page; progress fine.
- **1024**: the location screen renders its *tablet* layout (it measures content width, the criteria screen measures window width — `state_selection_screen.dart:395` vs `scraping_screen.dart:853`), so country tiles are 2 × 170 px.
- **820 tablet**: icon-only rail with no labels; otherwise the cleanest current layout (city rows are 56 px).
- **430/390 phone**: pinned stepper + two bars (~215 px) + bottom dock (~100 px); nested 220 px city list; progress below the fold after Start; results start at ~540 px.
- **360 phone**: Home tiles take the whole first screen; long UUIDs wrap; History cards break job IDs across lines.

---

## 6. Screen specifications (with exact copy)

Mockups: `docs/user-ux-evidence/mockups/` — `01_home`, `02_find` (country), `03_cities`, `04_review` (details & start), `05_running`, `06_results`, each at 1440 / 820 / 390.

### 6.1 Home

Above the fold at 1440×900 and 390×844: the primary action, a running search (if any) and the balance. (Mockup `01_home_*`.)

| Block | Content and copy | Data source |
|---|---|---|
| Hero | **Find business leads** · "Choose a country, cities and a business type. You see the maximum cost before anything is charged." · [**＋ Find leads**] · [Run "dentists · Quebec" again] (only if a previous search exists) | Static; last search from `GET /api/jobs[0]` (`category`, `cities`) |
| Running now (only when a search is queued/running) | "**plumbers** · 4 cities in Quebec, Canada" · "2 of 4 cities done · 9 leads so far · started 1 min ago" · bar · [View progress] | `GET /api/jobs/active` (`completed_cities`, `total_cities`, `result_count`, `created_at`) |
| Credits | "**4,102** credits" · "About 270 cities at 10 leads each" (computed: (balance − job fee) ÷ (per-city + 10 × per-lead)) · [Get credits ›]; low (< one minimum job): amber "Not enough for a search (minimum 25 credits)" | `CreditProvider` (`/api/credits/balance`) + `/api/credits/config` (formula) |
| Recent searches (5 rows) | Columns: **Search** (category + "Saint-Jérôme +3 · Quebec, Canada"), **Status** badge, **Leads** ("9 so far" while running), **Credits used** (net; "27 (13 refunded)"; "up to 70" while running), **Date** (local; "Today 13:00"), **Action** (Searching → *View progress*; Completed → *Open results*; Cancelled with leads → *Open 3 leads*; Failed → *See why*) · [All searches ›] | `GET /api/jobs`: `category`, `cities`, `status`, `result_count`, `credit_charged`, `credit_refunded`, `created_at`, `error` |
| Monthly line | "This month: 4 searches · 19 leads · 108 credits used" | client aggregation of `/api/jobs` (first page; exact once paginated, see API) |
| Empty state (first visit) | **Find your first leads** · "Pick a country and cities, choose a business type, and we'll collect names, phones and websites from Google Maps." · [Find leads] · "New accounts get 100 free credits" (if `starting_credits` > 0) | static + settings |
| Error | "We couldn't load your searches. Your data is safe." [Try again] — never render zero tiles on error | — |

Removed: the four gradient tiles (lifetime totals are on My searches), duplicate "1 done", raw UUIDs.

### 6.2 Country (step 1)

Mockup `02_find_*`. Title "Find leads"; steps **1 Location · 2 Details & start** (no percentages).
- Heading **Where do you want leads?**; search "Search countries"; **Recent** chips from the user's last searches ("Canada · Quebec" jumps straight to that region with nothing selected).
- 15 countries as compact rows (52 px): flag, full name ("United Arab Emirates", not "UAE"), region count with the local term ("13 provinces", "50 states", "7 emirates").
- Grid columns: 4 (≥1200), 3 (tablet), 1 list (phone).
- Error: "Locations didn't load." [Try again] — no hard-coded fallback.

### 6.3 Region and cities (step 1, continued)

Mockup `03_cities_*`.

**Desktop/tablet split panel**: left = region list (search "Search provinces", name, city count, badge with selected count "4 / 30"); right = cities for the highlighted region: search, bulk buttons, 1–3 columns of 44 px checkbox rows (full name, no region suffix). Country appears as a chip with **Change country**.
**Phone drill-down**: Country list → Region list → City list; header "‹ Provinces  Quebec  Canada · step 1 of 2".

**Selection rules (product rules — exact)**
| Action | Result | Copy |
|---|---|---|
| Tick/untick a city | toggles that city only | — |
| Filter text entered | list shows matches; selection unaffected | "4 of 30 cities match "saint". Your other selections are kept." |
| **Select N shown** | **adds** every shown city to the selection (union) | button "Select 4 shown" (hidden when all shown are selected) |
| **Clear shown** | removes only the shown cities | "Clear shown" |
| **Clear all** (in the selection bar) | empties the selection after confirmation if > 5 cities | "Clear all 12 selected cities?" [Keep] [Clear all] |
| Switch region (single-region mode, current backend contract) | if cities are selected: dialog | "**Switch to Ontario?** Your 4 Quebec cities will be removed from this search." [Stay in Quebec] [Switch and remove] |
| Switch region (multi-region mode, only if D1 = yes) | selections kept per region; the bar summarises "6 cities in 2 provinces" | — |
| Change country | if anything selected: dialog | "**Change country?** Your 4 selected cities in Canada will be removed." [Keep Canada] [Change country] |
| Region with 0 cities loaded | — | "No cities listed for this region yet." |
| > 100 cities selected | allowed up to 500 (backend limit), warning at 100 | "Large searches take longer — about {N} minutes for {M} cities." ({N} computed from the user's own recent per-city durations; hide the estimate when there is no history) |

**Sticky selection bar** (always visible on this step; above the bottom nav on phones): "**4 cities selected**" · names truncated "Montreal, Laval, Saint-Jérôme +1" · [Review list] (sheet/popover with removable chips) · [Clear all] · "Up to 70 credits at 10 leads/city" · [**Continue with 4 cities**] (disabled: "Select at least one city").
**Long lists**: USA states go up to 201 cities → virtualised list, alphabetical, with search; never cards.
**Drafts**: the selection is kept automatically per session; "Save draft" is replaced by automatic restore ("Continue where you left off: 4 cities in Quebec" [Continue] [Start over]) — the explicit draft keys remain for compatibility.

### 6.4 Details & start (step 2)

Mockup `04_review_*`.
- **Business type** (text, 1–120 chars) with suggestion chips (Dentists, Restaurants, Plumbers, Real estate agents, Lawyers, Gyms, Coffee shops, Auto repair). Error: "Enter a business type, for example 'dentists'."
- **Leads per city (maximum)**: segmented 10 · 20 · 50 · 100 (default 10). Helper: "Google Maps often has fewer businesses than this in small towns. You only pay for leads delivered."
- **Cities**: chips with remove (target ≥ 24 px) and [Edit cities].
- **Cost panel** (right on desktop, below on phones + sticky bar):
  "Job fee 10 · 4 cities × 5 = 20 · Up to 40 leads × 1 = 40 · **Charged now 70** · Balance after 4,032" and the rule: "You pay for the leads we deliver. Unused credits return to your balance when the search ends. If it fails without leads, everything is refunded." (Text generated from the configured refund policy; for `none`: "Credits are not refunded.")
- **Start button**: "Start search · 70 credits". Disabled states: "Enter a business type", "Not enough credits — you need 70, you have 12" + [Get credits].
- After Start: navigate immediately to `/searches/<id>` with status **Starting…**.

### 6.5 Search page — progress (`/searches/<id>`)

Mockup `05_running_*`. Header: status badge · "Updated 3 s ago" · title "plumbers in 4 cities" · "Quebec, Canada · started 13:04 · up to 10 leads per city". Progress = **cities**, not %: "**2 of 4 cities done** · 9 leads so far" + bar + "Now searching Havre-Saint-Pierre · about 1 min left". Cities list with per-city state; credits box; latest 3 leads (P2); technical log collapsed ("Technical log (35 lines)"); [Cancel search].

**Status names and microcopy (exact)**

| State (backend) | Badge | Headline / body | Actions |
|---|---|---|---|
| request in flight | ◌ Starting… | "Starting your search…" (after 10 s: "Still starting — this is safe to wait for. Pressing Start again won't charge twice.") | — |
| `pending` | ○ Queued | "Waiting for a free search slot. Searches usually start within a minute." | Cancel search |
| `running` | ◐ Searching | "2 of 4 cities done · 9 leads so far" / "Now searching {city}" | Cancel search |
| running + poll failing | ◐ Searching (amber notice) | "**Connection lost — retrying in 4 s.** Your search keeps running on our servers; nothing is lost." [Retry now] | — |
| session expired | ◐ Searching (amber notice) | "**You've been signed out.** Your search is still running. Sign in to keep following it." [Sign in] | — |
| cancel requested | ◐ Stopping… | "Stopping after the current business. Leads found so far are kept." | — |
| `cancelled` | ⊘ Cancelled (neutral grey) | "You cancelled this search. 3 leads were saved. 19 unused credits were returned." | Open 3 leads · Download · Run again |
| `failed`, 0 leads | ✕ Failed (red) | "This search couldn't finish: {reason in plain words}. All 30 credits were returned." | Run again · Contact support |
| `failed`, leads > 0 | ✕ Failed with partial results | "This search stopped early: {reason}. 6 leads were saved; unused credits were returned." | Open 6 leads · Download · Run again |
| `completed`, all cities produced | ✓ Completed (green) | "17 leads from 4 cities. 47 credits used (70 charged, 23 returned)." | Download Excel · Open results · Run again |
| `completed`, some cities 0/failed | ✓ Completed · 1 city found nothing (amber) | "Saint-Jean-sur-Richelieu: no businesses found." | same |
| refund not yet settled | (inline) | "Calculating your refund…" (poll until settled) | — |

Raw error text is mapped to plain reasons ("Google Maps didn't respond", "the business type returned nothing") with the raw text available under "Details".

### 6.6 Search page — results entry

Mockup `06_results_*`. Same URL as progress; the header turns into the result summary. Primary [**Download Excel**], [CSV], [Run again], [Copy search link]. Lead list: name, city, phone, website/email/map icons, actions (Call, Email, Open website, Open in Google Maps (stored URL), Copy). Filters default **off**; "Has phone", "Has website" toggles; city filter. No "Verified" badge. Phone: first lead visible within the first screen (header ≤ 200 px).

### 6.7 My searches (History)

Tabs: **All · Running · Completed · Cancelled · Failed** with counts. Rows as on Home (search, status, leads, net credits, date, action). Row menu: Open, Download, Run again, Copy ID, Delete… (confirm: "Delete this search and its 17 leads? This can't be undone." [Keep] [Delete]). Search by business type, city or ID. Server pagination (API change).

### 6.8 Credits

Balance with meaning, [Request credits] or [Buy credits] depending on live payments, **History** (from `/api/credits/history`): date, description ("Search: plumbers · 4 cities — charged", "Refund: unused leads"), +/−, balance after. Available in both payment modes.

---

## 7. Capability-preservation matrix

| # | Current capability | Where today | Proposed location | Risk if forgotten |
|---|---|---|---|---|
| 1 | Guest can explore Cities/Search without an account; sign-in sheet saves the draft | Cities/Search tabs, `_ReviewSheet` auth sheet | Find leads open to guests; "Sign in to start" in step 2 keeps the draft | **High** |
| 2 | Country/region/city selection from API data | Cities tab | Step 1 | Low |
| 3 | Region search, city search | Cities tab | Step 1 (both kept) | Low |
| 4 | Select all / unselect all | Cities tab | "Select N shown" / "Clear shown" / "Clear all" (semantics corrected) | Med |
| 5 | Location draft save/load/clear (`wizard_location_draft_v1`) | Cities footer + banner | Automatic restore banner; keys kept | **High** |
| 6 | Search draft save/load/clear (`wizard_search_draft_v1`), auto-save before sign-in | Search tab | Step 2 (auto) | **High** |
| 7 | Free-text "Target Cities" (any city, multiple regions) | Search tab | "Add a city not listed" in step 2 with format validation | **High** (power users rely on it) |
| 8 | City chips with remove + Clear All | Search tab | Step 2 chips; selection bar | Low |
| 9 | Category suggestion chips | Search tab | Step 2 | Low |
| 10 | Results per city | Search slider | Segmented 10/20/50/100 | Low |
| 11 | Live cost estimate, balance, after-charge | Stat cards + review sheet | Cost panel | Low |
| 12 | Review before charge | Review sheet | Cost panel + labelled Start button | Med |
| 13 | Idempotent start with retry, "pressing start again is safe" | `ScraperProvider` | Unchanged; copy in Starting… state | **High** |
| 14 | Rate-limit / insufficient-credit messages | Snackbars | Disabled Start with reason + Get credits | Low |
| 15 | Reattach to running job after refresh | `resumeActiveJob` | `/searches/<id>` + live chip | **High** |
| 16 | Reconnecting / auth-expired notices | Activity panel | Search page notices (with Sign in button) | Med |
| 17 | Cancel with confirmation | Activity panel, History | Search page + My searches row | Low |
| 18 | Stages, elapsed, est. remaining, leads, cities, rate | Activity panel | Search page summary | Low |
| 19 | Per-city progress list | Activity panel | Search page "Cities" | Low |
| 20 | Logs: search, filter, auto-scroll, copy, export | Activity panel | "Technical log" disclosure (all functions kept) | **Med** (hidden by default) |
| 21 | Charged / refunded display | Activity panel | Search page + every row | Low |
| 22 | Completion card: leads, cities, duration, top city, avg/city | Search tab, History | Search page summary | Med |
| 23 | Repeat last job | Search tab chip | "Run again" on Home hero, search page, rows | Low |
| 24 | Copy job ID | Kebab on card | Row menu "Copy ID" | Low |
| 25 | View results (3 entry paths) | Dashboard, completion, History | Search page | Low |
| 26 | Excel download (completed) | History, completion card, pushed Results header | Search page primary action + row menu | Low |
| 27 | Bulk CSV/JSON export of selected leads (desktop) | Results table | Results selection bar (all widths) | **Med** |
| 28 | Results search, contact filters ANY/ALL, city filter, has-website, sort, cards/table | Results | Search page results (defaults changed) | Med |
| 29 | Lead actions: website, call, email, maps | Results | Same + Copy | Low |
| 30 | History: search, status filter, date filter, sort, cards/table, pagination, details panel (≥1440) | History | My searches (tabs, search, date, sort, table on desktop) | Med |
| 31 | Delete finished job (confirm) | History | Row menu | Low |
| 32 | Cancel job from History | History | My searches running tab | Low |
| 33 | Credit pill + refresh | Top bar | Top bar | Low |
| 34 | Wallet entry from sidebar, dock, pill, Credits tile, Profile | various | Credits nav + pill | Low |
| 35 | Wallet: buy (live payments) / request credits (coming soon), payment methods, subscription, invoices, requests | `/wallet*` | Credits page (unchanged sub-screens) | **Med** |
| 36 | Credit ledger (full wallet) | Wallet Credits tab | Credits → History (both modes) | Low |
| 37 | Profile view, Billing & Plan link, logout (phone) | Profile | Account page + avatar menu | Low |
| 38 | Avatar menu logout with confirmation | Top bar | Same | Low |
| 39 | Admin entry for admins | Sidebar, top bar | Avatar menu "Admin" + sidebar (admins) | Low |
| 40 | Mobile swipe between pages | PageView | **Dropped** (conflicts with horizontal lists); bottom nav instead — decision flagged | Med |
| 41 | Pull-to-refresh on Home/Results | RefreshIndicator | Kept + explicit refresh in headers | Low |
| 42 | Sidebar collapse toggle on tablet | Top bar menu | Labelled rail; collapse not needed | Low |
| 43 | "Include Suburbs" toggle | Cities | **Removed** (non-functional) — decision D2 | Intentional |
| 44 | API Status card | Search tab | **Removed** (checked once; misleading) | Intentional |

---

## 8. Phased plan

Effort: S ≤ 1 day · M 2–4 days · L 1–2 weeks. Each item lists **V** = visual, **F** = frontend behaviour, **B** = backend/API.

### P0 — Truthfulness and blockers (small, ship first)
| # | Change | Type | Impact | Effort | Acceptance criteria |
|---|---|---|---|---|---|
| P0.1 | Leads per city: 10/20/50/100 (cap 100); map 422 details to readable messages | F | Critical (S1) | S | No path sends > 100; a forced 422 shows a sentence, never JSON |
| P0.2 | Bulk selection semantics: Select N shown = union; Clear shown; Clear all; checkbox reflects membership | F | High (L3) | S | Test: pick 2, filter, select shown → 6 selected |
| P0.3 | Region/country change: confirm before discarding cities | F | High (L4) | S | Test: change region with 4 selected shows dialog; Stay keeps 4 |
| P0.4 | Remove "Include Suburbs" (or implement, per D2) | F (+B if implement) | High (L5) | S | Toggle gone; drafts with the key still load |
| P0.5 | Remove both percentage bars; named steps only | V/F | High (P1) | S | No "%" anywhere in setup |
| P0.6 | Low credits: pre-flight in step 2 with Get credits link | F | High (S2) | S | 12-credit user sees the reason and a working link before Start |
| P0.7 | Times always local (completion card) | F | Med (R2) | S | Same job shows the same time on all screens |
| P0.8 | History uses `result_count` | F | High (D1) | S | Table and sort show real counts |
| P0.9 | Download of saved leads for cancelled/failed jobs | B + F | High (R1) | S–M | Cancelled job with 3 leads downloads 3 rows |
| P0.10 | Export hardening: attach link + delayed revoke; escape `= + - @`; sanitise sheet title; Android test | B + F | High (D4) | S | xlsx opens in Google Sheets (Android) and Excel; category "a/b" works |
| P0.11 | Session-expired: Sign in button; resume polling | F | High (P3) | S | Expire token mid-job → sign in → progress resumes |
| P0.12 | Clear form memory and drafts on sign-out | F | Med (R5) | S | User B never sees user A's form |
| P0.13 | Remove misleading content: "Verified Lead", fake profile badges, dead bell, API Status card | V | Med | S | None of these strings remain |

### P1 — New structure (the redesign)
| # | Change | Type | Effort | Depends | Acceptance criteria |
|---|---|---|---|---|---|
| P1.1 | Shell + navigation (§3): labels, labelled rail, phone bottom bar, live chip/banner, account menu | V/F | M | — | Labels identical at all widths; live chip opens the running search from any page |
| P1.2 | Routes `/find`, `/searches/<id>` etc. with refresh/back support | F | M | P1.1 | Reloading any page returns to the same place; browser back works |
| P1.3 | Home redesign (§6.1) | V/F | M | P1.1 | Primary action + running + balance above the fold at 1440×900 and 390×844 |
| P1.4 | Location picker redesign (§6.2–6.3): compact countries with recents, split panel, phone drill-down, virtualised lists, sticky selection bar, review list | V/F | L | P0.2–P0.3 | 30 cities visible in ≤ 2 screens at 1440; Continue always visible; Montana (201) scrolls smoothly |
| P1.5 | Details & start (§6.4) with cost panel and policy-driven copy | V/F (+B: expose refund policy in `/api/credits/config`) | M | — | Breakdown equals backend charge for 5 test cases |
| P1.6 | Search page: progress + results (§6.5–6.6), status table copy | V/F | L | P1.2 | Every state in §6.5 reproducible in the harness with the exact copy |
| P1.7 | My searches (§6.7) incl. Cancelled tab, menus, pagination | V/F + B (pagination) | M | API-1 | 200 jobs list in pages of 20; filters server-side |
| P1.8 | Credits page with history in both payment modes | V/F | M | — | Refund rows visible with payments off |
| P1.9 | Accessibility pass (A1–A6) | F | M | design system | §9 a11y checklist passes |

### P2 — Depth
- Multi-region searches within one country (D1) — F (+B checks); M.
- Latest-leads preview while running (poll `/api/jobs/{id}/results?limit=3`) — F; S.
- "Notify me when done" (browser notification/email when SMTP is configured) — F + B; M.
- Location data curation and dedupe (D6) — data; M.
- Saved searches / schedules — B + F; L.

### API changes (separate from UI)
| ID | Change | Why |
|---|---|---|
| API-1 | `GET /api/jobs`: `limit`/`offset`/`status` filters + `total`; add `max_results_per_city`, `failed_cities`, `settled_at` | My searches pagination; fill rate; refund state |
| API-2 | Store `country` on jobs (new nullable column) or return it from a region lookup | Show "Quebec, Canada" reliably; recents |
| API-3 | `GET /api/jobs/{id}/download`: allow cancelled/failed with ≥ 1 lead; formula-escape cells; sanitise sheet title | R1, D4 |
| API-4 | `GET /api/credits/config`: include the active refund policy name | Correct refund copy |
| API-5 | `GET /api/countries`: region term and counts (or client derives from `/api/states`) | Country rows |
| API-6 | Data files: curated, deduped city lists; optional `display_name` without region suffix | L9 |
No change needed for: job creation, idempotency, cancel, results, reattach (`/api/jobs/active`), credit history.

---

## 9. Manual QA checklist (desktop 1440, tablet 820, phones 390 and 360)

**Navigation**
- [ ] "Find leads", "My searches", "Credits", "Account" visible and identical at every width; page title matches.
- [ ] With a search running, the live chip/banner appears on every page and opens it.
- [ ] Reload on `/find`, `/searches/<id>`, `/credits` returns to the same screen; browser back never leaves the app unexpectedly.

**Location**
- [ ] Countries: search finds "Arab" → UAE; recents shown after one search.
- [ ] Canada → Quebec: 30 cities visible within two screens on desktop; Continue always visible.
- [ ] USA → Montana (201 cities) and California (200): smooth scroll, search works.
- [ ] Select Montreal + Quebec City → filter "saint" → "Select 4 shown" → **6 selected**; "Clear shown" → 2 remain.
- [ ] Change region with cities selected → dialog; "Stay" keeps them; "Switch" clears them.
- [ ] Change country with a selection → dialog.
- [ ] Load failure (block `/api/states`) → error with Try again, never fake regions.

**Details & cost**
- [ ] Leads/city offers only 10/20/50/100; cost matches the backend charge for 1, 4 and 30 cities.
- [ ] 12-credit account: Start disabled with "you need 25, you have 12" and a working Get credits link.
- [ ] Refund copy matches the configured policy.

**Running and recovery**
- [ ] Start → search page within 1 s with "Starting…" then "Queued"/"Searching".
- [ ] Double-click Start → one search, one charge.
- [ ] Slow network (3 s added latency) → no false "Failed"; "Connection lost" notice when polls time out; recovers.
- [ ] Offline 30 s mid-search → notice; online → resumes with correct counts.
- [ ] Reload mid-search → same page, progress continues.
- [ ] Reload right after completion → completed summary (not a bare Home).
- [ ] Token expiry mid-search → "Sign in" button → progress resumes.
- [ ] Cancel → "Stopping…" → Cancelled with saved leads, refund line, download works.
- [ ] Failed job (fake "Boom" city) → plain reason, refund line, partial download if leads exist.
- [ ] Two searches running → both listed under My searches → Running.

**Results and history**
- [ ] Completed: Download Excel opens on desktop Excel, Google Sheets (Android) and iOS Files.
- [ ] Category containing "/" downloads correctly; a business name starting with "=" stays text.
- [ ] Times identical on Home, My searches and search page (local, with relative).
- [ ] My searches: Cancelled tab; lead counts correct in list and table; Delete asks first.
- [ ] Phone: first lead visible on the first screen of results.

**Accessibility**
- [ ] Keyboard-only: complete the whole journey (Tab, Space/Enter, Esc closes dialogs); focus visible on every control.
- [ ] Screen reader (NVDA + Chrome): city checkboxes announce name and state; status changes announced politely; dialogs labelled.
- [ ] All text ≥ 4.5:1 (computed for the token set: 5.1–12.3:1); controls ≥ 3:1; targets ≥ 24 px (44 px on touch).
- [ ] 200 % zoom and 320 px width without horizontal page scroll.

---

## 10. Visual direction (consistent with ADMIN_UX_PLAN.md)

Keep the dark theme, teal primary (`#2C5F6D`, white text 7.08:1) and the Inter-like type. Replace gradient tiles with neutral cards (`#242427`); reserve colour for status badges with icon + word (Searching blue `#669df1` 5.56:1 on its tint, Completed `#4bce97` 7.89:1, Partial `#eed12b` 10.4:1, Failed `#f87168` 6.08:1, Cancelled grey 6.32:1); links/accents `#6cc4d6` (7.7:1 on cards); secondary text `#a9b4c2` (7.4:1); muted `#8b95a3` (5.1:1). Minimum text 12 px (body 14). One primary button per screen. Destructive actions in menus or text-style red, filled red only inside the confirmation dialog. No charts on user screens: the numbers are small and a sentence ("2 of 4 cities done") reads faster.

---

## 11. Owner decisions (genuine product choices)

| # | Decision | Recommendation | Trade-off |
|---|---|---|---|
| D1 | **Allow cities from several regions (same country) in one search?** The backend already accepts any list of "City, Region" strings (≤ 500), so this is mostly frontend work. | **Yes, in P2**, one country per search. Ship P0/P1 with single-region plus the confirmation dialog. | Bigger searches take longer and cost more; rate limits (5/hour, 2 concurrent) unchanged; needs clear summary ("6 cities in 2 provinces"). |
| D2 | **"Include Suburbs"**: remove, or build it? Building it means changing the scraper query and probably the cost. | **Remove now**; revisit if users ask. | Removing drops a visible (but fake) feature; building it is backend work with unknown quality impact. |
| D3 | **Leads per city maximum**: keep the backend cap at 100? | **Keep 100** (choices 10/20/50/100). | Higher caps mean longer jobs and larger charges with low fill in small towns. |
| D4 | **Download partial results** for cancelled/failed searches? | **Yes** — users paid for delivered leads. | Small backend change; support may see more partial files. |
| D5 | **Two-step setup** (merge the Review sheet into "Details & start")? | **Yes** — the cost panel and "Start search · 70 credits" button are the confirmation. | One fewer explicit checkpoint; mitigated by the labelled button and visible charge. |
| D6 | **Curate the location lists** (remove landmarks/districts, merged municipalities, duplicates)? | **Yes** — likely improves the 38 % fill rate. | Some saved drafts/recents may reference removed entries (handle as "no longer listed"). |
| D7 | **Drop mobile swipe between pages** in favour of the bottom bar? | **Yes** — swipes conflict with horizontal chip rows and hide navigation. | Users who learned the swipe lose it. |

**Nothing will be implemented until you approve.** After approval I would create a new branch from `fix/job-durability-audit`, implement P0 then P1 in order, run backend tests, Flutter analysis/tests, the isolated browser walk-through at all widths, then push the branch for review without merging or deploying.
