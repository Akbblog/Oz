/// Non-web builds (and tests): there is no WebGL globe; the app draws its own.
class GlobeHandle {
  void pulse(String from, [String? to]) {}
  void link(String from, String to) {}
  void hover(double nx, double ny) {}
  void leave() {}
  void dragStart() {}
  void drag(double dx) {}
  void dragEnd(double velocity) {}
  void destroy() {}
}

Future<GlobeHandle?> mountGlobe(Object element, List<Map<String, Object>> markers) async => null;
