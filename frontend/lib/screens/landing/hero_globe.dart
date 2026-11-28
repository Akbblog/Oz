import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../widgets/country_flag_badge.dart';
import '../find/find_common.dart' show countryDisplayName, pluralTerm;
import 'globe_land.dart';
import 'landing_kit.dart';

/// Hero illustration: the Earth as a field of dots, slowly turning, with the
/// covered countries lit up. Leads "fly" from a country into a results card.
///
/// * Hover: the globe leans toward the pointer and the nearest country is named.
/// * Drag sideways: spin it; it keeps turning for a moment, then drifts again.
/// * Everything in the card is invented sample data and says so.
///
/// Drawn directly on a canvas with a hand-written 3D projection, so there is
/// nothing extra to download and it stays sharp at any size.
class HeroGlobe extends StatefulWidget {
  /// Covered countries (API key -> number of regions), from the live data.
  final List<MapEntry<String, int>> countries;
  const HeroGlobe({super.key, required this.countries});

  @override
  State<HeroGlobe> createState() => _HeroGlobeState();
}

// ------------------------------------------------------------------ geometry

/// Where to put each country's pin (degrees north, degrees east).
const Map<String, (double, double)> kCountryCenters = {
  'USA': (39.5, -98.5),
  'UK': (54.0, -2.5),
  'UAE': (24.2, 54.3),
  'KSA': (24.0, 45.0),
  'Australia': (-25.5, 134.0),
  'Canada': (57.0, -106.0),
  'India': (21.5, 78.5),
  'Qatar': (25.3, 51.2),
  'Indonesia': (-2.5, 117.5),
  'Malaysia': (4.2, 102.0),
  'Singapore': (1.35, 103.8),
  'China': (35.5, 103.5),
  'Finland': (64.0, 26.0),
  'Germany': (51.0, 10.3),
  'France': (46.5, 2.5),
};

/// Unit vector for a latitude/longitude. Y is up, +Z faces longitude 0.
List<double> _vec(double latDeg, double lonDeg) {
  final lat = latDeg * math.pi / 180, lon = lonDeg * math.pi / 180;
  return [math.cos(lat) * math.sin(lon), math.sin(lat), math.cos(lat) * math.cos(lon)];
}

/// Dots of the globe, computed once: evenly spread points, kept where the
/// land mask says land (plus a sparse set over the oceans for the outline).
class _GlobeDots {
  final Float32List land; // x, y, z triples
  final Float32List ocean;
  _GlobeDots(this.land, this.ocean);

  static _GlobeDots? _cached;
  static _GlobeDots get instance => _cached ??= _build();

  static _GlobeDots _build() {
    final mask = base64Decode(kLandMaskBase64);
    bool isLand(double lat, double lon) {
      final col = (((lon + math.pi) / (2 * math.pi)) * kLandMaskWidth).floor() % kLandMaskWidth;
      final row = (((math.pi / 2 - lat) / math.pi) * kLandMaskHeight)
          .floor()
          .clamp(0, kLandMaskHeight - 1);
      final k = row * kLandMaskWidth + col;
      return (mask[k >> 3] >> (k & 7)) & 1 == 1;
    }

    const n = 5400;
    final golden = math.pi * (3 - math.sqrt(5));
    final land = <double>[], ocean = <double>[];
    for (var i = 0; i < n; i++) {
      final y = 1 - 2 * (i + 0.5) / n;
      final r = math.sqrt(1 - y * y);
      final t = i * golden;
      final x = r * math.cos(t), z = r * math.sin(t);
      if (isLand(math.asin(y), math.atan2(x, z))) {
        land..add(x)..add(y)..add(z);
      } else if (i % 7 == 0) {
        ocean..add(x)..add(y)..add(z);
      }
    }
    return _GlobeDots(Float32List.fromList(land), Float32List.fromList(ocean));
  }
}

class _Pin {
  final String key;
  final String label;
  final List<double> v;
  _Pin(this.key, this.label, this.v);
}

