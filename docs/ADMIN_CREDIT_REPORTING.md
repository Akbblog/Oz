# Admin credit reporting fix (review branch `fix/admin-credit-reporting`)

Status: **review only. Not merged, not deployed.** The branch is based on the backend commit
currently in production (`7c410b2`, plus a docs-only commit).

All examples in this document, the tests and the screenshots are **synthetic**. The account,
search and payment identifiers are invented. The production investigation was done read-only
and shared with the owner privately. Nothing from it is stored in this repository.

---

## 1. The reported case (synthetic replica)

An account's old admin modal showed **"Credits Purchased: 100"** and **"Credits Used: 130"**
while its balance was 30. The ledger shape is reproduced below with invented identifiers
(`replica_case`, searches A and B). The amounts and their order match the reported case.

| # | Type (`transaction_type`) | Classified as | Amount | Reason | Related | Balance after |
|---|---|---|---:|---|---|---:|
| – | opening balance | – | – | – | – | 0 |
| 1 | `credit` | Free signup credits | +100 | Starting credits on auto-approval | admin setting `starting_credits = 100` | 100 |
| 2 | `debit` | Search charge | −65 | Job charge: Restaurants | search A (1 city × 50 max) | 35 |
| 3 | `refund` | Search refund | +30 | Refund for undelivered work (completed, 20 leads) | search A | 65 |
| 4 | `debit` | Search charge | −65 | Job charge: Restaurants | search B (1 city × 50 max) | 0 |
| 5 | `refund` | Search refund | +30 | Refund for undelivered work (completed, 20 leads) | search B | **30** |

**Why the old figures were wrong:**
* **"Credits Purchased: 100"** was `SUM(amount)` over every `credit` row. Signup credits use that
  type, so a free grant was shown as a purchase. The account has no payments.
* **"Credits Used: 130"** summed every negative row: gross charges, ignoring the 60 credits
  refunded for undelivered work.
* **Where the balance comes from:** 100 free signup credits − 130 charged + 60 refunded = 30.

The new dialog shows the six headline figures in this order:

| Free signup credits | Paid credits | Search charges | Search refunds | Net search usage | Current balance |
|---:|---:|---:|---:|---:|---:|
| 100 | 0 | 130 | 60 | 70 | 30 |

This is asserted by `test_replica_of_reported_case_shows_the_six_headline_figures_in_order`
(backend) and by `replica shows 100 / 0 / 130 / 60 / 70 / 30 in the required order` (Flutter).

---

## 2. Definitions

### Account dialog ("Credit history" on a user card)

| Figure | Definition |
|---|---|
| **Free signup credits** | The one grant written by the approval flow: an exact approval reason (`Starting credits on auto-approval` / `…on account approval[ (bulk)]`), written by the account's approver (`created_by` = `users.approved_by`, NULL for auto-approval) within 10 minutes of `users.approved_at`, first such row only. A manual staff grant with the same text is a **staff grant**. Never a purchase |
| **Paid credits** | Payment credits whose provenance is verified (below). Each confirmed live payment counts once |
| **Search charges** | Gross `debit` rows tied to a search, before refunds |
| **Search refunds** | `refund` rows tied to a search (settlement for undelivered work) |
| **Net search usage** | Search charges − search refunds |
| **Current balance** | `users.credit_balance`, read in the same snapshot as the history |
| Staff grants | `credit`/`bonus` rows written by a staff member (`created_by` set): manual grants and approved credit requests, **whatever their reason text says** |
| Sandbox test credits (not paid) | Safepay sandbox payments and their promo bonuses |
| Unmatched payment credits | Rows that look like payments but fail a provenance check |
| Promo / referral bonuses, subscription allocations, other | Kept separate. Shown when non-zero, or "Unavailable" when missing |
| Net credits per lead | (charged − refunded) for searches still on file ÷ leads they hold. This replaces the old "Cost / Result" (gross ÷ stored results) |
| Reconciliation flag | Green when, in one snapshot, the ledger sums from 0 to the current balance **and** every `balance_after` chains. Red shows the unexplained difference and the first break. Grey "unavailable" if the server returns no result |

