/// Admin console design kit: colours, type, and the small set of building
/// blocks every admin page is made of (panels, KPI tiles, tables, pills,
/// buttons, slide-over sheets, charts).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/utils/server_time.dart';
import '../widgets/app_shell_common.dart' show formatCount;

// ------------------------------------------------------------------ tokens

/// Admin colours. Matches the signed-in app (UiTokens) so both feel like one
/// product, with a slightly deeper canvas for long data sessions.
class AC {
  AC._();

  static const Color bg = Color(0xFF121315);
  static const Color sidebar = Color(0xFF17181B);
  static const Color surface = Color(0xFF1C1D21);
  static const Color raised = Color(0xFF25272C);
  static const Color hover = Color(0xFF22242A);
  static const Color border = Color(0xFF2C2E34);
  static const Color borderStrong = Color(0xFF3A3D45);

  static const Color text = Color(0xFFE6E8EB);
  static const Color textDim = Color(0xFFA9B4C2);
  static const Color textMute = Color(0xFF7D8795);

  static const Color accent = Color(0xFF6CC4D6);
  static const Color primary = Color(0xFF2C5F6D);
  static const Color primaryHover = Color(0xFF347381);
  static const Color selected = Color(0xFF1B3038);

  static const Color green = Color(0xFF4BCE97);
  static const Color red = Color(0xFFF87168);
  static const Color amber = Color(0xFFF5B544);
  static const Color yellow = Color(0xFFEED12B);
  static const Color blue = Color(0xFF669DF1);
  static const Color purple = Color(0xFFC97CF4);
  static const Color grey = Color(0xFFA0A6AD);

  /// Series colours for charts, in order.
  static const List<Color> series = [accent, purple, amber, green, blue, red];
}

/// Admin text styles.
class AT {
  AT._();

  static const List<FontFeature> _tab = [FontFeature.tabularFigures()];

  static const TextStyle h1 = TextStyle(
      color: AC.text, fontSize: 20, fontWeight: FontWeight.w700, height: 1.25);
  static const TextStyle h2 = TextStyle(
      color: AC.text, fontSize: 15, fontWeight: FontWeight.w600, height: 1.3);
  static const TextStyle body =
      TextStyle(color: AC.text, fontSize: 13, height: 1.4);
  static const TextStyle bodyDim =
      TextStyle(color: AC.textDim, fontSize: 13, height: 1.4);
  static const TextStyle small =
      TextStyle(color: AC.textDim, fontSize: 12, height: 1.35);
  static const TextStyle mute =
      TextStyle(color: AC.textMute, fontSize: 12, height: 1.35);
  static const TextStyle label = TextStyle(
      color: AC.textMute,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      height: 1.2);
  static const TextStyle num = TextStyle(
      color: AC.text, fontSize: 13, height: 1.4, fontFeatures: _tab);
  static const TextStyle big = TextStyle(
      color: AC.text,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      height: 1.1,
      fontFeatures: _tab);
  static const TextStyle mono = TextStyle(
      color: AC.textDim, fontSize: 12, fontFamily: 'monospace', height: 1.4);
}

// --------------------------------------------------------------- formatting

String fmtInt(Object? v) {
  if (v == null) return '–';
  final n = v is num ? v : num.tryParse('$v');
  return n == null ? '$v' : formatCount(n);
}

String fmtMoney(Object? cents, {String symbol = r'$'}) {
  final n = cents is num ? cents : num.tryParse('${cents ?? ''}');
  if (n == null) return '–';
  final v = n / 100.0;
  final whole = v.truncate();
  final frac = ((v - whole).abs() * 100).round().toString().padLeft(2, '0');
  return '$symbol${formatCount(whole)}.$frac';
}

String _two(int n) => n.toString().padLeft(2, '0');

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// "26 Nov 2026, 14:05" in the viewer's local time; "–" when missing.
String fmtDateTime(Object? serverValue) {
  final d = parseServerTimeLocal(serverValue);
  if (d == null) return '–';
  return '${d.day} ${_months[d.month - 1]} ${d.year}, ${_two(d.hour)}:${_two(d.minute)}';
}

