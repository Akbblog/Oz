import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/crm/crm_filters.dart';
import '../../core/crm/crm_format.dart';
import '../../core/crm/crm_import.dart';
import '../../core/lead_selection.dart';
import '../../services/crm_api.dart';
import '../app_shell.dart';
import 'crm_widgets.dart';

/// CRM side of a search's results: per-lead state (from
/// `GET /api/crm/jobs/{id}/state`), Add one / Add selected / Add all with
/// retry-safe idempotency keys, the review dialog for possible matches and
/// the summary snack. Only leads with a saved `lead_id` can be added.
class CrmResultsController extends ChangeNotifier {
  CrmResultsController({required this.jobId, required this.api, CrmImporter? importer})
      : importer = importer ?? CrmImporter(api);

  final String jobId;
  final CrmApi api;
  final CrmImporter importer;

  Map<int, CrmLeadStatus> _states = const {};
  Map<String, int> _counts = const {};
  bool _stateLoaded = false;
  Object? _stateError;
  bool _busy = false;
  String? _progress;
  final Set<int> _adding = {};
  bool _disposed = false;

  bool get stateLoaded => _stateLoaded;
  Object? get stateError => _stateError;
  bool get busy => _busy;

  /// "Adding… 200 done, 212 to go" while an import runs.
  String? get progress => _progress;
  Map<String, int> get counts => _counts;

  bool isAdding(int resultId) => _adding.contains(resultId);

  CrmLeadStatus statusOf(Map<String, dynamic> lead) {
    final id = leadIdOf(lead);
    if (id == null) return CrmLeadStatus.notAdded;
    return _states[id] ?? CrmLeadStatus.notAdded;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> loadState() async {
    try {
      final data = await api.getJobState(jobId);
      _states = parseCrmJobState(data);
      final c = crmMap(data['counts']);
      _counts = {for (final e in c.entries) e.key: crmInt(e.value)};
      _stateLoaded = true;
      _stateError = null;
    } catch (e) {
      _stateError = e;
    }
    _notify();
  }

  /// Marks the outcome locally right away (the state reload follows).
  void _apply(CrmImportResult r) {
    final next = Map<int, CrmLeadStatus>.from(_states);
    r.created.forEach((id, rec) => next[id] = CrmLeadStatus(CrmLeadState.added, recordId: rec.isEmpty ? null : rec));
    r.alreadyAdded.forEach((id, rec) => next[id] = CrmLeadStatus(CrmLeadState.added, recordId: rec.isEmpty ? null : rec));
    r.linked.forEach((id, rec) => next[id] = CrmLeadStatus(CrmLeadState.added, recordId: rec.isEmpty ? null : rec));
    for (final e in r.possibleMatches.entries) {
      next[e.key] = CrmLeadStatus(CrmLeadState.possibleMatch,
          candidateRecordIds: [for (final c in crmList(e.value['candidates'])) crmStr(c['record_id'])]);
    }
    _states = next;
  }

  Future<CrmImportResult?> _run(
    BuildContext context,
    Future<CrmImportResult> Function() call, {
    Iterable<int> ids = const [],
  }) async {
    if (_busy) return null;
    _busy = true;
    _adding.addAll(ids);
    _notify();
    try {
      final result = await call();
      _apply(result);
      _busy = false;
      _progress = null;
      _adding.clear();
      _notify();
      if (context.mounted) crmSnack(context, result.summary);
      unawaited(loadState());
      if (result.possibleMatches.isNotEmpty && context.mounted) {
        await review(context, result.possibleMatches.values.toList());
      }
      return result;
    } catch (e) {
      _busy = false;
      _progress = null;
      _adding.clear();
      _notify();
      if (context.mounted) {
        final retry = crmErrorKind(e) == CrmErrorKind.offline || crmErrorKind(e) == CrmErrorKind.other;
        crmSnack(
          context,
          '${crmActionError('Adding to CRM', e)}${retry ? ' Trying again is safe: nothing is added twice.' : ''}',
          error: true,
        );
      }
      return null;
    }
  }

  /// Add selected / Add one.
  Future<CrmImportResult?> addIds(BuildContext context, List<int> ids) =>
      _run(context, () => importer.importIds(jobId, ids), ids: ids);

  /// Add all saved leads of the search (repeats the resumable import).
  Future<CrmImportResult?> addAll(BuildContext context) => _run(context, () {
        _progress = 'Adding leads to CRM…';
        _notify();
        return importer.importAll(jobId, onProgress: (r) {
          final handled = r.created.length + r.alreadyAdded.length + r.possibleMatches.length + r.rejected.length;
          _progress = r.done
              ? null
              : 'Adding leads to CRM… ${formatCount(handled)} done, ${formatCount(r.remaining)} to go';
          _notify();
        });
      });

  /// Review possible matches and send the decisions.
  Future<CrmImportResult?> review(BuildContext context, List<Map<String, dynamic>> matches) async {
    final decisions = await showCrmImportReviewDialog(context, matches);
    if (decisions == null || decisions.isEmpty || !context.mounted) return null;
    return _run(context, () => importer.resolve(jobId, decisions),
        ids: [for (final d in decisions) crmInt(d['result_id'])]);
  }
}

// ------------------------------------------------------------ review

/// Possible matches: Add new / Link to an existing record / Skip per item
/// (Skip preselected; nothing is merged without a choice). Returns the
/// decisions or null when cancelled.
Future<List<Map<String, dynamic>>?> showCrmImportReviewDialog(BuildContext context, List<Map<String, dynamic>> matches) =>
    showDialog<List<Map<String, dynamic>>>(context: context, builder: (_) => _ReviewDialog(matches: matches));

class _ReviewDialog extends StatefulWidget {
  final List<Map<String, dynamic>> matches;