class _Delivery {
  final int pin;
  final double start;
  final int id;
  _Delivery(this.pin, this.start, this.id);
}

class _Arc {
  final int a, b;
  final double start;
  _Arc(this.a, this.b, this.start);
}

class GlobeLead {
  final int id;
  final String name;
  final String kind;
  final String country;
  const GlobeLead(this.id, this.name, this.kind, this.country);
}

const kGlobeSamples = [
  ('Bright Smile Dental', 'Dentist'),
  ('Harbor Coffee Roasters', 'Café'),
  ('Northside Auto Care', 'Car repair'),
  ('Luma Yoga Studio', 'Fitness'),
  ('Greenleaf Landscaping', 'Landscaper'),
  ('Atlas Legal Partners', 'Law firm'),
  ('Saffron Kitchen', 'Restaurant'),
  ('BlueDoor Realty', 'Real estate'),
  ('Peak Physio Clinic', 'Physiotherapy'),
  ('Copper & Oak Barbers', 'Barber'),
  ('Sunline Solar', 'Solar installer'),
  ('Paws & Co. Vets', 'Veterinary'),
];

// --------------------------------------------------------------------- state

class _HeroGlobeState extends State<HeroGlobe> with SingleTickerProviderStateMixin {
  static const double _deliveryEvery = 1.55;
  static const double _deliveryTime = 1.25;
  static const double _arcTime = 2.2;

  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final ValueNotifier<List<GlobeLead>> _leads = ValueNotifier<List<GlobeLead>>(const []);
  final ValueNotifier<int> _count = ValueNotifier<int>(0);
  final math.Random _rnd = math.Random(7);

  List<_Pin> _pins = const [];
  final List<_Delivery> _deliveries = [];
  final List<_Arc> _arcs = [];

  double _time = 0;
  Duration _last = Duration.zero;
  double _yaw = -62 * math.pi / 180; // start facing the Middle East / South Asia
  double _spin = 0; // extra turning speed left over from a drag
  double _lean = 0, _leanTarget = 0; // pointer left/right
  double _nod = 0, _nodTarget = 0; // pointer up/down
  bool _dragging = false;
  Offset? _pointer;
  double _nextDelivery = 0.9;
  double _nextArc = 0.4;
  int _ids = 0, _sample = 0, _pinCursor = 0;

  @override
  void initState() {
    super.initState();
    _buildPins();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(covariant HeroGlobe old) {
    super.didUpdateWidget(old);
    if (old.countries != widget.countries) _buildPins();
  }

  void _buildPins() {
    final pins = <_Pin>[];
    for (final c in widget.countries) {
      final at = kCountryCenters[c.key];
      if (at == null) continue;
      pins.add(_Pin(c.key, countryDisplayName(c.key), _vec(at.$1, at.$2)));
    }
    _pins = pins;
    _deliveries.clear();
    _arcs.clear();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _leads.dispose();
    _count.dispose();
    super.dispose();
  }

  bool _onScreen() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return true;
    final top = box.localToGlobal(Offset.zero).dy;
    return top + box.size.height > 0 && top < MediaQuery.of(context).size.height;
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    // Scrolled away: stand still and stop repainting.
    if (_frame.value % 20 == 0 && !_onScreen()) {
      _frame.value += 20;
      return;
    }
    _time += dt;
    if (!_dragging) {
      _yaw -= (0.10 + _spin) * dt;
      _spin *= math.pow(0.12, dt).toDouble(); // drag momentum fades in about a second
    }
    final ease = 1 - math.pow(0.004, dt).toDouble();
    _lean += (_leanTarget - _lean) * ease;
    _nod += (_nodTarget - _nod) * ease;

    if (_pins.isNotEmpty) {
      if (_time >= _nextDelivery) {
        _nextDelivery = _time + _deliveryEvery;
        final pin = _pickFacingPin();
        if (pin != null) _deliveries.add(_Delivery(pin, _time, ++_ids));
      }
      if (_time >= _nextArc && _pins.length > 1) {
        _nextArc = _time + 1.3 + _rnd.nextDouble() * 1.2;
        final a = _rnd.nextInt(_pins.length);
        var b = _rnd.nextInt(_pins.length - 1);
        if (b >= a) b++;
        _arcs.add(_Arc(a, b, _time));
      }
    }
    _arcs.removeWhere((a) => _time - a.start > _arcTime);
    for (var i = _deliveries.length - 1; i >= 0; i--) {
      final d = _deliveries[i];
      if (_time - d.start >= _deliveryTime) {
        _deliveries.removeAt(i);
        _arrive(d);
      }
    }
    _frame.value++;
  }

