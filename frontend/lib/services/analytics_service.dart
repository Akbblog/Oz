import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
  static const Duration _flushInterval = Duration(seconds: 5);
  static const int _maxQueueSize = 20;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  void init() {
    _sessionId ??= DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
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
    _currentPage = pageName;
    track('page_view', properties: {'page': pageName});
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