**Paid-credit provenance.** A ledger row counts as paid only if all of these hold:
1. It was written by the system (`created_by IS NULL`). Staff-entered text can never create a purchase.
2. Its reason is exactly the payment path's format (`Safepay payment <tracker>[ [env]]` or legacy `Payment confirmed`).
3. The payment path's own `credit_expiry` row (`expiry_type='purchased'`) links to this ledger id with the **same amount**. Staff grants and signup credits never write one.
4. A payment of the same user is `completed`, has `credits_purchased == amount`, and has the same tracker (Safepay). An untagged Safepay reason requires the payment row to say `production` **explicitly**. A missing environment is never paid. A tagged reason must match the payment's environment.
5. No earlier ledger row already claimed that payment. Claims are resolved over the account's **full** ledger, also for the overview, before the date range is applied. A duplicate inside the range whose original is outside it is therefore unmatched, not paid.

Rows that pass are **Paid credits** when the payment environment is live/production, or
**Sandbox test credits** when it is sandbox. Rows that look like payments but fail any check are
**Unmatched payment credits**. A read-only check confirmed that every existing production payment
row satisfies rules 1–4.

### Overview

* **Range selector:** 24 hours / 7 days / 30 days / All time. Every windowed query applies
  **both bounds** (`start ≤ ts ≤ end`, and `ts ≤ end` for All time). Mixed `T`/space timestamp
  formats are normalised before comparison. Bounds are returned with an explicit UTC offset.
* **Activity in range:** new users, active users, searches started, leads delivered,
  Search charges, Search refunds, Net search usage, Paid credits, Free signup credits,
  Staff grants, and sandbox test credits.
* **Active users** means accounts with at least one audited action in the range. It replaces
  the fabricated "Active Sessions": there is no session store, and the old card always showed 0.
* **Right now** (unaffected by range): total users, pending approval, credits in circulation,
  searches in progress, credit requests, active promos, promo uses (all time).
* **Internal API health** reads OK only when all three core checks pass:
  * database: `SELECT 1` answers;
  * schema migrations: every migration file on disk is applied (a gap in the middle is "missing");
  * search runner: the last scheduling pass **succeeded** within the staleness limit.

  A failed pass (DB, claim or sweep error) is "failing". A missing migration, a failing or stale
  runner, or a missing runner gives "degraded". An unobservable check gives "unknown". The
  tunnel connector is informational.
* **Public API reachability** is measured by the browser through `/api` → Cloudflare tunnel → backend. It reads "Reachable" only if the answer is HTTP 200 **and** the API's own health JSON (`{"status": "healthy", "timestamp": …}`). A proxy or portal answering 200 with HTML is shown as unreachable.
* A metric or count that fails to load shows **Unavailable**, never 0. That includes the promo
  counts, which used to default to 0.
* A slow response for a previously selected range, health re-check, or history page is
  discarded. Only the newest request updates the view.

### Consistent snapshot

Each report reads the balance, ledger, payments, payment links and searches inside **one**
read-only transaction:
* **MariaDB/MySQL:** `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ` followed by
  `START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY`. Production runs READ COMMITTED,
  where each statement would otherwise see newer data.
* **SQLite:** `BEGIN`. Writers wait for the read to finish.

---

## 3. Changes

| File | Change |
|---|---|
| `backend/admin_reporting.py` | Snapshot reads, provenance-verified classification, reconciliation, pagination, two-sided windows, strict health |
| `backend/main.py` | `GET /api/admin/users/{id}/credit-report`, `GET /api/admin/overview?range=`, `GET /api/admin/health` (`get_admin_user`: support and above, read-only) |
| `backend/audit/queries.py` | Legacy `/kpis` credit fields derived from the classified report (`credits_purchased` = paid only, `credits_used` = net) |
| `backend/job_runner.py` | Records each scheduling pass's outcome (`last_pass_ok`, `last_ok_pass_at`, `last_pass_error`). Scheduling behaviour is unchanged |
| `frontend/lib/screens/admin_credit_account_dialog.dart` | Credit history dialog |
| `frontend/lib/widgets/admin_overview_panel.dart` | Overview panel |
| `frontend/lib/screens/admin_dashboard_screen.dart` | Wiring. Promo counts are nullable |
| `frontend/lib/services/api_service.dart` | Client methods |