/// "26 Nov" (or "26 Nov 2025" for another year).
String fmtDate(Object? serverValue) {
  final d = parseServerTimeLocal(serverValue);
  if (d == null) return '–';
  final now = DateTime.now();
  return d.year == now.year
      ? '${d.day} ${_months[d.month - 1]}'
      : '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// "just now", "5m ago", "3h ago", "2d ago", then a date.
String timeAgo(Object? serverValue) {
  final d = parseServerTimeLocal(serverValue);
  if (d == null) return '–';
  final diff = DateTime.now().difference(d);
  if (diff.isNegative || diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 14) return '${diff.inDays}d ago';
  return fmtDate(serverValue);
}

String fmtDuration(Object? seconds) {
  final s = seconds is num ? seconds.toInt() : int.tryParse('${seconds ?? ''}');
  if (s == null) return '–';
  if (s < 60) return '${s}s';
  if (s < 3600) return '${s ~/ 60}m ${s % 60}s';
  return '${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
}

/// Regional-indicator flag for a 2-letter country code ("PK" → 🇵🇰).
String flagEmoji(Object? code) {
  final c = '${code ?? ''}'.trim().toUpperCase();
  if (c.length != 2 || !RegExp(r'^[A-Z]{2}$').hasMatch(c)) return '';
  return String.fromCharCodes(c.codeUnits.map((u) => 0x1F1E6 + (u - 65)));
}

String cleanError(Object e) => e
    .toString()
    .replaceFirst(RegExp(r'^(Exception|ApiException|NetworkException):\s*'), '');

/// Stable colour for a name (avatars, source chips).
Color colorFor(String seed) {
  const palette = [AC.accent, AC.purple, AC.amber, AC.green, AC.blue, AC.red];
  var h = 0;
  for (final u in seed.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

// ------------------------------------------------------------------ basics

class APanel extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const APanel({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || trailing != null;
    return Container(
      decoration: BoxDecoration(
        color: AC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AC.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null) Text(title!, style: AT.h2),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(subtitle!, style: AT.mute),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class APill extends StatelessWidget {
  final String label;
  final Color color;
  final bool dot;
  const APill(this.label, this.color, {super.key, this.dot = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Colour + label for the statuses used across admin (users, searches,
/// payments, audit).
APill statusPill(Object? raw) {
  final s = '${raw ?? ''}'.trim().toLowerCase();
  Color c;
  switch (s) {
    case 'approved':
    case 'active':
    case 'completed':
    case 'success':
    case 'ok':
    case 'paid':
      c = AC.green;
    case 'pending':
    case 'trialing':
    case 'degraded':
    case 'partial':
      c = AC.amber;
    case 'running':
    case 'processing':
      c = AC.blue;
    case 'failed':
    case 'failure':
    case 'denied':
    case 'error':
    case 'down':
      c = AC.red;
    case 'suspended':
      c = AC.amber;
    default:
      c = AC.grey;
  }
  final label = s.isEmpty ? 'Unknown' : '${s[0].toUpperCase()}${s.substring(1)}';
  return APill(label, c, dot: true);
}

enum AButtonKind { primary, secondary, ghost, danger, success }

class AButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AButtonKind kind;
  final bool busy;
  final bool expand;

  const AButton(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.kind = AButtonKind.secondary,
    this.busy = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    Color? side;
    switch (kind) {
      case AButtonKind.primary:
        bg = AC.primary;
        fg = Colors.white;
      case AButtonKind.success:
        bg = const Color(0xFF1F7A56);
        fg = Colors.white;
      case AButtonKind.danger:
        bg = AC.red.withValues(alpha: 0.14);
        fg = AC.red;
        side = AC.red.withValues(alpha: 0.35);
      case AButtonKind.ghost:
        bg = Colors.transparent;
        fg = AC.textDim;
      case AButtonKind.secondary:
        bg = AC.raised;
        fg = AC.text;
        side = AC.borderStrong;
    }
    final enabled = onPressed != null && !busy;
    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: fg),
          )
        else if (icon != null)
          Icon(icon, size: 16, color: fg),
        if (busy || icon != null) const SizedBox(width: 7),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: fg, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: enabled || busy ? 1 : 0.45,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: side == null ? BorderSide.none : BorderSide(color: side),
        ),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.05),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class AIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  const AIconButton(this.icon, this.tooltip,
      {super.key, this.onPressed, this.color});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white.withValues(alpha: 0.06),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon,
                size: 18,
                color: onPressed == null
                    ? AC.textMute.withValues(alpha: 0.5)
                    : (color ?? AC.textDim)),
          ),
        ),
      ),
    );
  }
}

