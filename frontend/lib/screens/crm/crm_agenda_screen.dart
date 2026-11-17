import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/crm/crm_filters.dart';
import '../../core/crm/crm_format.dart';
import '../../providers/crm_provider.dart';
import '../../services/crm_api.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/crm/crm_record_dialogs.dart';
import '../../widgets/crm/crm_widgets.dart';

/// Activities agenda (`/crm/activities?bucket=`): Overdue / Today /
/// Upcoming / Done. "Today" is computed by the server in the viewer's UTC
/// offset (`tz_offset_minutes`).
class CrmAgendaScreen extends StatefulWidget {
  final Map<String, String> initialQuery;
  final CrmApi? api;

  /// Offset sent to the server (tests); default: this device's offset.
  final int? tzOffsetMinutes;

  const CrmAgendaScreen({super.key, this.initialQuery = const {}, this.api, this.tzOffsetMinutes});

  @override
  State<CrmAgendaScreen> createState() => _CrmAgendaScreenState();
}

class _CrmAgendaScreenState extends State<CrmAgendaScreen> {
  late final CrmApi _api = crmApiOf(context, widget.api);
  late String _bucket = crmAgendaBuckets.contains(widget.initialQuery['bucket']) ? widget.initialQuery['bucket']! : 'today';
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  List<Map<String, dynamic>> _items = const [];
  String? _cursor;
  Map<String, int> _counts = const {};
  final Set<String> _busy = {};
  int _generation = 0;

