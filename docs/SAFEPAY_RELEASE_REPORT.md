# Safepay checkout — release report

Branch `feat/safepay-checkout` (built on `feat/pricing-page-polish` de135d3, which contains the CRM and mobile work).

## What changed

- **New purchases go through Safepay only.** The checkout page sends the buyer to Safepay's hosted Express Checkout
  (Payments 2.0: `POST /order/payments/v3/` → `POST /client/passport/v1/token` → `{checkout}/embedded/`).
- **Coinbase is closed for new checkouts.** `POST /api/payments/purchase` with any other provider, `/api/payments/simple-purchase`
  and `/api/payments/crypto/create-charge` return 410. The Coinbase webhook and status endpoints still work for
  charges already in progress, and no historical rows were changed. The Coinbase webhook now reads the real
  `{"event": {...}}` envelope as well as the old top-level shape.
- **Credits are granted only on proof from Safepay.** That proof is either a webhook to `POST /api/webhooks/safepay`
  whose `X-SFPY-SIGNATURE` (hex HMAC-SHA512 of the body, using the endpoint's shared secret) verifies, or a
  server-to-server tracker lookup (`GET /reporter/api/v1/payments/{tracker}`) in state `TRACKER_ENDED`. Before
  crediting, the server checks that the tracker, order id (our transaction id), amount (minor units), currency,
  merchant key and environment all match. The browser return URL only asks the server to check.
- **Each payment credits once.** The status change to `completed`, the credit, the ledger row, credit expiry and the
  invoice are written in one DB transaction guarded by `status <> 'completed'`. Duplicate, concurrent and late
  confirmations are acknowledged without crediting again. Webhook events are also de-duplicated by Safepay's event token.
- **Payment states:** completed, failed (declined), cancelled (cancel link), expired (no payment within
  `SAFEPAY_CHECKOUT_EXPIRY_MINUTES`, default 75), under review (Safepay reported a payment that doesn't match — no credit).
  A background reconciler runs every 120 s. It confirms paid trackers whose webhook is late and expires abandoned
  checkouts. A payment that Safepay confirms after expiry is still credited.
- **Web app:** the checkout page shows the exact charge ("Pay US$25.00 by card"). After paying, the buyer lands on
  `/payment/return/{id}` (or `/payment/cancelled/{id}`), which shows **"Confirming payment"** until the server
  confirms. After 2 minutes with no confirmation it switches to **"Still confirming"**: credits are added
  automatically if the payment is confirmed later. `/pricing` now waits for the saved session before loading packs.
- **Sandbox safety on the live site:** in sandbox mode, checkout is open only to `SAFEPAY_CHECKOUT_ALLOWLIST`, so nobody
  can buy real credits with a test card. Sandbox payments are labelled `[sandbox]` in the ledger. They are excluded
  from revenue totals and pricing-tier volume, and never trigger referral rewards.
- **Schema:** migration `018_safepay` adds `safepay` to the provider ENUMs and seven nullable columns to
  `payment_transactions`: `provider_environment`, `provider_status`, `status_detail`, `provider_base_amount`,
  `provider_base_currency`, `provider_fx_rate` and `completed_at`. It is additive only.

## Currency decision

**Buyers pay in USD, at exactly the pack price.** Packs are priced in USD, and Safepay Payments 2.0 accepts a USD
session (verified in sandbox: hosted page shows "$25.00"):

| Pack | Credits | Charged |
|---|---|---|
| Starter (id 4) | 500 | US$25.00 |
| Growth (id 5) | 2,500 | US$100.00 |
| Bulk (id 3) | 15,000 | US$450.00 |

Safepay converts to the merchant's PKR settlement at its own rate. That conversion is between Safepay and the
merchant. We store Safepay's quote (`provider_base_amount`/`provider_base_currency`/`provider_fx_rate`, e.g. 691,187
paisa at 276.475038 for US$25.00) for reconciliation. A card in another currency is converted by the buyer's bank, and
the checkout page says so. **We never silently charge a different amount:**
- The code only supports USD.
- The session is rejected unless Safepay echoes back the exact amount and currency.
- If an account cannot take USD, checkout fails with an error. It never falls back to PKR.

**Before going live, confirm with Safepay that the live merchant account accepts USD card payments.**

## Configuration (backend/.env on the server)

| Variable | Meaning |
|---|---|
| `SAFEPAY_ENV` | `sandbox` (default) or `production`. Picks the fixed hosts and which credentials are read. |
| `SAFEPAY_SANDBOX_API_KEY` / `SAFEPAY_SANDBOX_SECRET_KEY` | Sandbox merchant key (`sec_…`) and secret key. `SAFEPAY_API_KEY` / `SAFEPAY_API_SECRET` are still read as legacy names for the **sandbox** pair only. |
| `SAFEPAY_SANDBOX_WEBHOOK_SECRET` | Shared secret of the **sandbox** dashboard endpoint |
| `SAFEPAY_LIVE_API_KEY` / `SAFEPAY_LIVE_SECRET_KEY` / `SAFEPAY_LIVE_WEBHOOK_SECRET` | Live equivalents. Production never falls back to sandbox values. Identical sandbox and live values are refused. |
| `SAFEPAY_CHECKOUT_ALLOWLIST` | Comma-separated user ids/emails allowed to pay. In sandbox the list is required, unless `SAFEPAY_SANDBOX_OPEN_TO_ALL=true` (only for isolated test stacks). In production, an empty list means everyone. |
| `SAFEPAY_CHECKOUT_EXPIRY_MINUTES`, `SAFEPAY_RECONCILE_INTERVAL_SECONDS` | Defaults 75 and 120 |

Hosts (fixed in `backend/payments/safepay_service.py`):
- sandbox: API and checkout at `https://sandbox.api.getsafepay.com`
- production: API at `https://api.getsafepay.com`, checkout at `https://getsafepay.com`

**Webhook URL to enter in the Safepay dashboard** (Developers → Endpoints, for sandbox and later for live):
`https://server.progresslms.io/api/webhooks/safepay`

## Deployment facts

- **Backend:** Oracle Cloud VM, hostname `il-staging` (despite the name this is **production**). Checkout is in
  `~/infinity-leads`, run with `sudo docker compose --env-file backend/.env -f docker-compose.worker.yml up -d`.
  Cloudflare tunnel → `https://server.progresslms.io`. The DB is MariaDB 11.8.9 on Hostinger.
- **Frontend:** Vercel project `frontend` (`infinity-leads.vercel.app`). `/api/*` is rewritten to `server.progresslms.io`.
