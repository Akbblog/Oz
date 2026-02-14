import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

class SubscriptionStatusBanner extends StatelessWidget {
  final Map<String, dynamic>? subscription;
  final VoidCallback? onManage;
  final VoidCallback? onUpgrade;

  const SubscriptionStatusBanner({
    super.key,
    this.subscription,
    this.onManage,
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    if (subscription == null || subscription!.isEmpty) {
      return _buildNoSubscription();
    }
    return _buildActiveSubscription();
  }

  Widget _buildNoSubscription() {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: _BannerColors.surface.withValues(alpha: 0.4),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _BannerColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.star_outline,
              color: _BannerColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No Active Subscription',
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Subscribe to get monthly credits at a discount.',
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
          if (onUpgrade != null)
            GestureDetector(
              onTap: onUpgrade,
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
                  'Subscribe',
                  style: AppTypography.labelMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveSubscription() {
    final status = subscription?['status'] ?? 'active';
    final planName = subscription?['plan_name'] ?? 'Subscription';
    final nextBilling = subscription?['next_billing_date'] ?? '';
    final creditsUsed = subscription?['credits_used_this_period'] ?? 0;
    final creditsTotal = subscription?['credits_allocated_this_period'] ?? 0;
    final cancelAtEnd = subscription?['cancel_at_period_end'] == true;

    final statusColor = _getStatusColor(status);
    final statusLabel = cancelAtEnd ? 'Cancelling' : status.toUpperCase();

    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: _BannerColors.surface.withValues(alpha: 0.4),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: statusColor.withValues(alpha: 0.3),
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
                  color: statusColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getStatusIcon(status),
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      planName,
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          statusLabel,
                          style: AppTypography.labelSmall.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onManage != null)
                GestureDetector(
                  onTap: onManage,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: AppSpacing.borderRadiusSm,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      'Manage',
                      style: AppTypography.labelMedium.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (creditsTotal > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Credits used this period',
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white54,
                  ),
                ),
                Text(
                  '$creditsUsed / $creditsTotal',
                  style: AppTypography.labelMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: AppSpacing.borderRadiusRound,
              child: LinearProgressIndicator(
                minHeight: 6,
                value: creditsTotal > 0 ? (creditsUsed / creditsTotal).clamp(0.0, 1.0) : 0,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _BannerColors.primary,
                ),
              ),
            ),
          ],
          if (nextBilling.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              cancelAtEnd
                  ? 'Ends: $nextBilling'
                  : 'Next billing: $nextBilling',
              style: AppTypography.bodySmall.copyWith(
                color: cancelAtEnd
                    ? const Color(0xFFF59E0B)
                    : Colors.white38,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return AppColors.successGreen;
      case 'past_due':
        return const Color(0xFFF59E0B);
      case 'canceled':
      case 'expired':
        return AppColors.dangerRed;
      case 'paused':
        return const Color(0xFF60A5FA);
      default:
        return Colors.white54;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'active':
        return Icons.check_circle;
      case 'past_due':
        return Icons.warning_amber_rounded;
      case 'canceled':
      case 'expired':
        return Icons.cancel;
      case 'paused':
        return Icons.pause_circle;
      default:
        return Icons.help_outline;
    }
  }
}

class _BannerColors {
  static const Color primary = AppColors.primaryBlue;
  static const Color surface = AppColors.elevatedCardDark;
}
