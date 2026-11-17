/// Selection of leads (results) within ONE search, keyed by stable lead
/// identities so a selection survives filtering, sorting, switching between
/// cards and table, and reloading the same search.
///
/// This is the groundwork for a future "Add to CRM" action, which would send
/// [LeadSelection.selectedLeadIds]. See `docs/CRM_LEAD_SELECTION.md`.
library;

import 'dart:collection';

import 'package:flutter/foundation.dart';

/// How trustworthy a selection id is.
enum LeadIdKind {
  /// `lead:<lead_id>` – the results-row primary key. Stable for the life of
  /// the lead and unique across all searches. The only id a CRM import
  /// should rely on.
  leadId,

  /// `key:<job_id>:<lead_key>` – the per-business dedupe key, unique within
  /// one search. Stable across reloads of that search.
  leadKey,

  /// `row:<job_id>:<maps url | name|phone|address>` – derived from the lead's
  /// content (older servers, live results before they are stored). Stable
  /// only while that content does not change; NOT an identity.
  fallback,
}

/// Numeric `lead_id` of [lead] (`lead_id`, or `id` as returned by admin
/// reads), or null when absent or not a positive integer.
int? leadIdOf(Map<String, dynamic> lead) {
  for (final key in const ['lead_id', 'id']) {
    final v = lead[key];
    final n = v is int ? v : (v is num && v == v.roundToDouble() ? v.toInt() : int.tryParse('${v ?? ''}'.trim()));
    if (n != null && n > 0) return n;
  }
  return null;
}

/// `lead_key` of [lead], or null when absent or blank.
String? leadKeyOf(Map<String, dynamic> lead) {
  final v = lead['lead_key'];
  if (v == null) return null;
  final s = '$v'.trim();
  return s.isEmpty || s == 'null' ? null : s;
}

String _norm(Object? v) {
  final s = '${v ?? ''}'.trim().toLowerCase();
  return s == 'n/a' || s == 'null' ? '' : s;
}

/// Selection id of one lead:
///
/// 1. `lead:<lead_id>` when the lead has a `lead_id` (or `id`);
/// 2. else `key:<job_id>:<lead_key>`;
/// 3. else `row:<job_id>:<google_maps_url>` or
///    `row:<job_id>:<name>|<phone>|<address>` (lower-cased, documented as
///    unstable).
///
/// [jobId] is the search the lead belongs to; a `job_id` inside the lead
/// wins when present.
String leadSelectionId(Map<String, dynamic> lead, {String? jobId}) {
  final id = leadIdOf(lead);
  if (id != null) return 'lead:$id';
  final job = '${lead['job_id'] ?? jobId ?? ''}'.trim();
  final key = leadKeyOf(lead);
  if (key != null) return 'key:$job:$key';
  final maps = _norm(lead['google_maps_url']);
  if (maps.isNotEmpty) return 'row:$job:$maps';
  final name = _norm(lead['business_name'] ?? lead['name']);
  return 'row:$job:$name|${_norm(lead['phone'])}|${_norm(lead['address'])}';
}

/// Kind of a selection id built by [leadSelectionId] / [leadSelectionIds].
LeadIdKind leadIdKind(String selectionId) {
  if (selectionId.startsWith('lead:')) return LeadIdKind.leadId;
  if (selectionId.startsWith('key:')) return LeadIdKind.leadKey;
  return LeadIdKind.fallback;
}

/// Selection ids for [leads], in order. Equal ids (two leads with the same
/// fallback content, or a server bug) are made unique with `#2`, `#3`, ...
/// in list order, so selecting one never selects another.
List<String> leadSelectionIds(List<Map<String, dynamic>> leads, {String? jobId}) {
  final seen = <String, int>{};
  return [
    for (final lead in leads)
      () {
        final base = leadSelectionId(lead, jobId: jobId);
        final n = (seen[base] ?? 0) + 1;
        seen[base] = n;
        return n == 1 ? base : '$base#$n';
      }(),
  ];
}

/// "3 selected · 12 shown of 40" style summary. [hiddenSelected] (selected
/// leads the filters hide) adds "· 1 not shown".
String leadSelectionSummary({
  required int selected,
  required int shown,
  required int total,
  int hiddenSelected = 0,
}) {
  final parts = <String>[
    shown == total ? '$selected selected of $total' : '$selected selected · $shown shown of $total',
    if (hiddenSelected > 0) '$hiddenSelected not shown',
  ];
  return parts.join(' · ');
}

