"""
Pydantic models for payment and subscription entities

These models provide type safety and validation for:
- Credit packages and pricing
- Payment transactions (Stripe, Coinbase)
- Invoices and billing
- Saved payment methods
- Webhook events
- Subscription plans and user subscriptions
- Promo codes and referrals
- Pricing tiers
"""

import uuid
from datetime import datetime
from decimal import Decimal
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, validator, EmailStr


# ============================================================================
# Credit Packages
# ============================================================================

class CreditPackageBase(BaseModel):
    """Base fields for credit packages"""
    name: str = Field(..., min_length=1, max_length=100, description="Package name")
    credits: int = Field(..., gt=0, description="Number of credits in package")
    base_price_cents: int = Field(..., gt=0, description="Base price in cents")
    display_price_cents: int = Field(..., gt=0, description="Display price in cents")
    discount_percentage: Optional[Decimal] = Field(default=0.00, ge=0, le=100)
    tier_id: Optional[int] = Field(default=None, description="Associated pricing tier")
    is_active: bool = Field(default=True)
    is_featured: bool = Field(default=False, description="Show as featured package")
    features: Optional[Dict[str, Any]] = Field(default=None, description="Package features JSON")


class CreditPackageCreate(CreditPackageBase):
    """Model for creating a credit package"""
    pass


class CreditPackageUpdate(BaseModel):
    """Model for updating a credit package (all fields optional)"""
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    credits: Optional[int] = Field(None, gt=0)
    base_price_cents: Optional[int] = Field(None, gt=0)
    display_price_cents: Optional[int] = Field(None, gt=0)
    discount_percentage: Optional[Decimal] = Field(None, ge=0, le=100)
    tier_id: Optional[int] = None
    is_active: Optional[bool] = None
    is_featured: Optional[bool] = None
    features: Optional[Dict[str, Any]] = None


class CreditPackageResponse(CreditPackageBase):
    """Model for credit package responses"""
    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ============================================================================
# Payment Transactions
# ============================================================================

class PaymentTransactionBase(BaseModel):
    """Base fields for payment transactions"""
    user_id: int = Field(..., gt=0)
    payment_provider: str = Field(..., description="'stripe' or 'coinbase'")
    amount_cents: int = Field(..., gt=0, description="Transaction amount in cents")
    currency: str = Field(default="USD", min_length=3, max_length=10)
    credits_purchased: int = Field(..., gt=0)
    package_id: Optional[int] = None
    subscription_id: Optional[int] = None
    promo_code_id: Optional[int] = None

    @validator('payment_provider')
    def validate_provider(cls, v):
        if v not in ['stripe', 'coinbase']:
            raise ValueError("payment_provider must be 'stripe' or 'coinbase'")
        return v


class PaymentTransactionCreate(PaymentTransactionBase):
    """Model for creating a payment transaction"""
    transaction_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    idempotency_key: str = Field(default_factory=lambda: str(uuid.uuid4()))
    provider_transaction_id: Optional[str] = None
    status: str = Field(default="pending")
    invoice_id: Optional[int] = None

    @validator('status')
    def validate_status(cls, v):
        valid_statuses = ['pending', 'processing', 'completed', 'failed', 'refunded']
        if v not in valid_statuses:
            raise ValueError(f"status must be one of {valid_statuses}")
        return v


class PaymentTransactionResponse(PaymentTransactionBase):
    """Model for payment transaction responses"""
    id: int
    transaction_id: str
    provider_transaction_id: Optional[str]
    status: str
    idempotency_key: str
    invoice_id: Optional[int]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ============================================================================
# Invoices
# ============================================================================

class InvoiceBase(BaseModel):
    """Base fields for invoices"""
    user_id: int = Field(..., gt=0)
    invoice_type: str = Field(..., description="'purchase', 'subscription', or 'refund'")
    amount_cents: int = Field(..., gt=0)
    tax_amount_cents: int = Field(default=0, ge=0)
    total_amount_cents: int = Field(..., gt=0)
    billing_name: Optional[str] = Field(None, max_length=255)
    billing_email: Optional[EmailStr] = None
    billing_address: Optional[Dict[str, Any]] = None

    @validator('invoice_type')
    def validate_type(cls, v):
        valid_types = ['purchase', 'subscription', 'refund']
        if v not in valid_types:
            raise ValueError(f"invoice_type must be one of {valid_types}")
        return v


