import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

class LowBalanceAlert extends StatelessWidget {
  final int currentBalance;
  final int threshold;
  final VoidCallback? onBuyCredits;
  final bool dismissible;
  final VoidCallback? onDismiss;

  const LowBalanceAlert({
    super.key,
    required this.currentBalance,
    this.threshold = 10,
    this.onBuyCredits,
    this.dismissible = true,
    this.onDismiss,
  });

  bool get shouldShow => currentBalance <= threshold;

  @override
  Widget build(BuildContext context) {
    if (!shouldShow) return const SizedBox.shrink();

    final isZero = currentBalance <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: (isZero ? AppColors.dangerRed : _AlertColors.amber)
            .withValues(alpha: 0.1),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: (isZero ? AppColors.dangerRed : _AlertColors.amber)
              .withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isZero ? AppColors.dangerRed : _AlertColors.amber)
                  .withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isZero ? Icons.error_outline : Icons.warning_amber_rounded,
              color: isZero ? AppColors.dangerRed : _AlertColors.amber,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isZero ? 'No Credits Remaining' : 'Low Credit Balance',
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isZero
                      ? 'Purchase credits to continue using the service.'
                      : 'You have $currentBalance credits left. Consider buying more.',
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
          if (onBuyCredits != null)
            GestureDetector(
              onTap: onBuyCredits,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: Text(
                  'Buy',
                  style: AppTypography.labelMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          if (dismissible && onDismiss != null) ...[
            const SizedBox(width: AppSpacing.xs),
            GestureDetector(
              onTap: onDismiss,
              child: const Icon(Icons.close, color: Colors.white38, size: 18),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlertColors {
  static const Color amber = Color(0xFFF59E0B);
}
