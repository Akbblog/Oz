import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('ilGlobe')
external JSObject? get _ilGlobe;

/// The WebGL globe drawn by web/hero_globe.js (COBE).
class GlobeHandle {
  final JSObject _h;
  GlobeHandle._(this._h);

  void _call(String method, [JSAny? a, JSAny? b]) {
    try {
      _h.callMethod(method.toJS, a, b);
    } catch (_) {
      // The globe is decoration; never let it break the page.
    }
  }

  /// Sends a lead from [key]'s country to the results card. False when that
  /// country is on the far side of the globe right now.
  bool pulse(String key) {
    try {
      return _h.callMethod<JSBoolean?>('pulse'.toJS, key.toJS)?.toDart ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Where the results card sits, as a fraction of the globe's box.
  void anchor(double nx, double ny) => _call('anchor', nx.toJS, ny.toJS);
  void link(String from, String to) => _call('link', from.toJS, to.toJS);
  void hover(double nx, double ny) => _call('hover', nx.toJS, ny.toJS);
  void leave() => _call('leave');
  void dragStart() => _call('dragStart');
  void drag(double dx) => _call('drag', dx.toJS);
  void dragEnd(double velocity) => _call('dragEnd', velocity.toJS);
  void destroy() => _call('destroy');
}

/// Starts the globe inside [element]. Null when the script is missing or the
/// browser has no WebGL, in which case the caller draws its own globe.
Future<GlobeHandle?> mountGlobe(Object element, List<Map<String, Object>> markers) async {
  try {
    final api = _ilGlobe;
    if (api == null) return null;
    final promise = api.callMethod<JSPromise<JSObject?>>(
      'mount'.toJS,
      element as JSObject,
      {'markers': markers}.jsify(),
    );
    final handle = await promise.toDart;
    return handle == null ? null : GlobeHandle._(handle);
  } catch (_) {
    return null;
  }
}
