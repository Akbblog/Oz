import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

class CreditPackageCard extends StatelessWidget {
  final Map<String, dynamic> package;
  final bool isSelected;
  final bool isFeatured;
  final VoidCallback? onTap;

  const CreditPackageCard({
    super.key,
    required this.package,
    this.isSelected = false,
    this.isFeatured = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = package['name'] ?? 'Package';
    final credits = package['credits'] ?? 0;
    final priceCents = package['display_price_cents'] ?? package['base_price_cents'] ?? 0;
    final price = (priceCents / 100).toStringAsFixed(2);
    final pricePerCredit = credits > 0
        ? (priceCents / credits / 100).toStringAsFixed(3)
        : '0.000';
    final discount = package['discount_percentage'] ?? 0;
    final features = package['features'] as List? ?? [];

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppSpacing.durationMedium,
        curve: Curves.easeOutCubic,
        padding: AppSpacing.paddingLg,
        decoration: BoxDecoration(
          color: isSelected
              ? _CardColors.primary.withValues(alpha: 0.12)
              : _CardColors.surface.withValues(alpha: 0.4),
          borderRadius: AppSpacing.borderRadiusLg,
          border: Border.all(
            color: isSelected
                ? _CardColors.primary
                : isFeatured
                    ? _CardColors.primary.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isFeatured)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: AppSpacing.borderRadiusRound,
                    ),
                    child: Text(
                      'POPULAR',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '\$$price',
                  style: AppTypography.headlineLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: AppSpacing.xxs),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'one-time',
                    style: AppTypography.bodySmall.copyWith(
                      color: Colors.white54,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _CardColors.emerald.withValues(alpha: 0.15),
                    borderRadius: AppSpacing.borderRadiusSm,
                  ),
                  child: Text(
                    '$credits credits',
                    style: AppTypography.labelMedium.copyWith(
                      color: _CardColors.emerald,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '\$$pricePerCredit/credit',
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
            if (discount > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: _CardColors.amber.withValues(alpha: 0.15),
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: Text(
                  'Save ${discount.toStringAsFixed(0)}%',
                  style: AppTypography.labelSmall.copyWith(
                    color: _CardColors.amber,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            if (features.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              ...features.take(3).map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: _CardColors.emerald, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            f.toString(),
                            style: AppTypography.bodySmall.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
            if (isSelected) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: AppSpacing.borderRadiusMd,
                ),
                child: Text(
                  'Selected',
                  textAlign: TextAlign.center,
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CardColors {
  static const Color primary = AppColors.primaryBlue;
  static const Color surface = AppColors.elevatedCardDark;
  static const Color emerald = AppColors.successGreen;
  static const Color amber = AppColors.warningYellow;
}
