from fastapi.testclient import TestClient


def test_purchase_endpoint_returns_503_for_coinbase_outage(test_db, monkeypatch):
    from main import app, purchase_credits
    from payments.coinbase_service import CoinbaseProviderUnavailableError

    async def fake_current_user():
        return {"id": 123, "username": "tester"}

    def fake_purchase(**kwargs):
        raise CoinbaseProviderUnavailableError(
            "Coinbase Commerce is temporarily unavailable. Please try again shortly."
        )

    monkeypatch.setattr("main._payment_processor.initiate_coinbase_package_purchase", fake_purchase)
    app.dependency_overrides.clear()
    app.dependency_overrides[purchase_credits.__globals__["get_current_user"]] = fake_current_user

    try:
        client = TestClient(app)
        response = client.post(
            "/api/payments/purchase",
            json={
                "package_id": 1,
                "quantity": 1,
                "idempotency_key": "outage-test-key",
                "provider": "coinbase",
            },
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 503
    assert response.json()["detail"] == "Coinbase Commerce is temporarily unavailable. Please try again shortly."


def test_purchase_endpoint_returns_502_for_coinbase_provider_error(test_db, monkeypatch):
    from main import app, purchase_credits
    from payments.coinbase_service import CoinbaseServiceError

    async def fake_current_user():
        return {"id": 123, "username": "tester"}

    def fake_purchase(**kwargs):
        raise CoinbaseServiceError("upstream failure")

    monkeypatch.setattr("main._payment_processor.initiate_coinbase_package_purchase", fake_purchase)
    app.dependency_overrides.clear()
    app.dependency_overrides[purchase_credits.__globals__["get_current_user"]] = fake_current_user

    try:
        client = TestClient(app)
        response = client.post(
            "/api/payments/purchase",
            json={
                "package_id": 1,
                "quantity": 1,
                "idempotency_key": "provider-error-key",
                "provider": "coinbase",
            },
        )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 502
    assert response.json()["detail"] == "Coinbase Commerce request failed. Please try again."


def test_coinbase_purchase_marks_transaction_failed_on_charge_error(
    test_db,
    sample_user,
    sample_credit_package,
    monkeypatch,
):
    from db.base import execute_query
    from payments.coinbase_service import CoinbaseProviderUnavailableError
    from payments.payment_processor import PaymentProcessor

    processor = PaymentProcessor()

    def fake_charge(**kwargs):
        raise CoinbaseProviderUnavailableError(
            "Coinbase Commerce is temporarily unavailable. Please try again shortly."
        )

    monkeypatch.setattr(processor._coinbase, "create_charge", fake_charge)

    try:
        processor.initiate_coinbase_package_purchase(
            user_id=sample_user,
            package_id=sample_credit_package,
            quantity=1,
            promo_code=None,
            idempotency_key="failed-charge-key",
            currency="USD",
        )
    except CoinbaseProviderUnavailableError:
        pass
    else:
        raise AssertionError("Expected CoinbaseProviderUnavailableError")

    row = execute_query(
        """
        SELECT status
        FROM payment_transactions
        WHERE idempotency_key = ?
        """,
        ("failed-charge-key",),
        fetch_one=True,
        commit=False,
    )
    assert row is not None
    assert row[0] == "failed"
