/// Non-web builds (and tests): there is no WebGL globe; the app draws its own.
class GlobeHandle {
  bool pulse(String key) => false;
  void anchor(double nx, double ny) {}
  void link(String from, String to) {}
  void hover(double nx, double ny) {}
  void leave() {}
  void dragStart() {}
  void drag(double dx) {}
  void dragEnd(double velocity) {}
  void destroy() {}
}

Future<GlobeHandle?> mountGlobe(Object element, List<Map<String, Object>> markers) async => null;
