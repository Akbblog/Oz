import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Gradient elevated button
class GradientButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final LinearGradient? gradient;
  final double? width;
  final double height;
  final IconData? icon;
  final bool expanded;

  const GradientButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.gradient,
    this.width,
    this.height = 56,
    this.icon,
    this.expanded = true,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppSpacing.durationFast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null && !widget.isLoading;
    final baseGradient = widget.gradient ?? AppColors.primaryGradient;
    final hoverGradient = widget.gradient == null
        ? LinearGradient(
            begin: baseGradient.begin,
            end: baseGradient.end,
            colors: [
              AppColors.brighten(AppColors.primaryBlue, 0.10),
              AppColors.brighten(AppColors.primaryBlueDark, 0.10),
            ],
          )
        : baseGradient;

    final button = AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
      child: MouseRegion(
        onEnter: (_) {
          if (!mounted) return;
          setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (!mounted) return;
          setState(() => _isHovered = false);
        },
        child: Container(
          width: widget.expanded ? double.infinity : widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            gradient: isEnabled
                ? (_isHovered ? hoverGradient : baseGradient)
                : LinearGradient(
                    colors: [Colors.grey.shade400, Colors.grey.shade500],
                  ),
            borderRadius: AppSpacing.borderRadiusLg, // 12px to match cards
            boxShadow: isEnabled
                ? [
                    if (_isHovered)
                      BoxShadow(
                        // Soft outer glow ("charged" state)
                        color: AppColors.primaryBlue.withValues(alpha: 0.55),
                        blurRadius: 18,
                        spreadRadius: 2,
                        offset: const Offset(0, 0),
                      ),
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(
                        alpha: _isHovered ? 0.35 : 0.30,
                      ),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.isLoading ? null : widget.onPressed,
              onTapDown: (_) => _controller.forward(),
              onTapUp: (_) => _controller.reverse(),
              onTapCancel: () => _controller.reverse(),
              borderRadius: AppSpacing.borderRadiusLg,
              child: Center(
                child: widget.isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(
                              widget.icon,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                          ],
                          Text(
                            widget.text,
                            style: AppTypography.labelLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );

    return button;
  }
}

/// Outline button with gradient border
class GradientOutlineButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  const GradientOutlineButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: AppSpacing.borderRadiusLg, // 12px to match cards
        gradient: AppColors.primaryGradient,
      ),
      padding: const EdgeInsets.all(2),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg - 2),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg - 2),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      color: AppColors.primaryBlue,
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Text(
                    text,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
