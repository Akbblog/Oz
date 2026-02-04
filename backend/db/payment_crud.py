"""
CRUD operations for payment and subscription entities

Provides database operations for:
- Credit packages
- Payment transactions
- Invoices
- Payment methods
- Webhook events
- Subscription plans
- User subscriptions
- Promo codes
- Pricing tiers
"""

import logging
from datetime import datetime
from typing import List, Optional, Dict, Any
from .base import execute_query, execute_many, get_placeholder

logger = logging.getLogger(__name__)


# ============================================================================
# Credit Packages CRUD
# ============================================================================

def create_credit_package(
    name: str,
    credits: int,
    base_price_cents: int,
    display_price_cents: int,
    discount_percentage: float = 0.00,
    tier_id: Optional[int] = None,
    is_active: bool = True,
    is_featured: bool = False,
    features: Optional[str] = None
) -> int:
    """Create a new credit package"""
    query = f"""
        INSERT INTO credit_packages (
            name, credits, base_price_cents, display_price_cents,
            discount_percentage, tier_id, is_active, is_featured, features,
            created_at, updated_at
        ) VALUES ({', '.join([get_placeholder()] * 11)})
    """

    now = datetime.now().isoformat()
    params = (
        name, credits, base_price_cents, display_price_cents,
        discount_percentage, tier_id, 1 if is_active else 0, 1 if is_featured else 0,
        features, now, now
    )

    package_id = execute_query(query, params)
    logger.info(f"Created credit package '{name}' with ID {package_id}")
    return package_id


def get_credit_package(package_id: int) -> Optional[Dict]:
    """Get a credit package by ID"""
    query = f"SELECT * FROM credit_packages WHERE id = {get_placeholder()}"
    return execute_query(query, (package_id,), fetch_one=True)


def list_active_packages() -> List[Dict]:
    """List all active credit packages"""
    query = "SELECT * FROM credit_packages WHERE is_active = 1 ORDER BY display_price_cents ASC"
    rows = execute_query(query, fetch_all=True)
    return rows if rows else []


def update_credit_package(package_id: int, updates: Dict[str, Any]) -> bool:
    """Update a credit package"""
    if not updates:
        return False

    set_clauses = []
    params = []

    for key, value in updates.items():
        set_clauses.append(f"{key} = {get_placeholder()}")
        params.append(value)

    # Add updated_at
    set_clauses.append(f"updated_at = {get_placeholder()}")
    params.append(datetime.now().isoformat())

    # Add ID for WHERE clause
    params.append(package_id)

    query = f"UPDATE credit_packages SET {', '.join(set_clauses)} WHERE id = {get_placeholder()}"
    rows_affected = execute_query(query, tuple(params))

    logger.info(f"Updated credit package {package_id}: {updates}")
    return rows_affected > 0


def delete_credit_package(package_id: int) -> bool:
    """Soft delete a credit package (set is_active = 0)"""
    return update_credit_package(package_id, {'is_active': 0})


# ============================================================================
# Payment Transactions CRUD
# ============================================================================

def create_payment_transaction(
    transaction_id: str,
    user_id: int,
    payment_provider: str,
    amount_cents: int,
    currency: str,
    credits_purchased: int,
    idempotency_key: str,
    status: str = "pending",
    provider_transaction_id: Optional[str] = None,
    package_id: Optional[int] = None,
    subscription_id: Optional[int] = None,
    promo_code_id: Optional[int] = None,
    invoice_id: Optional[int] = None
) -> int:
    """Create a new payment transaction"""
    query = f"""
        INSERT INTO payment_transactions (
            transaction_id, user_id, payment_provider, provider_transaction_id,
            amount_cents, currency, credits_purchased, status, idempotency_key,
            package_id, subscription_id, promo_code_id, invoice_id,
            created_at, updated_at
        ) VALUES ({', '.join([get_placeholder()] * 15)})
    """

    now = datetime.now().isoformat()
    params = (
        transaction_id, user_id, payment_provider, provider_transaction_id,
        amount_cents, currency, credits_purchased, status, idempotency_key,
        package_id, subscription_id, promo_code_id, invoice_id,
        now, now
    )

    txn_id = execute_query(query, params)
    logger.info(f"Created payment transaction {transaction_id} for user {user_id}")
    return txn_id


