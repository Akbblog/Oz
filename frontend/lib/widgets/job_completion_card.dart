import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class JobCardMetaItem {
  final IconData icon;
  final String text;

  const JobCardMetaItem({
    required this.icon,
    required this.text,
  });
}

class JobCompletionCard extends StatelessWidget {
  final String category;
  final String jobId;
  final DateTime completedAt;
  final int leadCount;
  final String citiesText;
  final String durationText;
  final String topCityText;
  final String avgPerCityText;
  final bool isDownloading;
  final VoidCallback onViewResults;
  final VoidCallback onDownload;
  final String downloadLabel;
  final Widget? trailing;
  final EdgeInsetsGeometry? margin;

  const JobCompletionCard({
    super.key,
    required this.category,
    required this.jobId,
    required this.completedAt,
    required this.leadCount,
    required this.citiesText,
    required this.durationText,
    required this.topCityText,
    required this.avgPerCityText,
    required this.isDownloading,
    required this.onViewResults,
    required this.onDownload,
    this.downloadLabel = 'Download Excel',
    this.trailing,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.backgroundDarkAlt,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.elevatedCardDark,
                  borderRadius: AppSpacing.borderRadiusMd,
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(
                  _jobCategoryIcon(category),
                  color: AppColors.primaryBlueLight,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '#$jobId   ${_formatJobCompactDateTime(completedAt)}',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white54,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.successGreen.withValues(alpha: 0.12),
                  borderRadius: AppSpacing.borderRadiusRound,
                  border: Border.all(
                    color: AppColors.successGreen.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: AppColors.successGreen,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Completed',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.successGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: AppSpacing.paddingSm,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: AppSpacing.borderRadiusMd,
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(
                  icon: Icons.business_center_rounded,
                  label: '$leadCount leads found',
                  color: AppColors.primaryBlueLight,
                  bold: true,
                ),
                const SizedBox(height: AppSpacing.xxs),
                _infoRow(
                  icon: Icons.location_city_rounded,
                  label: 'Cities: $citiesText',
                  color: Colors.white70,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    _metaPill(Icons.timer_rounded, durationText),
                    _metaPill(Icons.insights_rounded, topCityText),
                    _metaPill(Icons.speed_rounded, avgPerCityText),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final stackButtons = constraints.maxWidth < 500;
              if (stackButtons) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: onViewResults,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryBlueLight,
                        side: const BorderSide(color: AppColors.primaryBlue),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppSpacing.borderRadiusSm,
                        ),
                      ),
                      child: const Text('View Results'),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _downloadButton(),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onViewResults,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryBlueLight,
                        side: const BorderSide(color: AppColors.primaryBlue),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppSpacing.borderRadiusSm,
                        ),
                      ),
                      child: const Text('View Results'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _downloadButton()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _downloadButton() {
    return ElevatedButton.icon(
      onPressed: isDownloading ? null : onDownload,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.primaryBlue.withValues(alpha: 0.45),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusSm,
        ),
      ),
      icon: isDownloading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Icon(Icons.download_rounded, size: 18),
      label: Text(isDownloading ? 'Downloading...' : downloadLabel),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required Color color,
    bool bold = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white70,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _metaPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white54),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class JobStatusCard extends StatelessWidget {
  final String category;
  final String jobId;
  final DateTime timestamp;
  final String statusLabel;
  final Color statusColor;
  final Color statusBackground;
  final IconData statusIcon;
  final String primaryInfo;
  final String secondaryInfo;
  final List<JobCardMetaItem> metaItems;
  final bool isDownloading;
  final VoidCallback onViewResults;
  final VoidCallback onDownload;
  final String viewLabel;
  final String downloadLabel;
  final String busyLabel;
  final IconData secondaryIcon;
  final bool secondaryAsOutlined;
  final Color secondaryColor;
  final Color secondaryForegroundColor;
  final Color? secondaryBorderColor;
  final Widget? trailing;
  final EdgeInsetsGeometry? margin;

  const JobStatusCard({
    super.key,
    required this.category,
    required this.jobId,
    required this.timestamp,
    required this.statusLabel,
    required this.statusColor,
    required this.statusBackground,
    required this.statusIcon,
    required this.primaryInfo,
    required this.secondaryInfo,
    this.metaItems = const [],
    required this.isDownloading,
    required this.onViewResults,
    required this.onDownload,
    this.viewLabel = 'View Results',
    this.downloadLabel = 'Download CSV',
    this.busyLabel = 'Downloading...',
    this.secondaryIcon = Icons.download_rounded,
    this.secondaryAsOutlined = false,
    this.secondaryColor = AppColors.primaryBlue,
    this.secondaryForegroundColor = Colors.white,
    this.secondaryBorderColor,
    this.trailing,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.backgroundDarkAlt,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 18,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.elevatedCardDark,
                  borderRadius: AppSpacing.borderRadiusMd,
                  border: Border.all(
                    color: AppColors.primaryBlue.withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(
                  _jobCategoryIcon(category),
                  color: AppColors.primaryBlueLight,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '#$jobId   ${_formatJobCompactDateTime(timestamp)}',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white54,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: AppSpacing.borderRadiusRound,
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.32),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 6),
                    Text(
                      statusLabel,
                      style: AppTypography.labelSmall.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: AppSpacing.paddingSm,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: AppSpacing.borderRadiusMd,
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(
                  icon: Icons.account_circle_rounded,
                  label: primaryInfo,
                  color: AppColors.primaryBlueLight,
                  bold: true,
                ),
                const SizedBox(height: AppSpacing.xxs),
                _infoRow(
                  icon: Icons.list_alt_rounded,
                  label: secondaryInfo,
                  color: Colors.white70,
                ),
                if (metaItems.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final item in metaItems)
                        _metaPill(item.icon, item.text),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final stackButtons = constraints.maxWidth < 500;
              if (stackButtons) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: onViewResults,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryBlueLight,
                        side: const BorderSide(color: AppColors.primaryBlue),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppSpacing.borderRadiusSm,
                        ),
                      ),
                      child: Text(viewLabel),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _secondaryButton(),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onViewResults,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryBlueLight,
                        side: const BorderSide(color: AppColors.primaryBlue),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppSpacing.borderRadiusSm,
                        ),
                      ),
                      child: Text(viewLabel),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: _secondaryButton()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _secondaryButton() {
    if (secondaryAsOutlined) {
      return OutlinedButton.icon(
        onPressed: isDownloading ? null : onDownload,
        style: OutlinedButton.styleFrom(
          foregroundColor: secondaryColor,
          side: BorderSide(
            color:
                secondaryBorderColor ?? secondaryColor.withValues(alpha: 0.55),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderRadiusSm,
          ),
        ),
        icon: isDownloading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(secondaryColor),
                ),
              )
            : Icon(secondaryIcon, size: 18, color: secondaryColor),
        label: Text(isDownloading ? busyLabel : downloadLabel),
      );
    }