  const _ReviewDialog({required this.matches});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  /// result id → `skip`, `add_new` or `link:RECORD_ID`.
  late final Map<int, String> _choice = {for (final m in widget.matches) crmInt(m['result_id']): 'skip'};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: UiTokens.card,
      title: Text(
        widget.matches.length == 1 ? 'Possible match: review' : '${widget.matches.length} possible matches: review',
        style: const TextStyle(color: UiTokens.text),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'These businesses look like records already in your CRM. Choose for each one. '
                'Linking keeps the existing record as it is and adds this search as a source.',
                style: TextStyle(color: UiTokens.textSecondary, fontSize: 13.5, height: 1.4),
              ),
              for (final m in widget.matches) _item(m),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Decide later'),
        ),
        FilledButton(
          style: searchPrimaryButtonStyle(),
          onPressed: () {
            final out = <Map<String, dynamic>>[];
            _choice.forEach((id, c) {
              if (c.startsWith('link:')) {
                out.add({'result_id': id, 'action': 'link', 'record_id': c.substring(5)});
              } else {
                out.add({'result_id': id, 'action': c});
              }
            });
            Navigator.of(context).pop(out);
          },
          child: const Text('Apply choices'),
        ),
      ],
    );
  }

  static String? _candidateLine(Map<String, dynamic> c) {
    final stage = c['stage'] is Map ? crmStr(crmMap(c['stage'])['name']) : crmStr(c['stage']);
    final reasons = c['reasons'] is List ? [for (final r in c['reasons'] as List) '$r'.replaceAll('_', ' ')] : <String>[];
    final parts = [if (stage.isNotEmpty) 'Stage: $stage', if (reasons.isNotEmpty) 'Why: ${reasons.join(', ')}'];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _item(Map<String, dynamic> m) {
    final id = crmInt(m['result_id']);
    final name = crmStr(m['business_name']).isEmpty ? 'Business' : crmStr(m['business_name']);
    final candidates = crmList(m['candidates']);
    Widget option(String value, String title, {String? subtitle}) => RadioListTile<String>(
          value: value,
          contentPadding: EdgeInsets.zero,
          title: Text(title, style: const TextStyle(color: UiTokens.text, fontSize: 14)),
          subtitle: subtitle == null
              ? null
              : Text(subtitle, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 12.5)),
        );
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: UiTokens.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: UiTokens.border),
      ),
      child: Semantics(
        container: true,
        label: 'Choice for $name',
        child: RadioGroup<String>(
          groupValue: _choice[id],
          onChanged: (v) => setState(() => _choice[id] = v ?? 'skip'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(name, style: const TextStyle(color: UiTokens.text, fontSize: 15, fontWeight: FontWeight.w700)),
              for (final c in candidates)
                option(
                  'link:${crmStr(c['record_id'])}',
                  'Link to "${crmStr(c['name'])}"',
                  subtitle: _candidateLine(c),
                ),
              option('add_new', 'Add as a new record'),
              option('skip', 'Skip for now'),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- widgets

/// Per-lead CRM state: "Add to CRM", "In CRM · View", "Possible match ·
/// Review", or a disabled button with the reason when the lead has no
/// saved id yet.
class CrmLeadChip extends StatelessWidget {
  final Map<String, dynamic> lead;
  final CrmResultsController controller;
  final bool compact;

  const CrmLeadChip({super.key, required this.lead, required this.controller, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final id = leadIdOf(lead);
    final name = crmStr(lead['business_name'] ?? lead['name']);
    final style = TextButton.styleFrom(
      foregroundColor: UiTokens.accent,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
    );
    if (id == null) {
      return Tooltip(
        message: "This lead isn't saved with an ID yet, so it can't be added to the CRM. Reload the search later.",
        child: TextButton.icon(
          style: style,
          onPressed: null,
          icon: const Icon(Icons.playlist_add_rounded, size: 18),
          label: Text(compact ? 'Not saved yet' : "Can't add yet (not saved)",
              semanticsLabel: "Can't add $name to CRM yet: this lead is not saved"),
        ),
      );
    }
    if (controller.isAdding(id)) {
      return const SizedBox(
        height: 48,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Adding…', style: TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
        ]),
      );
    }
    final s = controller.statusOf(lead);
    switch (s.state) {
      case CrmLeadState.added:
        return TextButton.icon(
          style: style.copyWith(foregroundColor: const WidgetStatePropertyAll(UiTokens.completedFg)),
          onPressed: s.recordId == null ? null : () => Navigator.of(context).pushNamed(crmRecordRoute(s.recordId!)),
          icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: Text(compact ? 'In CRM' : 'Already in CRM · View', semanticsLabel: '$name is in your CRM. View the record'),
        );
      case CrmLeadState.possibleMatch:
        return TextButton.icon(
          style: style.copyWith(foregroundColor: const WidgetStatePropertyAll(UiTokens.partialFg)),
          onPressed: controller.busy ? null : () => controller.addIds(context, [id]),
          icon: const Icon(Icons.compare_arrows_rounded, size: 18),
          label: Text(compact ? 'Review' : 'Possible match · Review',
              semanticsLabel: '$name may already be in your CRM. Review the match'),
        );
      case CrmLeadState.notAdded:
        return TextButton.icon(
          style: style,
          onPressed: controller.busy ? null : () => controller.addIds(context, [id]),
          icon: const Icon(Icons.playlist_add_rounded, size: 18),
          label: Text('Add to CRM', semanticsLabel: 'Add $name to CRM'),
        );
    }
  }
}

/// CRM line above the leads: counts, Add all, View this search in CRM and
/// the progress of a running import.
class CrmResultsStrip extends StatelessWidget {
  final CrmResultsController controller;
  final List<Map<String, dynamic>> leads;

  const CrmResultsStrip({super.key, required this.controller, required this.leads});

  @override
  Widget build(BuildContext context) {
    final added = controller.counts['added'];
    final review = controller.counts['possible_match'] ?? 0;
    final withId = leads.where((l) => leadIdOf(l) != null).length;
    final withoutId = leads.length - withId;
    final parts = <String>[
      if (added != null) '${formatCount(added)} in CRM',
      if (review > 0) '${formatCount(review)} to review',
      if (withoutId > 0) "${formatCount(withoutId)} not saved yet (can't be added)",
    ];
    final allAdded = added != null && withId > 0 && added >= withId;
    return SearchCard(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const ExcludeSemantics(child: Icon(Icons.view_kanban_outlined, size: 18, color: UiTokens.accent)),
              const Text('CRM', style: TextStyle(color: UiTokens.text, fontWeight: FontWeight.w700)),
              if (parts.isNotEmpty)
                Semantics(
                  liveRegion: true,
                  child: Text(parts.join(' · '), style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13.5)),
                ),
              OutlinedButton.icon(
                style: searchSecondaryButtonStyle(),
                onPressed: controller.busy || withId == 0 || allAdded ? null : () => controller.addAll(context),
                icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                label: Text(allAdded ? 'All leads are in CRM' : 'Add all to CRM',
                    semanticsLabel: allAdded ? 'All saved leads are in your CRM' : 'Add all saved leads of this search to CRM'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                onPressed: () => AppNav.go(context, crmSearchRoute(controller.jobId)),
                child: const Text('View this search in CRM'),
              ),
            ],
          ),
          if (controller.progress != null) ...[
            const SizedBox(height: 6),
            Semantics(
              liveRegion: true,
              child: Text(controller.progress!, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
            ),
            const SizedBox(height: 4),
            const LinearProgressIndicator(minHeight: 4),
          ],
        ],
      ),
    );
  }
}