class AAvatar extends StatelessWidget {
  final String name;
  final double size;
  const AAvatar(this.name, {super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final n = name.trim();
    final c = colorFor(n.isEmpty ? '?' : n);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Text(
        n.isEmpty ? '?' : n[0].toUpperCase(),
        style: TextStyle(
            color: c, fontSize: size * 0.42, fontWeight: FontWeight.w700),
      ),
    );
  }
}

InputDecoration aInput({String? hint, String? label, IconData? icon}) {
  OutlineInputBorder b(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c),
      );
  return InputDecoration(
    hintText: hint,
    labelText: label,
    isDense: true,
    filled: true,
    fillColor: AC.bg,
    hintStyle: const TextStyle(color: AC.textMute, fontSize: 13),
    labelStyle: const TextStyle(color: AC.textDim, fontSize: 13),
    floatingLabelStyle: const TextStyle(color: AC.accent, fontSize: 13),
    prefixIcon: icon == null ? null : Icon(icon, size: 17, color: AC.textMute),
    prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 36),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: b(AC.borderStrong),
    enabledBorder: b(AC.borderStrong),
    focusedBorder: b(AC.accent),
  );
}

class ASearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  const ASearchField({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: AT.body,
      cursorColor: AC.accent,
      decoration: aInput(hint: hint, icon: Icons.search),
    );
  }
}

/// Compact segmented control (range switches, status filters).
class ASegmented<T> extends StatelessWidget {
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Map<T, int>? counts;
  const ASegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.counts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AC.bg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AC.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in options.entries)
              _seg(e.key, e.value, e.key == value),
          ],
        ),
      ),
    );
  }

  Widget _seg(T key, String label, bool on) {
    final count = counts?[key];
    return Material(
      key: ValueKey('seg-$key'),
      color: on ? AC.raised : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: on ? null : () => onChanged(key),
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: on ? AC.text : AC.textDim,
                  fontSize: 12.5,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text('$count',
                    style: TextStyle(
                        color: on ? AC.accent : AC.textMute,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact dropdown used in filter bars. A null [value] shows [hint].
class ADropdown<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  final double width;
  const ADropdown({
    super.key,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
    this.width = 170,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 38,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: AC.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AC.borderStrong),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: items.containsKey(value) ? value : null,
          isExpanded: true,
          dropdownColor: AC.raised,
          borderRadius: BorderRadius.circular(8),
          icon: const Icon(Icons.expand_more, size: 18, color: AC.textMute),
          style: AT.body,
          hint: Text(hint,
              style: const TextStyle(color: AC.textDim, fontSize: 13),
              overflow: TextOverflow.ellipsis),
          items: [
            DropdownMenuItem<T?>(
                value: null,
                child: Text(hint,
                    style: const TextStyle(color: AC.textDim, fontSize: 13),
                    overflow: TextOverflow.ellipsis)),
            for (final e in items.entries)
              DropdownMenuItem<T?>(
                  value: e.key,
                  child: Text(e.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- KPI

class AKpi extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? hint;
  final String? tooltip;
  final VoidCallback? onTap;
  final List<double>? spark;

  const AKpi({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color = AC.accent,
    this.hint,
    this.tooltip,
    this.onTap,
    this.spark,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: AC.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AC.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AT.small.copyWith(fontWeight: FontWeight.w500)),
              ),
              if (onTap != null)
                const Icon(Icons.arrow_outward, size: 13, color: AC.textMute),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: AT.big),
                ),
              ),
              if (spark != null && spark!.length > 1)
                SizedBox(
                  width: 64,
                  height: 26,
                  child: CustomPaint(painter: _SparkPainter(spark!, color)),
                ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: AT.mute),
          ],
        ],
      ),
    );
    Widget out = onTap == null
        ? body
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(onTap: onTap, child: body),
          );
    if (tooltip != null && tooltip!.isNotEmpty) {
      out = Tooltip(
          message: tooltip!,
          waitDuration: const Duration(milliseconds: 500),
          child: out);
    }
    return out;
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> v;
  final Color color;
  _SparkPainter(this.v, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = v.reduce(math.max);
    final minV = v.reduce(math.min);
    final span = (maxV - minV) == 0 ? 1.0 : (maxV - minV);
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / (v.length - 1);
      final y = size.height - 2 - (size.height - 4) * ((v[i] - minV) / span);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.v != v || old.color != color;
}

