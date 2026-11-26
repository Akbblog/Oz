import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;

import '../config/environment.dart';

/// Lightweight behavioral event tracker for the Infinity Leads Flutter app.
///
/// Usage:
///   AnalyticsService.instance.identify(user.id);
///   AnalyticsService.instance.page('#/admin');
///   AnalyticsService.instance.feature('Activity', context: 'admin');
///   AnalyticsService.instance.track('search_start', properties: {'job_type': 'Gyms'});
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  // ── State ──────────────────────────────────────────────────────────────────
  int? _userId;
  String? _currentPage;
  String? _sessionId;
  final List<Map<String, dynamic>> _queue = [];
  Timer? _flushTimer;

  static const String _endpoint = '/api/analytics/events';
  static const String _visitEndpoint = '/api/analytics/visit';
  static const String _visitorKey = 'il_visitor_id';

  // Visit tracking (who opened the app, from where). Only active after
  // [init], so widget tests never start network calls or timers.
  bool _started = false;
  Timer? _heartbeatTimer;
  static const Duration _heartbeatInterval = Duration(seconds: 60);
  String? _visitorId;
  String? _lastVisitPath;
  DateTime? _lastVisitAt;
  String? _lastPagePath;
  DateTime? _lastPageAt;
  static const Duration _flushInterval = Duration(seconds: 5);
  static const int _maxQueueSize = 20;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void init() {
    _started = true;
    _sessionId ??= _resumeSession() ?? _newId();
    _rememberSession();
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
    // While the tab stays open and visible, tell the server the session is
    // still here (admin "Live now"). A heartbeat is not a page view.
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final path = _lastVisitPath;
      if (path == null) return;
      if (kIsWeb && html.document.visibilityState == 'hidden') return;
      unawaited(_sendVisit(path, heartbeat: true));
    });
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    flush();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Associate subsequent events with a logged-in user.
  void identify(int userId) {
    _userId = userId;
  }

  /// Track a page/screen view.
  /// Call this when the user navigates to a new route.
  void page(String pageName) {
    // The router reports every navigation; a few screens also call page()
    // themselves. Count a page once.
    final now = DateTime.now();
    if (_lastPagePath == pageName &&
        _lastPageAt != null &&
        now.difference(_lastPageAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastPagePath = pageName;
    _lastPageAt = now;
    _currentPage = pageName;
    track('page_view', properties: {'page': pageName});
  }

  // One visit = one stretch of activity in this browser. A reload or a second
  // tab continues the same visit; 30 minutes without activity ends it.
  static const String _sessionKey = 'il_session_id';
  static const String _sessionSeenKey = 'il_session_seen';
  static const Duration _sessionIdle = Duration(minutes: 30);

  String? _resumeSession() {
    if (!kIsWeb) return null;
    try {
      final id = html.window.localStorage[_sessionKey];
      final seen = int.tryParse(html.window.localStorage[_sessionSeenKey] ?? '');
      if (id == null || id.length < 6 || seen == null) return null;
      final idle = DateTime.now().millisecondsSinceEpoch - seen;
      return idle >= 0 && idle < _sessionIdle.inMilliseconds ? id : null;
    } catch (_) {
      return null;
    }
  }

  void _rememberSession() {
    if (!kIsWeb || _sessionId == null) return;
    try {
      html.window.localStorage[_sessionKey] = _sessionId!;
      html.window.localStorage[_sessionSeenKey] =
          '${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {}
  }

  // Where this browser is, as the hosting edge sees it (country / region /
  // city). Asked once per page load; empty when the host does not offer it.
  Future<Map<String, String>>? _geoFuture;

  Future<Map<String, String>> geo() => _geoFuture ??= _loadGeo();

  /// Forget the cached location (tests).
  void resetGeo() => _geoFuture = null;

  Future<Map<String, String>> _loadGeo() async {
    final out = <String, String>{};
    try {
      final response = await http
          .get(Uri.parse('${Environment.apiUrl}/api/edge-geo'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          for (final key in const ['country', 'region', 'city']) {
            final v = data[key];
            if (v is String && v.trim().isNotEmpty) out[key] = v.trim();
          }
        }
      }
    } catch (_) {
      // No location is fine; the server stores what it has.
    }
    return out;
  }

  /// This browser's visitor id and the current session id, so a new account
  /// can be linked to the visits that led to it. Null before [init].
  Future<({String? visitorId, String? sessionId})> identity() async {
    if (!_started) return (visitorId: null, sessionId: null);
    try {
      final prefs = await SharedPreferences.getInstance();
      _visitorId ??= prefs.getString(_visitorKey);
    } catch (_) {}
    return (visitorId: _visitorId, sessionId: _sessionId);
  }

  /// Called by the router for every navigation: records the page view and
  /// keeps the visit (session) row on the server fresh, so the admin
  /// Visitors page shows who is on the site, where they came from and what
  /// they looked at. Works for signed-out visitors too.
  void routeChanged(String? routeName) {
    if (!_started) return;
    final path = _cleanPath(routeName);
    final now = DateTime.now();
    if (_lastVisitPath == path &&
        _lastVisitAt != null &&
        now.difference(_lastVisitAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastVisitPath = path;
    _lastVisitAt = now;
    page(path);
    unawaited(_sendVisit(path));
  }

  /// Path without query string or ids that could identify a record
  /// ("/reset-password/<token>" → "/reset-password").
  static String _cleanPath(String? routeName) {
    var path = Uri.tryParse(routeName ?? '/')?.path ?? '/';
    if (path.isEmpty) path = '/';
    for (final prefix in const ['/reset-password/', '/payment/return/', '/payment/cancelled/']) {
      if (path.startsWith(prefix)) {
        return prefix.substring(0, prefix.length - 1);
      }
    }
    return path.length > 200 ? path.substring(0, 200) : path;
  }

  static String _newId() {
    final rnd = Random();
    final a = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final b = List.generate(12, (_) => rnd.nextInt(36).toRadixString(36)).join();
    return '$a$b';
  }

  Future<void> _sendVisit(String path, {bool heartbeat = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _visitorId ??= prefs.getString(_visitorKey);
      if (_visitorId == null || _visitorId!.isEmpty) {
        _visitorId = _newId();
        await prefs.setString(_visitorKey, _visitorId!);
      }
      final token = prefs.getString('auth_token');
      final query = Uri.base.queryParameters;
      final where = await geo();
      _rememberSession();
      String? referrer;
      String? language;
      int? screenW;
      int? screenH;
      if (kIsWeb) {
        referrer = html.document.referrer;
        language = html.window.navigator.language;
        screenW = html.window.screen?.width;
        screenH = html.window.screen?.height;
      }
      await http.post(
        Uri.parse('${Environment.apiUrl}$_visitEndpoint'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'visitor_id': _visitorId,
          'session_id': _sessionId ?? 'unknown',
          'path': path,
          if (heartbeat) 'heartbeat': true,
          'referrer': referrer,
          'utm_source': query['utm_source'],
          'utm_medium': query['utm_medium'],
          'utm_campaign': query['utm_campaign'],
          'language': language,
          'screen_w': screenW,
          'screen_h': screenH,
          'timezone': DateTime.now().timeZoneName,
          if (where['country'] != null) 'geo_country': where['country'],
          if (where['region'] != null) 'geo_region': where['region'],
          if (where['city'] != null) 'geo_city': where['city'],
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Never surface tracking failures.
    }
  }

  /// Shortcut for feature_use events (tab clicks, feature toggles).
  void feature(String featureName, {String? context}) {
    track('feature_use', properties: {
      'feature': featureName,
      if (context != null) 'context': context,
    });
  }

  /// Track any custom event with optional freeform properties.
  void track(String eventName, {Map<String, dynamic>? properties}) {
    if (!kIsWeb && kReleaseMode) {
      // Optionally restrict tracking to web/debug in your use case
    }

    final now = DateTime.now().toUtc();
    final dateBucket =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Build event — mirror the analytics_events table columns
    final extra = properties != null ? Map<String, dynamic>.from(properties) : <String, dynamic>{};
    final featureVal = extra.remove('feature') as String?;
    final elementVal = extra.remove('element') as String?;
    extra.remove('page'); // page goes in its own column

    _queue.add({
      'user_id':    _userId,
      'session_id': _sessionId ?? 'unknown',
      'event_name': eventName,
      'page':       properties?['page'] as String? ?? _currentPage,
      'element':    elementVal,
      'feature':    featureVal,
      'extra_json': extra.isNotEmpty ? extra : null,
      'date_bucket': dateBucket,
      'created_at':  now.toIso8601String(),
    });

    if (_queue.length >= _maxQueueSize) flush();
  }

  // ── Flush ──────────────────────────────────────────────────────────────────

  Future<void> flush() async {
    if (_queue.isEmpty) return;

    final batch = List<Map<String, dynamic>>.from(_queue);
    _queue.clear();

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      await http.post(
        Uri.parse('${Environment.apiUrl}$_endpoint'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty)
            'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'events': batch}),
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Analytics failures are always silent — never surface to the user.
    }
  }
}
