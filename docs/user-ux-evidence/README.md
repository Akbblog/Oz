# User UX evidence and mockups

Companion to [`USER_UX_AUDIT_PLAN.md`](../../USER_UX_AUDIT_PLAN.md). Nothing here is production code.

## `current/` — the app as it is today (branch `fix/job-durability-audit`, build of `42603b7`)

Captured 2026-11-17 with Playwright against an **isolated** backend (SQLite, fake scraper, test accounts),
never the live system. Widths: 1440 (desktop), 1024 and 820 (tablet), 430/390/360 (phones).
The fake scraper returns 0–6 leads per city, so lead counts are illustrative.

| File | Shows |
|---|---|
| 01–04 | Home at 1440 / 820 / 390 / 360 |
| 05–06 | Country choice at 1024 and 390 |
| 07–08 | Canada regions; Quebec city list (178 px cards, one column) at 1440 |
| 09 | Filtered "Select All" kept only the 4 filtered cities (2 earlier picks dropped) |
| 10 | "Change region" cleared the selected cities immediately |
| 11–12 | City list at 820 and 390 (nested 220 px list on phone) |
| 13–16 | Criteria and review sheet, desktop and phone |
| 17–19 | Running job; on phone the progress is below the fold after Start |
| 20 | Completed card on phone: time shown in UTC (08:00) while local time was 13:00 |
| 21 | Reload just after completion lands on Home with no summary |
| 22–23 | History at 1024 (local 13:00 for the same job) and 360 |
| 24–25 | Results opened from History: no shell, no back button; phone shows first lead at ~540 px |
| 26 | Low credits: small red text, no path to credits |
| 27 | Historic (Feb 2026) Android screenshot: downloaded spreadsheet "appears to be corrupted" |

## `mockups/` — proposed design

`mockup.html` is a static, responsive mockup (open with `?s=home|find|cities|review|running|results`).
PNG renders at 1440×900, 820×1180 and 390×844 are alongside it; `full/` has full-page renders.
Emoji flags render as letters on Windows Chromium; real flags would be images/SVG.