def get_transaction(transaction_id: str) -> Optional[Dict]:
    """Get a payment transaction by transaction_id (UUID)"""
    # Explicit column order for stable tuple indices (tests rely on this).
    query = f"""
        SELECT
            id, transaction_id, user_id, payment_provider, provider_transaction_id,
            amount_cents, currency, status, credits_purchased, idempotency_key,
            package_id, subscription_id, promo_code_id, invoice_id,
            created_at, updated_at
        FROM payment_transactions
        WHERE transaction_id = {get_placeholder()}
    """
    return execute_query(query, (transaction_id,), fetch_one=True)


def get_transaction_by_id(txn_id: int) -> Optional[Dict]:
    """Get a payment transaction by database ID"""
    query = f"SELECT * FROM payment_transactions WHERE id = {get_placeholder()}"
    return execute_query(query, (txn_id,), fetch_one=True)


def get_user_transactions(user_id: int, limit: int = 50) -> List[Dict]:
    """Get payment transactions for a user"""
    query = f"""
        SELECT
            id, transaction_id, user_id, payment_provider, provider_transaction_id,
            amount_cents, currency, status, credits_purchased, idempotency_key,
            package_id, subscription_id, promo_code_id, invoice_id,
            created_at, updated_at
        FROM payment_transactions
        WHERE user_id = {get_placeholder()}
        ORDER BY created_at DESC
        LIMIT {get_placeholder()}
    """
    rows = execute_query(query, (user_id, limit), fetch_all=True)
    return rows if rows else []


def update_transaction_status(
    transaction_id: str,
    status: str,
    provider_txn_id: Optional[str] = None
) -> bool:
    """Update payment transaction status"""
    updates = {'status': status, 'updated_at': datetime.now().isoformat()}
    if provider_txn_id:
        updates['provider_transaction_id'] = provider_txn_id

    set_clauses = [f"{k} = {get_placeholder()}" for k in updates.keys()]
    params = list(updates.values()) + [transaction_id]

    query = f"""
        UPDATE payment_transactions
        SET {', '.join(set_clauses)}
        WHERE transaction_id = {get_placeholder()}
    """

    rows_affected = execute_query(query, tuple(params))
    logger.info(f"Updated transaction {transaction_id} to status '{status}'")
    return rows_affected > 0


def link_transaction_to_invoice(transaction_id: str, invoice_id: int) -> bool:
    """Link a payment transaction to an invoice"""
    query = f"""
        UPDATE payment_transactions
        SET invoice_id = {get_placeholder()}, updated_at = {get_placeholder()}
        WHERE transaction_id = {get_placeholder()}
    """
    params = (invoice_id, datetime.now().isoformat(), transaction_id)
    rows_affected = execute_query(query, params)
    return rows_affected > 0


# ============================================================================
# Invoices CRUD
# ============================================================================

def create_invoice(
    invoice_number: str,
    user_id: int,
    invoice_type: str,
    amount_cents: int,
    total_amount_cents: int,
    tax_amount_cents: int = 0,
    transaction_id: Optional[int] = None,
    subscription_id: Optional[int] = None,
    status: str = "paid",
    pdf_path: Optional[str] = None,
    line_items: Optional[str] = None,
    billing_name: Optional[str] = None,
    billing_email: Optional[str] = None,
    billing_address: Optional[str] = None
) -> int:
    """Create a new invoice"""
    query = f"""
        INSERT INTO invoices (
            invoice_number, user_id, transaction_id, subscription_id,
            invoice_type, amount_cents, tax_amount_cents, total_amount_cents,
            status, pdf_path, line_items, billing_name, billing_email,
            billing_address, created_at, updated_at
        ) VALUES ({', '.join([get_placeholder()] * 16)})
    """

    now = datetime.now().isoformat()
    params = (
        invoice_number, user_id, transaction_id, subscription_id,
        invoice_type, amount_cents, tax_amount_cents, total_amount_cents,
        status, pdf_path, line_items, billing_name, billing_email,
        billing_address, now, now
    )

    invoice_id = execute_query(query, params)
    logger.info(f"Created invoice {invoice_number} for user {user_id}")
    return invoice_id