/// Lays children out in equal columns that wrap by available width.
class AGrid extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  final double gap;
  const AGrid({
    super.key,
    required this.children,
    this.minTileWidth = 200,
    this.gap = 12,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols =
          math.max(1, ((c.maxWidth + gap) / (minTileWidth + gap)).floor());
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

/// Two columns on wide screens, stacked on narrow ones.
class ASplit extends StatelessWidget {
  final Widget left;
  final Widget right;
  final int leftFlex;
  final int rightFlex;
  final double breakpoint;
  const ASplit({
    super.key,
    required this.left,
    required this.right,
    this.leftFlex = 3,
    this.rightFlex = 2,
    this.breakpoint = 900,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < breakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: 12), right],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: leftFlex, child: left),
          const SizedBox(width: 12),
          Expanded(flex: rightFlex, child: right),
        ],
      );
    });
  }
}

// ------------------------------------------------------------------- states

class AEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const AEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: AC.textMute),
          const SizedBox(height: 10),
          Text(title, style: AT.h2, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child:
                  Text(message!, style: AT.mute, textAlign: TextAlign.center),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}

class AErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const AErrorBox(this.message, {super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AC.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AC.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AC.red),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AT.body)),
          if (onRetry != null) ...[
            const SizedBox(width: 10),
            AButton('Retry', icon: Icons.refresh, onPressed: onRetry),
          ],
        ],
      ),
    );
  }
}

class ALoading extends StatelessWidget {
  final double height;
  const ALoading({super.key, this.height = 160});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: AC.accent),
        ),
      ),
    );
  }
}

void aToast(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    width: math.min(520, MediaQuery.of(context).size.width - 32),
    backgroundColor: AC.raised,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
          color: (error ? AC.red : AC.green).withValues(alpha: 0.5)),
    ),
    content: Row(
      children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline,
            size: 18, color: error ? AC.red : AC.green),
        const SizedBox(width: 10),
        Expanded(child: Text(message, style: AT.body)),
      ],
    ),
  ));
}

// -------------------------------------------------------------------- table

class ACol<T> {
  final String label;
  final int flex;
  final double? width;
  final bool numeric;
  final Widget Function(T row) cell;
  const ACol(
    this.label,
    this.cell, {
    this.flex = 1,
    this.width,
    this.numeric = false,
  });
}

/// Dense data table. Scrolls sideways below [minWidth] instead of squeezing.
class ATable<T> extends StatelessWidget {
  final List<ACol<T>> columns;
  final List<T> rows;
  final void Function(T row)? onRowTap;
  final double minWidth;
  final bool Function(T row)? isSelected;
  final void Function(T row, bool value)? onSelect;
  final bool Function(T row)? selectable;
  final Widget? empty;

