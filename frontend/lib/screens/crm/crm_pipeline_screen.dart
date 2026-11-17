import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/crm/crm_filters.dart';
import '../../core/crm/crm_format.dart';
import '../../core/theme/app_breakpoints.dart';
import '../../providers/crm_provider.dart';
import '../../services/crm_api.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/crm/crm_new_record_dialog.dart';
import '../../widgets/crm/crm_record_card.dart';
import '../../widgets/crm/crm_widgets.dart';

/// One pipeline column (a stage with its first cards).
class CrmPipelineColumn {
  final Map<String, dynamic> stage;
  int count;
  List<Map<String, dynamic>> values;
  List<Map<String, dynamic>> items;
  String? cursor;
  bool loadingMore = false;

  CrmPipelineColumn({required this.stage, required this.count, required this.values, required this.items, this.cursor});

  String get id => crmStr(stage['id']);
  String get name => crmStr(stage['name']);
  bool get isWon => crmStr(stage['outcome_kind']) == 'won' || crmStr(stage['key']) == 'won';

  CrmPipelineColumn copy() => CrmPipelineColumn(
        stage: stage,
        count: count,
        values: [for (final v in values) Map<String, dynamic>.from(v)],
        items: List<Map<String, dynamic>>.from(items),
        cursor: cursor,
      );

  static List<CrmPipelineColumn> parse(Map<String, dynamic> data) {
    final out = <CrmPipelineColumn>[];
    for (final s in crmList(data['stages'])) {
      out.add(CrmPipelineColumn(
        stage: crmMap(s['stage']),
        count: crmInt(s['count']),
        values: crmList(s['values']),
        items: crmList(s['items']),
        cursor: crmStr(s['next_cursor']).isEmpty ? null : crmStr(s['next_cursor']),
      ));
    }
    out.sort((a, b) => crmInt(a.stage['position']).compareTo(crmInt(b.stage['position'])));
    return out;
  }

  /// Adds [delta] × the record's value to this column's total in its
  /// currency (no conversion; other currencies untouched).
  void addValue(Map<String, dynamic> record, int delta) {
    final v = crmNum(record['value']);
    final c = crmStr(record['currency']).toUpperCase();
    if (v == null || c.isEmpty) return;
    final i = values.indexWhere((e) => crmStr(e['currency']).toUpperCase() == c);
    if (i < 0) {
      if (delta > 0) values.add({'currency': c, 'total': v});
      return;
    }
    final total = (crmNum(values[i]['total']) ?? 0) + v * delta;
    values[i] = {'currency': c, 'total': total};
  }
}

/// CRM pipeline (`/crm`): Kanban with per-stage counts and per-currency
/// values on desktop (≥1024 px), drag and drop plus a "Move to stage" menu
/// on every card; a stage-chip filtered list on tablet and phone. Moves are
/// optimistic and roll back with a message when the save fails. Filters
/// (`q`, `tag`, `source`, `stage`) live in the URL.
class CrmPipelineScreen extends StatefulWidget {
  final Map<String, String> initialQuery;
  final CrmApi? api;

  const CrmPipelineScreen({super.key, this.initialQuery = const {}, this.api});

  @override
  State<CrmPipelineScreen> createState() => _CrmPipelineScreenState();
}

class _CrmPipelineScreenState extends State<CrmPipelineScreen> {
  late final CrmApi _api = crmApiOf(context, widget.api);
  late CrmPipelineFilters _filters = CrmPipelineFilters.fromQuery(widget.initialQuery);
  late final TextEditingController _query = TextEditingController(text: _filters.q ?? '');
  Timer? _debounce;

