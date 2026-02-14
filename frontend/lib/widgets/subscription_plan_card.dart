import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

class SubscriptionPlanCard extends StatelessWidget {
  final Map<String, dynamic> plan;
  final bool isSelected;
  final bool isCurrent;
  final VoidCallback? onTap;

  const SubscriptionPlanCard({
    super.key,
    required this.plan,
    this.isSelected = false,
    this.isCurrent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = plan['name'] ?? 'Plan';
    final interval = plan['billing_interval'] ?? 'monthly';
    final credits = plan['credits_per_period'] ?? 0;
    final priceCents = plan['base_price_cents'] ?? 0;
    final price = (priceCents / 100).toStringAsFixed(2);
    final trialDays = plan['trial_days'] ?? 0;
    final rollover = plan['rollover_credits'] ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppSpacing.durationMedium,
        curve: Curves.easeOutCubic,
        padding: AppSpacing.paddingLg,
        decoration: BoxDecoration(
          color: isSelected
              ? _PlanColors.primary.withValues(alpha: 0.12)
              : _PlanColors.surface.withValues(alpha: 0.4),
          borderRadius: AppSpacing.borderRadiusLg,
          border: Border.all(
            color: isSelected
                ? _PlanColors.primary
                : isCurrent
                    ? _PlanColors.emerald.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.08),
            width: isSelected || isCurrent ? 2 : 1,
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
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: _PlanColors.emerald.withValues(alpha: 0.15),
                      borderRadius: AppSpacing.borderRadiusRound,
                      border: Border.all(
                        color: _PlanColors.emerald.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'CURRENT',
                      style: AppTypography.labelSmall.copyWith(
                        color: _PlanColors.emerald,
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
                    '/$interval',
                    style: AppTypography.bodySmall.copyWith(
                      color: Colors.white54,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _featureRow(Icons.bolt_rounded, '$credits credits/$interval', _PlanColors.primary),
            if (trialDays > 0)
              _featureRow(Icons.card_giftcard, '$trialDays-day free trial', _PlanColors.amber),
            if (rollover > 0)
              _featureRow(Icons.sync, 'Up to $rollover rollover credits', _PlanColors.blue),
            _featureRow(Icons.autorenew, 'Auto-renew $interval', Colors.white54),
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

  Widget _featureRow(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanColors {
  static const Color primary = AppColors.primaryBlue;
  static const Color surface = AppColors.elevatedCardDark;
  static const Color emerald = AppColors.successGreen;
  static const Color amber = AppColors.warningYellow;
  static const Color blue = AppColors.primaryBlueLight;
}
