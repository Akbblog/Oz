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

// --------------------------------------------------------------------- hero

class _SampleLead {
  final String name;
  final String kind;
  final Color color;
  const _SampleLead(this.name, this.kind, this.color);
}

const _leads = [
  _SampleLead('Bright Smile Dental', 'Dentist', LC.accent),
  _SampleLead('Harbor Coffee Roasters', 'Café', LC.warm),
  _SampleLead('Northside Auto Care', 'Car repair', LC.violet),
  _SampleLead('Luma Yoga Studio', 'Fitness', LC.green),
  _SampleLead('Greenleaf Landscaping', 'Landscaper', LC.accent),
];

/// The hero illustration: a search running. Pins appear on a dotted map,
/// result rows arrive one by one, a counter climbs, then it starts over.
/// Everything shown is made-up sample data and is labelled as such.
class HeroVisual extends StatelessWidget {
  final Animation<double> t; // 0..1, repeating
  const HeroVisual({super.key, required this.t});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.06,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final s = (w / 520).clamp(0.62, 1.15);
        return AnimatedBuilder(
          animation: t,
          builder: (context, _) {
            final v = t.value;
            final bob = math.sin(v * 2 * math.pi);
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _MapPainter(v)),
                ),
                // Results window
                Positioned(
                  left: w * 0.07,
                  right: w * 0.05,
                  top: w * 0.13 + bob * 3,
                  child: _ResultsWindow(v: v, scale: s),
                ),
                // Floating chips
                Positioned(
                  right: -w * 0.02,
                  top: w * 0.02 - bob * 5,
                  child: _Chip(
                    scale: s,
                    icon: Icons.bolt_rounded,
                    color: LC.warm,
                    label: 'Search running',
                    value: '${(v * 100).clamp(0, 99).floor()}%',
                  ),
                ),
                Positioned(
                  left: -w * 0.03,
                  bottom: w * 0.10 + bob * 6,
                  child: _Chip(
                    scale: s,
                    icon: Icons.table_view_rounded,
                    color: LC.green,
                    label: 'Ready to export',
                    value: 'Excel · CSV',
                  ),
                ),
              ],
            );
          },
        );
      }),
    );
  }
}