  const ATable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.minWidth = 760,
    this.isSelected,
    this.onSelect,
    this.selectable,
    this.empty,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty && empty != null) return empty!;
    return LayoutBuilder(builder: (context, c) {
      final w = math.max(c.maxWidth, minWidth);
      final table = SizedBox(
        width: w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            for (var i = 0; i < rows.length; i++) _row(rows[i], i),
          ],
        ),
      );
      if (w <= c.maxWidth) return table;
      return SingleChildScrollView(
          scrollDirection: Axis.horizontal, child: table);
    });
  }

  Widget _cellBox(ACol<T> col, Widget child) {
    final aligned = Align(
      alignment: col.numeric ? Alignment.centerRight : Alignment.centerLeft,
      child: child,
    );
    final padded = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10), child: aligned);
    return col.width != null
        ? SizedBox(width: col.width, child: padded)
        : Expanded(flex: col.flex, child: padded);
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
      decoration: const BoxDecoration(
        color: AC.bg,
        border: Border(bottom: BorderSide(color: AC.border)),
      ),
      child: Row(
        children: [
          if (onSelect != null) const SizedBox(width: 40),
          for (final col in columns)
            _cellBox(col, Text(col.label.toUpperCase(), style: AT.label)),
        ],
      ),
    );
  }

  Widget _row(T row, int index) {
    final selected = isSelected?.call(row) ?? false;
    final canSelect = selectable?.call(row) ?? true;
    return Material(
      color: selected ? AC.selected : Colors.transparent,
      child: InkWell(
        onTap: onRowTap == null ? null : () => onRowTap!(row),
        hoverColor: AC.hover,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            border: index == rows.length - 1
                ? null
                : const Border(bottom: BorderSide(color: AC.border)),
          ),
          child: Row(
            children: [
              if (onSelect != null)
                SizedBox(
                  width: 40,
                  child: canSelect
                      ? Checkbox(
                          value: selected,
                          onChanged: (v) => onSelect!(row, v ?? false),
                          activeColor: AC.accent,
                          checkColor: AC.bg,
                          side: const BorderSide(color: AC.borderStrong),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        )
                      : null,
                ),
              for (final col in columns)
                _cellBox(
                  col,
                  DefaultTextStyle.merge(
                    style: col.numeric ? AT.num : AT.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: col.cell(row),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class APager extends StatelessWidget {
  final int offset;
  final int limit;
  final int total;
  final ValueChanged<int> onOffset;
  const APager({
    super.key,
    required this.offset,
    required this.limit,
    required this.total,
    required this.onOffset,
  });

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox.shrink();
    final from = offset + 1;
    final to = math.min(offset + limit, total);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text('$from–$to of ${fmtInt(total)}', style: AT.mute),
          const Spacer(),
          AIconButton(Icons.chevron_left, 'Previous page',
              onPressed: offset > 0
                  ? () => onOffset(math.max(0, offset - limit))
                  : null),
          AIconButton(Icons.chevron_right, 'Next page',
              onPressed:
                  offset + limit < total ? () => onOffset(offset + limit) : null),
        ],
      ),
    );
  }
}

/// A two-line cell: primary text over a muted secondary line.
class ATwoLine extends StatelessWidget {
  final String primary;
  final String? secondary;
  final Widget? leading;
  const ATwoLine(this.primary, {super.key, this.secondary, this.leading});

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(primary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AT.body.copyWith(fontWeight: FontWeight.w600)),
        if (secondary != null && secondary!.isNotEmpty)
          Text(secondary!,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: AT.mute),
      ],
    );
    if (leading == null) return text;
    return Row(
      children: [leading!, const SizedBox(width: 10), Expanded(child: text)],
    );
  }
}

// ------------------------------------------------------------ detail fields