def get_invoice(invoice_number: str) -> Optional[Dict]:
    """Get an invoice by invoice number"""
    query = f"SELECT * FROM invoices WHERE invoice_number = {get_placeholder()}"
    return execute_query(query, (invoice_number,), fetch_one=True)


def get_invoice_by_id(invoice_id: int) -> Optional[Dict]:
    """Get an invoice by database ID"""
    query = f"SELECT * FROM invoices WHERE id = {get_placeholder()}"
    return execute_query(query, (invoice_id,), fetch_one=True)


def get_user_invoices(user_id: int) -> List[Dict]:
    """Get all invoices for a user"""
    query = f"""
        SELECT * FROM invoices
        WHERE user_id = {get_placeholder()}
        ORDER BY created_at DESC
    """
    rows = execute_query(query, (user_id,), fetch_all=True)
    return rows if rows else []


def update_invoice_pdf_path(invoice_id: int, pdf_path: str) -> bool:
    """Update the PDF path for an invoice"""
    query = f"""
        UPDATE invoices
        SET pdf_path = {get_placeholder()}, updated_at = {get_placeholder()}
        WHERE id = {get_placeholder()}
    """
    params = (pdf_path, datetime.now().isoformat(), invoice_id)
    rows_affected = execute_query(query, params)
    return rows_affected > 0


# ============================================================================
# Payment Methods CRUD
# ============================================================================

def create_payment_method(
    user_id: int,
    stripe_payment_method_id: str,
    method_type: str = "card",
    is_default: bool = False,
    card_brand: Optional[str] = None,
    card_last4: Optional[str] = None,
    card_exp_month: Optional[int] = None,
    card_exp_year: Optional[int] = None,
    billing_name: Optional[str] = None,
    billing_email: Optional[str] = None,
    billing_address: Optional[str] = None
) -> int:
    """Create a new payment method"""
    query = f"""
        INSERT INTO payment_methods (
            user_id, stripe_payment_method_id, type, is_default,
            card_brand, card_last4, card_exp_month, card_exp_year,
            billing_name, billing_email, billing_address,
            created_at, updated_at
        ) VALUES ({', '.join([get_placeholder()] * 13)})
    """

    now = datetime.now().isoformat()
    params = (
        user_id, stripe_payment_method_id, method_type, 1 if is_default else 0,
        card_brand, card_last4, card_exp_month, card_exp_year,
        billing_name, billing_email, billing_address,
        now, now
    )

    method_id = execute_query(query, params)
    logger.info(f"Created payment method for user {user_id}")
    return method_id


def get_user_payment_methods(user_id: int) -> List[Dict]:
    """Get all payment methods for a user"""
    query = f"""
        SELECT * FROM payment_methods
        WHERE user_id = {get_placeholder()}
        ORDER BY is_default DESC, created_at DESC
    """
    rows = execute_query(query, (user_id,), fetch_all=True)
    return rows if rows else []


def set_default_payment_method(user_id: int, method_id: int) -> bool:
    """Set a payment method as default (unsets all others)"""
    # First, unset all defaults for this user
    query1 = f"""
        UPDATE payment_methods
        SET is_default = 0, updated_at = {get_placeholder()}
        WHERE user_id = {get_placeholder()}
    """
    execute_query(query1, (datetime.now().isoformat(), user_id))

    # Then set the specified method as default
    query2 = f"""
        UPDATE payment_methods
        SET is_default = 1, updated_at = {get_placeholder()}
        WHERE id = {get_placeholder()} AND user_id = {get_placeholder()}
    """
    params = (datetime.now().isoformat(), method_id, user_id)
    rows_affected = execute_query(query2, params)
    logger.info(f"Set payment method {method_id} as default for user {user_id}")
    return rows_affected > 0


def delete_payment_method(method_id: int) -> bool:
    """Delete a payment method"""
    query = f"DELETE FROM payment_methods WHERE id = {get_placeholder()}"
    rows_affected = execute_query(query, (method_id,))
    logger.info(f"Deleted payment method {method_id}")
    return rows_affected > 0


# ============================================================================
# Webhook Events CRUD
# ============================================================================

