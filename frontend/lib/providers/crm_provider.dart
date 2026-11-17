import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/crm/crm_format.dart';
import '../services/crm_api.dart';

/// CRM feature gate and shared workspace data.
///
/// After sign-in [start] asks `GET /api/crm/status`; the CRM navigation item
/// is shown only when [enabled] is true. While enabled it keeps the
/// workspace (stages, lost reasons, tags) and the agenda counts used by the
/// nav badge (overdue + due today), refreshed every few minutes.
class CrmProvider extends ChangeNotifier {
  CrmProvider({CrmApi? api, this.countsInterval = const Duration(minutes: 2)}) : api = api ?? CrmApi();

  final CrmApi api;
  final Duration countsInterval;

  bool? _enabled;
  Map<String, dynamic>? _workspace;
  Map<String, int> _counts = const {};
  Timer? _timer;
  int _generation = 0;
  Future<Map<String, dynamic>?>? _workspaceLoad;

  /// null until the status is known (or after sign-out).
  bool? get enabled => _enabled;
  bool get isEnabled => _enabled == true;
  Map<String, dynamic>? get workspace => _workspace;
  Map<String, int> get counts => _counts;

  /// Overdue + due today (nav badge).
  int get dueCount => (_counts['overdue'] ?? 0) + (_counts['today'] ?? 0);

  List<Map<String, dynamic>> get stages {
    final stages = crmList(crmMap(_workspace?['pipeline'])['stages']);
    stages.sort((a, b) => crmInt(a['position']).compareTo(crmInt(b['position'])));
    return stages;
  }

  List<Map<String, dynamic>> get lostReasons => crmList(_workspace?['lost_reasons']);
  List<Map<String, dynamic>> get tags => crmList(_workspace?['tags']);

  /// Checks the feature flag; on success loads workspace and counts.
  Future<void> start() async {
    final generation = ++_generation;
    try {
      final on = await api.getStatus();
      if (generation != _generation) return;
      _enabled = on;
      notifyListeners();
      if (on) {
        unawaited(loadWorkspace(force: true));
        unawaited(refreshCounts());
        _timer?.cancel();
        _timer = Timer.periodic(countsInterval, (_) => refreshCounts());
      } else {
        _timer?.cancel();
      }
    } catch (e) {
      // Unknown (offline, older server): hide the nav item; CRM pages still
      // explain what is wrong when opened directly.
      if (generation != _generation) return;
      if (e is CrmException && (e.isDisabled || e.statusCode == 404)) {
        _enabled = false;
        notifyListeners();
      }
    }
  }

  /// Workspace (pipeline, stages, lost reasons, tags), cached.
  Future<Map<String, dynamic>?> loadWorkspace({bool force = false}) {
    if (!force && _workspace != null) return Future.value(_workspace);
    if (!force && _workspaceLoad != null) return _workspaceLoad!;
    final generation = _generation;
    final load = () async {
      try {
        final ws = await api.getWorkspace();
        if (generation != _generation) return null;
        _workspace = ws;
        if (_enabled != true) _enabled = true;
        notifyListeners();
        return ws;
      } catch (e) {
        if (e is CrmException && e.isDisabled && generation == _generation) {
          _enabled = false;
          notifyListeners();
        }
        rethrow;
      } finally {
        _workspaceLoad = null;
      }
    }();
    _workspaceLoad = load;
    return load;
  }

  /// Adds/replaces a tag in the cached workspace (after creating one).
  void rememberTag(Map<String, dynamic> tag) {
    final ws = _workspace;
    if (ws == null) return;
    final tags = crmList(ws['tags'])..removeWhere((t) => t['id'] == tag['id']);
    tags.add(tag);
    _workspace = {...ws, 'tags': tags};
    notifyListeners();
  }

  /// Adds a custom lost reason created by "Mark lost".
  void rememberLostReason(Map<String, dynamic> reason) {
    final ws = _workspace;
    if (ws == null) return;
    final reasons = crmList(ws['lost_reasons'])..removeWhere((t) => t['id'] == reason['id']);
    reasons.add(reason);
    _workspace = {...ws, 'lost_reasons': reasons};
    notifyListeners();
  }

  Future<void> refreshCounts() async {
    if (_enabled != true) return;
    final generation = _generation;
    try {
      final c = await api.getAgendaCounts();
      if (generation != _generation) return;
      _counts = c;
      notifyListeners();
    } catch (_) {
      // Badge stays as it was; the agenda screen reports errors.
    }
  }

  /// Fresh counts fetched by a screen (keeps the nav badge in step).
  void setCounts(Map<String, int> counts) {
    _counts = Map<String, int>.from(counts);
    notifyListeners();
  }

  /// Sign-out: forget everything.
  void clear() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _enabled = null;
    _workspace = null;
    _workspaceLoad = null;
    _counts = const {};
    notifyListeners();
  }

  /// Test helper: set the state without network calls.
  @visibleForTesting
  void debugSet({bool? enabled, Map<String, dynamic>? workspace, Map<String, int>? counts}) {
    _enabled = enabled;
    if (workspace != null) _workspace = workspace;
    if (counts != null) _counts = counts;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
