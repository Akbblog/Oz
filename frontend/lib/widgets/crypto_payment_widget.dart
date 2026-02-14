import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

class CryptoPaymentWidget extends StatelessWidget {
  final Map<String, dynamic>? chargeData;
  final bool isLoading;
  final VoidCallback onCreateCharge;
  final String? error;

  const CryptoPaymentWidget({
    super.key,
    this.chargeData,
    this.isLoading = false,
    required this.onCreateCharge,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (chargeData == null) {
      return _buildInitial(context);
    }
    return _buildPaymentDetails(context);
  }

  Widget _buildInitial(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pay with Cryptocurrency',
          style: AppTypography.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Pay with BTC, ETH, or USDT via Coinbase Commerce (from any wallet).',
          style: AppTypography.bodySmall.copyWith(color: Colors.white54),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            _cryptoChip('BTC', const Color(0xFFF7931A)),
            const SizedBox(width: AppSpacing.xs),
            _cryptoChip('ETH', const Color(0xFF627EEA)),
            const SizedBox(width: AppSpacing.xs),
            _cryptoChip('USDT', const Color(0xFF26A17B)),
          ],
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
          onTap: isLoading ? null : onCreateCharge,
          child: Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFF7931A), Color(0xFF627EEA)],
              ),
              borderRadius: AppSpacing.borderRadiusMd,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF7931A).withValues(alpha: 0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
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
                        const Icon(Icons.currency_bitcoin,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Generate Crypto Payment',
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

  Widget _buildPaymentDetails(BuildContext context) {
    final hostedUrl = chargeData?['hosted_url'] ?? '';
    final status = chargeData?['status'] ?? 'pending';
    final expiresAt = chargeData?['expires_at'] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF7931A).withValues(alpha: 0.15),
                borderRadius: AppSpacing.borderRadiusSm,
              ),
              child: const Icon(Icons.currency_bitcoin,
                  color: Color(0xFFF7931A), size: 24),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Crypto Payment Created',
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Status: ${status.toUpperCase()}',
                    style: AppTypography.bodySmall.copyWith(
                      color: status == 'completed'
                          ? AppColors.successGreen
                          : const Color(0xFFF59E0B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          width: double.infinity,
          padding: AppSpacing.paddingLg,
          decoration: BoxDecoration(
            color: AppColors.elevatedCardDark.withValues(alpha: 0.5),
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              Icon(
                Icons.qr_code_2,
                color: Colors.white54,
                size: 120,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Scan QR code or use the payment link',
                style: AppTypography.bodySmall.copyWith(color: Colors.white54),
              ),
            ],
          ),
        ),
        if (hostedUrl.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: hostedUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Payment link copied!')),
              );
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
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: () async {
              final uri = Uri.tryParse(hostedUrl);
              if (uri == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid payment link')),
                );
                return;
              }
              final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open payment link')),
                );
              }
            },
            child: Container(
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.elevatedCardDark.withValues(alpha: 0.6),
                borderRadius: AppSpacing.borderRadiusMd,
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Center(
                child: Text(
                  'Open Payment Link',
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
        if (expiresAt.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Payment expires: $expiresAt',
            style: AppTypography.bodySmall.copyWith(
              color: const Color(0xFFF59E0B),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Once payment is confirmed on the blockchain, credits will be added automatically.',
          style: AppTypography.bodySmall.copyWith(color: Colors.white38),
        ),
      ],
    );
  }

  Widget _cryptoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppSpacing.borderRadiusRound,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