/// Selected leads of one search.
///
/// Call [attach] whenever the search's lead list changes (load, reload,
/// live updates); it indexes the leads and drops selected ids that are no
/// longer present. Call [setScope] when the search changes; that clears the
/// selection, so a selection never mixes searches.
///
/// "Visible" (what the filters show) and "selected" are separate: filtering
/// or sorting never changes the selection; [selectAll] / [deselectAll] act
/// on the leads passed (normally the visible ones) only.
class LeadSelection extends ChangeNotifier {
  LeadSelection({String? scope}) : _scope = scope;

  String? _scope;
  final Set<String> _selected = <String>{};
  // Leads are looked up by object identity: two equal-looking maps are two
  // leads.
  final Map<Map<String, dynamic>, String> _ids = HashMap.identity();
  final Map<String, Map<String, dynamic>> _byId = <String, Map<String, dynamic>>{};

  /// The search (job id) this selection belongs to.
  String? get scope => _scope;

  /// Switches to [scope]. A different search clears the selection.
  void setScope(String? scope) {
    if (scope == _scope) return;
    _scope = scope;
    _ids.clear();
    _byId.clear();
    if (_selected.isNotEmpty) {
      _selected.clear();
      notifyListeners();
    }
  }

  /// Indexes [leads] (all leads of the search) and drops selected ids that
  /// are not among them.
  void attach(List<Map<String, dynamic>> leads) {
    _ids.clear();
    _byId.clear();
    final ids = leadSelectionIds(leads, jobId: _scope);
    for (var i = 0; i < leads.length; i++) {
      _ids[leads[i]] = ids[i];
      _byId[ids[i]] = leads[i];
    }
    final before = _selected.length;
    _selected.retainWhere(_byId.containsKey);
    if (_selected.length != before) notifyListeners();
  }

  /// Selection id of [lead] (from [attach] when indexed).
  String idOf(Map<String, dynamic> lead) => _ids[lead] ?? leadSelectionId(lead, jobId: _scope);

  bool isSelected(Map<String, dynamic> lead) => _selected.contains(idOf(lead));
  bool isSelectedId(String id) => _selected.contains(id);

  /// Toggles [lead], or sets it to [value] when given.
  void toggle(Map<String, dynamic> lead, [bool? value]) {
    final id = idOf(lead);
    final select = value ?? !_selected.contains(id);
    final changed = select ? _selected.add(id) : _selected.remove(id);
    if (changed) notifyListeners();
  }

  /// Adds every lead of [leads] (e.g. the visible ones) to the selection.
  void selectAll(Iterable<Map<String, dynamic>> leads) {
    var changed = false;
    for (final l in leads) {
      changed = _selected.add(idOf(l)) || changed;
    }
    if (changed) notifyListeners();
  }

  /// Removes every lead of [leads] from the selection; others stay.
  void deselectAll(Iterable<Map<String, dynamic>> leads) {
    var changed = false;
    for (final l in leads) {
      changed = _selected.remove(idOf(l)) || changed;
    }
    if (changed) notifyListeners();
  }

  void clear() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  int get count => _selected.length;
  bool get isEmpty => _selected.isEmpty;
  bool get isNotEmpty => _selected.isNotEmpty;

  /// Selected ids in the order they were selected (read-only).
  Set<String> get selectedIds => UnmodifiableSetView(_selected);

  /// How many of [leads] are selected.
  int countIn(Iterable<Map<String, dynamic>> leads) => leads.where(isSelected).length;

  /// `true` all of [leads] selected, `false` none, `null` some (for a
  /// tri-state "select all shown" checkbox). Empty [leads] -> false.
  bool? stateOf(Iterable<Map<String, dynamic>> leads) {
    final list = leads.toList();
    if (list.isEmpty) return false;
    final n = countIn(list);
    if (n == 0) return false;
    return n == list.length ? true : null;
  }

  /// The selected leads among [allLeads], in [allLeads] order (export
  /// order = list order, not click order).
  List<Map<String, dynamic>> selectedLeads(Iterable<Map<String, dynamic>> allLeads) =>
      [for (final l in allLeads) if (isSelected(l)) l];

  /// Numeric `lead_id`s of the selected leads among [allLeads], de-duplicated,
  /// in list order. Leads without a `lead_id` are left out — check
  /// [selectedWithoutLeadId] before offering an action that needs ids.
  List<int> selectedLeadIds(Iterable<Map<String, dynamic>> allLeads) {
    final out = <int>{};
    for (final l in selectedLeads(allLeads)) {
      final id = leadIdOf(l);
      if (id != null) out.add(id);
    }
    return out.toList();
  }

  /// How many selected leads among [allLeads] have no `lead_id`.
  int selectedWithoutLeadId(Iterable<Map<String, dynamic>> allLeads) =>
      selectedLeads(allLeads).where((l) => leadIdOf(l) == null).length;
}
