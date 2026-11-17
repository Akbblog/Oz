import 'package:flutter/foundation.dart';

import '../services/api_service.dart';

/// Single source of truth for the signed-in user's credit balance.
///
/// Previously the top bar, the search screen and the wallet each kept their own
/// copy, so a job charge (or refund) updated one number and left the others
/// stale. Every screen now reads this provider; anything that changes the
/// balance (job created/settled, purchase, grant) calls [refresh] or [setBalance].
class CreditProvider with ChangeNotifier {
  CreditProvider._();

  /// Shared instance so non-widget code (e.g. ScraperProvider) can update it.
  static final CreditProvider instance = CreditProvider._();

  final ApiService _api = ApiService();

  int? _balance;
  bool _loading = false;
  bool _canCreateJob = true;
  String? _error;
  DateTime? _updatedAt;
  Future<void>? _inFlight;

  Map<String, dynamic>? _config;
  Future<void>? _configInFlight;

  int get balance => _balance ?? 0;
  bool get hasValue => _balance != null;
  bool get loading => _loading && _balance == null;
  bool get refreshing => _loading;
  bool get canCreateJob => _canCreateJob;
  String? get error => _error;
  DateTime? get updatedAt => _updatedAt;

  /// Server-confirmed balance from another response (e.g. job creation).
  void setBalance(int value) {
    _balance = value;
    _error = null;
    _updatedAt = DateTime.now();
    notifyListeners();
  }

  /// Fetch the balance. Concurrent callers share one request. On failure the
  /// last known value is kept (and [error] set) instead of showing 0.
  Future<void> refresh() {
    return _inFlight ??= _doRefresh().whenComplete(() => _inFlight = null);
  }

  Future<void> _doRefresh() async {
    _loading = true;
    notifyListeners();
    try {
      final data = await _api.getCreditBalance();
      final value = data['balance'];
      _balance = value is int ? value : int.tryParse('$value') ?? _balance;
      _canCreateJob = data['rate_limits']?['can_create_job'] ?? true;
      _error = null;
      _updatedAt = DateTime.now();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ config

  /// GET /api/credits/config, cached for the session ([loadConfig]).
  Map<String, dynamic>? get config => _config;

  /// Cost of the smallest possible search, when the server reports it.
  int? get minJobCost {
    final v = _config?['min_job_cost'];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }

  /// `delivered`, `unattempted`, `none`, or null when unknown.
  String? get refundPolicy {
    final v = _config?['refund_policy'];
    if (v is! String) return null;
    final p = v.trim().toLowerCase();
    return p.isEmpty ? null : p;
  }

  /// The configured refund policy as a sentence, or null when the policy is
  /// missing/unknown (never guessed).
  String? get refundPolicySentence => refundPolicySentenceFor(refundPolicy);

  static String? refundPolicySentenceFor(String? policy) {
    switch (policy) {
      case 'delivered':
        return 'You pay for what we deliver. Unused credits are returned when '
            'the search ends. If it finds no leads, everything is returned.';
      case 'unattempted':
        return "If the search stops early, credits for cities that weren't "
            'searched are returned. If it fails without finding leads, '
            'everything is returned.';
      case 'none':
        return 'Credits are not returned after the search starts.';
      default:
        return null;
    }
  }

  /// Server-confirmed configuration from another source (and tests).
  void setConfig(Map<String, dynamic> config) {
    _config = Map<String, dynamic>.from(config);
    notifyListeners();
  }

  /// Loads the credit configuration once per session (concurrent callers
  /// share the request). Failures keep the previous value.
  Future<void> loadConfig({bool force = false}) {
    if (_config != null && !force) return Future<void>.value();
    return _configInFlight ??= _doLoadConfig().whenComplete(() => _configInFlight = null);
  }

  Future<void> _doLoadConfig() async {
    try {
      _config = await _api.getCreditConfig();
      notifyListeners();
    } catch (_) {
      // Keep the previous value; screens omit config-based lines without it.
    }
  }

  void clear() {
    final hadConfig = _config != null;
    _config = null;
    if (_balance == null && _error == null && !hadConfig) return;
    _balance = null;
    _error = null;
    _canCreateJob = true;
    _updatedAt = null;
    notifyListeners();
  }
}
