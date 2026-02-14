import 'package:flutter/material.dart';

import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

// ---------------------------------------------------------------------------
// Credit Pill – animated header widget (shared across mobile + web/desktop)
// ---------------------------------------------------------------------------

class CreditPill extends StatefulWidget {
  final int balance;
  final int maxBalance;
  final bool loading;
  final VoidCallback onTap;
  final VoidCallback? onRefresh;

  const CreditPill({
    super.key,
    required this.balance,
    this.maxBalance = 100,
    required this.loading,
    required this.onTap,
    this.onRefresh,
  });

  @override
  State<CreditPill> createState() => _CreditPillState();
}

class _CreditPillState extends State<CreditPill> with TickerProviderStateMixin {
  static const _teal = Color(0xFF2C5F6D);
  static const _ochre = Color(0xFFD69446);
  static const _rose = Color(0xFFB86E6E);

  bool _isHovered = false;

  // Pulsing glow – high balance
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Breathing border – low balance
  late final AnimationController _breatheCtrl;
  late final Animation<double> _breatheAnim;

  // Refresh icon spin
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseAnim = Tween<double>(begin: 0.25, end: 0.55).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _breatheAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _breatheCtrl, curve: Curves.easeInOut),
    );

    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant CreditPill old) {
    super.didUpdateWidget(old);
    if (old.balance != widget.balance) _syncAnimations();
  }

  void _syncAnimations() {
    if (widget.balance > 50) {
      _pulseCtrl.repeat(reverse: true);
      _breatheCtrl
        ..stop()
        ..value = 0;
    } else if (widget.balance <= 10) {
      _pulseCtrl
        ..stop()
        ..value = 0;
      _breatheCtrl.repeat(reverse: true);
    } else {
      _pulseCtrl
        ..stop()
        ..value = 0;
      _breatheCtrl
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _breatheCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  Color get _color {
    if (widget.balance > 50) return _teal;
    if (widget.balance > 10) return _ochre;
    return _rose;
  }

  void _handleRefresh() {
    if (widget.onRefresh == null) return;
    _spinCtrl.forward(from: 0);
    widget.onRefresh!.call();
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.maxBalance > 0
        ? (widget.balance / widget.maxBalance).clamp(0.0, 1.0)
        : 0.0;
    final color = _color;
    final isHigh = widget.balance > 50;
    final isLow = widget.balance <= 10;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulseCtrl, _breatheCtrl]),
          builder: (context, _) {
            // --- glow intensity ---
            final glowAlpha =
                isHigh ? _pulseAnim.value : (_isHovered ? 0.45 : 0.30);
            final glowSpread = isHigh
                ? -6.0 + (_pulseAnim.value * 8)
                : (_isHovered ? -2.0 : -6.0);

            // --- border colour ---
            final borderCol = isLow
                ? Color.lerp(
                    color.withValues(alpha: 0.4),
                    const Color(0xFFFF5555).withValues(alpha: 0.9),
                    _breatheAnim.value,
                  )!
                : color.withValues(alpha: _isHovered ? 0.7 : 0.5);

            return AnimatedScale(
              scale: _isHovered ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.20),
                  borderRadius: AppSpacing.borderRadiusRound,
                  border: Border.all(
                    color: borderCol,
                    width: isLow ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: glowAlpha),
                      blurRadius: _isHovered ? 18 : 12,
                      spreadRadius: glowSpread,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Progress fill
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: fill,
                        child: Container(color: color),
                      ),
                    ),

                    // Content
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (widget.loading)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          else
                            Text(
                              '${widget.balance} Cr',
                              style: AppTypography.labelSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (!widget.loading && widget.onRefresh != null) ...[
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: _handleRefresh,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                child: RotationTransition(
                                  turns: _spinCtrl,
                                  child: const Icon(
                                    Icons.refresh_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

