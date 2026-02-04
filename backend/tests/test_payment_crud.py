"""
Tests for payment CRUD operations

Verifies:
- Credit package CRUD
- Payment transaction CRUD
- Invoice CRUD
- Payment method CRUD
- Promo code CRUD
"""

import pytest
from datetime import datetime
from db.payment_crud import (
    # Credit Packages
    create_credit_package,
    get_credit_package,
    list_active_packages,
    update_credit_package,
    delete_credit_package,

    # Payment Transactions
    create_payment_transaction,
    get_transaction,
    get_user_transactions,
    update_transaction_status,

    # Invoices
    create_invoice,
    get_invoice,
    get_user_invoices,

    # Payment Methods
    create_payment_method,
    get_user_payment_methods,
    set_default_payment_method,
    delete_payment_method,

    # Promo Codes
    create_promo_code,
    get_promo_code,
    increment_promo_code_usage,
)


# ============================================================================
# Credit Package Tests
# ============================================================================

def test_create_credit_package(test_db):
    """Test creating a credit package"""
    package_id = create_credit_package(
        name="Starter Pack",
        credits=50,
        base_price_cents=500,
        display_price_cents=500,
        is_active=True,
        is_featured=False
    )

    assert package_id > 0, "Should return valid package ID"


def test_get_credit_package(sample_credit_package):
    """Test retrieving a credit package"""
    package = get_credit_package(sample_credit_package)

    assert package is not None, "Should find the package"
    assert package[1] == "Test Package"  # name column
    assert package[2] == 100  # credits column


def test_list_active_packages(sample_credit_package):
    """Test listing active packages"""
    packages = list_active_packages()

    assert len(packages) > 0, "Should have at least one package"
    assert any(p[0] == sample_credit_package for p in packages), "Should include our test package"


def test_update_credit_package(sample_credit_package):
    """Test updating a credit package"""
    success = update_credit_package(sample_credit_package, {
        "name": "Updated Package",
        "credits": 200
    })

    assert success is True, "Update should succeed"

    # Verify the update
    package = get_credit_package(sample_credit_package)
    assert package[1] == "Updated Package"
    assert package[2] == 200


def test_delete_credit_package(sample_credit_package):
    """Test soft-deleting a credit package"""
    success = delete_credit_package(sample_credit_package)
    assert success is True, "Delete should succeed"

    # Verify it's no longer in active packages
    active_packages = list_active_packages()
    assert not any(p[0] == sample_credit_package for p in active_packages), "Should not be in active list"


# ============================================================================
# Payment Transaction Tests
# ============================================================================

def test_create_payment_transaction(sample_user):
    """Test creating a payment transaction"""
    txn_id = create_payment_transaction(
        transaction_id="txn_test_123",
        user_id=sample_user,
        payment_provider="stripe",
        amount_cents=1000,
        currency="USD",
        credits_purchased=100,
        idempotency_key="idempotency_test_123",
        status="pending"
    )

    assert txn_id > 0, "Should return valid transaction ID"


def test_get_transaction(sample_user):
    """Test retrieving a transaction"""
    # Create transaction
    create_payment_transaction(
        transaction_id="txn_test_456",
        user_id=sample_user,
        payment_provider="stripe",
        amount_cents=2000,
        currency="USD",
        credits_purchased=200,
        idempotency_key="idempotency_test_456"
    )

    # Retrieve it
    txn = get_transaction("txn_test_456")

    assert txn is not None, "Should find the transaction"
    assert txn[5] == 2000  # amount_cents column


def test_update_transaction_status(sample_user):
    """Test updating transaction status"""
    # Create transaction
    create_payment_transaction(
        transaction_id="txn_test_789",
        user_id=sample_user,
        payment_provider="stripe",
        amount_cents=1500,
        currency="USD",
        credits_purchased=150,
        idempotency_key="idempotency_test_789"
    )

    # Update status
    success = update_transaction_status("txn_test_789", "completed", "stripe_ch_123")
    assert success is True, "Status update should succeed"

    # Verify
    txn = get_transaction("txn_test_789")
    assert txn[7] == "completed"  # status column


def test_get_user_transactions(sample_user):
    """Test getting user transactions"""
    # Create a transaction
    create_payment_transaction(
        transaction_id="txn_user_test",
        user_id=sample_user,
        payment_provider="stripe",
        amount_cents=1000,
        currency="USD",
        credits_purchased=100,
        idempotency_key="idempotency_user_test"
    )

    # Get transactions
    transactions = get_user_transactions(sample_user)

    assert len(transactions) > 0, "Should have transactions"
    assert any(t[1] == "txn_user_test" for t in transactions), "Should include our transaction"


# ============================================================================
# Invoice Tests
# ============================================================================

def test_create_invoice(sample_user):
    """Test creating an invoice"""
    invoice_id = create_invoice(
        invoice_number="INV-TEST-001",
        user_id=sample_user,
        invoice_type="purchase",
        amount_cents=1000,
        total_amount_cents=1000,
        billing_name="Test User",
        billing_email="test@example.com"
    )

    assert invoice_id > 0, "Should return valid invoice ID"


def test_get_invoice(sample_user):
    """Test retrieving an invoice"""
    # Create invoice
    create_invoice(
        invoice_number="INV-TEST-002",
        user_id=sample_user,
        invoice_type="purchase",
        amount_cents=2000,
        total_amount_cents=2000
    )

    # Retrieve it
    invoice = get_invoice("INV-TEST-002")

    assert invoice is not None, "Should find the invoice"
    assert invoice[1] == "INV-TEST-002"  # invoice_number column


# ============================================================================
# Payment Method Tests
# ============================================================================

def test_create_payment_method(sample_user):
    """Test creating a payment method"""
    method_id = create_payment_method(
        user_id=sample_user,
        stripe_payment_method_id="pm_test_123",
        method_type="card",
        card_brand="Visa",
        card_last4="4242"
    )

    assert method_id > 0, "Should return valid payment method ID"


def test_get_user_payment_methods(sample_user):
    """Test getting user payment methods"""
    # Create a method
    create_payment_method(
        user_id=sample_user,
        stripe_payment_method_id="pm_test_456",
        card_brand="Mastercard",
        card_last4="5555"
    )

    # Get methods
    methods = get_user_payment_methods(sample_user)

    assert len(methods) > 0, "Should have payment methods"


def test_set_default_payment_method(sample_user):
    """Test setting default payment method"""
    # Create two methods
    method1 = create_payment_method(
        user_id=sample_user,
        stripe_payment_method_id="pm_test_default1",
        card_last4="1111"
    )
    method2 = create_payment_method(
        user_id=sample_user,
        stripe_payment_method_id="pm_test_default2",
        card_last4="2222"
    )

    # Set method2 as default
    success = set_default_payment_method(sample_user, method2)
    assert success is True, "Should set default successfully"


# ============================================================================
# Promo Code Tests
# ============================================================================

def test_create_promo_code(test_db):
    """Test creating a promo code"""
    promo_id = create_promo_code(
        code="SAVE10",
        promo_type="percentage_off",
        discount_percentage=10.0,
        is_active=True
    )

    assert promo_id > 0, "Should return valid promo code ID"


def test_get_promo_code(sample_promo_code):
    """Test retrieving a promo code"""
    promo = get_promo_code("TEST20")

    assert promo is not None, "Should find the promo code"
    assert promo[1] == "TEST20"  # code column


def test_increment_promo_code_usage(sample_promo_code):
    """Test incrementing promo code usage"""
    success = increment_promo_code_usage(sample_promo_code)
    assert success is True, "Should increment usage count"
