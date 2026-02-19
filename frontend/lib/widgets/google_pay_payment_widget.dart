import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:pay/pay.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

/// Google Pay payment widget that follows the same pattern as
/// [PayPalPaymentWidget] and [CryptoPaymentWidget].
///
/// Flow:
/// 1. Parent creates a Stripe PaymentIntent and passes [clientSecret].
/// 2. User taps Google Pay button → Google Pay sheet opens.
/// 3. On approval, [onPaymentResult] fires with the Stripe token.
/// 4. Parent confirms the PaymentIntent via Stripe.js interop.
class GooglePayPaymentWidget extends StatefulWidget {
  /// Stripe publishable key for Google Pay tokenization.
  final String stripePublishableKey;

  /// Total amount in display format (e.g. "9.99").
  final String amount;

  /// ISO 4217 currency code (e.g. "USD").
  final String currencyCode;

  /// ISO 3166-1 alpha-2 country code (e.g. "US").
  final String countryCode;

  /// Merchant name shown in Google Pay sheet.
  final String merchantName;

  /// Google Pay environment: "TEST" or "PRODUCTION".
  final String environment;

  /// Called with the Stripe token string from Google Pay authorization.
  final void Function(String stripeToken) onPaymentResult;

  /// Whether payment is being processed.
  final bool isLoading;

  /// Error message to display.
  final String? error;

  /// Called when user taps the initial "Pay with Google Pay" button
  /// (before the Google Pay sheet opens). Use this to create the
  /// PaymentIntent on the backend.
  final VoidCallback? onInitiatePayment;

  /// Whether the PaymentIntent is ready (client_secret obtained).
  final bool isReady;

  const GooglePayPaymentWidget({
    super.key,
    required this.stripePublishableKey,
    required this.amount,
    this.currencyCode = 'USD',
    this.countryCode = 'US',
    this.merchantName = 'Infinity Leads Pro',
    this.environment = 'TEST',
    required this.onPaymentResult,
    this.isLoading = false,
    this.error,
    this.onInitiatePayment,
    this.isReady = true,
  });

  @override
  State<GooglePayPaymentWidget> createState() => _GooglePayPaymentWidgetState();
}

class _GooglePayPaymentWidgetState extends State<GooglePayPaymentWidget> {
  bool _googlePayAvailable = true;

  PaymentConfiguration _buildPayConfig() {
    final config = {
      "provider": "google_pay",
      "data": {
        "environment": widget.environment,
        "apiVersion": 2,
        "apiVersionMinor": 0,
        "allowedPaymentMethods": [
          {
            "type": "CARD",
            "tokenizationSpecification": {
              "type": "PAYMENT_GATEWAY",
              "parameters": {
                "gateway": "stripe",
                "stripe:version": "2024-12-18.acacia",
                "stripe:publishableKey": widget.stripePublishableKey,
              }
            },
            "parameters": {
              "allowedCardNetworks": [
                "VISA",
                "MASTERCARD",
                "AMEX",
                "DISCOVER"
              ],
              "allowedAuthMethods": ["PAN_ONLY", "CRYPTOGRAM_3DS"]
            }
          }
        ],
        "merchantInfo": {
          "merchantName": widget.merchantName,
        },
        "transactionInfo": {
          "countryCode": widget.countryCode,
          "currencyCode": widget.currencyCode,
        }
      }
    };
    return PaymentConfiguration.fromJsonString(jsonEncode(config));
  }

  void _handlePaymentResult(Map<String, dynamic> result) {
    // The pay package returns the full Google Pay response.
    // With Stripe as gateway, the token is at:
    //   paymentMethodData.tokenizationData.token (JSON string containing stripe token id)
    try {
      final tokenData = result['paymentMethodData']?['tokenizationData'];
      if (tokenData == null) {
        return;
      }

      final tokenString = tokenData['token'];
      if (tokenString is String) {
        // Stripe gateway returns a JSON string: {"id":"tok_xxx","type":"card",...}
        final decoded = jsonDecode(tokenString);
        final stripeToken = decoded['id'] as String?;
        if (stripeToken != null && stripeToken.isNotEmpty) {
          widget.onPaymentResult(stripeToken);
          return;
        }
      }
    } catch (_) {
      // Fall through to error state
    }
  }

  void _handleError(Object? error) {
    if (mounted) {
      setState(() => _googlePayAvailable = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pay with Google Pay',
          style: AppTypography.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Fast, secure checkout with Google Pay.',
          style: AppTypography.bodySmall.copyWith(color: Colors.white54),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (widget.error != null) ...[
          Container(
            padding: AppSpacing.paddingSm,
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.dangerRed.withValues(alpha: 0.1),
              borderRadius: AppSpacing.borderRadiusSm,
              border:
                  Border.all(color: AppColors.dangerRed.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.dangerRed, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.error!,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.dangerRed),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (widget.isLoading)
          _buildLoadingButton()
        else if (!_googlePayAvailable)
          _buildUnavailable()
        else if (!widget.isReady && widget.onInitiatePayment != null)
          _buildInitiateButton()
        else
          _buildGooglePayButton(),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_rounded, color: Colors.white38, size: 14),
            const SizedBox(width: 4),
            Text(
              'Processed securely via Stripe + Google Pay.',
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGooglePayButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: GooglePayButton(
        paymentConfiguration: _buildPayConfig(),
        paymentItems: [
          PaymentItem(
            label: widget.merchantName,
            amount: widget.amount,
            status: PaymentItemStatus.final_price,
          ),
        ],
        type: GooglePayButtonType.pay,
        margin: EdgeInsets.zero,
        onPaymentResult: _handlePaymentResult,
        onError: _handleError,
        loadingIndicator: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitiateButton() {
    return GestureDetector(
      onTap: widget.onInitiatePayment,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: AppSpacing.borderRadiusMd,
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              'Continue with Google Pay',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: AppSpacing.borderRadiusMd,
      ),
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildUnavailable() {
    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: AppColors.elevatedCardDark.withValues(alpha: 0.5),
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: AppColors.warningYellow.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: AppColors.warningYellow, size: 32),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Google Pay is not available',
            style: AppTypography.titleSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Google Pay is not supported on this device or browser. '
            'Please use another payment method.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
