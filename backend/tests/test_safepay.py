"""Safepay Payments 2.0: checkout, signature, exactly-once crediting, failure paths.

Safepay HTTP is faked at ``requests.request``; everything else (DB, migrations,
FastAPI routes) is real.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import threading
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

SANDBOX_KEY = "sec_sandbox_key_0000000000000000000000000"
SANDBOX_SECRET = "s" * 64
SANDBOX_WH = "sandbox-webhook-shared-secret"
LIVE_KEY = "sec_live_key_00000000000000000000000000000"
LIVE_SECRET = "l" * 64
LIVE_WH = "live-webhook-shared-secret"


class _Resp:
    def __init__(self, status, body):
        self.status_code = status
        self._body = body

    def json(self):
        return self._body


class FakeSafepay:
    """Minimal stand-in for the Payments 2.0 endpoints the app calls."""

    def __init__(self, environment="sandbox"):
        self.environment = environment
        self.trackers = {}
        self.calls = []

    def __call__(self, method, url, headers=None, json=None, timeout=None):  # noqa: A002 - mirrors requests
        self.calls.append((method, url, dict(headers or {})))
        path = url.split(".com", 1)[1]
        if method == "POST" and path == "/order/payments/v3/":
            token = f"track_{uuid.uuid4()}"
            self.trackers[token] = {
                "token": token, "environment": self.environment, "state": "TRACKER_STARTED",
                "metadata": {"order_id": {"key": "order_id", "value": json["metadata"]["order_id"]}},
                "purchase_totals": {
                    "quote_amount": {"currency": json["currency"], "amount": json["amount"]},
                    "base_amount": {"currency": "PKR", "amount": int(json["amount"] * 276.475)},
                    "conversion_rate": {"base_currency": "PKR", "quote_currency": json["currency"], "rate": 276.475},
                },
            }
            return _Resp(201, {"data": {"tracker": dict(self.trackers[token])}, "status": {"errors": [], "message": "success"}})
        if method == "POST" and path == "/client/passport/v1/token":
            return _Resp(200, {"data": "tbt-opaque"})
        if method == "GET" and path.startswith("/reporter/api/v1/payments/"):
            token = path.rsplit("/", 1)[1]
            if token not in self.trackers:
                return _Resp(404, {"status": {"errors": ["not found"]}})
            return _Resp(200, {"ok": True, "data": dict(self.trackers[token])})
        return _Resp(404, {})

    def set_state(self, tracker, state):
        self.trackers[tracker]["state"] = state


@pytest.fixture
def safepay(test_db, monkeypatch):
    import config

    monkeypatch.setattr(config, "SAFEPAY_ENV", "sandbox")
    monkeypatch.setattr(config, "SAFEPAY_SANDBOX_API_KEY", SANDBOX_KEY)
    monkeypatch.setattr(config, "SAFEPAY_SANDBOX_SECRET_KEY", SANDBOX_SECRET)
    monkeypatch.setattr(config, "SAFEPAY_SANDBOX_WEBHOOK_SECRET", SANDBOX_WH)
    monkeypatch.setattr(config, "SAFEPAY_LIVE_API_KEY", "")
    monkeypatch.setattr(config, "SAFEPAY_LIVE_SECRET_KEY", "")
    monkeypatch.setattr(config, "SAFEPAY_LIVE_WEBHOOK_SECRET", "")
    monkeypatch.setattr(config, "SAFEPAY_CHECKOUT_ALLOWLIST", ["buyer@example.com"])
    monkeypatch.setattr(config, "SAFEPAY_SANDBOX_OPEN_TO_ALL", False)
    monkeypatch.setattr(config, "FRONTEND_URL", "https://app.example.test")
    fake = FakeSafepay("sandbox")
    monkeypatch.setattr("payments.safepay_service.requests.request", fake)
    from payments import safepay_checkout

    safepay_checkout._last_check.clear()
    return fake


@pytest.fixture
def buyer(db_connection):
    cur = db_connection.cursor()
    cur.execute(
        "INSERT INTO users (username, email, password_hash, is_approved, created_at, credit_balance) VALUES (?, ?, ?, ?, ?, ?)",
        ("buyer", "buyer@example.com", "x", 1, datetime.now().isoformat(), 100),
    )
    db_connection.commit()
    return {"id": int(cur.lastrowid), "username": "buyer", "email": "buyer@example.com"}


@pytest.fixture
def pack(db_connection):
    from db.payment_crud import create_credit_package

    return create_credit_package(name="Starter", credits=500, base_price_cents=2500,
                                 display_price_cents=2500, is_active=True)


def _start(buyer, pack, key=None):
    from payments import safepay_checkout

    return safepay_checkout.start_package_checkout(
        user=buyer, package_id=pack, quantity=1, promo_code=None, idempotency_key=key or str(uuid.uuid4()))


def _balance(uid):
    from db.base import execute_query

    return int(execute_query("SELECT credit_balance FROM users WHERE id = ?", (uid,), fetch_one=True, commit=False)[0])


def _ledger(uid):
    from db.base import execute_query

    return execute_query("SELECT amount, transaction_type, reason FROM credit_ledger WHERE user_id = ? ORDER BY id",
                         (uid,), fetch_all=True, commit=False) or []


def _txn(tid):
    from payments.safepay_checkout import get_transaction

    return get_transaction(tid)


def _event(start, *, etype="payment.succeeded", token=None, amount=None, currency="USD", tracker=None,
           order_id=None, merchant_key=SANDBOX_KEY, state="TRACKER_ENDED"):
    data = {"tracker": tracker or start["provider_transaction_id"], "intent": "CYBERSOURCE", "state": state,
            "currency": currency, "metadata": {"order_id": order_id or start["transaction_id"], "source": "hosted"}}
    if etype == "payment.succeeded":
        data.update({"amount": start["amount_cents"] if amount is None else amount, "net": 1, "fee": 1})
    else:
        data.update({"code": "DECLINED", "message": "Card declined"})
    body = {"token": token or f"evt_{uuid.uuid4()}", "version": "2.0.0", "merchant_api_key": merchant_key,
            "type": etype, "data": data}
    return json.dumps(body, separators=(", ", ": ")).encode()  # deliberately non-compact


def _sign(raw: bytes, secret=SANDBOX_WH):
    return hmac.new(secret.encode(), raw, hashlib.sha512).hexdigest()


def _client(user):
    from main import app, get_current_user

    async def current():
        return user

    app.dependency_overrides[get_current_user] = current
    return app, TestClient(app)


# ------------------------------------------------------------------ environments & signatures
def test_hosts_and_credentials_are_strictly_per_environment(monkeypatch):
    import config
    from payments.safepay_service import SafepayNotConfigured, SafepayService

    monkeypatch.setattr(config, "SAFEPAY_SANDBOX_API_KEY", SANDBOX_KEY)
    monkeypatch.setattr(config, "SAFEPAY_SANDBOX_SECRET_KEY", SANDBOX_SECRET)
    monkeypatch.setattr(config, "SAFEPAY_LIVE_API_KEY", "")
    monkeypatch.setattr(config, "SAFEPAY_LIVE_SECRET_KEY", "")
    sb = SafepayService("sandbox")
    assert sb.hosts["api"] == "https://sandbox.api.getsafepay.com"
    prod = SafepayService("production")
    assert prod.hosts == {"api": "https://api.getsafepay.com", "checkout": "https://getsafepay.com"}
    # Production never falls back to the sandbox keys.
    assert not prod.checkout_configured()
    with pytest.raises(SafepayNotConfigured):
        prod.create_auth_token()
    # Identical sandbox/live keys are refused outright.
    monkeypatch.setattr(config, "SAFEPAY_LIVE_API_KEY", SANDBOX_KEY)
    monkeypatch.setattr(config, "SAFEPAY_LIVE_SECRET_KEY", SANDBOX_SECRET)
    with pytest.raises(SafepayNotConfigured):
        SafepayService("production").create_auth_token()


def test_webhook_signature_raw_and_compact(monkeypatch):
    import config
    from payments.safepay_service import SafepayService

    monkeypatch.setattr(config, "SAFEPAY_SANDBOX_WEBHOOK_SECRET", SANDBOX_WH)
    svc = SafepayService("sandbox")
    raw = b'{"a": 1, "b": "x"}'
    assert svc.verify_webhook_signature(raw, _sign(raw))
    compact = b'{"a":1,"b":"x"}'
    assert svc.verify_webhook_signature(raw, _sign(compact))
    assert not svc.verify_webhook_signature(raw, _sign(raw, "wrong"))
    assert not svc.verify_webhook_signature(raw, "")
    monkeypatch.setattr(config, "SAFEPAY_SANDBOX_WEBHOOK_SECRET", "")
    assert not SafepayService("sandbox").verify_webhook_signature(raw, _sign(raw))


# ------------------------------------------------------------------ checkout start
def test_start_checkout_creates_tracker_for_exact_pack_price(safepay, buyer, pack):
    start = _start(buyer, pack)
    assert start["amount_cents"] == 2500 and start["currency"] == "USD" and start["credits_purchased"] == 500
    url = start["checkout_url"]
    assert url.startswith("https://sandbox.api.getsafepay.com/embedded/?")
    assert "environment=sandbox" in url and "source=hosted" in url
    assert f"payment%2Freturn%2F{start['transaction_id']}" in url
    assert f"payment%2Fcancelled%2F{start['transaction_id']}" in url
    txn = _txn(start["transaction_id"])
    assert txn["status"] == "processing" and txn["payment_provider"] == "safepay"
    assert txn["provider_transaction_id"] == start["provider_transaction_id"]
    assert txn["provider_environment"] == "sandbox"
    session_call = safepay.calls[0]
    assert session_call[2]["X-SFPY-MERCHANT-SECRET"] == SANDBOX_SECRET
    assert _balance(buyer["id"]) == 100  # nothing granted at checkout start


def test_sandbox_checkout_is_limited_to_allowlist(safepay, buyer, pack, monkeypatch):
    import config
    from payments import safepay_checkout

    other = {"id": 999999, "email": "someone@else.test"}
    ok, reason, env = safepay_checkout.checkout_availability(other)
    assert not ok and env == "sandbox" and "launching soon" in reason
    with pytest.raises(safepay_checkout.CheckoutUnavailable):
        _start(other, pack)
    monkeypatch.setattr(config, "SAFEPAY_CHECKOUT_ALLOWLIST", [])
    assert not safepay_checkout.checkout_availability(buyer)[0]  # sandbox + empty list = closed
    monkeypatch.setattr(config, "SAFEPAY_SANDBOX_OPEN_TO_ALL", True)
    assert safepay_checkout.checkout_availability(other)[0]


def test_purchase_endpoint_and_retired_coinbase_endpoints(safepay, buyer, pack):
    app, client = _client(buyer)
    try:
        r = client.post("/api/payments/purchase", json={"package_id": pack, "idempotency_key": "k1"})
        assert r.status_code == 200, r.text
        assert r.json()["checkout_url"].startswith("https://sandbox.api.getsafepay.com/embedded/")
        again = client.post("/api/payments/purchase", json={"package_id": pack, "idempotency_key": "k1"})
        assert again.status_code == 400
        assert client.post("/api/payments/purchase", json={"package_id": pack, "idempotency_key": "k2",
                                                           "payment_provider": "coinbase"}).status_code == 410
        assert client.post("/api/payments/simple-purchase", json={"credits": 100}).status_code == 410
        assert client.post("/api/payments/crypto/create-charge",
                           json={"package_id": pack, "idempotency_key": "k3"}).status_code == 410
        cfg = client.get("/api/payments/checkout-config").json()
        assert cfg == {"provider": "safepay", "environment": "sandbox", "currency": "USD",
                       "checkout_available": True, "unavailable_reason": None}
    finally:
        app.dependency_overrides.clear()


# ------------------------------------------------------------------ webhook: success, duplicates, mismatches
def test_signed_webhook_credits_exactly_once(safepay, buyer, pack):
    start = _start(buyer, pack)
    app, client = _client(buyer)
    try:
        raw = _event(start, token="evt_one")
        r1 = client.post("/api/webhooks/safepay", content=raw, headers={"X-SFPY-SIGNATURE": _sign(raw)})
        assert r1.status_code == 200 and r1.json()["credited"] is True
        r2 = client.post("/api/webhooks/safepay", content=raw, headers={"X-SFPY-SIGNATURE": _sign(raw)})
        assert r2.json().get("duplicate") is True
        raw2 = _event(start, token="evt_two")  # same payment, new delivery id
        r3 = client.post("/api/webhooks/safepay", content=raw2, headers={"X-SFPY-SIGNATURE": _sign(raw2)})
        assert r3.status_code == 200 and r3.json().get("credited") is False
        st = client.get(f"/api/payments/safepay/{start['transaction_id']}/status").json()
        assert st["status"] == "completed" and st["credits_purchased"] == 500
    finally:
        app.dependency_overrides.clear()
    assert _balance(buyer["id"]) == 600
    purchases = [row for row in _ledger(buyer["id"]) if row[1] == "credit"]
    assert len(purchases) == 1 and purchases[0][0] == 500 and "[sandbox]" in purchases[0][2]
    txn = _txn(start["transaction_id"])
    assert txn["status"] == "completed" and txn["invoice_id"]


def test_concurrent_confirmations_credit_once(safepay, buyer, pack):
    from payments import safepay_checkout

    start = _start(buyer, pack)
    results = []

    def go():
        results.append(safepay_checkout.fulfill(start["transaction_id"], tracker=start["provider_transaction_id"],
                                                source="test"))

    threads = [threading.Thread(target=go) for _ in range(6)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sum(1 for r in results if r.get("credited")) == 1
    assert _balance(buyer["id"]) == 600


@pytest.mark.parametrize("change", [
    {"amount": 2499}, {"currency": "PKR"}, {"tracker": "track_someone-else"},
])
def test_webhook_with_mismatched_payment_does_not_credit(safepay, buyer, pack, change):
    start = _start(buyer, pack)
    raw = _event(start, **change)
    app, client = _client(buyer)
    try:
        r = client.post("/api/webhooks/safepay", content=raw, headers={"X-SFPY-SIGNATURE": _sign(raw)})
    finally:
        app.dependency_overrides.clear()
    assert r.status_code == 200
    assert _balance(buyer["id"]) == 100
    assert _txn(start["transaction_id"])["status"] != "completed"


def test_bad_signature_or_foreign_merchant_is_rejected(safepay, buyer, pack):
    start = _start(buyer, pack)
    app, client = _client(buyer)
    try:
        raw = _event(start)
        assert client.post("/api/webhooks/safepay", content=raw,
                           headers={"X-SFPY-SIGNATURE": _sign(raw, LIVE_WH)}).status_code == 401
        assert client.post("/api/webhooks/safepay", content=raw).status_code == 401
        foreign = _event(start, merchant_key=LIVE_KEY)
        assert client.post("/api/webhooks/safepay", content=foreign,
                           headers={"X-SFPY-SIGNATURE": _sign(foreign)}).status_code == 401
    finally:
        app.dependency_overrides.clear()
    assert _balance(buyer["id"]) == 100


def test_production_mode_rejects_sandbox_signed_webhooks(safepay, buyer, pack, monkeypatch):
    import config

    start = _start(buyer, pack)
    monkeypatch.setattr(config, "SAFEPAY_ENV", "production")
    monkeypatch.setattr(config, "SAFEPAY_LIVE_API_KEY", LIVE_KEY)
    monkeypatch.setattr(config, "SAFEPAY_LIVE_SECRET_KEY", LIVE_SECRET)
    monkeypatch.setattr(config, "SAFEPAY_LIVE_WEBHOOK_SECRET", LIVE_WH)
    app, client = _client(buyer)
    try:
        raw = _event(start)
        assert client.post("/api/webhooks/safepay", content=raw,
                           headers={"X-SFPY-SIGNATURE": _sign(raw)}).status_code == 401
        # Even correctly signed with the live secret, a sandbox transaction is not credited in production.
        raw_live = _event(start, merchant_key=LIVE_KEY)
        r = client.post("/api/webhooks/safepay", content=raw_live, headers={"X-SFPY-SIGNATURE": _sign(raw_live, LIVE_WH)})
        assert r.status_code == 200 and r.json().get("ignored") == "mismatch"
        # And the status poll does not look a sandbox tracker up on the live API.
        calls_before = len(safepay.calls)
        assert client.get(f"/api/payments/safepay/{start['transaction_id']}/status").json()["status"] != "completed"
        assert len(safepay.calls) == calls_before
    finally:
        app.dependency_overrides.clear()
    assert _balance(buyer["id"]) == 100


# ------------------------------------------------------------------ failure, cancel, delay, timeout
def test_failed_then_retried_payment(safepay, buyer, pack):
    start = _start(buyer, pack)
    app, client = _client(buyer)
    try:
        failed = _event(start, etype="payment.failed", state="TRACKER_ENROLLED")
        assert client.post("/api/webhooks/safepay", content=failed,
                           headers={"X-SFPY-SIGNATURE": _sign(failed)}).status_code == 200
        st = client.get(f"/api/payments/safepay/{start['transaction_id']}/status").json()
        assert st["status"] == "failed"
        assert _balance(buyer["id"]) == 100
        # Shopper retries on the same Safepay page and succeeds.
        ok = _event(start)
        assert client.post("/api/webhooks/safepay", content=ok,
                           headers={"X-SFPY-SIGNATURE": _sign(ok)}).json()["credited"] is True
    finally:
        app.dependency_overrides.clear()
    assert _balance(buyer["id"]) == 600


def test_cancel_return_marks_cancelled_but_paid_tracker_still_credits(safepay, buyer, pack):
    first = _start(buyer, pack)
    second = _start(buyer, pack)
    safepay.set_state(second["provider_transaction_id"], "TRACKER_ENDED")
    app, client = _client(buyer)
    try:
        r = client.post(f"/api/payments/safepay/{first['transaction_id']}/cancel").json()
        assert r["status"] == "cancelled"
        r2 = client.post(f"/api/payments/safepay/{second['transaction_id']}/cancel").json()
        assert r2["status"] == "completed"
        other = {"id": 424242, "email": "x@y.z"}
        app.dependency_overrides.clear()
        app2, client2 = _client(other)
        assert client2.post(f"/api/payments/safepay/{first['transaction_id']}/cancel").status_code == 404
        assert client2.get(f"/api/payments/safepay/{first['transaction_id']}/status").status_code == 404
    finally:
        app.dependency_overrides.clear()
    assert _balance(buyer["id"]) == 600


def test_return_url_alone_never_credits_and_delayed_webhook_is_handled(safepay, buyer, pack):
    start = _start(buyer, pack)
    app, client = _client(buyer)
    try:
        # Browser came back (redirect_url) but Safepay has not confirmed: stays processing.
        st = client.get(f"/api/payments/safepay/{start['transaction_id']}/status").json()
        assert st["status"] == "processing"
        assert _balance(buyer["id"]) == 100
        # Payment completes; webhook is delayed. Server-side tracker lookup confirms it.
        safepay.set_state(start["provider_transaction_id"], "TRACKER_ENDED")
        from payments import safepay_checkout

        safepay_checkout._last_check.clear()
        st = client.get(f"/api/payments/safepay/{start['transaction_id']}/status").json()
        assert st["status"] == "completed"
        # The late webhook arrives afterwards: acknowledged, no second credit.
        raw = _event(start)
        r = client.post("/api/webhooks/safepay", content=raw, headers={"X-SFPY-SIGNATURE": _sign(raw)})
        assert r.status_code == 200 and r.json().get("credited") is False
    finally:
        app.dependency_overrides.clear()
    assert _balance(buyer["id"]) == 600


def test_reconciler_expires_abandoned_checkout_and_honours_late_payment(safepay, buyer, pack):
    from db.base import execute_query
    from payments import safepay_checkout

    start = _start(buyer, pack)
    old = (datetime.now(timezone.utc) - timedelta(minutes=120)).strftime("%Y-%m-%d %H:%M:%S")
    execute_query("UPDATE payment_transactions SET created_at = ? WHERE transaction_id = ?",
                  (old, start["transaction_id"]))
    counts = safepay_checkout.reconcile_open_transactions()
    assert counts["expired"] == 1
    st = safepay_checkout.public_status(_txn(start["transaction_id"]))
    assert st["status"] == "expired"
    # Safepay later reports the payment as completed: the customer is still credited, once.
    app, client = _client(buyer)
    try:
        raw = _event(start)
        assert client.post("/api/webhooks/safepay", content=raw,
                           headers={"X-SFPY-SIGNATURE": _sign(raw)}).json()["credited"] is True
    finally:
        app.dependency_overrides.clear()
    assert _balance(buyer["id"]) == 600


def test_reconciler_completes_paid_tracker_without_webhook(safepay, buyer, pack):
    from payments import safepay_checkout

    start = _start(buyer, pack)
    safepay.set_state(start["provider_transaction_id"], "TRACKER_ENDED")
    assert safepay_checkout.reconcile_open_transactions()["completed"] == 1
    assert safepay_checkout.reconcile_open_transactions()["completed"] == 0
    assert _balance(buyer["id"]) == 600


def test_existing_coinbase_purchase_still_settles_by_webhook(test_db, sample_user, monkeypatch):
    """Coinbase is closed for new checkouts, but an in-flight charge still completes."""
    import config
    from db.base import execute_query
    from main import app

    monkeypatch.setattr(config, "COINBASE_WEBHOOK_SECRET", "cb-secret")
    import main

    monkeypatch.setattr(main._webhook_handler._coinbase, "webhook_secret", "cb-secret")
    txn_id = str(uuid.uuid4())
    execute_query(
        """INSERT INTO payment_transactions (transaction_id, user_id, payment_provider, provider_transaction_id,
           amount_cents, currency, credits_purchased, status, idempotency_key, created_at, updated_at)
           VALUES (?, ?, 'coinbase', 'CHG1', 2500, 'USD', 500, 'processing', ?, ?, ?)""",
        (txn_id, sample_user, "cb-" + txn_id, datetime.now().isoformat(), datetime.now().isoformat()),
    )
    body = json.dumps({"event": {"id": "cb-evt-1", "type": "charge:confirmed",
                                 "data": {"id": "CHG1", "metadata": {"transaction_id": txn_id}}}}).encode()
    sig = hmac.new(b"cb-secret", body, hashlib.sha256).hexdigest()
    r = TestClient(app).post("/api/webhooks/coinbase", content=body, headers={"X-CC-Webhook-Signature": sig})
    assert r.status_code == 200, r.text
    assert _txn_status(txn_id) == "completed"
    assert _balance(sample_user) == 600


def _txn_status(tid):
    from db.base import execute_query

    return execute_query("SELECT status FROM payment_transactions WHERE transaction_id = ?", (tid,),
                         fetch_one=True, commit=False)[0]
