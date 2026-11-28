/// Building blocks for the public landing page: palette, type, buttons,
/// scroll-reveal, count-up numbers and the animated hero illustration.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class LC {
  LC._();
  static const Color bg = Color(0xFF0A0C0E);
  static const Color surface = Color(0xFF111418);
  static const Color card = Color(0xFF151A1F);
  static const Color cardHi = Color(0xFF1A2026);
  static const Color border = Color(0xFF222932);
  static const Color borderHi = Color(0xFF303946);
  static const Color text = Color(0xFFF3F5F7);
  static const Color dim = Color(0xFFA9B3BE);
  static const Color mute = Color(0xFF6D7783);
  static const Color accent = Color(0xFF6CC4D6);
  static const Color accentDeep = Color(0xFF2C5F6D);
  static const Color violet = Color(0xFF8E7CF8);
  static const Color warm = Color(0xFFF5B544);
  static const Color green = Color(0xFF4BCE97);

  static const LinearGradient brand = LinearGradient(
    colors: [Color(0xFF7FE0EE), Color(0xFF6CC4D6), Color(0xFF9B8CFA)],
    stops: [0.0, 0.45, 1.0],
  );
}

class LT {
  LT._();
  static const String font = 'Inter';

  static TextStyle display(double size) => TextStyle(
      fontFamily: font,
      color: LC.text,
      fontSize: size,
      height: 1.04,
      fontWeight: FontWeight.w700,
      letterSpacing: -size * 0.032);
  static const TextStyle h2 = TextStyle(
      fontFamily: font,
      color: LC.text,
      fontSize: 34,
      height: 1.12,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.9);
  static const TextStyle h3 = TextStyle(
      fontFamily: font,
      color: LC.text,
      fontSize: 18,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2);
  static const TextStyle lead = TextStyle(
      fontFamily: font, color: LC.dim, fontSize: 18, height: 1.55);
  static const TextStyle body = TextStyle(
      fontFamily: font, color: LC.dim, fontSize: 15, height: 1.6);
  static const TextStyle small = TextStyle(
      fontFamily: font, color: LC.mute, fontSize: 13, height: 1.45);
  static const TextStyle eyebrow = TextStyle(
      fontFamily: font,
      color: LC.accent,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.3);
}

/// Text painted with the brand gradient.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const GradientText(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LC.brand.createShader(r),
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

class LButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final IconData? trailing;
  final bool large;
  const LButton(this.label,
      {super.key,
      required this.onPressed,
      this.primary = true,
      this.trailing,
      this.large = false});

  @override
  State<LButton> createState() => _LButtonState();
}

class _LButtonState extends State<LButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.primary;
    final h = widget.large ? 52.0 : 42.0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: h,
          padding: EdgeInsets.symmetric(horizontal: widget.large ? 24 : 18),
          transform: Matrix4.translationValues(0, _hover ? -1.5 : 0, 0),
          decoration: BoxDecoration(
            color: p
                ? (_hover ? const Color(0xFF86D6E6) : LC.accent)
                : (_hover ? LC.cardHi : Colors.transparent),
            borderRadius: BorderRadius.circular(h / 2),
            border: p ? null : Border.all(color: _hover ? LC.borderHi : LC.border),
            boxShadow: p
                ? [
                    BoxShadow(
                      color: LC.accent.withValues(alpha: _hover ? 0.38 : 0.22),
                      blurRadius: _hover ? 28 : 18,
                      offset: const Offset(0, 8),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.label,
                  style: TextStyle(
                      fontFamily: LT.font,
                      color: p ? const Color(0xFF06181D) : LC.text,
                      fontSize: widget.large ? 15.5 : 14,
                      fontWeight: FontWeight.w700)),
              if (widget.trailing != null) ...[
                const SizedBox(width: 8),
                AnimatedSlide(
                  duration: const Duration(milliseconds: 160),
                  offset: Offset(_hover ? 0.18 : 0, 0),
                  child: Icon(widget.trailing,
                      size: 17, color: p ? const Color(0xFF06181D) : LC.text),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tells [Reveal] widgets that the page scrolled.
class RevealScope extends InheritedNotifier<ValueNotifier<int>> {
  const RevealScope({super.key, required ValueNotifier<int> tick, required super.child})
      : super(notifier: tick);

  static ValueNotifier<int>? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RevealScope>()?.notifier;
}

/// Fades and slides its child in the first time it scrolls into view.
class Reveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double dy;
  final ValueChanged<bool>? onShown;
  const Reveal(
      {super.key,
      required this.child,
      this.delay = Duration.zero,
      this.dy = 26,
      this.onShown});

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 720));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    RevealScope.of(context); // rebuild (and re-check) whenever the page scrolls
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_started || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final screen = MediaQuery.of(context).size.height;
    if (top < screen * 0.92) {
      _started = true;
      Future.delayed(widget.delay, () {
        if (!mounted) return;
        _c.forward();
        widget.onShown?.call(true);
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
            offset: Offset(0, (1 - curve.value) * widget.dy), child: child),
      ),
      child: widget.child,
    );
  }
}

/// A number that counts up when [play] becomes true.
class CountUp extends StatelessWidget {
  final int value;
  final bool play;
  final TextStyle style;
  final String suffix;
  const CountUp(
      {super.key,
      required this.value,
      required this.play,
      required this.style,
      this.suffix = ''});

  static String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: play ? value.toDouble() : 0),
      duration: const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${_fmt(v.round())}$suffix', style: style),
    );
  }
}

/// Card that lifts and lights its border on hover.
class HoverCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color glow;
  const HoverCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(24),
      this.glow = LC.accent});

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover ? -4 : 0, 0),
        padding: widget.padding,
        decoration: BoxDecoration(
          color: _hover ? LC.cardHi : LC.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: _hover ? widget.glow.withValues(alpha: 0.45) : LC.border),
          boxShadow: [
            BoxShadow(
              color: _hover
                  ? widget.glow.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.18),
              blurRadius: _hover ? 36 : 18,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

// --------------------------------------------------------------- background

/// Slow-moving colour fields and a faint grid behind the hero.
class AuroraBackground extends StatelessWidget {
  final Animation<double> t;
  const AuroraBackground({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _AuroraPainter(t), size: Size.infinite),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final Animation<double> t;
  _AuroraPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final a = t.value * 2 * math.pi;
    void blob(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    final w = size.width, h = size.height;
    blob(Offset(w * (0.78 + 0.05 * math.sin(a)), h * (0.18 + 0.06 * math.cos(a))),
        w * 0.42, LC.accentDeep.withValues(alpha: 0.55));
    blob(Offset(w * (0.12 + 0.05 * math.cos(a * 0.8)), h * (0.42 + 0.08 * math.sin(a * 0.8))),
        w * 0.36, LC.violet.withValues(alpha: 0.20));
    blob(Offset(w * (0.55 + 0.06 * math.sin(a * 1.3)), h * (0.92 + 0.04 * math.cos(a))),
        w * 0.30, LC.accent.withValues(alpha: 0.10));

    // Grid, fading out toward the bottom.
    const step = 56.0;
    final grid = Paint()..strokeWidth = 1;
    for (double x = 0; x < w; x += step) {
      grid.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white.withValues(alpha: 0.045), Colors.white.withValues(alpha: 0)],
      ).createShader(Rect.fromLTWH(x, 0, 1, h));
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
    }
    for (double y = 0; y < h; y += step) {
      grid.shader = null;
      grid.color = Colors.white.withValues(alpha: 0.045 * (1 - y / h).clamp(0.0, 1.0));
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter old) => false;
}
