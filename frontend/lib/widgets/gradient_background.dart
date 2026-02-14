import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Animated gradient background widget
class GradientBackground extends StatelessWidget {
  final Widget child;
  final LinearGradient? gradient;
  final bool showPattern;

  const GradientBackground({
    super.key,
    required this.child,
    this.gradient,
    this.showPattern = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: gradient ?? LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.backgroundDark, AppColors.surfaceDark],
        ),
      ),
      child: Stack(
        children: [
          if (showPattern) ...[
            // Decorative circles
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceDark,
                ),
              ),
            ),
            Positioned(
              bottom: -150,
              left: -100,
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryBlue.withValues(alpha: 0.05),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).size.height * 0.3,
              left: -50,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryBlue.withValues(alpha: 0.05),
                ),
              ),
            ),
          ],
          child,
        ],
      ),
    );
  }
}
