import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

class PayPalPaymentWidget extends StatelessWidget {
  final Map<String, dynamic>? orderData;
  final bool isLoading;
  final VoidCallback onCreateOrder;
  final VoidCallback onCapture;
  final String? error;

  const PayPalPaymentWidget({
    super.key,
    this.orderData,
    this.isLoading = false,
    required this.onCreateOrder,
    required this.onCapture,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (orderData == null) {
      return _buildInitial(context);
    }
    return _buildOrderDetails(context);
  }

  Widget _buildInitial(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pay with PayPal',
          style: AppTypography.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'You will be redirected to PayPal to approve the payment.',
          style: AppTypography.bodySmall.copyWith(color: Colors.white54),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (error != null) ...[
          Container(
            padding: AppSpacing.paddingSm,
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.dangerRed.withValues(alpha: 0.1),
              borderRadius: AppSpacing.borderRadiusSm,
              border: Border.all(color: AppColors.dangerRed.withValues(alpha: 0.3)),
            ),
            child: Text(
              error!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.dangerRed),
            ),
          ),
        ],
        GestureDetector(
          onTap: isLoading ? null : onCreateOrder,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF003087), Color(0xFF009CDE)],
              ),
              borderRadius: AppSpacing.borderRadiusMd,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF009CDE).withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.account_balance_wallet_rounded,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Create PayPal Checkout',
                          style: AppTypography.labelLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderDetails(BuildContext context) {
    final hostedUrl = (orderData?['hosted_url'] ?? '').toString();
    final orderId = (orderData?['provider_transaction_id'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF009CDE).withValues(alpha: 0.15),
                borderRadius: AppSpacing.borderRadiusSm,
              ),
              child: const Icon(Icons.payments_rounded,
                  color: Color(0xFF009CDE), size: 24),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PayPal Checkout Ready',
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (orderId.isNotEmpty)
                    Text(
                      'Order: ${orderId.length > 12 ? '${orderId.substring(0, 12)}...' : orderId}',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white54,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (hostedUrl.isNotEmpty) ...[
          GestureDetector(
            onTap: () async {
              final uri = Uri.parse(hostedUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not open PayPal link')),
                  );
                }
              }
            },
            child: Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: AppSpacing.borderRadiusMd,
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.open_in_new,
                        color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Open PayPal to Pay',
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: hostedUrl));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PayPal link copied!')),
                );
              }
            },
            child: Container(
              width: double.infinity,
              padding: AppSpacing.paddingSm,
              decoration: BoxDecoration(
                color: AppColors.elevatedCardDark.withValues(alpha: 0.5),
                borderRadius: AppSpacing.borderRadiusSm,
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hostedUrl,
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white54,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.copy, color: Colors.white38, size: 16),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'After approving in PayPal, return here and tap Complete.',
          style: AppTypography.bodySmall.copyWith(color: Colors.white38),
        ),
        const SizedBox(height: AppSpacing.md),
        GestureDetector(
          onTap: isLoading ? null : onCapture,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius: AppSpacing.borderRadiusMd,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Complete PayPal Payment',
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

