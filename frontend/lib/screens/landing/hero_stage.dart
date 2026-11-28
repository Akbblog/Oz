import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'globe_bridge_stub.dart' if (dart.library.js_interop) 'globe_bridge_web.dart';
import 'hero_globe.dart';
import 'landing_kit.dart';

/// The hero illustration.
///
/// In a browser with WebGL the globe is drawn by COBE (a small open-source
/// WebGL library, see web/hero_globe.js): a dotted Earth with the covered
/// countries as glowing markers and arcs between them. Anywhere else (no
/// WebGL, tests) the app draws its own globe, [HeroGlobe].
///
/// The page, not the globe, listens to the pointer: hovering leans the globe,
/// dragging sideways spins it, and the mouse wheel keeps scrolling the page.
class HeroStage extends StatefulWidget {
  final List<MapEntry<String, int>> countries;
  const HeroStage({super.key, required this.countries});

  @override
  State<HeroStage> createState() => _HeroStageState();
}

class _HeroStageState extends State<HeroStage> {
  final ValueNotifier<List<GlobeLead>> _leads = ValueNotifier<List<GlobeLead>>(const []);
  final ValueNotifier<int> _count = ValueNotifier<int>(0);
  final math.Random _rnd = math.Random(11);

  GlobeHandle? _globe;
  bool _fallback = !kIsWeb;
  bool _dragging = false;
  Timer? _timer;
  int _beat = 0, _ids = 0, _sample = 0, _cursor = 0;

  List<String> get _keys => [
        for (final c in widget.countries)
          if (kCountryCenters.containsKey(c.key)) c.key
      ];

  @override
  void dispose() {
    _timer?.cancel();
    _globe?.destroy();
    _leads.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _mount(Object element) async {
    final markers = <Map<String, Object>>[
      for (final key in _keys)
        {'key': key, 'lat': kCountryCenters[key]!.$1, 'lng': kCountryCenters[key]!.$2},
    ];
    final handle = await mountGlobe(element, markers);
    if (!mounted) {
      handle?.destroy();
      return;
    }
    if (handle == null) {
      setState(() => _fallback = true);
      return;
    }
    _globe = handle;
    // A steady beat: every 0.8 s something happens on the globe.
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) => _onBeat());
  }

  void _onBeat() {
    final keys = _keys;
    final globe = _globe;
    if (globe == null || keys.length < 2 || !mounted) return;
    _beat++;
    if (_beat.isOdd) {
      // A lead "arrives": its country lights up and an arc leaves it.
      final from = keys[_cursor++ % keys.length];
      var to = keys[_rnd.nextInt(keys.length)];
      if (to == from) to = keys[(keys.indexOf(from) + 1) % keys.length];
      globe.pulse(from, to);
      Timer(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        final s = kGlobeSamples[_sample++ % kGlobeSamples.length];
        final next = [GlobeLead(++_ids, s.$1, s.$2, from), ..._leads.value];
        _leads.value = next.length > 4 ? next.sublist(0, 4) : next;
        _count.value += 4 + _rnd.nextInt(9);
      });
    } else if (_beat % 4 == 0) {
      final a = keys[_rnd.nextInt(keys.length)];
      final b = keys[_rnd.nextInt(keys.length)];
      if (a != b) globe.link(a, b);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fallback) return HeroGlobe(countries: widget.countries);
    return AspectRatio(
      aspectRatio: 1.0,
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth;
        final s = (w / 540).clamp(0.6, 1.12);
        final cardW = math.min(w * 0.64, 318.0 * s);
        final cardH = 286.0 * s;
        final globeSize = w * 0.98;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -w * 0.07,
              top: -w * 0.06,
              width: globeSize,
              height: globeSize,
              child: HtmlElementView.fromTagName(
                tagName: 'div',
                onElementCreated: _mount,
              ),
            ),
            // Pointer layer above the globe (which ignores the pointer itself).
            Positioned.fill(
              child: MouseRegion(
                cursor: _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
                onHover: (e) => _globe?.hover(
                    e.localPosition.dx / w - 0.42, e.localPosition.dy / w - 0.43),
                onExit: (_) => _globe?.leave(),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    _globe?.dragStart();
                    setState(() => _dragging = true);
                  },
                  onHorizontalDragUpdate: (d) => _globe?.drag(d.delta.dx),
                  onHorizontalDragEnd: (d) {
                    _globe?.dragEnd(d.velocity.pixelsPerSecond.dx);
                    setState(() => _dragging = false);
                  },
                  onHorizontalDragCancel: () {
                    _globe?.dragEnd(0);
                    setState(() => _dragging = false);
                  },
                ),
              ),
            ),
            Positioned(
              left: w - cardW,
              top: w - cardH - w * 0.005,
              width: cardW,
              height: cardH,
              child: IgnorePointer(
                child: GlobeLeadCard(leads: _leads, count: _count, scale: s),
              ),
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
