import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/crm/crm_filters.dart';
import '../../core/crm/crm_format.dart';
import '../../core/download_helper.dart';
import '../../providers/crm_provider.dart';
import '../../services/crm_api.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/crm/crm_new_record_dialog.dart';
import '../../widgets/crm/crm_record_card.dart';
import '../../widgets/crm/crm_widgets.dart';

/// All leads (`/crm/leads`): server-side search and filters (stage,
/// outcome, archived, type, tag, source search, follow-up due) and sort,
/// all in the URL; keyset "Load more"; CSV/XLSX export of the same filters.
class CrmLeadsScreen extends StatefulWidget {
  final Map<String, String> initialQuery;
  final CrmApi? api;

  /// Page size (tests use small pages).
  final int pageSize;

  const CrmLeadsScreen({super.key, this.initialQuery = const {}, this.api, this.pageSize = 50});

  @override
  State<CrmLeadsScreen> createState() => _CrmLeadsScreenState();
}

class _CrmLeadsScreenState extends State<CrmLeadsScreen> {
  late final CrmApi _api = crmApiOf(context, widget.api);
  late CrmRecordFilters _filters = CrmRecordFilters.fromQuery(widget.initialQuery);
  late final TextEditingController _query = TextEditingController(text: _filters.q ?? '');
  Timer? _debounce;

  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  List<Map<String, dynamic>> _items = const [];
  String? _cursor;
  int _total = 0;
  int _generation = 0;
  String? _exporting;
  final Set<String> _deleting = {};

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CrmProvider?>()?.loadWorkspace().catchError((_) => null);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.listRecords(_filters.toApiQuery(limit: widget.pageSize));
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items;
        _cursor = page.nextCursor;
        _total = page.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _cursor == null) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.listRecords(_filters.toApiQuery(limit: widget.pageSize, cursor: _cursor));
      if (!mounted || generation != _generation) return;
      setState(() {
        final seen = {for (final r in _items) crmStr(r['id'])};
        _items = [..._items, ...page.items.where((r) => !seen.contains(crmStr(r['id'])))];
        _cursor = page.nextCursor;
        _total = page.total;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      crmSnack(context, crmActionError('Loading more records', e), error: true);
    }
  }

  void _set(CrmRecordFilters f) {
    if (f == _filters) return;
    setState(() => _filters = f);
    crmReplaceUrl(f.toRoute());
    _load();
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _set(_filters.copyWith(q: () => v));
    });
  }

  Future<void> _open(Map<String, dynamic> r) async {
    await Navigator.of(context).pushNamed(crmRecordRoute(crmStr(r['id'])));
    if (!mounted) return;
    crmReplaceUrl(_filters.toRoute());
    unawaited(_load());
  }

  Future<void> _deleteRecord(Map<String, dynamic> record) async {
    final id = crmStr(record['id']);
    if (id.isEmpty || _deleting.contains(id)) return;
    final title = crmRecordTitle(record);
    final ok = await crmConfirm(context,
      title: 'Delete $title from CRM?',
      body: 'This permanently removes the CRM record, its notes and activities. '
          'The original search result stays available and can be added again.',
      confirmLabel: 'Delete record', danger: true);
    if (!ok || !mounted || _deleting.contains(id)) return;
    setState(() => _deleting.add(id));
    try {
      await _api.deleteRecord(id, version: crmIntOrNull(record['version']));
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      unawaited(context.read<CrmProvider?>()?.refreshCounts());
      crmSnack(context, '$title removed from CRM.');
    } catch (e) {
      if (!mounted) return;
      crmSnack(context, crmActionError('Deleting $title', e), error: true);
      if (crmErrorKind(e) == CrmErrorKind.conflict) unawaited(_load());
    } finally {
      if (mounted) setState(() => _deleting.remove(id));
    }
  }

  Future<void> _newLead() async {
    final stages = context.read<CrmProvider?>()?.stages ?? const <Map<String, dynamic>>[];
    final created = await showCrmNewRecordDialog(context, api: _api, stages: stages);
    if (created == null || !mounted) return;
    if (crmStr(created['id']).isNotEmpty) {
      await _open(created);
    } else {
      unawaited(_load());
    }
  }

  Future<void> _export(String format) async {
    if (_exporting != null) return;
    setState(() => _exporting = format);
    try {
      final data = await _api.exportRecords(format: format, filters: _filters.toApiQuery());
      if (!mounted) return;
      final name = crmStr(data['filename']).isEmpty ? 'crm_records_${fileTimestamp()}.$format' : crmStr(data['filename']);
      if (format == 'xlsx') {
        await saveExcel(crmStr(data['content']), name, context: context);
      } else {
        final text = utf8.decode(base64Decode(crmStr(data['content'])), allowMalformed: true);
        // saveCsv adds its own byte-order mark.
        final clean = text.codeUnits.isNotEmpty && text.codeUnitAt(0) == 0xFEFF ? text.substring(1) : text;
        final base = name.toLowerCase().endsWith('.csv') ? name.substring(0, name.length - 4) : name;
        await saveCsv(clean, base, context: context);
      }
    } catch (e) {
      if (mounted) crmSnack(context, crmActionError('The export', e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final crm = context.watch<CrmProvider?>();
    final stages = crm?.stages ?? const <Map<String, dynamic>>[];
    final tags = crm?.tags ?? const <Map<String, dynamic>>[];
    return CrmPageBody(
      tab: CrmTab.leads,
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: crmPagePadding(constraints.maxWidth),
            children: [
              CrmContent(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildFilters(stages, tags, phone: constraints.maxWidth < 600),
                    const SizedBox(height: 12),
                    _buildBody(wide),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildFilters(List<Map<String, dynamic>> stages, List<Map<String, dynamic>> tags, {required bool phone}) {
    String stageName(String id) =>
        crmStr(stages.firstWhere((s) => crmStr(s['id']) == id, orElse: () => {'name': 'Stage'})['name']);
    String tagName(String id) =>
        crmStr(tags.firstWhere((s) => crmStr(s['id']) == id, orElse: () => {'name': 'Tag'})['name']);

    final search = TextField(
      controller: _query,
      onChanged: _onQuery,
      onSubmitted: (v) {
        _debounce?.cancel();
        _set(_filters.copyWith(q: () => v));
      },
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: UiTokens.text, fontSize: 14),
      decoration: crmInputDecoration(
        'Search records',
        hint: 'Name, phone, email, website, tag or note',
        prefix: const Icon(Icons.search_rounded, size: 20, color: UiTokens.textMuted),
        suffix: _query.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 18, color: UiTokens.textMuted),
                onPressed: () {
                  _query.clear();
                  _set(_filters.copyWith(q: () => null));
                },
              ),
      ),
    );

    final menus = <Widget>[
      if (stages.isNotEmpty)
        CrmMenu<String>(
          tooltip: 'Filter by stage',
          icon: Icons.view_column_outlined,
          label: _filters.stageId == null ? 'All stages' : 'Stage: ${stageName(_filters.stageId!)}',
          value: _filters.stageId ?? '',
          values: ['', for (final s in stages) crmStr(s['id'])],
          labelOf: (v) => v.isEmpty ? 'All stages' : stageName(v),
          onSelected: (v) => _set(_filters.copyWith(stageId: () => v)),
        ),
      CrmMenu<String>(
        tooltip: 'Filter by outcome',
        icon: Icons.flag_outlined,
        label: crmOutcomeLabel(_filters.outcome),
        value: _filters.outcome,
        values: crmOutcomeValues,
        labelOf: crmOutcomeLabel,
        onSelected: (v) => _set(_filters.copyWith(outcome: v)),
      ),
      CrmMenu<String>(
        tooltip: 'Show archived records',
        icon: Icons.inventory_2_outlined,
        label: crmArchivedLabel(_filters.archived),
        value: _filters.archived,
        values: crmArchivedValues,
        labelOf: crmArchivedLabel,
        onSelected: (v) => _set(_filters.copyWith(archived: v)),
      ),
      CrmMenu<String>(
        tooltip: 'Filter by type',
        icon: Icons.category_outlined,
        label: crmTypeLabel(_filters.type),
        value: _filters.type,
        values: crmTypeValues,
        labelOf: crmTypeLabel,
        onSelected: (v) => _set(_filters.copyWith(type: v)),
      ),
      if (tags.isNotEmpty)
        CrmMenu<String>(
          tooltip: 'Filter by tag',
          icon: Icons.sell_outlined,
          label: _filters.tagId == null ? 'All tags' : 'Tag: ${tagName(_filters.tagId!)}',
          value: _filters.tagId ?? '',
          values: ['', for (final t in tags) crmStr(t['id'])],
          labelOf: (v) => v.isEmpty ? 'All tags' : tagName(v),
          onSelected: (v) => _set(_filters.copyWith(tagId: () => v)),
        ),
      CrmMenu<String>(
        tooltip: 'Filter by follow-up',
        icon: Icons.event_note_outlined,
        label: crmDueLabel(_filters.due),
        value: _filters.due,
        values: crmDueValues,
        labelOf: crmDueLabel,
        onSelected: (v) => _set(_filters.copyWith(due: v)),
      ),
      CrmMenu<String>(
        tooltip: 'Sort records',
        icon: Icons.sort_rounded,
        label: 'Sort: ${crmSortLabel(_filters.sort)}',
        value: _filters.sort,
        values: crmSortValues,
        labelOf: crmSortLabel,
        onSelected: (v) => _set(_filters.copyWith(sort: v)),
      ),
    ];

    final actions = <Widget>[
      FilledButton.icon(
        style: searchPrimaryButtonStyle(),
        onPressed: _newLead,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('New lead'),
      ),
      OutlinedButton.icon(
        style: searchSecondaryButtonStyle(),
        onPressed: _exporting != null || _items.isEmpty ? null : () => _export('csv'),
        icon: _exporting == 'csv'
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.download_rounded, size: 18),
        label: const Text('Export CSV', semanticsLabel: 'Export these records as CSV'),
      ),
      OutlinedButton.icon(
        style: searchSecondaryButtonStyle(),
        onPressed: _exporting != null || _items.isEmpty ? null : () => _export('xlsx'),
        icon: _exporting == 'xlsx'
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.table_view_rounded, size: 18),
        label: const Text('Export Excel', semanticsLabel: 'Export these records as Excel'),
      ),
      OutlinedButton.icon(
        style: searchSecondaryButtonStyle(),
        onPressed: () => AppNav.go(
            context, CrmPipelineFilters(q: _filters.q, tagId: _filters.tagId, sourceJobId: _filters.sourceJobId).toRoute()),
        icon: const Icon(Icons.view_kanban_outlined, size: 18),
        label: const Text('Board view'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        search,
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: menus),
        if (_filters.sourceJobId != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              InputChip(
                label: const Text('From one search'),
                avatar: const Icon(Icons.list_alt_rounded, size: 16),
                onDeleted: () => _set(_filters.copyWith(sourceJobId: () => null)),
                deleteButtonTooltipMessage: 'Show records from every search',
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                onPressed: () => AppNav.go(context, '/searches/${Uri.encodeComponent(_filters.sourceJobId!)}'),
                child: const Text('Open the search'),
              ),
            ]),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }

  Widget _buildBody(bool wide) {
    if (_loading && _items.isEmpty) return const CrmLoading(label: 'Loading records…');
    if (_error != null) return CrmErrorView(error: _error, onRetry: _load, what: 'your records');
    if (_items.isEmpty) {
      if (_filters.narrowed || _filters.q != null) {
        return CrmEmptyView(
          title: 'No records match these filters',
          icon: Icons.filter_alt_off_outlined,
          actions: [
            OutlinedButton(
              style: searchSecondaryButtonStyle(),
              onPressed: () {
                _query.clear();
                _set(const CrmRecordFilters());
              },
              child: const Text('Clear filters'),
            ),
          ],
        );
      }
      return CrmEmptyView(
        title: 'No records yet',
        body: 'Add businesses from one of your searches, or create a lead by hand.',
        actions: [
          FilledButton(
            style: searchPrimaryButtonStyle(),
            onPressed: () => AppNav.go(context, '/searches'),
            child: const Text('Add from a search'),
          ),
          OutlinedButton(style: searchSecondaryButtonStyle(), onPressed: _newLead, child: const Text('Create manually')),
        ],
      );
    }
    final rows = <Widget>[
      Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _items.length >= _total
                ? 'Showing ${plural(_items.length, 'record', 'records')}'
                : 'Showing ${formatCount(_items.length)} of ${plural(_total, 'record', 'records')}',
            style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13),
          ),
        ),
      ),
      if (wide) _tableHeader(),
      for (final r in _items)
        Padding(
          padding: EdgeInsets.only(bottom: wide ? 0 : 8),
          child: wide
              ? _TableRow(record: r, onOpen: () => _open(r))
              : CrmRecordCard(record: r, stages: const [], showStage: true,
                  busy: _deleting.contains(crmStr(r['id'])),
                  onOpen: () => _open(r), onDelete: () => _deleteRecord(r)),
        ),
      if (_cursor != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: _loadingMore
                ? const CircularProgressIndicator()
                : OutlinedButton(
                    style: searchSecondaryButtonStyle(),
                    onPressed: _loadMore,
                    child: const Text('Load more'),
                  ),
          ),
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Widget _tableHeader() {
    Widget h(String t, int flex) => Expanded(
          flex: flex,
          child: Text(t, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w700)),
        );
    return ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: UiTokens.border))),
        child: Row(children: [
          h('Business', 4),
          h('Contact', 3),
          h('Stage', 2),
          h('Type', 2),
          h('Next activity', 3),
          h('Sources', 1),
          h('Updated', 2),
        ]),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  final Map<String, dynamic> record;
  final VoidCallback onOpen;

  const _TableRow({required this.record, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final company = crmMap(record['company']);
    final hint = crmContactHint(company);
    final next = record['next_activity'] is Map ? crmMap(record['next_activity']) : null;
    final title = crmRecordTitle(record);
    final place = crmPlace(company);
    final stage = crmStageName(record);
    final outcome = crmStr(record['outcome']);
    final archived = record['archived'] == true;
    Widget cell(Widget child, int flex) => Expanded(flex: flex, child: Padding(padding: const EdgeInsets.only(right: 8), child: child));
    Text t(String s, {Color color = UiTokens.text, FontWeight weight = FontWeight.w400}) =>
        Text(s.isEmpty ? '—' : s, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 13, fontWeight: weight));

    return Semantics(
      button: true,
      label: 'Open $title${stage.isEmpty ? '' : ', $stage'}${place.isEmpty ? '' : ', $place'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: UiTokens.border))),
          child: Row(
            children: [
              cell(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  t(title, weight: FontWeight.w700),
                  if (place.isNotEmpty) Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 12.5)),
                ]),
                4,
              ),
              cell(t(hint?.text ?? '', color: UiTokens.textSecondary), 3),
              cell(
                Wrap(spacing: 4, runSpacing: 4, children: [
                  Text(stage.isEmpty ? '—' : stage, style: const TextStyle(color: UiTokens.text, fontSize: 13)),
                  if (outcome == 'won' || outcome == 'lost' || archived) CrmOutcomeBadge(record: record),
                ]),
                2,
              ),
              cell(t(crmTypeName(record['type']), color: UiTokens.textSecondary), 2),
              cell(next == null ? t('None', color: UiTokens.textMuted) : CrmDueBadge(activity: next), 3),
              cell(t(formatCount(crmInt(record['source_count'])), color: UiTokens.textSecondary), 1),
              cell(t(crmWhen(record['updated_at']), color: UiTokens.textSecondary), 2),
            ],
          ),
        ),
      ),
    );
  }
}
