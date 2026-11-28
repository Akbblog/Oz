"""Public pricing endpoint (no account) and 'credits never expire' consistency."""
from fastapi.testclient import TestClient


def test_public_credit_packs_needs_no_account_and_uses_checkout_price(test_db, db_connection):
    from db.payment_crud import create_credit_package
    from main import app

    create_credit_package(name="Starter", credits=500, base_price_cents=2500, display_price_cents=2500, is_active=True)
    create_credit_package(name="Old", credits=100, base_price_cents=1000, display_price_cents=500, is_active=False)
    r = TestClient(app).get("/api/public/credit-packs")
    assert r.status_code == 200
    body = r.json()
    assert body["currency"] == "USD"
    assert [(p["name"], p["credits"], p["price_cents"]) for p in body["packs"]] == [("Starter", 500, 2500)]
    assert set(body["packs"][0]) == {"id", "name", "credits", "price_cents", "is_featured"}


def test_purchased_credits_have_no_expiry():
    import config

    assert int(config.DEFAULT_CREDIT_CONFIG["credit_expiry_days"]) == 0