  double get _tilt => 0.34 + _nod;
  double get _turn => _yaw + _lean;

  /// Depth (toward the viewer is positive) of a point after rotation.
  double _depth(List<double> v) {
    final cy = math.cos(_turn), sy = math.sin(_turn);
    final z1 = -v[0] * sy + v[2] * cy;
    return v[1] * math.sin(_tilt) + z1 * math.cos(_tilt);
  }

  int? _pickFacingPin() {
    for (var step = 0; step < _pins.length; step++) {
      final i = (_pinCursor + step) % _pins.length;
      if (_depth(_pins[i].v) > 0.30 && !_deliveries.any((d) => d.pin == i)) {
        _pinCursor = i + 1;
        return i;
      }
    }
    return null;
  }

  void _arrive(_Delivery d) {
    final s = kGlobeSamples[_sample++ % kGlobeSamples.length];
    final next = [GlobeLead(d.id, s.$1, s.$2, _pins[d.pin].key), ..._leads.value];
    _leads.value = next.length > 4 ? next.sublist(0, 4) : next;
    _count.value += 4 + _rnd.nextInt(9);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.0,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final s = (w / 540).clamp(0.6, 1.12);
        final cardW = math.min(w * 0.64, 318.0 * s);
        final cardH = 286.0 * s;
        final cardLeft = w - cardW;
        final cardTop = w - cardH - w * 0.005;
        final scene = _Scene(
          state: this,
          center: Offset(w * 0.43, w * 0.43),
          radius: w * 0.39,
          cardAnchor: Offset(cardLeft + 30 * s, cardTop + 78 * s),
          scale: s,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: MouseRegion(
                cursor: _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
                onHover: (e) {
                  _pointer = e.localPosition;
                  _leanTarget = ((e.localPosition.dx - scene.center.dx) / w).clamp(-0.5, 0.5) * 0.42;
                  _nodTarget = ((e.localPosition.dy - scene.center.dy) / w).clamp(-0.5, 0.5) * 0.26;
                },
                onExit: (_) {
                  _pointer = null;
                  _leanTarget = 0;
                  _nodTarget = 0;
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Sideways only, so a vertical swipe still scrolls the page.
                  onHorizontalDragStart: (_) => setState(() => _dragging = true),
                  onHorizontalDragUpdate: (d) => _yaw += d.delta.dx * 0.0085,
                  onHorizontalDragEnd: (d) {
                    _spin = (-d.velocity.pixelsPerSecond.dx * 0.0085).clamp(-5.0, 5.0);
                    setState(() => _dragging = false);
                  },
                  onHorizontalDragCancel: () => setState(() => _dragging = false),
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _GlobePainter(scene, _frame)),
                  ),
                ),
              ),
            ),
            Positioned(
              left: cardLeft,
              top: cardTop,
              width: cardW,
              height: cardH,
              child: GlobeLeadCard(leads: _leads, count: _count, scale: s),
            ),
            Positioned(
              left: 4 * s,
              bottom: 2 * s,
              child: IgnorePointer(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.threed_rotation_rounded, size: 14 * s, color: LC.mute),
                  SizedBox(width: 6 * s),
                  Text('Drag to spin',
                      style: TextStyle(fontFamily: LT.font, color: LC.mute, fontSize: 11.5 * s)),
                ]),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _Scene {
  final _HeroGlobeState state;
  final Offset center;
  final double radius;
  final Offset cardAnchor;
  final double scale;
  const _Scene({
    required this.state,
    required this.center,
    required this.radius,
    required this.cardAnchor,
    required this.scale,
  });
}

