import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

// ════════════════════════════════════════════════════════════════════════════
// SHARED HELPERS
// ════════════════════════════════════════════════════════════════════════════

Widget _chartCard({
  required String title,
  String? subtitle,
  Color accentColor = AppColors.brandPurple,
  required Widget child,
}) {
  return Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.surfaceDark,
      borderRadius: AppSpacing.borderRadiusLg,
      border: Border.all(color: AppColors.elevatedCardDark),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: accentColor),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              title,
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle, style: AppTypography.bodySmall.copyWith(color: Colors.white54)),
        ],
        const SizedBox(height: AppSpacing.lg),
        child,
      ],
    ),
  );
}

Widget _emptyState(String message) => SizedBox(
      height: 120,
      child: Center(
        child: Text(message, style: AppTypography.bodySmall.copyWith(color: Colors.white38)),
      ),
    );

// ════════════════════════════════════════════════════════════════════════════
// 1. DAU LINE CHART
// Daily Active Users for last 30 days — purple line on dark bg.
// ════════════════════════════════════════════════════════════════════════════

class DauLineChart extends StatelessWidget {
  /// Each item: {'date': 'YYYY-MM-DD', 'dau': int, 'sessions': int}
  final List<Map<String, dynamic>> data;
  final int days;

  const DauLineChart({super.key, required this.data, this.days = 30});

  @override
  Widget build(BuildContext context) {
    final hasData = data.isNotEmpty && data.any((d) => (d['dau'] as num? ?? 0) > 0);
    final peakDau = hasData
        ? data.map((d) => (d['dau'] as num? ?? 0).toInt()).reduce(math.max)
        : 0;

    return _chartCard(
      title: 'Daily Active Users',
      subtitle: 'Last $days days · peak $peakDau',
      accentColor: AppColors.brandPurple,
      child: hasData
          ? Column(
              children: [
                SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: CustomPaint(painter: _DauPainter(data)),
                ),
                const SizedBox(height: AppSpacing.sm),
                _DauXAxis(data: data),
              ],
            )
          : _emptyState('No activity data yet'),
    );
  }
}

class _DauXAxis extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _DauXAxis({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    final style = AppTypography.labelSmall.copyWith(color: Colors.white38);
    // Show first, middle, last label only
    final labels = <String>[];
    if (data.isNotEmpty) labels.add(_shortDate(data.first['date'] as String? ?? ''));
    if (data.length > 2) labels.add(_shortDate(data[data.length ~/ 2]['date'] as String? ?? ''));
    if (data.length > 1) labels.add(_shortDate(data.last['date'] as String? ?? ''));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels.map((l) => Text(l, style: style)).toList(),
    );
  }

  String _shortDate(String iso) {
    if (iso.length < 10) return iso;
    final parts = iso.split('-');
    if (parts.length < 3) return iso;
    return '${parts[1]}/${parts[2]}'; // MM/DD
  }
}

class _DauPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  _DauPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final values = data.map((d) => (d['dau'] as num? ?? 0).toDouble()).toList();
    final maxVal = values.reduce(math.max);
    final minVal = values.reduce(math.min);
    final range = (maxVal - minVal).abs() < 0.1 ? math.max(1.0, maxVal) : (maxVal - minVal);

    const pad = 8.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    // Grid lines
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    for (int i = 1; i <= 3; i++) {
      final y = pad + h * (i / 4);
      canvas.drawLine(Offset(pad, y), Offset(pad + w, y), gridPaint);
    }

    // Build smooth path
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = pad + (data.length == 1 ? w / 2 : w * i / (data.length - 1));
      final norm = maxVal <= 0 ? 0.5 : (values[i] - minVal) / range;
      final y = pad + h * (1 - norm);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final px = pad + w * (i - 1) / (data.length - 1);
        final pNorm = maxVal <= 0 ? 0.5 : (values[i - 1] - minVal) / range;
        final py = pad + h * (1 - pNorm);
        final cpX = (px + x) / 2;
        path.cubicTo(cpX, py, cpX, y, x, y);
      }
    }

    // Fill gradient below line
    final fillPath = Path.from(path);
    fillPath.lineTo(pad + w, pad + h);
    fillPath.lineTo(pad, pad + h);
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.brandPurple.withValues(alpha: 0.25),
            AppColors.brandPurple.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Glow + line
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..color = AppColors.brandPurple.withValues(alpha: 0.15)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColors.brandPurple
        ..strokeCap = StrokeCap.round,
    );

    // Dots
    final dot = Paint()..color = Colors.white;
    for (int i = 0; i < data.length; i++) {
      final x = pad + (data.length == 1 ? w / 2 : w * i / (data.length - 1));
      final norm = maxVal <= 0 ? 0.5 : (values[i] - minVal) / range;
      final y = pad + h * (1 - norm);
      canvas.drawCircle(Offset(x, y), 2.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _DauPainter old) => old.data != data;
}

// ════════════════════════════════════════════════════════════════════════════
// 2. FEATURE ADOPTION HORIZONTAL BAR CHART
// Shows which admin features (Stats, Users, Credits, Activity, Settings) are used most.
// ════════════════════════════════════════════════════════════════════════════

