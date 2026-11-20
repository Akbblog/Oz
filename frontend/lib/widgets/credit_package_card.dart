import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

class CreditPackageCard extends StatelessWidget {
  final Map<String, dynamic> package;
  final bool isSelected;
  final bool isFeatured;
  final int? savingsPercent;
  final String comparisonName;
  final VoidCallback? onTap;

  const CreditPackageCard({
    super.key,
    required this.package,
    this.isSelected = false,
    this.isFeatured = false,
    this.savingsPercent,
    this.comparisonName = 'Starter',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = '${package['name'] ?? 'Package'}';
    final credits = (package['credits'] as num?)?.toInt() ?? 0;
    final cents = (package['display_price_cents'] as num?)?.toInt() ??
        (package['base_price_cents'] as num?)?.toInt() ??
        0;
    final price = (cents / 100).toStringAsFixed(2);
    final unitPrice =
        credits > 0 ? (cents / credits / 100).toStringAsFixed(3) : '0.000';
    final features = package['features'] as List? ?? const [];

    return Semantics(
      button: true,
      selected: isSelected,
      label:
          '$name, $credits credits for $price dollars, ${isSelected ? 'selected' : 'select package'}',
      child: Material(
        color: isSelected ? AppColors.selectedDark : AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusLg,
          side: BorderSide(
            color:
                isSelected ? AppColors.primaryBlueLight : AppColors.borderDark,
            width: isSelected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: AppSpacing.paddingLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(name, style: AppTypography.titleMediumDark),
                    ),
                    if (isFeatured)
                      _badge('POPULAR', AppColors.primaryBlueLight),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '$credits credits',
                  style: AppTypography.headlineSmallDark.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '\$$price one-time  ·  \$$unitPrice per credit',
                  style: AppTypography.bodySmallDark,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (savingsPercent != null && savingsPercent! > 0)
                  _badge(
                    '$savingsPercent% less per credit than $comparisonName',
                    AppColors.successGreen,
                  )
                else
                  Text(
                    'Credits never expire',
                    style: AppTypography.bodySmallDark,
                  ),
                if (features.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  ...features.take(3).map(
                        (feature) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $feature',
                              style: AppTypography.bodySmallDark),
                        ),
                      ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: isSelected
                          ? AppColors.successGreen
                          : AppColors.textSecondaryDark,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      isSelected ? 'Selected package' : 'Select package',
                      style: AppTypography.labelLargeDark.copyWith(
                        color: isSelected
                            ? AppColors.successGreen
                            : AppColors.textPrimaryDark,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: AppSpacing.borderRadiusSm,
        ),
        child:
            Text(text, style: AppTypography.labelSmall.copyWith(color: color)),
      );
}
