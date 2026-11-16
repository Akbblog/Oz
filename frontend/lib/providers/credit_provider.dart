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

  void clear() {
    if (_balance == null && _error == null) return;
    _balance = null;
    _error = null;
    _canCreateJob = true;
    _updatedAt = null;
    notifyListeners();
  }
}