  bool _loading = true;
  Object? _error;
  List<CrmPipelineColumn> _columns = const [];
  Map<String, dynamic> _summary = const {};
  final Set<String> _busy = {};
  String? _dragOver;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _stages {
    final fromBoard = [for (final c in _columns) c.stage];
    if (fromBoard.isNotEmpty) return fromBoard;
    return context.read<CrmProvider?>()?.stages ?? const [];
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_generation;
    if (!silent || _error != null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _api.getPipeline(q: _filters.q, tagId: _filters.tagId, sourceJobId: _filters.sourceJobId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _columns = CrmPipelineColumn.parse(data);
        _summary = crmMap(data['summary']);
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

  void _setFilters(CrmPipelineFilters f, {bool reload = true}) {
    setState(() => _filters = f);
    crmReplaceUrl(f.toRoute());
    if (reload) _load();
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted || v.trim() == (_filters.q ?? '')) return;
      _setFilters(_filters.copyWith(q: () => v));
    });
  }

  Future<void> _open(Map<String, dynamic> record) async {
    await Navigator.of(context).pushNamed(crmRecordRoute(crmStr(record['id'])));
    if (!mounted) return;
    crmReplaceUrl(_filters.toRoute());
    unawaited(_load(silent: true));
    unawaited(context.read<CrmProvider?>()?.refreshCounts());
  }

  Future<void> _newLead() async {
    final created = await showCrmNewRecordDialog(context, api: _api, stages: _stages);
    if (created == null || !mounted) return;
    final id = crmStr(created['id']);
    if (id.isEmpty) {
      unawaited(_load(silent: true));
      return;
    }
    await _open(created);
  }

  CrmPipelineColumn? _columnOf(String recordId) {
    for (final c in _columns) {
      if (c.items.any((r) => crmStr(r['id']) == recordId)) return c;
    }
    return null;
  }