/// While a search runs: add the leads saved so far (resumable "all"
/// import; rows not saved yet are simply not included).
class CrmRunningSearchCard extends StatefulWidget {
  final String jobId;
  final CrmApi api;
  final int savedLeads;

  const CrmRunningSearchCard({super.key, required this.jobId, required this.api, required this.savedLeads});

  @override
  State<CrmRunningSearchCard> createState() => _CrmRunningSearchCardState();
}

class _CrmRunningSearchCardState extends State<CrmRunningSearchCard> {
  late final CrmResultsController _c = CrmResultsController(jobId: widget.jobId, api: widget.api)
    ..addListener(_changed);

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SearchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('CRM', style: TextStyle(color: UiTokens.text, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'You can add the leads saved so far to your CRM now. Adding does not change the search; '
            'add again later for the rest.',
            style: TextStyle(color: UiTokens.textSecondary, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              style: searchSecondaryButtonStyle(),
              onPressed: _c.busy || widget.savedLeads == 0 ? null : () => _c.addAll(context),
              icon: const Icon(Icons.playlist_add_rounded, size: 18),
              label: Text('Add ${plural(widget.savedLeads, 'saved lead', 'saved leads')} to CRM'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
              onPressed: () => AppNav.go(context, crmSearchRoute(widget.jobId)),
              child: const Text('View this search in CRM'),
            ),
          ]),
          if (_c.progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_c.progress!, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
