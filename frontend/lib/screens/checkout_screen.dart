import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/error_handler.dart';
import '../services/api_service.dart';
import '../widgets/promo_code_input.dart';

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
  bool _isStarting = false;
  Map<String, dynamic>? _checkoutConfig;
  bool _configLoading = true;

  @override
  void initState() {
    super.initState();
    if (!widget.isSubscription) {
      _calculatePrice();
      _loadCheckoutConfig();
    }
  }

  Future<void> _loadCheckoutConfig() async {
    try {
      final cfg = await _apiService.getCheckoutConfig();
      if (mounted) setState(() => _checkoutConfig = cfg);
    } catch (e) {
      if (mounted) {
        setState(() => _paymentError = ErrorHandler.getUserFriendlyMessage(e));
      }
    } finally {
      if (mounted) setState(() => _configLoading = false);
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
    } catch (e) {
      if (mounted) {
        setState(() => _paymentError = ErrorHandler.getUserFriendlyMessage(e));
      }
    }
  }

  /// Starts a Safepay hosted checkout and sends the browser there (same tab),
  /// so Safepay can redirect back to `/payment/return/{id}` afterwards.
  /// Credits are only added after the server confirms the payment.
  Future<void> _startCardCheckout() async {
    if (widget.isSubscription) return;
    final packageId = (widget.item['id'] as num?)?.toInt();
    if (packageId == null || packageId <= 0) {
      setState(() => _paymentError = 'Invalid package selected.');
      return;
    }

    setState(() {
      _isStarting = true;
      _paymentError = null;
    });

    try {
      final idempotencyKey =
          '${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
      final result = await _apiService.purchaseCredits(
        packageId: packageId,
        paymentProvider: 'safepay',
        promoCode: _promo?['code'],
        idempotencyKey: idempotencyKey,
      );
      final checkoutUrl =
          (result['checkout_url'] ?? result['hosted_url'] ?? '').toString();
      final uri = Uri.tryParse(checkoutUrl);
      if (uri == null || !uri.hasScheme || !uri.host.endsWith('getsafepay.com')) {
        throw Exception('The card checkout link was not returned. Please try again.');
      }
      final launched = await launchUrl(uri, webOnlyWindowName: '_self');
      if (!launched && mounted) {
        setState(() {
          _paymentError = 'Could not open the card checkout.';
          _isStarting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _paymentError = ErrorHandler.getUserFriendlyMessage(e);
          _isStarting = false;
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
                        // Safepay card checkout only
                        const SizedBox(height: AppSpacing.lg),
                        if (widget.isSubscription)
                          _buildSubscriptionUnsupportedCard()
                        else
                          _buildCardPayment(),
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
        : _priceBreakdown?['total_cents'] ??
            widget.item['display_price_cents'] ??
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

  Widget _buildCardPayment() {
    final cfg = _checkoutConfig;
    final available = cfg?['checkout_available'] == true;
    final unavailableReason = (cfg?['unavailable_reason'] ?? '').toString();
    final isSandbox = (cfg?['environment'] ?? '') == 'sandbox';
    final totalCents = _priceBreakdown?['total_cents'] ??
        widget.item['display_price_cents'] ??
        widget.item['base_price_cents'] ??
        0;
    final total = ((totalCents as num) / 100).toStringAsFixed(2);
    final canPay = available && !_isStarting && !_configLoading && _priceBreakdown != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pay by card',
          style: AppTypography.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Secure checkout by Safepay (Visa, Mastercard). You will be charged US\$$total. '
          'If your card is in another currency, your bank converts the amount.',
          style: AppTypography.bodySmall.copyWith(color: Colors.white60),
        ),
        if (isSandbox) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Sandbox mode: test cards only, no real money moves.',
            style: AppTypography.labelSmall.copyWith(color: const Color(0xFFF59E0B)),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (!_configLoading && cfg != null && !available)
          _notice(unavailableReason.isEmpty
              ? 'Card payments are not available right now.'
              : unavailableReason),
        if (_paymentError != null) _notice(_paymentError!, danger: true),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            key: const ValueKey('safepay-pay-button'),
            onPressed: canPay ? _startCardCheckout : null,
            icon: _isStarting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.lock_rounded, size: 18),
            label: Text(_isStarting ? 'Opening secure checkout...' : 'Pay US\$$total by card'),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Credits are added once Safepay confirms the payment.',
          style: AppTypography.labelSmall.copyWith(color: Colors.white38),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          key: const ValueKey('checkout-agreement'),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('By paying you agree to the ',
                style: AppTypography.labelSmall.copyWith(color: Colors.white54)),
            _policyLink('Terms and Conditions', '/terms'),
            Text(' and the ',
                style: AppTypography.labelSmall.copyWith(color: Colors.white54)),
            _policyLink('Refund and Cancellation Policy', '/refund-policy'),
            Text('.', style: AppTypography.labelSmall.copyWith(color: Colors.white54)),
          ],
        ),
      ],
    );
  }

  Widget _policyLink(String label, String route) => InkWell(
        onTap: () => Navigator.of(context).pushNamed(route),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: Colors.white,
            decoration: TextDecoration.underline,
          ),
        ),
      );

  Widget _notice(String text, {bool danger = false}) {
    final color = danger ? AppColors.dangerRed : const Color(0xFFF59E0B);
    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingSm,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: AppTypography.bodySmall.copyWith(color: color)),
    );
  }

  Widget _buildSubscriptionUnsupportedCard() {
    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: _CheckoutColors.surface.withValues(alpha: 0.3),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Text(
        'Subscriptions are not available yet. Please choose a credit pack.',
        style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
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
            style:
                (isBold ? AppTypography.labelLarge : AppTypography.bodyMedium)
                    .copyWith(
              color: Colors.white70,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          Text(
            value,
            style:
                (isBold ? AppTypography.titleMedium : AppTypography.bodyMedium)
                    .copyWith(
              color: color ?? Colors.white,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckoutColors {
  static const Color primary = AppColors.primaryBlue;
  static const Color background = AppColors.backgroundDark;
  static const Color surface = AppColors.elevatedCardDark;
}