def create_webhook_event(
    webhook_id: str,
    provider: str,
    event_type: str,
    payload: str,
    status: str = "pending",
    retry_count: int = 0
) -> int:
    """Create a new webhook event"""
    query = f"""
        INSERT INTO webhook_events (
            webhook_id, provider, event_type, payload, status, retry_count, created_at
        ) VALUES ({', '.join([get_placeholder()] * 7)})
    """

    params = (
        webhook_id, provider, event_type, payload, status, retry_count,
        datetime.now().isoformat()
    )

    event_id = execute_query(query, params)
    logger.info(f"Created webhook event {webhook_id} from {provider}")
    return event_id


def get_pending_webhooks(limit: int = 100) -> List[Dict]:
    """Get pending webhook events"""
    query = f"""
        SELECT * FROM webhook_events
        WHERE status = 'pending'
        ORDER BY created_at ASC
        LIMIT {get_placeholder()}
    """
    rows = execute_query(query, (limit,), fetch_all=True)
    return rows if rows else []


def mark_webhook_processed(webhook_id: int) -> bool:
    """Mark a webhook event as processed"""
    query = f"""
        UPDATE webhook_events
        SET status = 'processed', processed_at = {get_placeholder()}
        WHERE id = {get_placeholder()}
    """
    params = (datetime.now().isoformat(), webhook_id)
    rows_affected = execute_query(query, params)
    logger.info(f"Marked webhook {webhook_id} as processed")
    return rows_affected > 0


def mark_webhook_failed(webhook_id: int, error_message: str) -> bool:
    """Mark a webhook event as failed and increment retry count"""
    query = f"""
        UPDATE webhook_events
        SET status = 'failed',
            error_message = {get_placeholder()},
            retry_count = retry_count + 1,
            processed_at = {get_placeholder()}
        WHERE id = {get_placeholder()}
    """
    params = (error_message, datetime.now().isoformat(), webhook_id)
    rows_affected = execute_query(query, params)
    logger.error(f"Marked webhook {webhook_id} as failed: {error_message}")
    return rows_affected > 0


# ============================================================================
# Subscription Plans CRUD
# ============================================================================

def create_subscription_plan(
    name: str,
    billing_interval: str,
    credits_per_period: int,
    base_price_cents: int,
    stripe_price_id: Optional[str] = None,
    rollover_credits: bool = True,
    max_rollover_credits: int = 0,
    trial_days: int = 0,
    is_active: bool = True,
    is_featured: bool = False,
    features: Optional[str] = None
) -> int:
    """Create a new subscription plan"""
    query = f"""
        INSERT INTO subscription_plans (
            name, billing_interval, credits_per_period, base_price_cents,
            stripe_price_id, rollover_credits, max_rollover_credits, trial_days,
            is_active, is_featured, features, created_at, updated_at
        ) VALUES ({', '.join([get_placeholder()] * 13)})
    """

    now = datetime.now().isoformat()
    params = (
        name, billing_interval, credits_per_period, base_price_cents,
        stripe_price_id, 1 if rollover_credits else 0, max_rollover_credits, trial_days,
        1 if is_active else 0, 1 if is_featured else 0, features, now, now
    )

    plan_id = execute_query(query, params)
    logger.info(f"Created subscription plan '{name}' with ID {plan_id}")
    return plan_id


def get_subscription_plan(plan_id: int) -> Optional[Dict]:
    """Get a subscription plan by ID"""
    query = f"SELECT * FROM subscription_plans WHERE id = {get_placeholder()}"
    return execute_query(query, (plan_id,), fetch_one=True)


def list_active_subscription_plans() -> List[Dict]:
    """List all active subscription plans"""
    query = "SELECT * FROM subscription_plans WHERE is_active = 1 ORDER BY base_price_cents ASC"
    rows = execute_query(query, fetch_all=True)
    return rows if rows else []


def list_subscription_plans(active_only: bool = False) -> List[Dict]:
    """List subscription plans (optionally only active)"""
    if active_only:
        query = "SELECT * FROM subscription_plans WHERE is_active = 1 ORDER BY base_price_cents ASC"
        rows = execute_query(query, fetch_all=True)
        return rows if rows else []
    query = "SELECT * FROM subscription_plans ORDER BY base_price_cents ASC"
    rows = execute_query(query, fetch_all=True)
    return rows if rows else []