// ------------------------------------------------------------------- painter

class _GlobePainter extends CustomPainter {
  final _Scene scene;
  _GlobePainter(this.scene, Listenable repaint) : super(repaint: repaint);

  static const int _buckets = 6;
  static final List<Float32List> _buf = [];
  static Float32List _back = Float32List(0), _sea = Float32List(0);
  static final Map<String, TextPainter> _labels = {};

  @override
  void paint(Canvas canvas, Size size) {
    final st = scene.state;
    final dots = _GlobeDots.instance;
    final c = scene.center, r = scene.radius, k = scene.scale;
    final cy = math.cos(st._turn), sy = math.sin(st._turn);
    final ct = math.cos(st._tilt), sn = math.sin(st._tilt);

    // Rotates a unit vector; returns screen x, screen y and depth via out.
    final out = Float64List(3);
    void project(double x, double y, double z) {
      final x1 = x * cy + z * sy;
      final z1 = -x * sy + z * cy;
      final y2 = y * ct - z1 * sn;
      final z2 = y * sn + z1 * ct;
      final p = 1 + z2 * 0.10; // a touch of perspective
      out[0] = c.dx + x1 * r * p;
      out[1] = c.dy - y2 * r * p;
      out[2] = z2;
    }

    // Glow behind the globe.
    canvas.drawCircle(
      c,
      r * 1.5,
      Paint()
        ..shader = ui.Gradient.radial(c, r * 1.5, [
          LC.accent.withValues(alpha: 0.20),
          LC.accent.withValues(alpha: 0.05),
          LC.accent.withValues(alpha: 0),
        ], [
          0.55,
          0.78,
          1.0
        ]),
    );

    // Buffers sized once.
    final landCount = dots.land.length ~/ 3;
    if (_buf.isEmpty || _buf.first.length < landCount * 2) {
      _buf
        ..clear()
        ..addAll(List.generate(_buckets, (_) => Float32List(landCount * 2)));
      _back = Float32List(landCount * 2);
      _sea = Float32List((dots.ocean.length ~/ 3) * 2);
    }
    final fill = List<int>.filled(_buckets, 0);
    var backN = 0;
    final land = dots.land;
    // Light from the upper left, in front.
    const lx = -0.45, ly = 0.55, lz = 0.70;
    for (var i = 0; i < land.length; i += 3) {
      project(land[i], land[i + 1], land[i + 2]);
      final z = out[2];
      if (z < 0) {
        _back[backN++] = out[0];
        _back[backN++] = out[1];
        continue;
      }
      // Rotated normal = rotated position on a unit sphere.
      final nx = (out[0] - c.dx) / r, ny = -(out[1] - c.dy) / r;
      final lit = (nx * lx + ny * ly + z * lz).clamp(0.0, 1.0);
      final b = ((0.25 + 0.75 * z) * (0.45 + 0.55 * lit) * _buckets).floor().clamp(0, _buckets - 1);
      final list = _buf[b];
      list[fill[b]++] = out[0];
      list[fill[b]++] = out[1];
    }

    final dot = Paint()..strokeCap = StrokeCap.round;
    // Far side, seen through the globe.
    dot
      ..color = LC.accent.withValues(alpha: 0.10)
      ..strokeWidth = 1.5 * k;
    canvas.drawRawPoints(ui.PointMode.points, Float32List.sublistView(_back, 0, backN), dot);

    // The body of the globe: darker toward the lower right.
    final lightAt = c + Offset(-r * 0.38, -r * 0.42);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(lightAt, r * 1.55, [
          const Color(0xFF1A3A45).withValues(alpha: 0.78),
          const Color(0xFF0F2027).withValues(alpha: 0.86),
          const Color(0xFF080D10).withValues(alpha: 0.93),
        ], [
          0.0,
          0.55,
          1.0
        ]),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = ui.Gradient.linear(
            c + Offset(-r, -r), c + Offset(r, r), [
          LC.accent.withValues(alpha: 0.65),
          LC.accent.withValues(alpha: 0.06),
        ]),
    );

