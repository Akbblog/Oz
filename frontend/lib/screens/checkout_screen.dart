import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../services/api_service.dart';
import '../services/stripe_js_interop.dart';
// TODO(payments): Uncomment when re-enabling other payment methods.
// import '../widgets/payment_form.dart';
// import '../widgets/crypto_payment_widget.dart';
// import '../widgets/paypal_payment_widget.dart';
import '../widgets/promo_code_input.dart';
import '../widgets/google_pay_payment_widget.dart';
import 'payment_success_screen.dart';

class CheckoutScreen extends StatefulWidget {
  final Map<String, dynamic> item;
  final bool isSubscription;

  const CheckoutScreen({
    super.key,
    required this.item,
    this.isSubscription = false,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final ApiService _apiService = ApiService();
  String? _paymentError;
  Map<String, dynamic>? _promo;
  Map<String, dynamic>? _priceBreakdown;
  bool _isGooglePayLoading = false;

  // Google Pay state
  String? _stripePublishableKey;
  String _googlePayMerchantName = 'Infinity Leads Pro';
  String _googlePayEnvironment = 'TEST';
  String? _googlePayClientSecret;
  String? _googlePayTransactionId;

  @override
  void initState() {
    super.initState();
    if (!widget.isSubscription) {
      _calculatePrice();
    }
    _loadPaymentConfig();
  }

  String get _displayAmount {
    final totalCents = _priceBreakdown?['total_cents'] ??
        (widget.isSubscription
            ? widget.item['base_price_cents']
            : widget.item['display_price_cents'] ??
                widget.item['base_price_cents']) ??
        0;
    return (totalCents / 100).toStringAsFixed(2);
  }

  Future<void> _loadPaymentConfig() async {
    try {
      final flags = await _apiService.getFeatureFlags();
      if (!mounted) return;
      setState(() {
        _stripePublishableKey = flags['stripe_publishable_key'] as String?;
        _googlePayMerchantName =
            (flags['google_pay_merchant_name'] as String?) ?? 'Infinity Leads Pro';
        _googlePayEnvironment =
            (flags['google_pay_environment'] as String?) ?? 'TEST';
      });
    } catch (_) {
      // Non-critical: Google Pay tab just won't show.
    }
  }

  Future<void> _calculatePrice() async {
    try {
      final result = await _apiService.calculatePrice(
        packageId: widget.item['id'],
        promoCode: _promo?['code'],
      );
      if (mounted) {
        setState(() => _priceBreakdown = result);
      }
    } catch (_) {}
  }

  // TODO(payments): Restore _processCardPayment, _createCryptoCharge,
  // _createPayPalOrder, _capturePayPalOrder when re-enabling other methods.

  Future<void> _initiateGooglePay() async {
    setState(() {
      _isGooglePayLoading = true;
      _paymentError = null;
    });

    try {
      final idempotencyKey = DateTime.now().millisecondsSinceEpoch.toString();
      final result = await _apiService.purchaseCredits(
        packageId: widget.item['id'],
        paymentProvider: 'googlepay',
        promoCode: _promo?['code'],
        idempotencyKey: idempotencyKey,
      );
      if (mounted) {
        setState(() {
          _googlePayClientSecret = result['client_secret'] as String?;
          _googlePayTransactionId = result['transaction_id'] as String?;
          _isGooglePayLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _paymentError = e.toString().replaceFirst('Exception: ', '');
          _isGooglePayLoading = false;
        });
      }
    }
  }

  Future<void> _onGooglePayToken(String stripeToken) async {
    if (_googlePayClientSecret == null || _stripePublishableKey == null) {
      setState(() => _paymentError = 'Payment not ready. Please try again.');
      return;
    }

    setState(() {
      _isGooglePayLoading = true;
      _paymentError = null;
    });

    try {
      if (!kIsWeb) {
        setState(() {
          _paymentError = 'Google Pay is only supported on web.';
          _isGooglePayLoading = false;
        });
        return;
      }

      final stripe = StripeJs(_stripePublishableKey!);
      final confirmResult = await stripe.confirmCardPayment(
        _googlePayClientSecret!,
        googlePayToken: stripeToken,
      );

      if (!mounted) return;

      if (confirmResult.success) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => PaymentSuccessScreen(
              transaction: {
                'transaction_id': _googlePayTransactionId,
                'payment_provider': 'stripe',
                'status': confirmResult.status,
              },
              isSubscription: false,
            ),
          ),
        );
      } else {
        setState(() {
          _paymentError = confirmResult.errorMessage ?? 'Payment failed';
          _isGooglePayLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _paymentError = e.toString().replaceFirst('Exception: ', '');
          _isGooglePayLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CheckoutColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            _buildBackground(),
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildOrderSummary(),
                        const SizedBox(height: AppSpacing.lg),
                        if (!widget.isSubscription) ...[
                          PromoCodeInput(
                            packageId: (widget.item['id'] as num?)?.toInt(),
                            quantity: 1,
                            onPromoApplied: (promo) {
                              setState(() => _promo = promo);
                              _calculatePrice();
                            },
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        if (_priceBreakdown != null) ...[
                          _buildPriceBreakdown(),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        // Google Pay only (other methods hidden)
                        const SizedBox(height: AppSpacing.lg),
                        if (_stripePublishableKey != null)
                          GooglePayPaymentWidget(
                            stripePublishableKey: _stripePublishableKey!,
                            amount: _displayAmount,
                            currencyCode: 'USD',
                            countryCode: 'US',
                            merchantName: _googlePayMerchantName,
                            environment: _googlePayEnvironment,
                            isLoading: _isGooglePayLoading,
                            error: _paymentError,
                            isReady: _googlePayClientSecret != null,
                            onInitiatePayment: _initiateGooglePay,
                            onPaymentResult: _onGooglePayToken,
                          )
                        else
                          Center(
                            child: Padding(
                              padding: AppSpacing.paddingLg,
                              child: Column(
                                children: [
                                  const CircularProgressIndicator(
                                    color: AppColors.primaryBlue,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Text(
                                    'Loading payment method...',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              _CheckoutColors.primary.withValues(alpha: 0.15),
              Colors.transparent,
            ],
            radius: 1.5,
            center: const Alignment(0, -1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _CheckoutColors.background.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderDarkAlt.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          Expanded(
            child: Text(
              'Checkout',
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildOrderSummary() {
    final name = widget.item['name'] ?? 'Item';
    final credits = widget.isSubscription
        ? widget.item['credits_per_period'] ?? 0
        : widget.item['credits'] ?? 0;
    final priceCents = widget.isSubscription
        ? widget.item['base_price_cents'] ?? 0
        : widget.item['display_price_cents'] ??
            widget.item['base_price_cents'] ??
            0;
    final price = (priceCents / 100).toStringAsFixed(2);
    final interval = widget.isSubscription
        ? '/${widget.item['billing_interval'] ?? 'month'}'
        : '';

    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: _CheckoutColors.surface.withValues(alpha: 0.4),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: _CheckoutColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _CheckoutColors.primary.withValues(alpha: 0.15),
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: Icon(
                  widget.isSubscription
                      ? Icons.autorenew
                      : Icons.shopping_cart_rounded,
                  color: _CheckoutColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      widget.isSubscription
                          ? '$credits credits per period'
                          : '$credits credits',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '\$$price$interval',
                style: AppTypography.titleLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBreakdown() {
    final subtotal = (_priceBreakdown?['subtotal_cents'] ?? 0) / 100;
    final discount = (_priceBreakdown?['discount_cents'] ?? 0) / 100;
    final tax = (_priceBreakdown?['tax_cents'] ?? 0) / 100;
    final total = (_priceBreakdown?['total_cents'] ?? 0) / 100;
    final bonusCredits = _priceBreakdown?['bonus_credits'] ?? 0;

    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: _CheckoutColors.surface.withValues(alpha: 0.3),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.borderDarkAlt),
      ),
      child: Column(
        children: [
          _priceRow('Subtotal', '\$${subtotal.toStringAsFixed(2)}'),
          if (discount > 0)
            _priceRow(
              'Discount',
              '-\$${discount.toStringAsFixed(2)}',
              color: AppColors.successGreen,
            ),
          if (tax > 0) _priceRow('Tax', '\$${tax.toStringAsFixed(2)}'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Divider(color: AppColors.dividerDark),
          ),
          _priceRow(
            'Total',
            '\$${total.toStringAsFixed(2)}',
            isBold: true,
          ),
          if (bonusCredits > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: AppColors.successGreen.withValues(alpha: 0.1),
                borderRadius: AppSpacing.borderRadiusSm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.card_giftcard,
                    color: AppColors.successGreen,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '+$bonusCredits bonus credits!',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.successGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: (isBold ? AppTypography.labelLarge : AppTypography.bodyMedium)
                .copyWith(
              color: Colors.white70,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: (isBold ? AppTypography.titleMedium : AppTypography.bodyMedium)
                .copyWith(
              color: color ?? Colors.white,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // TODO(payments): Restore _buildPaymentMethodToggle and _methodTab
  // when re-enabling Card, PayPal, and Crypto payment methods.
}

class _CheckoutColors {
  static const Color primary = AppColors.primaryBlue;
  static const Color background = AppColors.backgroundDark;
  static const Color surface = AppColors.elevatedCardDark;
}