def update_subscription_plan(plan_id: int, updates: Dict[str, Any]) -> bool:
    """Update subscription plan fields"""
    if not updates:
        return False
    set_clauses = []
    params = []
    for key, value in updates.items():
        set_clauses.append(f"{key} = {get_placeholder()}")
        params.append(value)
    set_clauses.append(f"updated_at = {get_placeholder()}")
    params.append(datetime.now().isoformat())
    params.append(plan_id)
    query = f"UPDATE subscription_plans SET {', '.join(set_clauses)} WHERE id = {get_placeholder()}"
    return (execute_query(query, tuple(params)) or 0) > 0


def delete_subscription_plan(plan_id: int) -> bool:
    """Soft delete subscription plan"""
    return update_subscription_plan(plan_id, {"is_active": 0})


# ============================================================================
# User Subscriptions CRUD
# ============================================================================

def create_user_subscription(
    user_id: int,
    subscription_plan_id: int,
    stripe_subscription_id: Optional[str] = None,
    status: str = "active",
    current_period_start: Optional[str] = None,
    current_period_end: Optional[str] = None,
    next_billing_date: Optional[str] = None
) -> int:
    """Create a new user subscription"""
    query = f"""
        INSERT INTO user_subscriptions (
            user_id, subscription_plan_id, stripe_subscription_id, status,
            current_period_start, current_period_end, next_billing_date,
            created_at, updated_at
        ) VALUES ({', '.join([get_placeholder()] * 9)})
    """

    now = datetime.now().isoformat()
    params = (
        user_id, subscription_plan_id, stripe_subscription_id, status,
        current_period_start, current_period_end, next_billing_date,
        now, now
    )

    sub_id = execute_query(query, params)
    logger.info(f"Created subscription for user {user_id}")
    return sub_id


def get_user_active_subscription(user_id: int) -> Optional[Dict]:
    """Get user's active subscription"""
    query = f"""
        SELECT * FROM user_subscriptions
        WHERE user_id = {get_placeholder()} AND status IN ('active', 'trialing')
        LIMIT 1
    """
    return execute_query(query, (user_id,), fetch_one=True)


# ============================================================================
# Promo Codes CRUD
# ============================================================================

def create_promo_code(
    code: str,
    promo_type: str,
    discount_percentage: float = 0.00,
    discount_amount_cents: int = 0,
    bonus_credits: int = 0,
    max_uses: Optional[int] = None,
    max_uses_per_user: int = 1,
    min_purchase_cents: int = 0,
    valid_from: Optional[str] = None,
    valid_until: Optional[str] = None,
    applies_to: str = "all",
    is_active: bool = True
) -> int:
    """Create a new promo code"""
    query = f"""
        INSERT INTO promo_codes (
            code, type, discount_percentage, discount_amount_cents, bonus_credits,
            max_uses, max_uses_per_user, min_purchase_cents,
            valid_from, valid_until, applies_to, is_active,
            created_at, updated_at
        ) VALUES ({', '.join([get_placeholder()] * 14)})
    """

    now = datetime.now().isoformat()
    params = (
        code.upper(), promo_type, discount_percentage, discount_amount_cents, bonus_credits,
        max_uses, max_uses_per_user, min_purchase_cents,
        valid_from, valid_until, applies_to, 1 if is_active else 0,
        now, now
    )

    promo_id = execute_query(query, params)
    logger.info(f"Created promo code '{code}' with ID {promo_id}")
    return promo_id


def get_promo_code(code: str) -> Optional[Dict]:
    """Get a promo code by code"""
    query = f"SELECT * FROM promo_codes WHERE code = {get_placeholder()} AND is_active = 1"
    return execute_query(query, (code.upper(),), fetch_one=True)

def get_promo_code_by_id(promo_code_id: int) -> Optional[Dict]:
    """Get promo code by database ID"""
    query = f"SELECT * FROM promo_codes WHERE id = {get_placeholder()}"
    return execute_query(query, (promo_code_id,), fetch_one=True)