    // Sparse ocean dots give the sphere its curve.
    var seaN = 0;
    final ocean = dots.ocean;
    for (var i = 0; i < ocean.length; i += 3) {
      project(ocean[i], ocean[i + 1], ocean[i + 2]);
      if (out[2] < 0.05) continue;
      _sea[seaN++] = out[0];
      _sea[seaN++] = out[1];
    }
    dot
      ..color = Colors.white.withValues(alpha: 0.07)
      ..strokeWidth = 1.3 * k;
    canvas.drawRawPoints(ui.PointMode.points, Float32List.sublistView(_sea, 0, seaN), dot);

    // Land, from dim (edge, shadow) to bright (centre, lit).
    for (var b = 0; b < _buckets; b++) {
      final t = b / (_buckets - 1);
      dot
        ..color = Color.lerp(LC.accentDeep, const Color(0xFFBFF3FB), t)!
            .withValues(alpha: 0.38 + 0.62 * t)
        ..strokeWidth = (1.5 + 1.25 * t) * k;
      canvas.drawRawPoints(ui.PointMode.points, Float32List.sublistView(_buf[b], 0, fill[b]), dot);
    }

    // Country positions on screen.
    final pins = st._pins;
    final px = Float64List(pins.length), py = Float64List(pins.length), pz = Float64List(pins.length);
    for (var i = 0; i < pins.length; i++) {
      final v = pins[i].v;
      project(v[0], v[1], v[2]);
      px[i] = out[0];
      py[i] = out[1];
      pz[i] = out[2];
    }

