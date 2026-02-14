import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

class RevenueChartPoint {
  final String label;
  final double value;

  const RevenueChartPoint({required this.label, required this.value});
}

class RevenueChart extends StatelessWidget {
  final List<RevenueChartPoint> points;
  final String title;
  final String? subtitle;

  const RevenueChart({
    super.key,
    required this.points,
    this.title = 'Revenue',
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final hasData = points.isNotEmpty && points.any((p) => p.value > 0);
    final maxValue =
        points.isEmpty ? 0.0 : points.map((e) => e.value).reduce(math.max);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.primaryGradient,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                hasData ? _formatCompact(maxValue) : '—',
                style: AppTypography.labelLarge.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: AppTypography.bodySmall.copyWith(color: Colors.white54),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: hasData
                ? CustomPaint(painter: _RevenueChartPainter(points))
                : _EmptyChart(),
          ),
          const SizedBox(height: AppSpacing.md),
          _XAxisLabels(points: points),
        ],
      ),
    );
  }

  String _formatCompact(double v) {
    if (v >= 1000000) return '\$${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(1)}K';
    return '\$${v.toStringAsFixed(0)}';
  }
}

class _EmptyChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.5),
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.15)),
      ),
      child: Center(
        child: Text(
          'No data yet',
          style: AppTypography.bodySmall.copyWith(color: Colors.white54),
        ),
      ),
    );
  }
}

class _XAxisLabels extends StatelessWidget {
  final List<RevenueChartPoint> points;

  const _XAxisLabels({required this.points});

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final labels = points.length <= 6
        ? points.map((p) => p.label).toList()
        : [
            points.first.label,
            points[points.length ~/ 2].label,
            points.last.label,
          ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: labels
          .map(
            (l) => Text(
              l,
              style: AppTypography.labelSmall.copyWith(color: Colors.white54),
            ),
          )
          .toList(),
    );
  }
}

class _RevenueChartPainter extends CustomPainter {
  final List<RevenueChartPoint> points;

  _RevenueChartPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final values = points.map((p) => p.value).toList();
    final maxVal = values.reduce(math.max);
    final minVal = values.reduce(math.min);
    final range = (maxVal - minVal).abs() < 0.0001 ? 1.0 : (maxVal - minVal);

    final padding = 8.0;
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      final y = padding + h * (i / 4);
      canvas.drawLine(Offset(padding, y), Offset(padding + w, y), gridPaint);
    }

    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final x = padding + (points.length == 1 ? w / 2 : w * (i / (points.length - 1)));
      final norm = (points[i].value - minVal) / range;
      final y = padding + h * (1 - norm);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        final prevX = padding + w * ((i - 1) / (points.length - 1));
        final prevNorm = (points[i - 1].value - minVal) / range;
        final prevY = padding + h * (1 - prevNorm);
        final cpX = (prevX + x) / 2;
        path.cubicTo(cpX, prevY, cpX, y, x, y);
      }
    }

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = AppColors.primaryBlue.withValues(alpha: 0.12)
      ..strokeCap = StrokeCap.round;

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..shader = LinearGradient(
        colors: [AppColors.primaryBlue, AppColors.primaryBlueLight],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, glow);
    canvas.drawPath(path, line);

    final dotPaint = Paint()..color = Colors.white;
    for (int i = 0; i < points.length; i++) {
      final x = padding + (points.length == 1 ? w / 2 : w * (i / (points.length - 1)));
      final norm = (points[i].value - minVal) / range;
      final y = padding + h * (1 - norm);
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RevenueChartPainter oldDelegate) {
    if (oldDelegate.points.length != points.length) return true;
    for (int i = 0; i < points.length; i++) {
      if (oldDelegate.points[i].value != points[i].value) return true;
    }
    return false;
  }
}