    return ElevatedButton.icon(
      onPressed: isDownloading ? null : onDownload,
      style: ElevatedButton.styleFrom(
        backgroundColor: secondaryColor,
        foregroundColor: secondaryForegroundColor,
        disabledBackgroundColor: secondaryColor.withValues(alpha: 0.45),
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusSm,
        ),
      ),
      icon: isDownloading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  secondaryForegroundColor,
                ),
              ),
            )
          : Icon(
              secondaryIcon,
              size: 18,
              color: secondaryForegroundColor,
            ),
      label: Text(isDownloading ? busyLabel : downloadLabel),
    );
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required Color color,
    bool bold = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white70,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _metaPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white54),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _jobCategoryIcon(String category) {
  final value = category.toLowerCase();
  if (value.contains('restaurant') || value.contains('food')) {
    return Icons.restaurant_rounded;
  }
  if (value.contains('dentist') || value.contains('clinic')) {
    return Icons.medical_services_rounded;
  }
  if (value.contains('shop') || value.contains('e-commerce')) {
    return Icons.shopping_cart_rounded;
  }
  if (value.contains('startup') || value.contains('tech')) {
    return Icons.lan_rounded;
  }
  if (value.contains('real estate')) {
    return Icons.apartment_rounded;
  }
  return Icons.work_history_rounded;
}

String _formatJobCompactDateTime(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hh = value.hour.toString().padLeft(2, '0');
  final mm = value.minute.toString().padLeft(2, '0');
  return '${months[value.month - 1]} ${value.day}, $hh:$mm';
}
