import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/error_handler.dart';
import '../core/utils/refresh_bus.dart';
import '../core/utils/server_time.dart';
import '../services/api_service.dart';
import 'credit_provider.dart';

/// Searches that are queued or running for the signed-in user.
///
/// Polls GET /api/jobs/active every [interval] while [start]ed (signed in)
/// and while the browser tab is visible. Feeds the top-bar live chip, the
/// phone banner, the "N live" count and Home's "Running now" card.
/// Call [refresh] right after starting or cancelling a search.
class ActiveSearchesProvider with ChangeNotifier, WidgetsBindingObserver {
  ActiveSearchesProvider({ApiService? api, Duration? interval})
      : _api = api ?? ApiService(),
        _interval = interval ?? const Duration(seconds: 10);

  final ApiService _api;
  final Duration _interval;

  List<Map<String, dynamic>> _jobs = const <Map<String, dynamic>>[];
  bool _running = false;
  bool _visible = true;
  bool _observing = false;
  bool _loaded = false;
  bool _authExpired = false;
  bool _disposed = false;
  Object? _error;
  Duration _clockOffset = Duration.zero;
  Timer? _timer;
  Future<void>? _inFlight;

  /// Queued/running searches, newest first (server order).
  List<Map<String, dynamic>> get jobs => _jobs;
  int get count => _jobs.length;
  bool get hasActive => _jobs.isNotEmpty;
  bool get isLoaded => _loaded;
  bool get isPolling => _running;
  bool get authExpired => _authExpired;
  Object? get error => _error;

  /// serverTime - clientTime from the last response (for "started 3 min ago").
  Duration get clockOffset => _clockOffset;
  DateTime get serverNow => DateTime.now().add(_clockOffset);

  Map<String, dynamic>? jobById(String jobId) {
    for (final j in _jobs) {
      if ('${j['job_id']}' == jobId) return j;
    }
    return null;
  }

  /// Begin polling (signed in). Safe to call repeatedly.
  void start() {
    _authExpired = false;
    if (!_running) {
      _running = true;
      if (!_observing) {
        try {
          WidgetsBinding.instance.addObserver(this);
          _observing = true;
        } catch (_) {}
      }
    }
    unawaited(refresh());
  }

  /// Stop polling (signed out). Keeps nothing.
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
    if (_observing) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _observing = false;
    }
    clear();
  }

  void clear() {
    final had = _jobs.isNotEmpty || _error != null || _loaded;
    _jobs = const <Map<String, dynamic>>[];
    _error = null;
    _loaded = false;
    if (had) _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      if (_running) unawaited(refresh());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Fetch now (concurrent callers share one request) and reschedule.
  Future<void> refresh() {
    if (!_running) return Future<void>.value();
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<void> _fetch() async {
    _timer?.cancel();
    try {
      final previous = _jobs.map((j) => '${j['job_id']}').toSet();
      final jobs = await _api.getActiveJobs();
      if (!_running || _disposed) return;
      _jobs = List<Map<String, dynamic>>.unmodifiable(jobs);
      final serverTime = jobs.isNotEmpty ? parseServerTime(jobs.first['server_time']) : null;
      if (serverTime != null) _clockOffset = serverTime.difference(DateTime.now());
      _error = null;
      _authExpired = false;
      _loaded = true;
      final current = _jobs.map((j) => '${j['job_id']}').toSet();
      if (previous.difference(current).isNotEmpty) {
        // A search finished (or was cancelled): lists and balance changed.
        RefreshBus.notifyJobsChanged();
        unawaited(CreditProvider.instance.refresh());
      }
      _notify();
    } catch (e) {
      if (!_running || _disposed) return;
      _error = e;
      if (ErrorHandler.isAuthError(e)) {
        // Session expired: stop until the user signs in again (start()).
        _authExpired = true;
        _notify();
        return;
      }
      _notify();
    } finally {
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    if (!_running || !_visible || _authExpired || _disposed) return;
    _timer = Timer(_interval, () => unawaited(refresh()));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    if (_observing) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
    }
    super.dispose();
  }
}