No migration. No write path changed. No production data changed.

---

## 4. Tests

The new tests are in `backend/tests/test_admin_credit_reporting.py` and
`frontend/test/admin_credit_reporting_test.dart`. Coverage:

* **Classification:** staff text never produces a purchase.
* **Synthetic replica:** the six figures appear in order.
* **Real writers:** job charge and settlement refund, the admin grant endpoint, and Safepay fulfilment (sandbox and live).
* **Snapshot regression**, for a charge and for a refund: another connection commits the write
  after the report has read the balance and before it reads the ledger. The report must stay
  reconciled. On MariaDB the test also asserts that the commit really landed between the two
  reads. **Negative control:** with the snapshot statements removed, both cases fail on MariaDB
  (differences of 25 and −18 credits).
* **Paid-credit provenance:**
  * a staff grant copying a live payment's exact text and amount (plus a `Payment confirmed`
    grant) leaves Paid credits at the single real payment;
  * a duplicate claim, an amount mismatch, a missing payment-path link and an environment-tag
    mismatch are all unmatched;
  * the overview agrees with the account report.
* **Overview windows:** both bounds, including rows after the end in both timestamp formats. A duplicate payment credit inside the range whose original is outside it is not paid. A Safepay payment without an environment is never paid.
* **Signup provenance:** a real approval through the approve endpoint gives Free signup credits. Manual staff grants titled "Starting credits…" (by the approving admin and by an owner) stay staff grants. A repeated or late system row is not a second signup grant.
* **Reachability probe:** a proxy returning HTML with HTTP 200 is unreachable (unit and widget test). Only the health JSON is reachable.
* **Health and runner:** a failed scheduling pass and a missing migration (gap) prevent OK, and
  the runner never refreshes its OK timestamp on a failed pass.
* **Unavailable values:** missing metrics, promo counts, figures and the reconciliation result
  all show as unavailable.
* **Stale responses:** a late response for an earlier range or page is ignored.
* **Roles:** users get 403, support/admin/owner get 200.

| Run | Result |
|---|---|
| Reporting + admin-role + Safepay + job-durability suites, **MariaDB 11.8.9** | 137 passed |
| Same suites, SQLite | 137 passed |
| Full backend suite, MariaDB 11.8.9 | 288 passed, 4 skipped, 1 failed (pre-existing CRM test, see §5) |
| Flutter widget tests for these screens | 15 passed |
| Full Flutter suite | 215 passed |

**Smoke test:** a local release web build was run against a local backend and an isolated local
MariaDB 11.8.9 (production isolation settings) holding synthetic data. Both 1440×1500 and
390×844 were exercised with no page errors. States covered:
* overview: loading, 24h, 7d, and error with health/probe failures;
* credit dialog: reconciled replica, mismatch, empty, sandbox buyer with a payment-like staff
  grant, a 3,000-entry ledger and its page 2, loading, error, and error → retry.

Screenshots: [`docs/admin-credit-reporting-qa/`](admin-credit-reporting-qa/).

---

## 5. Known limits

* The ledger has no payment foreign key. Provenance relies on the payment path's
  `credit_expiry` link plus exact amount, tracker and status matching. A schema-level link
  would be stronger; it was deliberately left out of this reporting-only change.
* Active users depends on which actions write `audit_events`.
* The tunnel connector is observed by the backend only if `TUNNEL_METRICS_URL` is configured. No
  compose change is included.
* Leads and per-lead cost count results currently stored. Deleted searches are listed separately.
* Windowed net usage pairs refunds with the window in which they were written.
* Pre-existing and unrelated: `tests/test_crm_records.py::test_delete_record_removes_crm_only_and_allows_reimport`
  fails on MariaDB on the production base commit as well.

## 6. Release order (when approved)

**Backend first, then frontend.** The new frontend needs the three new endpoints. The current
frontend keeps working against the new backend: the `/kpis` keys are kept, and their values are
now correct. To roll back, redeploy the previous branch. No migration is involved.