class InvoiceCreate(InvoiceBase):
    """Model for creating an invoice"""
    invoice_number: str = Field(..., description="Unique invoice number")
    transaction_id: Optional[int] = None
    subscription_id: Optional[int] = None
    status: str = Field(default="paid")
    pdf_path: Optional[str] = None
    line_items: Optional[Dict[str, Any]] = None

    @validator('status')
    def validate_status(cls, v):
        valid_statuses = ['draft', 'sent', 'paid', 'void']
        if v not in valid_statuses:
            raise ValueError(f"status must be one of {valid_statuses}")
        return v


class InvoiceResponse(InvoiceBase):
    """Model for invoice responses"""
    id: int
    invoice_number: str
    transaction_id: Optional[int]
    subscription_id: Optional[int]
    status: str
    pdf_path: Optional[str]
    line_items: Optional[Dict[str, Any]]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ============================================================================
# Payment Methods
# ============================================================================

class PaymentMethodBase(BaseModel):
    """Base fields for payment methods"""
    user_id: int = Field(..., gt=0)
    stripe_payment_method_id: str = Field(..., description="Stripe payment method ID")
    type: str = Field(default="card", description="'card' or 'bank_account'")
    is_default: bool = Field(default=False)
    billing_name: Optional[str] = Field(None, max_length=255)
    billing_email: Optional[EmailStr] = None
    billing_address: Optional[Dict[str, Any]] = None

    @validator('type')
    def validate_type(cls, v):
        if v not in ['card', 'bank_account']:
            raise ValueError("type must be 'card' or 'bank_account'")
        return v


class PaymentMethodCreate(PaymentMethodBase):
    """Model for creating a payment method"""
    card_brand: Optional[str] = Field(None, max_length=50)
    card_last4: Optional[str] = Field(None, min_length=4, max_length=4)
    card_exp_month: Optional[int] = Field(None, ge=1, le=12)
    card_exp_year: Optional[int] = Field(None, ge=2024)


class PaymentMethodResponse(PaymentMethodBase):
    """Model for payment method responses"""
    id: int
    card_brand: Optional[str]
    card_last4: Optional[str]
    card_exp_month: Optional[int]
    card_exp_year: Optional[int]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ============================================================================
# Webhook Events
# ============================================================================

class WebhookEventCreate(BaseModel):
    """Model for creating a webhook event"""
    webhook_id: str = Field(..., description="Provider's webhook event ID")
    provider: str = Field(..., description="'stripe' or 'coinbase'")
    event_type: str = Field(..., max_length=100)
    payload: Dict[str, Any] = Field(..., description="Full webhook payload")
    status: str = Field(default="pending")
    retry_count: int = Field(default=0, ge=0)

    @validator('provider')
    def validate_provider(cls, v):
        if v not in ['stripe', 'coinbase']:
            raise ValueError("provider must be 'stripe' or 'coinbase'")
        return v

    @validator('status')
    def validate_status(cls, v):
        valid_statuses = ['pending', 'processed', 'failed']
        if v not in valid_statuses:
            raise ValueError(f"status must be one of {valid_statuses}")
        return v


class WebhookEventResponse(BaseModel):
    """Model for webhook event responses"""
    id: int
    webhook_id: str
    provider: str
    event_type: str
    payload: Dict[str, Any]
    status: str
    processed_at: Optional[datetime]
    error_message: Optional[str]
    retry_count: int
    created_at: datetime

    class Config:
        from_attributes = True


# ============================================================================
# Subscription Plans
# ============================================================================

class SubscriptionPlanBase(BaseModel):
    """Base fields for subscription plans"""
    name: str = Field(..., min_length=1, max_length=100)
    billing_interval: str = Field(..., description="'monthly' or 'yearly'")
    credits_per_period: int = Field(..., gt=0)
    base_price_cents: int = Field(..., gt=0)
    stripe_price_id: Optional[str] = Field(None, max_length=255)
    rollover_credits: bool = Field(default=True)
    max_rollover_credits: int = Field(default=0, ge=0)
    trial_days: int = Field(default=0, ge=0)
    is_active: bool = Field(default=True)
    is_featured: bool = Field(default=False)
    features: Optional[Dict[str, Any]] = None

    @validator('billing_interval')
    def validate_interval(cls, v):
        if v not in ['monthly', 'yearly']:
            raise ValueError("billing_interval must be 'monthly' or 'yearly'")
        return v


class SubscriptionPlanCreate(SubscriptionPlanBase):
    """Model for creating a subscription plan"""
    pass


class SubscriptionPlanResponse(SubscriptionPlanBase):
    """Model for subscription plan responses"""
    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ============================================================================
# User Subscriptions
# ============================================================================