def list_promo_codes(active_only: bool = False) -> List[Dict]:
    """List promo codes (optionally only active)"""
    if active_only:
        query = "SELECT * FROM promo_codes WHERE is_active = 1 ORDER BY created_at DESC"
        rows = execute_query(query, fetch_all=True)
        return rows if rows else []
    query = "SELECT * FROM promo_codes ORDER BY created_at DESC"
    rows = execute_query(query, fetch_all=True)
    return rows if rows else []


def update_promo_code(promo_code_id: int, updates: Dict[str, Any]) -> bool:
    """Update a promo code"""
    if not updates:
        return False
    set_clauses = []
    params = []
    for key, value in updates.items():
        set_clauses.append(f"{key} = {get_placeholder()}")
        params.append(value)

    set_clauses.append(f"updated_at = {get_placeholder()}")
    params.append(datetime.now().isoformat())
    params.append(promo_code_id)

    query = f"UPDATE promo_codes SET {', '.join(set_clauses)} WHERE id = {get_placeholder()}"
    return (execute_query(query, tuple(params)) or 0) > 0


def deactivate_promo_code(promo_code_id: int) -> bool:
    """Deactivate (soft delete) a promo code"""
    return update_promo_code(promo_code_id, {"is_active": 0})


def get_promo_usage_stats(promo_code_id: int) -> Dict[str, Any]:
    """Aggregated usage stats for a promo code"""
    row = execute_query(
        "SELECT COUNT(*), COALESCE(SUM(discount_amount_cents), 0), COALESCE(SUM(credits_awarded), 0) FROM promo_code_usage WHERE promo_code_id = ?",
        (promo_code_id,),
        fetch_one=True,
        commit=False,
    )
    uses = int(row[0] or 0) if row else 0
    discount = int(row[1] or 0) if row else 0
    credits = int(row[2] or 0) if row else 0
    return {"uses": uses, "discount_amount_cents": discount, "credits_awarded": credits}


def increment_promo_code_usage(promo_code_id: int) -> bool:
    """Increment the usage count for a promo code"""
    query = f"""
        UPDATE promo_codes
        SET uses_count = uses_count + 1, updated_at = {get_placeholder()}
        WHERE id = {get_placeholder()}
    """
    params = (datetime.now().isoformat(), promo_code_id)
    rows_affected = execute_query(query, params)
    return rows_affected > 0


# ============================================================================
# Pricing Tiers CRUD
# ============================================================================

def create_pricing_tier(
    name: str,
    min_monthly_credits: int = 0,
    max_monthly_credits: Optional[int] = None,
    price_per_credit_cents: float = 0.0,
    discount_percentage: float = 0.0,
    requires_approval: bool = False,
    is_active: bool = True,
) -> int:
    query = f"""
        INSERT INTO pricing_tiers (
            name, min_monthly_credits, max_monthly_credits, price_per_credit_cents,
            discount_percentage, requires_approval, is_active, created_at, updated_at
        ) VALUES ({', '.join([get_placeholder()] * 9)})
    """
    now = datetime.now().isoformat()
    return execute_query(
        query,
        (
            name,
            min_monthly_credits,
            max_monthly_credits,
            price_per_credit_cents,
            discount_percentage,
            1 if requires_approval else 0,
            1 if is_active else 0,
            now,
            now,
        ),
    )


def list_pricing_tiers(active_only: bool = True) -> List[Dict]:
    if active_only:
        query = "SELECT * FROM pricing_tiers WHERE is_active = 1 ORDER BY min_monthly_credits ASC"
    else:
        query = "SELECT * FROM pricing_tiers ORDER BY min_monthly_credits ASC"
    rows = execute_query(query, fetch_all=True)
    return rows if rows else []


def update_pricing_tier(tier_id: int, updates: Dict[str, Any]) -> bool:
    if not updates:
        return False
    set_clauses = []
    params = []
    for key, value in updates.items():
        set_clauses.append(f"{key} = {get_placeholder()}")
        params.append(value)
    set_clauses.append(f"updated_at = {get_placeholder()}")
    params.append(datetime.now().isoformat())
    params.append(tier_id)
    query = f"UPDATE pricing_tiers SET {', '.join(set_clauses)} WHERE id = {get_placeholder()}"
    return (execute_query(query, tuple(params)) or 0) > 0