class _Chip extends StatelessWidget {
  final double scale;
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _Chip(
      {required this.scale,
      required this.icon,
      required this.color,
      required this.label,
      required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
      decoration: BoxDecoration(
        color: const Color(0xF2161B21),
        borderRadius: BorderRadius.circular(14 * scale),
        border: Border.all(color: LC.borderHi),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 30,
              offset: const Offset(0, 14)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30 * scale,
            height: 30 * scale,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(9 * scale),
            ),
            child: Icon(icon, size: 17 * scale, color: color),
          ),
          SizedBox(width: 10 * scale),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: TextStyle(
                      fontFamily: LT.font, color: LC.mute, fontSize: 11 * scale)),
              Text(value,
                  style: TextStyle(
                      fontFamily: LT.font,
                      color: LC.text,
                      fontSize: 13.5 * scale,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultsWindow extends StatelessWidget {
  final double v;
  final double scale;
  const _ResultsWindow({required this.v, required this.scale});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    // Rows arrive during the first 70% of the loop, then hold, then fade.
    final fadeOut = v > 0.93 ? (1 - (v - 0.93) / 0.07) : 1.0;
    final found = (v.clamp(0.0, 0.8) / 0.8 * 128).round();
    return Opacity(
      opacity: fadeOut.clamp(0.0, 1.0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xF0131820),
          borderRadius: BorderRadius.circular(20 * s),
          border: Border.all(color: LC.borderHi),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 60,
                offset: const Offset(0, 30)),
            BoxShadow(
                color: LC.accent.withValues(alpha: 0.10),
                blurRadius: 80,
                spreadRadius: -10),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(18 * s, 16 * s, 18 * s, 12 * s),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 6 * s),
                    decoration: BoxDecoration(
                      color: LC.bg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: LC.border),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.search_rounded, size: 14 * s, color: LC.accent),
                      SizedBox(width: 6 * s),
                      Text('Local businesses · 3 cities',
                          style: TextStyle(
                              fontFamily: LT.font,
                              color: LC.dim,
                              fontSize: 12 * s,
                              fontWeight: FontWeight.w500)),
                    ]),
                  ),
                  const Spacer(),
                  Text('$found',
                      style: TextStyle(
                          fontFamily: LT.font,
                          color: LC.text,
                          fontSize: 20 * s,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  SizedBox(width: 5 * s),
                  Text('leads',
                      style: TextStyle(
                          fontFamily: LT.font, color: LC.mute, fontSize: 12 * s)),
                ],
              ),
            ),
            // Progress
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 18 * s),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(children: [
                  Container(height: 3, color: LC.border),
                  FractionallySizedBox(
                    widthFactor: (v / 0.8).clamp(0.0, 1.0),
                    child: Container(
                      height: 3,
                      decoration: const BoxDecoration(gradient: LC.brand),
                    ),
                  ),
                ]),
              ),
            ),
            SizedBox(height: 8 * s),
            for (var i = 0; i < _leads.length; i++)
              _row(_leads[i], ((v - 0.06 - i * 0.13) / 0.10).clamp(0.0, 1.0), s),
            Padding(
              padding: EdgeInsets.fromLTRB(18 * s, 8 * s, 18 * s, 14 * s),
              child: Text('Sample results for illustration',
                  style: TextStyle(
                      fontFamily: LT.font, color: LC.mute, fontSize: 10.5 * s)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(_SampleLead lead, double p, double s) {
    final e = Curves.easeOutCubic.transform(p);
    Widget dot(IconData icon, bool on) => Container(
          width: 24 * s,
          height: 24 * s,
          margin: EdgeInsets.only(left: 6 * s),
          decoration: BoxDecoration(
            color: on ? LC.green.withValues(alpha: 0.14) : LC.bg,
            borderRadius: BorderRadius.circular(7 * s),
            border: Border.all(color: on ? Colors.transparent : LC.border),
          ),
          child: Icon(icon, size: 13 * s, color: on ? LC.green : LC.mute),
        );
    return Opacity(
      opacity: e,
      child: Transform.translate(
        offset: Offset(0, (1 - e) * 14),
        child: Container(
          margin: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 3 * s),
          padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 9 * s),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.025),
            borderRadius: BorderRadius.circular(12 * s),
          ),
          child: Row(
            children: [
              Container(
                width: 32 * s,
                height: 32 * s,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: lead.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9 * s),
                ),
                child: Text(lead.name[0],
                    style: TextStyle(
                        fontFamily: LT.font,
                        color: lead.color,
                        fontSize: 14 * s,
                        fontWeight: FontWeight.w700)),
              ),
              SizedBox(width: 11 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(lead.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: LT.font,
                            color: LC.text,
                            fontSize: 13.5 * s,
                            fontWeight: FontWeight.w600)),
                    Text(lead.kind,
                        style: TextStyle(
                            fontFamily: LT.font, color: LC.mute, fontSize: 11.5 * s)),
                  ],
                ),
              ),
              dot(Icons.call_rounded, p > 0.35),
              dot(Icons.language_rounded, p > 0.6),
              dot(Icons.mail_rounded, p > 0.85),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dotted field with pins that ping as the "search" finds businesses.
class _MapPainter extends CustomPainter {
  final double v;
  _MapPainter(this.v);

  static final List<Offset> _pins = [
    const Offset(0.16, 0.20), const Offset(0.86, 0.34), const Offset(0.30, 0.86),
    const Offset(0.74, 0.90), const Offset(0.94, 0.66), const Offset(0.06, 0.58),
    const Offset(0.52, 0.06),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint();
    const n = 22;
    final step = size.width / n;
    final center = Offset(size.width / 2, size.height / 2);
    final maxD = size.width * 0.62;
    for (var i = 0; i <= n; i++) {
      for (var j = 0; j <= n; j++) {
        final p = Offset(i * step, j * step * (size.height / size.width));
        final d = (p - center).distance / maxD;
        if (d > 1) continue;
        // A ring sweeping outward, like a scan.
        final ring = (1 - ((d - v * 1.25).abs() * 7)).clamp(0.0, 1.0);
        dot.color = Color.lerp(
            Colors.white.withValues(alpha: 0.07 * (1 - d)),
            LC.accent.withValues(alpha: 0.75),
            ring * 0.8)!;
        canvas.drawCircle(p, 1.3 + ring * 1.1, dot);
      }
    }
    for (var i = 0; i < _pins.length; i++) {
      final p = Offset(_pins[i].dx * size.width, _pins[i].dy * size.height);
      final start = 0.08 + i * 0.10;
      final local = ((v - start) / 0.30).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final fade = v > 0.93 ? (1 - (v - 0.93) / 0.07).clamp(0.0, 1.0) : 1.0;
      canvas.drawCircle(
          p,
          6 + local * 22,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = LC.accent.withValues(alpha: (1 - local) * 0.6 * fade));
      canvas.drawCircle(p, 4.5, Paint()..color = LC.bg.withValues(alpha: fade));
      canvas.drawCircle(p, 3.2, Paint()..color = LC.accent.withValues(alpha: fade));
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => old.v != v;
}