class UserSubscriptionBase(BaseModel):
    """Base fields for user subscriptions"""
    user_id: int = Field(..., gt=0)
    subscription_plan_id: int = Field(..., gt=0)
    stripe_subscription_id: Optional[str] = Field(None, max_length=255)
    status: str = Field(default="active")
    cancel_at_period_end: bool = Field(default=False)

    @validator('status')
    def validate_status(cls, v):
        valid_statuses = ['active', 'past_due', 'canceled', 'paused', 'expired', 'trialing']
        if v not in valid_statuses:
            raise ValueError(f"status must be one of {valid_statuses}")
        return v


class UserSubscriptionCreate(UserSubscriptionBase):
    """Model for creating a user subscription"""
    current_period_start: Optional[datetime] = None
    current_period_end: Optional[datetime] = None
    next_billing_date: Optional[datetime] = None
    credits_allocated_this_period: int = Field(default=0, ge=0)
    credits_used_this_period: int = Field(default=0, ge=0)
    credits_rolled_over: int = Field(default=0, ge=0)


class UserSubscriptionResponse(UserSubscriptionBase):
    """Model for user subscription responses"""
    id: int
    current_period_start: Optional[datetime]
    current_period_end: Optional[datetime]
    next_billing_date: Optional[datetime]
    credits_allocated_this_period: int
    credits_used_this_period: int
    credits_rolled_over: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ============================================================================
# Promo Codes
# ============================================================================

class PromoCodeBase(BaseModel):
    """Base fields for promo codes"""
    code: str = Field(..., min_length=1, max_length=50, description="Unique promo code")
    type: str = Field(..., description="'percentage_off', 'fixed_amount_off', or 'bonus_credits'")
    discount_percentage: Optional[Decimal] = Field(default=0.00, ge=0, le=100)
    discount_amount_cents: Optional[int] = Field(default=0, ge=0)
    bonus_credits: Optional[int] = Field(default=0, ge=0)
    max_uses: Optional[int] = Field(None, description="NULL = unlimited")
    max_uses_per_user: int = Field(default=1, ge=1)
    min_purchase_cents: int = Field(default=0, ge=0)
    valid_from: Optional[datetime] = None
    valid_until: Optional[datetime] = None
    applies_to: str = Field(default="all", description="'all', 'packages', or 'subscriptions'")
    is_active: bool = Field(default=True)

    @validator('type')
    def validate_type(cls, v):
        valid_types = ['percentage_off', 'fixed_amount_off', 'bonus_credits']
        if v not in valid_types:
            raise ValueError(f"type must be one of {valid_types}")
        return v

    @validator('applies_to')
    def validate_applies_to(cls, v):
        valid_values = ['all', 'packages', 'subscriptions']
        if v not in valid_values:
            raise ValueError(f"applies_to must be one of {valid_values}")
        return v


class PromoCodeCreate(PromoCodeBase):
    """Model for creating a promo code"""
    uses_count: int = Field(default=0, ge=0)


class PromoCodeResponse(PromoCodeBase):
    """Model for promo code responses"""
    id: int
    uses_count: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ============================================================================
# Pricing Tiers
# ============================================================================

class PricingTierBase(BaseModel):
    """Base fields for pricing tiers"""
    name: str = Field(..., min_length=1, max_length=100)
    min_monthly_credits: int = Field(default=0, ge=0)
    max_monthly_credits: Optional[int] = Field(None, description="NULL = unlimited")
    price_per_credit_cents: Decimal = Field(..., gt=0)
    discount_percentage: Optional[Decimal] = Field(default=0.00, ge=0, le=100)
    requires_approval: bool = Field(default=False, description="Requires admin approval")
    is_active: bool = Field(default=True)


class PricingTierCreate(PricingTierBase):
    """Model for creating a pricing tier"""
    pass


class PricingTierResponse(PricingTierBase):
    """Model for pricing tier responses"""
    id: int
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


# ============================================================================
# Additional Helper Models
# ============================================================================

class PriceCalculationRequest(BaseModel):
    """Request model for price calculation"""
    package_id: Optional[int] = None
    subscription_plan_id: Optional[int] = None
    promo_code: Optional[str] = None
    quantity: int = Field(default=1, gt=0)


class PriceBreakdown(BaseModel):
    """Response model for price calculations"""
    subtotal_cents: int
    discount_cents: int
    tax_cents: int
    total_cents: int
    credits_to_receive: int
    bonus_credits: int = 0
    promo_code_applied: Optional[str] = None
    pricing_tier: Optional[str] = None


class ReferralStats(BaseModel):
    """Response model for referral statistics"""
    referral_code: str
    total_referrals: int
    completed_referrals: int
    pending_referrals: int
    total_credits_earned: int
