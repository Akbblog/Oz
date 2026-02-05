# Infinity Leads UI/UX — Implementation TODO Tracker

**Last updated:** 2026-02-05  
**Scope:** Flutter Web frontend + FastAPI backend  
**Source plan:** “World-Class UI/UX Analysis & Enhancement Plan” (your document)

Legend:
- `[x]` Done
- `[~]` Partially done / MVP shipped (needs follow-up polish)
- `[ ]` Not started

---

## Phase 1 — Critical (Week 1–2)

### Login
- [x] Password visibility toggle (`business_scraper_api/frontend/lib/screens/login_screen.dart`)
- [x] “Forgot password” link (`business_scraper_api/frontend/lib/screens/login_screen.dart`)
- [x] “Remember me for 30 days” (session-only when unchecked) (`business_scraper_api/frontend/lib/screens/login_screen.dart`, `business_scraper_api/frontend/lib/services/api_service.dart`)
- [x] Loading state during auth (`business_scraper_api/frontend/lib/screens/login_screen.dart`)
- [~] Better error messaging (uses API-specific errors; still not field-level) (`business_scraper_api/frontend/lib/screens/login_screen.dart`)
- [x] Rate limiting UI copy (“Too many attempts…”) (backend now returns 429 on auth) (`business_scraper_api/backend/main.py`, `business_scraper_api/frontend/lib/screens/login_screen.dart`)
- [ ] Accessibility pass (focus order, semantics, screen reader announcements)
- [ ] Social login (future)

### Dashboard
- [x] Dedicated dashboard tab with stats, quick actions, activity feed (`business_scraper_api/frontend/lib/screens/dashboard_screen.dart`, `business_scraper_api/frontend/lib/screens/home_screen.dart`, `business_scraper_api/frontend/lib/widgets/sidebar_navigation.dart`)
- [x] Charts/sparklines in stat cards (`business_scraper_api/frontend/lib/widgets/stat_card.dart`, `business_scraper_api/frontend/lib/screens/dashboard_screen.dart`)
- [ ] Real-time updates (WebSocket) + toast on completion
- [~] Empty state (basic “No jobs yet” implemented; needs illustration polish) (`business_scraper_api/frontend/lib/screens/dashboard_screen.dart`)

### Job progress
- [x] Multi-stage progress + city-by-city progress + ETA (best-effort) (`business_scraper_api/frontend/lib/screens/scraping_screen.dart`)
- [x] Enhanced logs: filter + export (`business_scraper_api/frontend/lib/screens/scraping_screen.dart`)
- [x] Job cancel control (UI + backend) (`business_scraper_api/frontend/lib/screens/scraping_screen.dart`, `business_scraper_api/frontend/lib/providers/scraper_provider.dart`, `business_scraper_api/backend/main.py`)
- [ ] Pause/resume (requires backend job control model)

### Results (basic filtering)
- [x] Search + city filter + contact filters + Has-website filter (`business_scraper_api/frontend/lib/screens/results_screen.dart`)
- [x] View toggle Cards/Table (`business_scraper_api/frontend/lib/screens/results_screen.dart`)
- [x] Bulk select + export selected rows (CSV/JSON) (`business_scraper_api/frontend/lib/screens/results_screen.dart`, `business_scraper_api/frontend/lib/widgets/infinity_data_table.dart`, `business_scraper_api/frontend/lib/core/download_helper.dart`)
- [~] Sorting (Newest/Name/Category/City) — “Newest” depends on backend order; no per-column server sort (`business_scraper_api/frontend/lib/screens/results_screen.dart`)
- [ ] Map view (future)

### Admin (stats)
- [x] Admin stats overview + user/credit request panels (already present) (`business_scraper_api/frontend/lib/screens/admin_dashboard_screen.dart`, `business_scraper_api/backend/main.py`)
- [~] Bulk actions for users/requests (bulk approve users + bulk approve/deny requests; bulk grant credits still TODO) (`business_scraper_api/frontend/lib/screens/admin_dashboard_screen.dart`, `business_scraper_api/frontend/lib/services/api_service.dart`, `business_scraper_api/backend/main.py`)
- [~] “System monitoring” placeholders (some UI cards exist; not real metrics)

---

## Phase 2 — High Priority (Week 3–4)

### “New job wizard” (Cities → Configure → Review → Start)
- [x] Step 1 (Cities) search/select UX exists (`business_scraper_api/frontend/lib/screens/state_selection_screen.dart`)
- [x] Progress bar (%) + Save draft for Cities step (`wizard_location_draft_v1`) (`business_scraper_api/frontend/lib/screens/state_selection_screen.dart`)
- [x] Save draft for Search step (`wizard_search_draft_v1`) (`business_scraper_api/frontend/lib/screens/scraping_screen.dart`)
- [x] Final review step before starting (“Review & Start” sheet) (`business_scraper_api/frontend/lib/screens/scraping_screen.dart`)
- [~] Step validation (gates start; still needs inline field validation and disabled CTA states refinement) (`business_scraper_api/frontend/lib/screens/scraping_screen.dart`)
- [x] “Back” navigation integration (Cities → Search via tab; Search → Cities via button) (`business_scraper_api/frontend/lib/screens/home_screen.dart`, `business_scraper_api/frontend/lib/screens/state_selection_screen.dart`, `business_scraper_api/frontend/lib/screens/scraping_screen.dart`)
- [ ] “Save as Draft” across the *entire* wizard as one object (country/state/cities/category/max-results/etc.)
- [ ] Country/State/City enhancements: favorites, bulk shortcuts, grouping/collapsibles, “Top 10 cities”

### Results (advanced)
- [~] Advanced filters panel (MVP filters exist; still missing rating/advanced toggles) (`business_scraper_api/frontend/lib/screens/results_screen.dart`)
- [x] Table view (`business_scraper_api/frontend/lib/screens/results_screen.dart`)
- [ ] Column-level sorting indicators + multi-sort
- [ ] Bulk actions beyond export (save list, delete leads, share)

### Profile
- [ ] Profile editing (username/email/avatar)
- [ ] Preferences/settings (notifications, defaults)
- [ ] API keys section

---

## Phase 3 — Medium (Week 5–6)

- [ ] Results map view (Google Maps / Mapbox)

- [~] Export options (Excel full export exists; CSV/JSON selected export exists; no PDF) (`business_scraper_api/frontend/lib/screens/results_screen.dart`, `business_scraper_api/frontend/lib/core/download_helper.dart`)
- [ ] Job comparison (select jobs and compare)
- [ ] System monitoring (real metrics + backend endpoints)

---

## Phase 4 — Polish (Week 7–8)

- [ ] Micro-interactions + animations audit (consistent)
- [ ] Accessibility (WCAG 2.1 AA) pass
- [ ] Performance (route lazy-load, list virtualization/pagination for large results)
- [ ] Mobile/tablet UX audit for tables + filters

---

## Backend support items (UI-dependent)

- [x] Cancel job: `POST /api/jobs/{job_id}/cancel` (`business_scraper_api/backend/main.py`)
- [x] Delete job: `DELETE /api/jobs/{job_id}` (`business_scraper_api/backend/main.py`)
- [ ] Pause/resume job (needs persistent worker control, not just status flags)
- [ ] WebSocket events for job progress