  /// Optimistic move with rollback.
  Future<void> _move(Map<String, dynamic> record, Map<String, dynamic> target) async {
    final id = crmStr(record['id']);
    final targetId = crmStr(target['id']);
    final from = _columnOf(id);
    if (from == null || from.id == targetId || _busy.contains(id)) return;
    final to = _columns.firstWhere((c) => c.id == targetId, orElse: () => from);
    if (identical(to, from)) return;
    final title = crmRecordTitle(record);
    final snapshot = [for (final c in _columns) c.copy()];
    final toWon = to.isWon;
    final optimistic = {
      ...record,
      'stage': {'id': to.id, 'key': to.stage['key'], 'name': to.name},
      'outcome': toWon ? 'won' : 'open',
    };

    setState(() {
      from.items.removeWhere((r) => crmStr(r['id']) == id);
      from.count = math.max(0, from.count - 1);
      from.addValue(record, -1);
      to.items.insert(0, optimistic);
      to.count += 1;
      to.addValue(record, 1);
      _busy.add(id);
    });

    try {
      final version = crmIntOrNull(record['version']);
      Map<String, dynamic> saved;
      if (toWon) {
        saved = await _api.markWon(id, version: version);
      } else if (crmStr(record['outcome']) != 'open' && crmStr(record['outcome']).isNotEmpty) {
        final reopened = await _api.reopen(id, version: version);
        saved = await _api.moveStage(id, targetId, version: crmIntOrNull(reopened['version']) ?? version);
      } else {
        saved = await _api.moveStage(id, targetId, version: version);
      }
      if (!mounted) return;
      setState(() {
        _busy.remove(id);
        if (crmStr(saved['id']) == id) {
          final i = to.items.indexWhere((r) => crmStr(r['id']) == id);
          if (i >= 0) to.items[i] = {...optimistic, ...saved, 'stage': saved['stage'] ?? optimistic['stage']};
        }
      });
      crmSnack(context, 'Moved $title to ${to.name}.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _columns = snapshot;
        _busy.remove(id);
      });
      final conflict = crmErrorKind(e) == CrmErrorKind.conflict;
      crmSnack(
        context,
        conflict
            ? '$title was changed elsewhere, so it was not moved. The pipeline has been reloaded.'
            : "$title couldn't be moved to ${to.name}: ${crmErrorText(e)} It is back in ${from.name}.",
        error: true,
      );
      if (conflict) unawaited(_load(silent: true));
    }
  }

  Future<void> _loadMore(CrmPipelineColumn column) async {
    if (column.loadingMore || column.cursor == null) return;
    setState(() => column.loadingMore = true);
    try {
      final page = await _api.listRecords({
        'stage_id': column.id,
        'outcome': column.isWon ? 'won' : 'open',
        'archived': 'false',
        if (_filters.q != null) 'q': _filters.q!,
        if (_filters.tagId != null) 'tag_id': _filters.tagId!,
        if (_filters.sourceJobId != null) 'source_job_id': _filters.sourceJobId!,
        'limit': '20',
        'cursor': column.cursor!,
      });
      if (!mounted) return;
      setState(() {
        final seen = {for (final r in column.items) crmStr(r['id'])};
        column.items = [...column.items, ...page.items.where((r) => !seen.contains(crmStr(r['id'])))];
        column.cursor = page.nextCursor;
        column.loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => column.loadingMore = false);
      crmSnack(context, crmActionError('Loading more cards', e), error: true);
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final kanban = MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;
    return CrmPageBody(
      tab: CrmTab.pipeline,
      child: LayoutBuilder(builder: (context, constraints) {
        final pad = crmPagePadding(constraints.maxWidth);
        final header = _buildHeader(constraints.maxWidth < 600);
        Widget? state;
        if (_loading && _columns.isEmpty) {
          state = const CrmLoading(label: 'Loading your pipeline…');
        } else if (_error != null) {
          state = CrmErrorView(error: _error, onRetry: _load, what: 'your pipeline');
        } else if (_columns.isEmpty || _columns.every((c) => c.count == 0 && c.items.isEmpty)) {
          state = _filters.narrowed
              ? CrmEmptyView(
                  title: 'No records match these filters',
                  icon: Icons.filter_alt_off_outlined,
                  actions: [
                    OutlinedButton(
                      style: searchSecondaryButtonStyle(),
                      onPressed: () {
                        _query.clear();
                        _setFilters(const CrmPipelineFilters());
                      },
                      child: const Text('Clear filters'),
                    ),
                  ],
                )
              : _emptyPipeline();
        }
        if (state != null || !kanban) {
          return RefreshIndicator(
            onRefresh: () => _load(silent: true),
            child: ListView(
              padding: pad,
              children: [
                CrmContent(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [header, const SizedBox(height: 12), state ?? _buildStageList()],
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [header, const SizedBox(height: 12), Expanded(child: _buildBoard())],
          ),
        );
      }),
    );
  }

  Widget _emptyPipeline() => CrmEmptyView(
        title: 'Your pipeline is empty',
        body: 'Add businesses from one of your searches, or create a lead by hand. '
            'Nothing is added to your CRM automatically.',
        icon: Icons.view_kanban_outlined,
        actions: [
          FilledButton.icon(
            style: searchPrimaryButtonStyle(),
            onPressed: () => AppNav.go(context, '/searches'),
            icon: const Icon(Icons.list_alt_rounded, size: 18),
            label: const Text('Add from a search'),
          ),
          OutlinedButton.icon(
            style: searchSecondaryButtonStyle(),
            onPressed: _newLead,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create manually'),
          ),
        ],
      );

  String _summaryText() {
    if (_summary.isEmpty) return '';
    final parts = <String>[
      '${formatCount(crmInt(_summary['open']))} open',
      '${formatCount(crmInt(_summary['due_today']))} due today',
      '${formatCount(crmInt(_summary['overdue']))} overdue',
      '${formatCount(crmInt(_summary['no_next_activity']))} with no next activity',
    ];
    return parts.join(' · ');
  }

  Widget _buildHeader(bool phone) {
    final tags = context.watch<CrmProvider?>()?.tags ?? const <Map<String, dynamic>>[];
    final tagName = _filters.tagId == null
        ? null
        : crmStr(tags.firstWhere((t) => crmStr(t['id']) == _filters.tagId, orElse: () => {'name': 'Tag'})['name']);
    final search = TextField(
      controller: _query,
      onChanged: _onQuery,
      onSubmitted: (v) {
        _debounce?.cancel();
        _setFilters(_filters.copyWith(q: () => v));
      },
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: UiTokens.text, fontSize: 14),
      decoration: crmInputDecoration(
        'Search the pipeline',
        hint: 'Name, phone, email, website, tag or note',
        prefix: const Icon(Icons.search_rounded, size: 20, color: UiTokens.textMuted),
        suffix: _query.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 18, color: UiTokens.textMuted),
                onPressed: () {
                  _query.clear();
                  _setFilters(_filters.copyWith(q: () => null));
                },
              ),
      ),
    );
    final newLead = FilledButton.icon(
      style: searchPrimaryButtonStyle(),
      onPressed: _newLead,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text('New lead'),
    );
    final listView = OutlinedButton.icon(
      style: searchSecondaryButtonStyle(),
      onPressed: () => AppNav.go(
        context,
        CrmRecordFilters(q: _filters.q, tagId: _filters.tagId, sourceJobId: _filters.sourceJobId).toRoute(),
      ),
      icon: const Icon(Icons.view_list_rounded, size: 18),
      label: const Text('List view'),
    );
    final tagMenu = tags.isEmpty
        ? null
        : CrmMenu<String>(
            tooltip: 'Filter by tag',
            icon: Icons.sell_outlined,
            label: tagName == null ? 'All tags' : 'Tag: $tagName',
            value: _filters.tagId ?? '',
            values: ['', for (final t in tags) crmStr(t['id'])],
            labelOf: (v) => v.isEmpty ? 'All tags' : crmStr(tags.firstWhere((t) => crmStr(t['id']) == v)['name']),
            onSelected: (v) => _setFilters(_filters.copyWith(tagId: () => v)),
          );
    final summary = _summaryText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (phone) ...[
          search,
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [newLead, listView, if (tagMenu != null) tagMenu]),
        ] else
          Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 8),
              if (tagMenu != null) ...[Flexible(child: tagMenu), const SizedBox(width: 8)],
              listView,
              const SizedBox(width: 8),
              newLead,
            ],
          ),
        if (_filters.sourceJobId != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                InputChip(
                  label: const Text('From one search'),
                  avatar: const Icon(Icons.list_alt_rounded, size: 16),
                  onDeleted: () => _setFilters(_filters.copyWith(sourceJobId: () => null)),
                  deleteButtonTooltipMessage: 'Show records from every search',
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                  onPressed: () => AppNav.go(context, '/searches/${Uri.encodeComponent(_filters.sourceJobId!)}'),
                  child: const Text('Open the search'),
                ),
              ],
            ),
          ),
        if (summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  liveRegion: true,
                  child: Text(summary, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13.5)),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 40)),
                  onPressed: () => AppNav.go(context, const CrmRecordFilters(outcome: 'lost').toRoute()),
                  child: const Text('Lost records'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _columnHeader(CrmPipelineColumn c) {
    final totals = crmCurrencyTotals(c.values);
    return Semantics(
      header: true,
      label: '${c.name}, ${plural(c.count, 'record', 'records')}${totals.isEmpty ? '' : ', $totals'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (c.isWon) const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.emoji_events_outlined, size: 16, color: UiTokens.completedFg),
                ),
                Expanded(
                  child: Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: UiTokens.text, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                CrmBadge(label: formatCount(c.count)),
              ],
            ),
            if (totals.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(totals, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _loadMoreButton(CrmPipelineColumn c) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Center(
          child: c.loadingMore
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                  onPressed: () => _loadMore(c),
                  child: Text('Load more (${formatCount(math.max(0, c.count - c.items.length))} more)',
                      semanticsLabel: 'Load more cards in ${c.name}'),
                ),
        ),
      );

  Widget _card(Map<String, dynamic> r, {bool showStage = false}) => CrmRecordCard(
        key: ValueKey('crm-card-${crmStr(r['id'])}'),
        record: r,
        stages: _stages,
        busy: _busy.contains(crmStr(r['id'])),
        showStage: showStage,
        onOpen: () => _open(r),
        onMove: (s) => _move(r, s),
      );

  Widget _buildBoard() {
    return LayoutBuilder(builder: (context, constraints) {
      const gap = 12.0;
      final n = _columns.length;
      final fit = (constraints.maxWidth - gap * (n - 1)) / n;
      final colWidth = math.max(248.0, fit);
      final scrolls = colWidth * n + gap * (n - 1) > constraints.maxWidth + 0.5;
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            SizedBox(width: colWidth, height: constraints.maxHeight, child: _buildColumn(_columns[i])),
          ],
        ],
      );
      if (!scrolls) return row;
      return Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: row),
      );
    });
  }

  Widget _buildColumn(CrmPipelineColumn c) {
    final highlight = _dragOver == c.id;
    return DragTarget<Map<String, dynamic>>(
      onWillAcceptWithDetails: (d) {
        final ok = _columnOf(crmStr(d.data['id']))?.id != c.id;
        if (ok && _dragOver != c.id) setState(() => _dragOver = c.id);
        return ok;
      },
      onLeave: (_) {
        if (_dragOver == c.id) setState(() => _dragOver = null);
      },
      onAcceptWithDetails: (d) {
        setState(() => _dragOver = null);
        _move(d.data, c.stage);
      },
      builder: (context, candidate, rejected) {
        return Container(
          key: ValueKey('crm-column-${c.id}'),
          decoration: BoxDecoration(
            color: highlight ? UiTokens.selectedSurface : const Color(0xFF1E1E21),
            borderRadius: BorderRadius.circular(UiTokens.radius),
            border: Border.all(color: highlight ? UiTokens.accent : UiTokens.border, width: highlight ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _columnHeader(c),
              const Divider(height: 1, color: UiTokens.border),
              Expanded(
                child: c.items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          c.count > 0 ? 'Cards are hidden by the filters.' : 'No records here yet. Drag a card here or use "Move to stage".',
                          style: const TextStyle(color: UiTokens.textMuted, fontSize: 12.5, height: 1.35),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: c.items.length + (c.cursor != null ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i >= c.items.length) return _loadMoreButton(c);
                          final r = c.items[i];
                          final card = _card(r);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Draggable<Map<String, dynamic>>(
                              data: r,
                              maxSimultaneousDrags: _busy.contains(crmStr(r['id'])) ? 0 : 1,
                              feedback: Material(
                                color: Colors.transparent,
                                child: SizedBox(width: 240, child: Opacity(opacity: 0.9, child: card)),
                              ),
                              childWhenDragging: Opacity(opacity: 0.35, child: card),
                              child: card,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Tablet/phone: stage chips + the chosen stage's cards.
  Widget _buildStageList() {
    final selected = _columns.firstWhere(
      (c) => c.id == _filters.stage || crmStr(c.stage['key']) == _filters.stage,
      orElse: () => _columns.first,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Stages',
          container: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _columns)
                ChoiceChip(
                  label: Text('${c.name} · ${formatCount(c.count)}',
                      style: TextStyle(
                          color: identical(c, selected) ? UiTokens.text : UiTokens.textSecondary,
                          fontWeight: identical(c, selected) ? FontWeight.w700 : FontWeight.w500)),
                  selected: identical(c, selected),
                  showCheckmark: true,
                  checkmarkColor: UiTokens.accent,
                  selectedColor: UiTokens.selectedSurface,
                  backgroundColor: UiTokens.card,
                  side: BorderSide(color: identical(c, selected) ? UiTokens.accent : UiTokens.border),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) => _setFilters(_filters.copyWith(stage: () => crmStr(c.stage['key']).isEmpty ? c.id : crmStr(c.stage['key'])), reload: false),
                ),
            ],
          ),
        ),
        if (crmCurrencyTotals(selected.values).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${selected.name}: ${crmCurrencyTotals(selected.values)}',
                style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
          ),
        const SizedBox(height: 12),
        if (selected.items.isEmpty)
          CrmEmptyView(
            title: selected.count > 0 ? 'No cards match the filters' : 'Nothing in ${selected.name} yet',
            body: selected.count > 0 ? null : 'Use "Move to stage" on a card in another stage to move it here.',
          )
        else ...[
          for (final r in selected.items) Padding(padding: const EdgeInsets.only(bottom: 8), child: _card(r)),
          if (selected.cursor != null) _loadMoreButton(selected),
        ],
      ],
    );
  }
}