  int get _tz => widget.tzOffsetMinutes ?? localTzOffsetMinutes();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_generation;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    unawaited(_loadCounts());
    try {
      final page = await _api.getAgenda(bucket: _bucket, tzOffsetMinutes: _tz);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items;
        _cursor = page.nextCursor;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _loadCounts() async {
    try {
      final c = await _api.getAgendaCounts(tzOffsetMinutes: _tz);
      if (!mounted) return;
      setState(() => _counts = c);
      context.read<CrmProvider?>()?.setCounts(c);
    } catch (_) {
      // Tabs simply show no counts.
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _cursor == null) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.getAgenda(bucket: _bucket, tzOffsetMinutes: _tz, cursor: _cursor);
      if (!mounted || generation != _generation) return;
      setState(() {
        final seen = {for (final a in _items) crmStr(a['id'])};
        _items = [..._items, ...page.items.where((a) => !seen.contains(crmStr(a['id'])))];
        _cursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showSearchSnack(context, crmActionError('Loading more activities', e), error: true);
    }
  }

  void _select(String bucket) {
    if (bucket == _bucket) return;
    setState(() => _bucket = bucket);
    crmReplaceUrl(crmRoute('/crm/activities', bucket == 'today' ? const {} : {'bucket': bucket}));
    _load();
  }

  Future<void> _act(Map<String, dynamic> a, Future<Object?> Function() call, String what, String done) async {
    final id = crmStr(a['id']);
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try {
      await call();
      if (!mounted) return;
      showSearchSnack(context, done);
      await _load(silent: true);
    } catch (e) {
      if (mounted) showSearchSnack(context, crmActionError(what, e), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _done(Map<String, dynamic> a) async {
    final outcome = await showCrmDoneDialog(context, a);
    if (outcome == null || !mounted) return;
    await _act(a, () => _api.completeActivity(crmStr(a['id']), outcome: outcome), 'Marking done', 'Activity done.');
  }

  Future<void> _openRecord(Map<String, dynamic> a) async {
    final id = _recordId(a);
    if (id.isEmpty) return;
    await Navigator.of(context).pushNamed(crmRecordRoute(id));
    if (mounted) {
      crmReplaceUrl(crmRoute('/crm/activities', _bucket == 'today' ? const {} : {'bucket': _bucket}));
      unawaited(_load(silent: true));
    }
  }

  static String _recordId(Map<String, dynamic> a) {
    final r = a['record'];
    return r is Map ? crmStr(r['id']) : crmStr(a['record_id']);
  }

  static String _recordTitle(Map<String, dynamic> a) {
    final r = a['record'];
    final t = r is Map ? crmStr(r['title']) : crmStr(a['record_title']);
    return t.isEmpty ? 'Record' : t;
  }

  @override
  Widget build(BuildContext context) {
    return CrmPageBody(
      tab: CrmTab.activities,
      child: LayoutBuilder(builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: () => _load(silent: true),
          child: ListView(
            padding: crmPagePadding(constraints.maxWidth),
            children: [
              CrmContent(
                maxWidth: 960,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [_tabs(), const SizedBox(height: 12), _body()],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _tabs() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final b in crmAgendaBuckets)
          ChoiceChip(
            label: Text(
              _counts[b] == null ? crmAgendaBucketLabel(b) : '${crmAgendaBucketLabel(b)} (${formatCount(_counts[b]!)})',
              style: TextStyle(
                color: b == _bucket ? UiTokens.text : UiTokens.textSecondary,
                fontWeight: b == _bucket ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            avatar: b == 'overdue' && (_counts['overdue'] ?? 0) > 0
                ? const Icon(Icons.warning_amber_rounded, size: 16, color: UiTokens.failedFg)
                : null,
            selected: b == _bucket,
            showCheckmark: b != 'overdue' || (_counts['overdue'] ?? 0) == 0,
            checkmarkColor: UiTokens.accent,
            selectedColor: UiTokens.selectedSurface,
            backgroundColor: UiTokens.card,
            side: BorderSide(color: b == _bucket ? UiTokens.accent : UiTokens.border),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) => _select(b),
          ),
      ],
    );
  }

  String get _emptyText {
    switch (_bucket) {
      case 'overdue':
        return 'Nothing overdue. Well done.';
      case 'upcoming':
        return 'No upcoming activities. Schedule follow-ups from a record.';
      case 'done':
        return 'No completed activities yet.';
      default:
        return 'Nothing due today.';
    }
  }

  Widget _body() {
    if (_loading && _items.isEmpty) return const CrmLoading(label: 'Loading activities…');
    if (_error != null) return CrmErrorView(error: _error, onRetry: _load, what: 'your activities');
    if (_items.isEmpty) {
      final noNext = _counts['no_next_activity'] ?? 0;
      return CrmEmptyView(
        title: _emptyText,
        icon: Icons.event_available_outlined,
        body: noNext > 0 ? '${plural(noNext, 'open record has', 'open records have')} no next activity.' : null,
        actions: [
          if (noNext > 0)
            OutlinedButton(
              style: searchSecondaryButtonStyle(),
              onPressed: () => AppNav.go(context, const CrmRecordFilters(due: 'none').toRoute()),
              child: const Text('Show records without a next activity'),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final a in _items) _tile(a),
        if (_cursor != null)
          Center(
            child: _loadingMore
                ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                : OutlinedButton(style: searchSecondaryButtonStyle(), onPressed: _loadMore, child: const Text('Load more')),
          ),
      ],
    );
  }

  Widget _tile(Map<String, dynamic> a) {
    final done = crmActivityDone(a);
    final busy = _busy.contains(crmStr(a['id']));
    final subject = crmStr(a['subject']);
    final title = _recordTitle(a);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SearchCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 8),
                  child: ExcludeSemantics(child: Icon(crmActivityIcon(a['type']), size: 18, color: UiTokens.textSecondary)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${crmActivityTypeLabel(a['type'])}: $subject',
                          style: const TextStyle(color: UiTokens.text, fontSize: 14.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      CrmDueBadge(activity: a),
                    ],
                  ),
                ),
              ],
            ),
            Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                onPressed: () => _openRecord(a),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(title, semanticsLabel: 'Open record $title'),
              ),
              if (!done)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                  onPressed: busy ? null : () => _done(a),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text('Mark done', semanticsLabel: 'Mark done: $subject'),
                )
              else
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                  onPressed: busy
                      ? null
                      : () => _act(a, () => _api.reopenActivity(crmStr(a['id'])), 'Reopening', 'Activity reopened.'),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: Text('Reopen', semanticsLabel: 'Reopen: $subject'),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}