/// Label/value row for record ("form view") panels. Long-press or click the
/// copy icon to copy the value.
class AField extends StatelessWidget {
  final String label;
  final String? value;
  final Widget? child;
  final bool copyable;
  final bool mono;
  const AField(
    this.label, {
    super.key,
    this.value,
    this.child,
    this.copyable = false,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final v = (value ?? '').trim();
    final missing = child == null && v.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 132, child: Text(label, style: AT.mute)),
          Expanded(
            child: child ??
                SelectableText(
                  missing ? '–' : v,
                  style: missing
                      ? AT.mute
                      : (mono ? AT.mono.copyWith(color: AC.text) : AT.body),
                ),
          ),
          if (copyable && !missing)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: v));
                aToast(context, 'Copied');
              },
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.copy_rounded, size: 14, color: AC.textMute),
              ),
            ),
        ],
      ),
    );
  }
}

class ASectionLabel extends StatelessWidget {
  final String text;
  const ASectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(text.toUpperCase(), style: AT.label),
      );
}

// ------------------------------------------------------------- sheets/dialog

/// Record detail: slides in from the right on wide screens, rises from the
/// bottom on phones.
Future<T?> showASheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = 560,
}) {
  final screen = MediaQuery.of(context).size;
  if (screen.width < 760) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.92,
        decoration: const BoxDecoration(
          color: AC.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        clipBehavior: Clip.antiAlias,
        child: builder(ctx),
      ),
    );
  }
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black.withValues(alpha: 0.5),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: AC.surface,
        child: Container(
          width: math.min(width, screen.width - 80),
          height: double.infinity,
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AC.border)),
          ),
          child: builder(ctx),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

/// Standard sheet frame: title bar, scrolling body, optional footer.
class ASheetFrame extends StatelessWidget {
  final Widget title;
  final Widget body;
  final Widget? footer;
  final bool scroll;
  const ASheetFrame({
    super.key,
    required this.title,
    required this.body,
    this.footer,
    this.scroll = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AC.border)),
          ),
          child: Row(
            children: [
              Expanded(child: title),
              AIconButton(Icons.close, 'Close',
                  onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
        Expanded(
          child: scroll
              ? SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                  child: body,
                )
              : body,
        ),
        if (footer != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AC.border)),
            ),
            child: footer,
          ),
      ],
    );
  }
}

/// Centered form dialog in the admin style.
Future<T?> showADialog<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget Function(BuildContext ctx) builder,
  double width = 460,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: AC.surface,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AC.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: AT.h1.copyWith(fontSize: 17)),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle, style: AT.small),
              ],
              const SizedBox(height: 16),
              builder(ctx),
            ],
          ),
        ),
      ),
    ),
  );
}

class AConfirmResult {
  final String note;
  const AConfirmResult(this.note);
}

/// Confirmation with an optional note field. Returns null when cancelled.
Future<AConfirmResult?> aConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool danger = false,
  String? noteHint,
}) async {
  final note = TextEditingController();
  final ok = await showADialog<bool>(
    context,
    title: title,
    subtitle: message,
    builder: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (noteHint != null) ...[
          TextField(
            controller: note,
            style: AT.body,
            cursorColor: AC.accent,
            maxLines: 2,
            decoration: aInput(hint: noteHint),
          ),
          const SizedBox(height: 16),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AButton('Cancel',
                kind: AButtonKind.ghost,
                onPressed: () => Navigator.pop(ctx, false)),
            const SizedBox(width: 8),
            AButton(confirmLabel,
                kind: danger ? AButtonKind.danger : AButtonKind.primary,
                onPressed: () => Navigator.pop(ctx, true)),
          ],
        ),
      ],
    ),
  );
  final text = note.text.trim();
  note.dispose();
  return ok == true ? AConfirmResult(text) : null;
}

// ------------------------------------------------------------------- charts

class ABarItem {
  final String label;
  final num value;
  final String? leading;
  const ABarItem(this.label, this.value, {this.leading});
}

/// Ranked list with proportional bars (top sources, countries, pages).
class ABarList extends StatelessWidget {
  final List<ABarItem> items;
  final Color color;
  final String emptyText;
  const ABarList({
    super.key,
    required this.items,
    this.color = AC.accent,
    this.emptyText = 'No data in this range yet',
  });