    // Arcs between countries, lifted off the surface.
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final a in st._arcs) {
      final u = ((st._time - a.start) / _HeroGlobeState._arcTime).clamp(0.0, 1.0);
      final va = pins[a.a].v, vb = pins[a.b].v;
      final d = (va[0] * vb[0] + va[1] * vb[1] + va[2] * vb[2]).clamp(-1.0, 1.0);
      final omega = math.acos(d);
      if (omega < 0.05) continue;
      final so = math.sin(omega);
      const steps = 26;
      final head = Curves.easeInOut.transform(u);
      Offset? prev;
      double prevZ = 0;
      for (var s = 0; s <= steps; s++) {
        final f = s / steps;
        if (f > head) break;
        final wa = math.sin((1 - f) * omega) / so, wb = math.sin(f * omega) / so;
        final lift = 1 + 0.42 * math.sin(f * math.pi) * (omega / math.pi + 0.35);
        project((va[0] * wa + vb[0] * wb) * lift, (va[1] * wa + vb[1] * wb) * lift,
            (va[2] * wa + vb[2] * wb) * lift);
        final p = Offset(out[0], out[1]);
        if (prev != null && (out[2] > -0.05 || prevZ > -0.05)) {
          final trail = (1 - (head - f) / 0.55).clamp(0.0, 1.0);
          final fade = u > 0.8 ? (1 - (u - 0.8) / 0.2) : 1.0;
          arcPaint
            ..color = LC.violet.withValues(alpha: 0.85 * trail * fade)
            ..strokeWidth = (0.8 + 1.4 * trail) * k;
          canvas.drawLine(prev, p, arcPaint);
        }
        prev = p;
        prevZ = out[2];
      }
    }

    // Pins.
    int? hovered;
    final pointer = st._pointer;
    if (pointer != null) {
      var best = 26.0 * k;
      for (var i = 0; i < pins.length; i++) {
        if (pz[i] < 0.12) continue;
        final dd = (Offset(px[i], py[i]) - pointer).distance;
        if (dd < best) {
          best = dd;
          hovered = i;
        }
      }
    }
    final delivering = <int>{for (final d in st._deliveries) d.pin};
    for (var i = 0; i < pins.length; i++) {
      if (pz[i] < 0.02) continue;
      final p = Offset(px[i], py[i]);
      final vis = ((pz[i] - 0.02) / 0.3).clamp(0.0, 1.0);
      final hot = delivering.contains(i) || hovered == i;
      final phase = (st._time * 0.7 + i * 0.37) % 1.0;
      canvas.drawCircle(
          p,
          (5 + phase * 13) * k,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2 * k
            ..color = LC.warm.withValues(alpha: (1 - phase) * 0.55 * vis));
      final glow = (hot ? 17.0 : 11.0) * k;
      canvas.drawCircle(
          p,
          glow,
          Paint()
            ..shader = ui.Gradient.radial(p, glow, [
              LC.warm.withValues(alpha: (hot ? 0.75 : 0.45) * vis),
              LC.warm.withValues(alpha: 0),
            ]));
      canvas.drawCircle(p, (hot ? 4.0 : 3.0) * k, Paint()..color = const Color(0xFFFFE9BF).withValues(alpha: vis));
    }

    // Leads flying from a country to the results card.
    final target = scene.cardAnchor;
    for (final d in st._deliveries) {
      if (d.pin >= pins.length) continue;
      final from = Offset(px[d.pin], py[d.pin]);
      final u = ((st._time - d.start) / _HeroGlobeState._deliveryTime).clamp(0.0, 1.0);
      final mid = Offset.lerp(from, target, 0.5)!;
      final ctrl = mid + Offset((target.dy - from.dy) * 0.22, -(target.dx - from.dx).abs() * 0.34 - 30 * k);
      Offset at(double t) {
        final a = 1 - t;
        return from * (a * a) + ctrl * (2 * a * t) + target * (t * t);
      }

      final head = Curves.easeInOutCubic.transform(u);
      const seg = 22;
      for (var s = 0; s < seg; s++) {
        final t1 = head - 0.42 * (s + 1) / seg, t0 = head - 0.42 * s / seg;
        if (t0 <= 0) break;
        final a = 1 - s / seg;
        arcPaint
          ..color = Color.lerp(LC.accent, LC.warm, 1 - a)!.withValues(alpha: 0.9 * a * a)
          ..strokeWidth = (0.8 + 2.4 * a) * k;
        canvas.drawLine(at(math.max(0, t1)), at(t0), arcPaint);
      }
      final h = at(head);
      canvas.drawCircle(
          h,
          12 * k,
          Paint()
            ..shader = ui.Gradient.radial(h, 12 * k, [
              LC.accent.withValues(alpha: 0.85),
              LC.accent.withValues(alpha: 0),
            ]));
      canvas.drawCircle(h, 2.8 * k, Paint()..color = Colors.white);
    }

    // Name the country under the pointer, or the one sending a lead.
    final named = hovered ?? (st._deliveries.isNotEmpty ? st._deliveries.last.pin : null);
    if (named != null && named < pins.length && pz[named] > 0.12) {
      _label(canvas, size, pins[named], Offset(px[named], py[named]), k, hovered == named);
    }
  }

  void _label(Canvas canvas, Size size, _Pin pin, Offset at, double k, bool detailed) {
    final regions = scene.state.widget.countries
        .firstWhere((c) => c.key == pin.key, orElse: () => const MapEntry('', 0))
        .value;
    final text = detailed && regions > 0 ? '${pin.label}  ·  $regions regions' : pin.label;
    final tp = _labels[text] ??= (TextPainter(
      text: TextSpan(
          text: text,
          style: const TextStyle(
              fontFamily: LT.font, color: LC.text, fontSize: 12, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout());
    final w = tp.width + 20, h = tp.height + 12;
    var left = at.dx - w / 2;
    left = left.clamp(2.0, math.max(2.0, size.width - w - 2));
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, at.dy - h - 14 * k, w, h), const Radius.circular(9));
    canvas.drawRRect(rect, Paint()..color = const Color(0xF0121920));
    canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = LC.warm.withValues(alpha: 0.55));
    tp.paint(canvas, Offset(left + 10, at.dy - h - 14 * k + 6));
  }

  @override
  bool shouldRepaint(covariant _GlobePainter old) => old.scene.radius != scene.radius;
}