class FeatureAdoptionChart extends StatelessWidget {
  /// Each item: {'feature': String, 'uses': int, 'unique_users': int}
  final List<Map<String, dynamic>> data;
  final int days;

  const FeatureAdoptionChart({super.key, required this.data, this.days = 30});

  static const _featureColors = {
    'Stats':    AppColors.infoBlue,
    'Users':    AppColors.successGreen,
    'Credits':  AppColors.brandOrange,
    'Activity': AppColors.brandPurple,
    'Settings': AppColors.textSecondaryDark,
  };

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return _chartCard(
        title: 'Feature Adoption',
        subtitle: 'Last $days days',
        accentColor: AppColors.infoBlue,
        child: _emptyState('No feature usage tracked yet'),
      );
    }

    final maxUses = data.map((d) => (d['uses'] as num? ?? 0).toInt()).reduce(math.max);

    return _chartCard(
      title: 'Feature Adoption',
      subtitle: 'Last $days days · by tab usage',
      accentColor: AppColors.infoBlue,
      child: Column(
        children: data.map((item) {
          final feature = item['feature'] as String? ?? 'Unknown';
          final uses = (item['uses'] as num? ?? 0).toInt();
          final users = (item['unique_users'] as num? ?? 0).toInt();
          final pct = maxUses > 0 ? uses / maxUses : 0.0;
          final color = _featureColors[feature] ?? AppColors.brandPurple;

          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        feature,
                        style: AppTypography.bodySmall.copyWith(color: Colors.white70),
                      ),
                    ),
                    Text(
                      '$uses uses · $users users',
                      style: AppTypography.labelSmall.copyWith(color: Colors.white38),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(
                    children: [
                      Container(height: 8, color: AppColors.elevatedCardDark),
                      FractionallySizedBox(
                        widthFactor: pct.clamp(0.0, 1.0),
                        child: Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 3. CONVERSION FUNNEL
// Landing → Registration → First Search → Credit Purchase
// ════════════════════════════════════════════════════════════════════════════

class ConversionFunnelChart extends StatelessWidget {
  /// Each item: {'step': String, 'count': int, 'drop_off_pct': double?}
  final List<Map<String, dynamic>> data;
  final int days;

  const ConversionFunnelChart({super.key, required this.data, this.days = 90});

  static const _stepColors = [
    AppColors.primaryBlueLight,
    AppColors.infoBlue,
    AppColors.brandPurple,
    AppColors.successGreen,
  ];

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return _chartCard(
        title: 'Conversion Funnel',
        subtitle: 'Last $days days',
        accentColor: AppColors.successGreen,
        child: _emptyState('No funnel data yet'),
      );
    }

    final maxCount = data.map((d) => (d['count'] as num? ?? 0).toInt()).reduce(math.max);

    return _chartCard(
      title: 'Conversion Funnel',
      subtitle: 'Last $days days · Landing → Purchase',
      accentColor: AppColors.successGreen,
      child: Column(
        children: List.generate(data.length, (i) {
          final item = data[i];
          final step = item['step'] as String? ?? '';
          final count = (item['count'] as num? ?? 0).toInt();
          final dropPct = item['drop_off_pct'] as double?;
          final pct = maxCount > 0 ? count / maxCount : 0.0;
          final color = i < _stepColors.length ? _stepColors[i] : AppColors.brandPurple;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        step,
                        style: AppTypography.bodySmall.copyWith(color: Colors.white70),
                      ),
                    ),
                    Text(
                      count.toString(),
                      style: AppTypography.labelMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (dropPct != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '↓ ${dropPct.toStringAsFixed(0)}%',
                        style: AppTypography.labelSmall.copyWith(
                          color: dropPct > 50
                              ? AppColors.dangerRed
                              : AppColors.warningYellow,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      Container(height: 10, color: AppColors.elevatedCardDark),
                      FractionallySizedBox(
                        widthFactor: pct.clamp(0.02, 1.0),
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 4. SESSION STATS ROW
// Simple metric tiles: Total Sessions, Bounce Rate
// ════════════════════════════════════════════════════════════════════════════

class SessionStatsRow extends StatelessWidget {
  final Map<String, dynamic> data;

  const SessionStatsRow({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final totalSessions = (data['total_sessions'] as num? ?? 0).toInt();
    final totalEvents   = (data['total_events'] as num? ?? 0).toInt();
    final bounceRate    = (data['bounce_rate_pct'] as num? ?? 0).toDouble();

    return Row(
      children: [
        Expanded(child: _StatTile(label: 'Sessions', value: totalSessions.toString(), color: AppColors.infoBlue)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: _StatTile(label: 'Events', value: totalEvents.toString(), color: AppColors.brandPurple)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatTile(
            label: 'Bounce Rate',
            value: '${bounceRate.toStringAsFixed(1)}%',
            color: bounceRate > 70 ? AppColors.dangerRed : AppColors.successGreen,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatTile({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: AppColors.elevatedCardDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.labelSmall.copyWith(color: Colors.white38)),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.titleLarge.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