  static List<ABarItem> fromRows(Object? rows,
      {String labelKey = 'label',
      String valueKey = 'count',
      String Function(String label)? leading}) {
    final out = <ABarItem>[];
    if (rows is! List) return out;
    for (final r in rows) {
      if (r is! Map) continue;
      final label = '${r[labelKey] ?? ''}'.trim();
      final v = r[valueKey];
      out.add(ABarItem(
        label.isEmpty ? 'Unknown' : label,
        v is num ? v : (num.tryParse('$v') ?? 0),
        leading: leading?.call(label),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(emptyText, style: AT.mute),
      );
    }
    final maxV = items.map((e) => e.value).reduce(math.max);
    final total = items.fold<num>(0, (a, e) => a + e.value);
    return Column(
      children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              children: [
                Row(
                  children: [
                    if (it.leading != null && it.leading!.isNotEmpty) ...[
                      Text(it.leading!, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: Text(it.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AT.body),
                    ),
                    Text(fmtInt(it.value), style: AT.num),
                    SizedBox(
                      width: 44,
                      child: Text(
                        total > 0
                            ? '${(it.value * 100 / total).round()}%'
                            : '',
                        textAlign: TextAlign.right,
                        style: AT.mute,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: maxV > 0 ? (it.value / maxV).toDouble() : 0,
                    minHeight: 4,
                    backgroundColor: AC.bg,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ASeries {
  final String name;
  final Color color;
  final List<double> values;
  const ASeries(this.name, this.color, this.values);
}

/// Multi-series line/area chart with a hover read-out.
class ALineChart extends StatefulWidget {
  final List<String> labels;
  final List<ASeries> series;
  final double height;
  final String Function(double v)? format;
  const ALineChart({
    super.key,
    required this.labels,
    required this.series,
    this.height = 200,
    this.format,
  });

  @override
  State<ALineChart> createState() => _ALineChartState();
}

class _ALineChartState extends State<ALineChart> {
  int? _hover;

  String _fmt(double v) =>
      widget.format?.call(v) ?? fmtInt(v == v.roundToDouble() ? v.round() : v);

  @override
  Widget build(BuildContext context) {
    final n = widget.labels.length;
    final hasData =
        n > 0 && widget.series.any((s) => s.values.any((v) => v > 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final s in widget.series)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: s.color,
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 6),
                  Text(
                    _hover != null && _hover! < s.values.length
                        ? '${s.name}: ${_fmt(s.values[_hover!])}'
                        : s.name,
                    style: AT.small,
                  ),
                ],
              ),
            if (_hover != null && _hover! < n)
              Text(widget.labels[_hover!], style: AT.mute),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: widget.height,
          child: !hasData
              ? const Center(
                  child: Text('No data in this range yet', style: AT.mute))
              : LayoutBuilder(builder: (context, c) {
                  return MouseRegion(
                    onExit: (_) => setState(() => _hover = null),
                    onHover: (e) => _setHover(e.localPosition.dx, c.maxWidth),
                    child: GestureDetector(
                      onPanUpdate: (d) =>
                          _setHover(d.localPosition.dx, c.maxWidth),
                      onTapDown: (d) =>
                          _setHover(d.localPosition.dx, c.maxWidth),
                      child: CustomPaint(
                        size: Size(c.maxWidth, widget.height),
                        painter: _LinePainter(
                            widget.series, widget.labels, _hover, _fmt),
                      ),
                    ),
                  );
                }),
        ),
      ],
    );
  }

  void _setHover(double dx, double width) {
    final n = widget.labels.length;
    if (n == 0) return;
    const left = _LinePainter.leftPad;
    final w = width - left - _LinePainter.rightPad;
    final t = ((dx - left) / (w <= 0 ? 1 : w)).clamp(0.0, 1.0);
    final i = n == 1 ? 0 : (t * (n - 1)).round();
    if (i != _hover) setState(() => _hover = i);
  }
}

class _LinePainter extends CustomPainter {
  static const double leftPad = 38;
  static const double rightPad = 8;
  static const double bottomPad = 20;
  static const double topPad = 6;

  final List<ASeries> series;
  final List<String> labels;
  final int? hover;
  final String Function(double) fmt;
  _LinePainter(this.series, this.labels, this.hover, this.fmt);

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    final w = size.width - leftPad - rightPad;
    final h = size.height - bottomPad - topPad;
    var maxV = 0.0;
    for (final s in series) {
      for (final v in s.values) {
        if (v > maxV) maxV = v;
      }
    }
    maxV = _niceMax(maxV);

    double x(int i) => leftPad + (n == 1 ? w / 2 : w * i / (n - 1));
    double y(double v) => topPad + h * (1 - (maxV == 0 ? 0 : v / maxV));

    final grid = Paint()
      ..color = AC.border
      ..strokeWidth = 1;
    const ticks = 4;
    for (var i = 0; i <= ticks; i++) {
      final gy = topPad + h * i / ticks;
      canvas.drawLine(Offset(leftPad, gy), Offset(size.width - rightPad, gy), grid);
      _text(canvas, fmt(maxV * (ticks - i) / ticks), Offset(leftPad - 6, gy),
          alignRight: true, centerY: true);
    }

    // X labels: first, middle, last (more would collide on small widths).
    final marks = <int>{0, if (n > 2) n ~/ 2, n - 1};
    for (final i in marks) {
      final lx = x(i);
      _text(canvas, _short(labels[i]), Offset(lx, size.height - 14),
          center: i != 0 && i != n - 1,
          alignRight: i == n - 1 && n > 1);
    }

    for (var si = 0; si < series.length; si++) {
      final s = series[si];
      if (s.values.isEmpty) continue;
      final path = Path();
      final count = math.min(n, s.values.length);
      for (var i = 0; i < count; i++) {
        final p = Offset(x(i), y(s.values[i]));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      if (si == 0 && count > 1) {
        final fill = Path.from(path)
          ..lineTo(x(count - 1), topPad + h)
          ..lineTo(x(0), topPad + h)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                s.color.withValues(alpha: 0.22),
                s.color.withValues(alpha: 0.0)
              ],
            ).createShader(Rect.fromLTWH(leftPad, topPad, w, h)),
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = s.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      if (count == 1) {
        canvas.drawCircle(Offset(x(0), y(s.values[0])), 3.5, Paint()..color = s.color);
      }
    }

    if (hover != null && hover! < n) {
      final hx = x(hover!);
      canvas.drawLine(Offset(hx, topPad), Offset(hx, topPad + h),
          Paint()..color = AC.borderStrong..strokeWidth = 1);
      for (final s in series) {
        if (hover! >= s.values.length) continue;
        final p = Offset(hx, y(s.values[hover!]));
        canvas.drawCircle(p, 4.5, Paint()..color = AC.surface);
        canvas.drawCircle(p, 3, Paint()..color = s.color);
      }
    }
  }

  /// Smallest axis top >= v that splits into 4 whole-number steps.
  static double _niceMax(double v) {
    if (v <= 4) return 4;
    final raw = v / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in [1, 2, 3, 5, 10]) {
      if (raw <= m * mag) return m * mag * 4;
    }
    return 10 * mag * 4;
  }

  /// "2026-11-26" → "26 Nov"; anything else unchanged.
  static String _short(String label) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(label);
    if (m == null) return label;
    final month = int.parse(m.group(2)!);
    return '${int.parse(m.group(3)!)} ${_months[month - 1]}';
  }

  void _text(Canvas canvas, String s, Offset at,
      {bool alignRight = false, bool center = false, bool centerY = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s, style: const TextStyle(color: AC.textMute, fontSize: 10.5)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (alignRight) dx -= tp.width;
    if (center) dx -= tp.width / 2;
    final dy = centerY ? at.dy - tp.height / 2 : at.dy;
    tp.paint(canvas, Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) =>
      old.series != series || old.hover != hover || old.labels != labels;
}
