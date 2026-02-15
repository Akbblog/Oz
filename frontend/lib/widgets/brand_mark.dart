import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';

/// Official brand mark (open-ended infinity loop).
///
/// Uses `assets/logo_mark.svg` (fill=currentColor) and supports an optional
/// teal tile background plus a hover glow for web/desktop.
class BrandMark extends StatefulWidget {
  final double size;
  final bool tiled;
  final double tileSize;
  final BorderRadius? tileRadius;
  final Color color;
  final Color tileColor;
  final bool hoverGlow;

  const BrandMark({
    super.key,
    this.size = 24,
    this.tiled = false,
    this.tileSize = 40,
    this.tileRadius,
    this.color = Colors.white,
    this.tileColor = AppColors.primaryBlue,
    this.hoverGlow = false,
  });

  @override
  State<BrandMark> createState() => _BrandMarkState();
}

class _BrandMarkState extends State<BrandMark> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final baseGlow = BoxShadow(
      color: AppColors.primaryBlue.withValues(alpha: 0.15),
      blurRadius: 20,
      offset: const Offset(0, 10),
    );
    final hoverGlow = BoxShadow(
      color: const Color(0xFF2C5F6D).withValues(alpha: 0.5),
      blurRadius: 15,
      spreadRadius: 0,
    );

    final mark = SvgPicture.asset(
      'assets/logo_mark.svg',
      width: widget.size,
      height: widget.size,
      colorFilter: ColorFilter.mode(widget.color, BlendMode.srcIn),
    );

    Widget content;
    if (widget.tiled) {
      content = AnimatedContainer(
        duration: AppSpacing.durationFast,
        curve: Curves.easeOut,
        width: widget.tileSize,
        height: widget.tileSize,
        decoration: BoxDecoration(
          color: widget.tileColor,
          borderRadius: widget.tileRadius ?? BorderRadius.circular(14),
          boxShadow: [
            baseGlow,
            if (widget.hoverGlow && _hovering) hoverGlow,
          ],
        ),
        child: Center(child: mark),
      );
    } else {
      // For the header logo, render the mark directly but still allow hover glow.
      content = AnimatedContainer(
        duration: AppSpacing.durationFast,
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: AppSpacing.borderRadiusMd,
          boxShadow: widget.hoverGlow && _hovering ? [hoverGlow] : const [],
        ),
        child: mark,
      );
    }

    if (!widget.hoverGlow) return content;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: content,
    );
  }
}
