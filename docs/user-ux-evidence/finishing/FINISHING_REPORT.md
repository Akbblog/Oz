# Finishing pass — branch `feat/user-ux-finishing`

Base: `feat/user-ux-redesign` @ `16000ad`. **Not merged, not deployed.** All tests and browser checks used an
isolated SQLite database with a fake scraper (`127.0.0.1:8098/8099`); no live service or data was touched.

## Commits

| Commit | Scope |
|---|---|
| `60c7da9` | **Security (separate, cherry-pickable):** profile saves never change roles; staff can't manage equal or higher ranks |
| `4b5dbf1` | API: server-side query/date/sort for My searches, per-city outcomes, stable lead ids |
| `d6de9f0` | Web: readable result cards, labelled contact actions, mixed-language addresses, CRM-ready selection model |
| `5ab1088` | Web: unambiguous search outcomes, server-side My searches, flags beside place names |
| `81670aa` | Web: country flags and accessibility in Find leads |
| (last) | My searches fallback for older servers, "Qatar, Qatar" label, host-only website names, evidence + this report |

## 1. Admin security fixes (ADMIN_UX_PLAN.md A1, A2)

- **A1:** `PUT /api/admin/users/{id}` edits username/email/phone only. `role`/`is_admin` from old clients are
  accepted only when equal to the stored value; a differing value returns **409** and nothing is written. Role
  changes use the new explicit, audited **`PUT /api/admin/users/{id}/role`** (owner only; never self, never another
  owner; last admin/owner guard; audit event `admin.user.role_change`). Manage Profile sends only changed fields,
  shows the role read-only, and offers "Change role…" to owners.
- **A2:** suspend, unsuspend, deny, restore, delete and profile edit require the actor to rank **strictly above** the
  target (owner > admin > support > user) → 403 with a plain reason. The users list hides those controls and shows a
  lock note ("Owner account: protected", "Only an owner can manage admins").
- Tests: `backend/tests/test_admin_role_safety.py` (24 role-matrix cases), `frontend/test/core/admin_roles_test.dart`.
- **Not changed:** credit grants to staff accounts (admin can still grant credits to an owner) — see decisions.

## 2. User experience

| Item | What changed | Verified |
|---|---|---|
| 1 Flags | SVG flags (`country_flags`) beside full country names and region counts in Find leads; flags beside place names in Home, My searches, search page. Decorative for screen readers; globe fallback | Screens at 1440/820/390/360 (`after/*find*`) |
| 2 Outcomes | Leads found · cities searched · with leads · with no leads (+ timed out / not finished) side by side; **"Completed · no leads"** separate from a useful search; old "N cities found nothing" (actually timeouts) → "N cities timed out"; cancelled/failed with leads → "· partial results", **"View partial results (N)"** button + "Download partial Excel" | Before/after pairs; partial Excel = 3 rows for 3 saved leads |
| 3 Result cards | Site name only (`e2e-biz-3.example.com`; tracking, redirects, paths removed; social profiles keep the profile); original URL opens/copies/exports; labelled Call/Email/Website/Map/Copy (48 px); 3-line wrapping, RTL-aware addresses with "Show full address" | `regression/360_result_cards_*`, 390, admin view results |
| 4 My searches | Query (category, city incl. accents, country name, ID), date filter (local day boundaries) and sort run on the server across **all** searches; exact pager | Backend test with 25+ searches; widget test of sent params; `after/*my_searches_many*` |
| 5 Accessibility | Find rows: one focus stop with visible ring, Enter/Space, checkbox semantics, polite count announcement, 48 px targets, AA borders/text; phone city header stacks (no truncation at 360 px); stats strip has one screen-reader label | Widget tests; screenshots |
| 6 CRM prep | `LeadSelection` keyed by `lead_id` (fallbacks documented), select/clear shown, selection bar; `docs/CRM_LEAD_SELECTION.md` | Unit + widget tests; no lead data changed |

### Accessibility-mode typing issue — exact finding

- Fix: activating a Find row now moves Flutter focus to that row, so returning to the city search opens a fresh
  editing session (`find_common.dart` `FindRow`). Widget regression test with semantics enabled.
- Browser: with semantics on, tap path Find leads → Canada → Quebec → tick Montreal → type "saint" works at 1440 and
  390 px on the new build (`typing/after_results.json`). **The same probe also passed on the old build**, so the
  original failure was **not reproduced** in this pass with pointer taps; synthetic screen-reader activation could
  not be driven by the harness. Real NVDA/VoiceOver QA is still required.

## 3. Tests

| Check | Result |
|---|---|
| Backend pytest (SQLite) | **168 passed** (132 → 168) |
| Flutter test | **139 passed** |
| flutter analyze | 48 issues, unchanged and all pre-existing (admin, wallet, api_service prints) |
| build_web.sh | passed |
| Browser (Chromium, isolated) | 1440, 820, 390, 360 px: before/after for search pages, My searches, Home, Find leads, admin |
| MySQL/MariaDB | **not run** (new SQL: `REPLACE`, `LIKE … ESCAPE '!'`, `LOWER`, `GROUP BY` — portable but unverified) |

## 4. Preview caveat

`frontend/vercel.json` rewrites `/api` to the **live** backend. The branch preview therefore runs the new frontend
against the old live backend and live data: server-side search (frontend falls back to local filtering), per-city
facts, lead ids, `PUT …/role` (shows an error) and the backend rank checks are **not** active there. Anything done in
the preview changes live data.

## 5. Remaining risks / manual QA

1. Screen reader (NVDA + Chrome, VoiceOver + Safari): complete a search; type in city search after ticking cities.
2. Deploy order: backend first (old frontend keeps working; role rewrite stops), then frontend.
3. Run the backend suite against MariaDB before deploy.
4. Text search folds ASCII case only on SQLite for accented capitals in stored JSON ("ÉVRY" vs "évry").
5. Multi-column result cards are top-aligned (no longer equal height); table action column is icon-only with
   tooltips/labels.
6. Android device check of partial Excel download; real Google Maps run (fake scraper only here).
7. Admin dashboard otherwise unchanged (by request).

## 6. Admin plan vs this branch — short sequence

Done here: P0.1, P0.2 (backend + list UI), part of P0.9 (admin user actions show backend `detail`).

1. **P0.3** credit-grant validation (reject negatives/zero, reason required) — small, backend.
2. **P0.4 + P0.5 + P0.6** remove the hard-coded "Active Sessions"/"API Health" tiles; add `/api/admin/system-status`
   (DB, runner heartbeat, queue, stuck jobs, unsettled refunds) and a status strip.
3. **P0.7** Jobs tab + named admin routes (`/admin/jobs` bookmarkable).
4. **P0.8 + P0.9 rest + P0.10** destructive-action hierarchy (Suspend secondary, Delete behind type-to-confirm),
   honest error states, pricing tier visibility.
5. **P1.1–P1.3** admin jobs API (server search, stuck filter, support-readable) + job detail; reuse this branch's
   server-side query pattern and city outcomes.
6. **P1.5–P1.6** support read-only UI + user detail page with the owner-only role action.
7. **P1.8–P1.13** time-windowed KPIs, activity export, audit completeness, revenue correctness, accessibility.

Decisions needed (from ADMIN_UX_PLAN.md §9, narrowed): **D2** — confirm owners cannot act on other owners (current
fix) and whether delete/live-payments become owner-only; **D3** — allow signed credit deductions?; **D1** — support:
read-only, and unmasked contact data or audited reveal?; **D5** — business timezone for "today"; **D4** — Jobs tab
first, or straight to the admin shell; also whether admins may grant credits to owner/admin accounts.