// ---------------------------------------------------------------- lead card

class GlobeLeadCard extends StatelessWidget {
  final ValueNotifier<List<GlobeLead>> leads;
  final ValueNotifier<int> count;
  final double scale;
  const GlobeLeadCard({required this.leads, required this.count, required this.scale});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    final rowH = 46.0 * s;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xEE10161C),
        borderRadius: BorderRadius.circular(18 * s),
        border: Border.all(color: LC.borderHi),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.55), blurRadius: 50, offset: const Offset(0, 24)),
          BoxShadow(color: LC.accent.withValues(alpha: 0.10), blurRadius: 70, spreadRadius: -12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16 * s, 14 * s, 16 * s, 10 * s),
            child: Row(
              children: [
                Container(
                  width: 8 * s,
                  height: 8 * s,
                  decoration: const BoxDecoration(color: LC.green, shape: BoxShape.circle),
                ),
                SizedBox(width: 8 * s),
                Expanded(
                  child: Text('Leads arriving',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: LT.font,
                          color: LC.dim,
                          fontSize: 12.5 * s,
                          fontWeight: FontWeight.w600)),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: count,
                  builder: (context, n, _) => TweenAnimationBuilder<double>(
                    tween: Tween(end: n.toDouble()),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    builder: (context, v, _) => Text('${v.round()}',
                        style: TextStyle(
                            fontFamily: LT.font,
                            color: LC.text,
                            fontSize: 21 * s,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: LC.border),
          SizedBox(height: 6 * s),
          Expanded(
            child: ClipRect(
              child: ValueListenableBuilder<List<GlobeLead>>(
                valueListenable: leads,
                builder: (context, list, _) => Stack(
                  children: [
                    if (list.isEmpty)
                      Center(
                        child: Text('Listening…',
                            style: TextStyle(fontFamily: LT.font, color: LC.mute, fontSize: 12 * s)),
                      ),
                    for (var i = 0; i < list.length; i++)
                      AnimatedPositioned(
                        key: ValueKey(list[i].id),
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                        left: 8 * s,
                        right: 8 * s,
                        top: i * rowH,
                        height: rowH,
                        child: GlobeLeadRow(lead: list[i], scale: s),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16 * s, 2 * s, 16 * s, 11 * s),
            child: Text('Sample results for illustration',
                style: TextStyle(fontFamily: LT.font, color: LC.mute, fontSize: 10.5 * s)),
          ),
        ],
      ),
    );
  }
}

class GlobeLeadRow extends StatelessWidget {
  final GlobeLead lead;
  final double scale;
  const GlobeLeadRow({required this.lead, required this.scale});

  @override
  Widget build(BuildContext context) {
    final s = scale;
    Widget mark(IconData icon) => Container(
          width: 22 * s,
          height: 22 * s,
          margin: EdgeInsets.only(left: 5 * s),
          decoration: BoxDecoration(
            color: LC.green.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(6 * s),
          ),
          child: Icon(icon, size: 12 * s, color: LC.green),
        );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(-16 * (1 - v), 0), child: child),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 3 * s),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 9 * s),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(11 * s),
          ),
          child: Row(
            children: [
              CountryFlagBadge(countryName: lead.country, size: 15 * s),
              SizedBox(width: 10 * s),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lead.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: LT.font,
                            color: LC.text,
                            fontSize: 12.8 * s,
                            fontWeight: FontWeight.w600,
                            height: 1.2)),
                    Text('${lead.kind} · ${countryDisplayName(lead.country)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: LT.font, color: LC.mute, fontSize: 10.8 * s, height: 1.25)),
                  ],
                ),
              ),
              mark(Icons.call_rounded),
              mark(Icons.language_rounded),
              mark(Icons.mail_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

/// "50 states" style caption used by callers that know the region term.
String regionCaption(int count, String term) => '$count ${count == 1 ? term : pluralTerm(term)}';
