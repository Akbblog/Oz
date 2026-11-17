import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/error_handler.dart';
import '../core/utils/refresh_bus.dart';
import '../core/utils/server_time.dart';
import '../providers/active_searches_provider.dart';
import '../providers/scraper_provider.dart';
import '../providers/search_setup_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/search_actions.dart';

/// Status tabs of My searches (`status` query of GET /api/jobs).
enum SearchTab { all, running, completed, cancelled, failed }

extension SearchTabX on SearchTab {
  String get label {
    switch (this) {
      case SearchTab.all:
        return 'All';
      case SearchTab.running:
        return 'Running';
      case SearchTab.completed:
        return 'Completed';
      case SearchTab.cancelled:
        return 'Cancelled';
      case SearchTab.failed:
        return 'Failed';
    }
  }

  /// API filter value (`active` = queued + running).
  String get apiStatus => this == SearchTab.running ? 'active' : name;
}

enum SearchDateFilter { all, today, last7Days, thisMonth }

enum SearchSort { newest, oldest, mostLeads }

String searchDateFilterLabel(SearchDateFilter f) {
  switch (f) {
    case SearchDateFilter.all:
      return 'All dates';
    case SearchDateFilter.today:
      return 'Today';
    case SearchDateFilter.last7Days:
      return 'Last 7 days';
    case SearchDateFilter.thisMonth:
      return 'This month';
  }
}

String searchSortLabel(SearchSort s) {
  switch (s) {
    case SearchSort.newest:
      return 'Newest';
    case SearchSort.oldest:
      return 'Oldest';
    case SearchSort.mostLeads:
      return 'Most leads';
  }
}

/// True when [job] matches a free-text query (business type, city, region,
/// country or ID).
bool searchMatchesQuery(Map<String, dynamic> job, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final hay = [
    job['category'],
    job['job_id'],
    job['region'],
    job['country'],
    ...jobCities(job),
  ].map((v) => '${v ?? ''}'.toLowerCase()).join(' | ');
  return hay.contains(q);
}

bool searchMatchesDate(Map<String, dynamic> job, SearchDateFilter f, {DateTime? now}) {
  if (f == SearchDateFilter.all) return true;
  final created = parseServerTimeLocal(job['created_at']);
  if (created == null) return false;
  final n = (now ?? DateTime.now()).toLocal();
  final today = DateTime(n.year, n.month, n.day);
  switch (f) {
    case SearchDateFilter.today:
      return !created.isBefore(today);
    case SearchDateFilter.last7Days:
      return !created.isBefore(today.subtract(const Duration(days: 6)));
    case SearchDateFilter.thisMonth:
      return !created.isBefore(DateTime(n.year, n.month));
    case SearchDateFilter.all:
      return true;
  }
}

/// My searches (`/searches`): status tabs with counts, server pagination
/// (20 per page), search, date filter and sort, table on desktop and cards
/// below, and per-search actions. Page body only (inside [AppShell]).
class MySearchesScreen extends StatefulWidget {
  final ApiService? api;

  const MySearchesScreen({super.key, this.api});

  @override
  State<MySearchesScreen> createState() => _MySearchesScreenState();
}

class _MySearchesScreenState extends State<MySearchesScreen> with SingleTickerProviderStateMixin {
  static const int pageSize = 20;

  late final ApiService _api = widget.api ?? ApiService();
  late final TabController _tabs = TabController(length: SearchTab.values.length, vsync: this);
  final TextEditingController _queryController = TextEditingController();
  Timer? _queryDebounce;

  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _jobs = const [];
  int _total = 0;
  Map<String, int> _counts = const {};
  int _page = 0;
  int _generation = 0;
  int _lastActiveCount = -1;
  int _loadedTabIndex = 0;

  String _query = '';
  SearchDateFilter _date = SearchDateFilter.all;
  SearchSort _sort = SearchSort.newest;
  final Set<String> _busy = <String>{};

  SearchTab get _tab => SearchTab.values[_tabs.index];

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      // React once per change of tab (tap, keyboard or programmatic).
      if (_tabs.index == _loadedTabIndex) return;
      _loadedTabIndex = _tabs.index;
      setState(() => _page = 0);
      _load();
    });
    RefreshBus.jobsChanged.addListener(_onJobsChanged);
    _load();
  }

  @override
  void dispose() {
    RefreshBus.jobsChanged.removeListener(_onJobsChanged);
    _queryDebounce?.cancel();
    _queryController.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onJobsChanged() {
    if (mounted) _load(silent: true);
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
      final searching = _query.trim().isNotEmpty;
      // With a query, every search of the tab is fetched and filtered here
      // (the API has no text search); otherwise one page of 20.
      final page = await _api.getJobs(
        limit: searching ? null : pageSize,
        offset: searching ? null : _page * pageSize,
        status: _tab.apiStatus,
      );
      if (!mounted || generation != _generation) return;
      final jobs = List<Map<String, dynamic>>.from(page['jobs'] as List);
      final counts = Map<String, int>.from(page['counts'] as Map? ?? const <String, int>{});
      setState(() {
        _jobs = jobs;
        _total = (page['total'] as num?)?.toInt() ?? jobs.length;
        if (counts.isNotEmpty) _counts = counts;
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

  void _onQueryChanged(String value) {
    _queryDebounce?.cancel();
    _queryDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final wasSearching = _query.trim().isNotEmpty;
      setState(() {
        _query = value;
        _page = 0;
      });
      // Starting or ending a search changes what is fetched (every search
      // vs one page); refining a query only filters what is loaded.
      if (wasSearching != value.trim().isNotEmpty) _load();
    });
  }

  bool get _filtersActive =>
      _query.trim().isNotEmpty || _date != SearchDateFilter.all || _tab != SearchTab.all;

  void _clearFilters() {
    _queryDebounce?.cancel();
    _queryController.clear();
    setState(() {
      _query = '';
      _date = SearchDateFilter.all;
      _sort = SearchSort.newest;
      _page = 0;
    });
    if (_tabs.index != 0) {
      _tabs.index = 0; // the listener reloads
    } else {
      _load();
    }
  }

  /// The loaded set after the client-side query, date filter and sort.
  List<Map<String, dynamic>> get _shown {
    final out = _jobs
        .where((j) => searchMatchesQuery(j, _query) && searchMatchesDate(j, _date))
        .toList();
    int created(Map<String, dynamic> j) =>
        parseServerTime(j['created_at'])?.millisecondsSinceEpoch ?? 0;
    switch (_sort) {
      case SearchSort.newest:
        out.sort((a, b) => created(b).compareTo(created(a)));
        break;
      case SearchSort.oldest:
        out.sort((a, b) => created(a).compareTo(created(b)));
        break;
      case SearchSort.mostLeads:
        out.sort((a, b) => jobInt(b, 'result_count').compareTo(jobInt(a, 'result_count')));
        break;
    }
    return out;
  }

  int? _countFor(SearchTab t) {
    if (_counts.isEmpty) return null;
    switch (t) {
      case SearchTab.all:
        return _counts['all'];
      case SearchTab.running:
        return _counts['active'];
      case SearchTab.completed:
        return _counts['completed'];
      case SearchTab.cancelled:
        return _counts['cancelled'];
      case SearchTab.failed:
        return _counts['failed'];
    }
  }

  // ------------------------------------------------------------- actions

  void _open(Map<String, dynamic> job) => Navigator.of(context).pushNamed('/searches/${job['job_id']}');

  void _runAgain(Map<String, dynamic> job) {
    context.read<SearchSetupProvider>().loadFromJob(job);
    Navigator.of(context).pushNamed('/find/details');
  }

  Future<void> _download(Map<String, dynamic> job) async {
    final id = '${job['job_id']}';
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    await downloadSearchExcel(context, _api, id);
    if (mounted) setState(() => _busy.remove(id));
  }

  Future<void> _cancel(Map<String, dynamic> job) async {
    final id = '${job['job_id']}';
    final ok = await confirmCancelSearch(context);
    if (!ok || !mounted) return;
    setState(() => _busy.add(id));
    final scraper = context.read<ScraperProvider>();
    final active = context.read<ActiveSearchesProvider>();
    try {
      if (scraper.currentJob?.jobId == id) {
        await scraper.cancelCurrentJob();
      } else {
        await _api.cancelJob(id);
      }
      if (!mounted) return;
      showSearchSnack(context, 'Stopping after the current business. Leads found so far are kept.');
      unawaited(active.refresh());
      unawaited(_load(silent: true));
    } catch (e) {
      if (mounted) {
        showSearchSnack(context, "We couldn't cancel the search: ${ErrorHandler.getUserFriendlyMessage(e)}",
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _delete(Map<String, dynamic> job) async {
    final id = '${job['job_id']}';
    final ok = await confirmDeleteSearch(context, jobInt(job, 'result_count'));
    if (!ok || !mounted) return;
    setState(() => _busy.add(id));
    final scraper = context.read<ScraperProvider>();
    try {
      await _api.deleteJob(id);
      if (!mounted) return;
      if (scraper.currentJob?.jobId == id) scraper.reset();
      showSearchSnack(context, 'Search deleted');
      // Stay on a page that still exists.
      if (_jobs.length == 1 && _page > 0) _page--;
      await _load(silent: true);
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException && e.statusCode == 409
          ? 'This search is still running. Cancel it first, then delete it.'
          : "We couldn't delete the search: ${ErrorHandler.getUserFriendlyMessage(e)}";
      showSearchSnack(context, msg, error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  void _onMenu(String action, Map<String, dynamic> job) {
    switch (action) {
      case 'open':
        _open(job);
        break;
      case 'download':
        _download(job);
        break;
      case 'again':
        _runAgain(job);
        break;
      case 'copy-id':
        copyWithSnack(context, '${job['job_id']}', message: 'Search ID copied');
        break;
      case 'cancel':
        _cancel(job);
        break;
      case 'delete':
        _delete(job);
        break;
    }
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final active = context.watch<ActiveSearchesProvider>();
    // A search started or finished elsewhere: refresh the list and counts.
    if (_lastActiveCount != -1 && _lastActiveCount != active.count) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(silent: true);
      });
    }
    _lastActiveCount = active.count;

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final phone = width < 600;
      final pad = phone ? 16.0 : 24.0;
      final table = MediaQuery.sizeOf(context).width >= 1024;
      final shown = _shown;

      return RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: ListView(
          padding: EdgeInsets.all(pad),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTabs(),
                    const SizedBox(height: 12),
                    _buildFilters(phone),
                    const SizedBox(height: 12),
                    _buildBody(shown, table),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildTabs() {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: UiTokens.border))),
      child: TabBar(
        controller: _tabs,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: UiTokens.text,
        unselectedLabelColor: UiTokens.textSecondary,
        indicatorColor: UiTokens.accent,
        indicatorWeight: 3,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        tabs: [
          for (final t in SearchTab.values)
            Tab(
              height: 48,
              text: _countFor(t) == null ? t.label : '${t.label} (${formatCount(_countFor(t)!)})',
            ),
        ],
      ),
    );
  }

  Widget _buildFilters(bool phone) {
    final field = TextField(
      controller: _queryController,
      textInputAction: TextInputAction.search,
      onChanged: _onQueryChanged,
      onSubmitted: (v) {
        _queryDebounce?.cancel();
        setState(() {
          _query = v;
          _page = 0;
        });
        _load();
      },
      style: const TextStyle(color: UiTokens.text, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search by business type, city or ID',
        hintStyle: const TextStyle(color: UiTokens.textMuted),
        helperText: 'Searching looks through all your searches. Date and sort apply to the searches listed.',
        helperMaxLines: 2,
        helperStyle: const TextStyle(color: UiTokens.textMuted, fontSize: 12),
        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: UiTokens.textMuted),
        suffixIcon: _queryController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 18, color: UiTokens.textMuted),
                onPressed: () {
                  _queryController.clear();
                  _queryDebounce?.cancel();
                  setState(() {
                    _query = '';
                    _page = 0;
                  });
                  _load();
                },
              ),
        filled: true,
        fillColor: UiTokens.card,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: UiTokens.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: UiTokens.border)),
      ),
    );

    final dateMenu = _menu<SearchDateFilter>(
      tooltip: 'Filter by date',
      icon: Icons.event_rounded,
      label: searchDateFilterLabel(_date),
      value: _date,
      values: SearchDateFilter.values,
      labelOf: searchDateFilterLabel,
      onSelected: (v) => setState(() => _date = v),
    );
    final sortMenu = _menu<SearchSort>(
      tooltip: 'Sort searches',
      icon: Icons.sort_rounded,
      label: 'Sort: ${searchSortLabel(_sort)}',
      value: _sort,
      values: SearchSort.values,
      labelOf: searchSortLabel,
      onSelected: (v) => setState(() => _sort = v),
    );
    final refresh = IconButton(
      tooltip: 'Refresh',
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      onPressed: _loading ? null : () => _load(silent: true),
      icon: const Icon(Icons.refresh_rounded, color: UiTokens.textSecondary),
    );

    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [dateMenu, sortMenu, refresh]),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        dateMenu,
        const SizedBox(width: 8),
        sortMenu,
        const SizedBox(width: 4),
        refresh,
      ],
    );
  }

  Widget _menu<T>({
    required String tooltip,
    required IconData icon,
    required String label,
    required T value,
    required List<T> values,
    required String Function(T) labelOf,
    required ValueChanged<T> onSelected,
  }) {
    return PopupMenuButton<T>(
      tooltip: tooltip,
      color: UiTokens.card,
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final v in values) CheckedPopupMenuItem<T>(value: v, checked: v == value, child: Text(labelOf(v))),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: UiTokens.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: UiTokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: UiTokens.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: UiTokens.text, fontSize: 14, fontWeight: FontWeight.w600)),
            const Icon(Icons.arrow_drop_down_rounded, color: UiTokens.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> shown, bool table) {
    if (_loading && _jobs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return SearchCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ErrorHandler.isAuthError(_error)
                  ? "You've been signed out. Sign in again to see your searches."
                  : "We couldn't load your searches. Your data is safe.",
              style: const TextStyle(color: UiTokens.text, fontSize: 15),
            ),
            const SizedBox(height: 12),
            OutlinedButton(style: searchSecondaryButtonStyle(), onPressed: () => _load(), child: const Text('Try again')),
          ],
        ),
      );
    }
    final noSearchesAtAll = (_countFor(SearchTab.all) ?? (_tab == SearchTab.all && _query.trim().isEmpty ? _total : 1)) == 0;
    if (noSearchesAtAll) {
      return SearchCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('No searches yet',
                style: TextStyle(color: UiTokens.text, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Find businesses in the cities you choose. Your searches will be listed here.',
                style: TextStyle(color: UiTokens.textSecondary, fontSize: 14)),
            const SizedBox(height: 14),
            FilledButton(
              style: searchPrimaryButtonStyle(),
              onPressed: () => AppNav.go(context, '/find'),
              child: const Text('Find leads'),
            ),
          ],
        ),
      );
    }
    if (shown.isEmpty) {
      return SearchCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('No searches match these filters.',
                style: TextStyle(color: UiTokens.text, fontSize: 15, fontWeight: FontWeight.w600)),
            if (_filtersActive) ...[
              const SizedBox(height: 12),
              OutlinedButton(style: searchSecondaryButtonStyle(), onPressed: _clearFilters, child: const Text('Clear filters')),
            ],
          ],
        ),
      );
    }

    final list = table
        ? _SearchesTable(jobs: shown, busy: _busy, onOpen: _open, onMenu: _onMenu)
        : Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: UiTokens.border),
                _SearchRow(job: shown[i], busy: _busy.contains('${shown[i]['job_id']}'), onOpen: _open, onMenu: _onMenu),
              ],
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchCard(padding: EdgeInsets.symmetric(horizontal: table ? 12 : 16, vertical: 4), child: list),
        const SizedBox(height: 12),
        _buildPager(shown.length),
      ],
    );
  }

  Widget _buildPager(int shownCount) {
    if (_query.trim().isNotEmpty) {
      return Text(
        '${plural(shownCount, 'search matches', 'searches match')} "${_query.trim()}".',
        style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13),
      );
    }
    final pages = (_total / pageSize).ceil();
    final from = _total == 0 ? 0 : _page * pageSize + 1;
    final to = (_page * pageSize + _jobs.length).clamp(0, _total);
    final summary = Text(
      'Showing $from–$to of ${formatCount(_total)}'
      '${shownCount != _jobs.length ? ' · ${formatCount(shownCount)} match the date filter' : ''}',
      style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13),
    );
    if (pages <= 1) return summary;
    final style = TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(44, 44));
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        summary,
        TextButton.icon(
          style: style,
          onPressed: _page > 0 && !_loading
              ? () {
                  setState(() => _page--);
                  _load();
                }
              : null,
          icon: const Icon(Icons.chevron_left_rounded),
          label: const Text('Previous'),
        ),
        Text('Page ${_page + 1} of $pages', style: const TextStyle(color: UiTokens.text, fontSize: 13)),
        TextButton.icon(
          style: style,
          onPressed: _page < pages - 1 && !_loading
              ? () {
                  setState(() => _page++);
                  _load();
                }
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
          label: const Text('Next'),
        ),
      ],
    );
  }
}

List<PopupMenuEntry<String>> _menuItems(Map<String, dynamic> job) {
  final leads = jobInt(job, 'result_count');
  final activeJob = jobIsActive(job);
  return [
    const PopupMenuItem(value: 'open', child: Text('Open')),
    if (leads > 0 && jobIsTerminal(job)) const PopupMenuItem(value: 'download', child: Text('Download Excel')),
    const PopupMenuItem(value: 'again', child: Text('Run again')),
    const PopupMenuItem(value: 'copy-id', child: Text('Copy ID')),
    if (activeJob)
      const PopupMenuItem(value: 'cancel', child: Text('Cancel…', style: TextStyle(color: UiTokens.failedFg))),
    if (jobIsTerminal(job))
      const PopupMenuItem(value: 'delete', child: Text('Delete…', style: TextStyle(color: UiTokens.failedFg))),
  ];
}

class _RowMenu extends StatelessWidget {
  final Map<String, dynamic> job;
  final bool busy;
  final void Function(String action, Map<String, dynamic> job) onMenu;

  const _RowMenu({required this.job, required this.busy, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'More actions for ${jobCategory(job)}',
      color: UiTokens.card,
      icon: const Icon(Icons.more_vert_rounded, color: UiTokens.textSecondary),
      onSelected: (v) => onMenu(v, job),
      itemBuilder: (_) => _menuItems(job),
    );
  }
}

class _CreditsCell extends StatelessWidget {
  final Map<String, dynamic> job;
  final TextAlign align;

  const _CreditsCell({required this.job, this.align = TextAlign.right});

  @override
  Widget build(BuildContext context) {
    final note = jobCreditsReturnedNote(job);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: jobCreditsUsedLabel(job)),
        if (note != null) TextSpan(text: ' $note', style: const TextStyle(color: UiTokens.textMuted, fontSize: 12)),
      ]),
      textAlign: align,
      style: const TextStyle(color: UiTokens.text, fontSize: 14),
    );
  }
}

ButtonStyle _rowButtonStyle() => OutlinedButton.styleFrom(
      foregroundColor: UiTokens.text,
      side: const BorderSide(color: UiTokens.border),
      minimumSize: const Size(44, 44),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

/// Desktop (≥1024 px) table.
class _SearchesTable extends StatelessWidget {
  final List<Map<String, dynamic>> jobs;
  final Set<String> busy;
  final void Function(Map<String, dynamic>) onOpen;
  final void Function(String, Map<String, dynamic>) onMenu;

  const _SearchesTable({required this.jobs, required this.busy, required this.onOpen, required this.onMenu});

  static const _head = TextStyle(color: UiTokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w600);

  Widget _cell(Widget child, {Alignment align = Alignment.centerLeft}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Align(alignment: align, child: child),
      );

  @override
  Widget build(BuildContext context) {
    const border = BoxDecoration(border: Border(bottom: BorderSide(color: UiTokens.border)));
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(2.1),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1.8),
        4: FlexColumnWidth(1.5),
        5: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: border,
          children: [
            _cell(const Text('Search', style: _head)),
            _cell(const Text('Status', style: _head)),
            _cell(const Text('Leads', style: _head), align: Alignment.centerRight),
            _cell(const Text('Credits used', style: _head), align: Alignment.centerRight),
            _cell(const Text('Date', style: _head)),
            _cell(const SizedBox.shrink()),
          ],
        ),
        for (final job in jobs)
          TableRow(
            decoration: border,
            children: [
              _cell(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(jobCategory(job),
                      style: const TextStyle(color: UiTokens.text, fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(jobCitiesSummary(job), style: const TextStyle(color: UiTokens.textSecondary, fontSize: 12)),
                ],
              )),
              _cell(SearchStatusBadge(job: job)),
              _cell(
                Text(jobLeadsLabel(job), textAlign: TextAlign.right, style: const TextStyle(color: UiTokens.text)),
                align: Alignment.centerRight,
              ),
              _cell(_CreditsCell(job: job), align: Alignment.centerRight),
              _cell(Text(formatServerDateTime(job['created_at']),
                  style: const TextStyle(color: UiTokens.text, fontSize: 14))),
              _cell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    style: _rowButtonStyle(),
                    onPressed: () => onOpen(job),
                    child: Text(jobActionLabel(job)),
                  ),
                  _RowMenu(job: job, busy: busy.contains('${job['job_id']}'), onMenu: onMenu),
                ],
              )),
            ],
          ),
      ],
    );
  }
}

/// Phone/tablet card row.
class _SearchRow extends StatelessWidget {
  final Map<String, dynamic> job;
  final bool busy;
  final void Function(Map<String, dynamic>) onOpen;
  final void Function(String, Map<String, dynamic>) onMenu;

  const _SearchRow({required this.job, required this.busy, required this.onOpen, required this.onMenu});

  @override
  Widget build(BuildContext context) {
    final leads = jobInt(job, 'result_count');
    final leadsText = jobIsActive(job)
        ? '${formatCount(leads)} ${leads == 1 ? 'lead' : 'leads'} so far'
        : plural(leads, 'lead', 'leads');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(jobCategory(job),
                    style: const TextStyle(color: UiTokens.text, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              const SizedBox(width: 8),
              Flexible(child: SearchStatusBadge(job: job)),
            ],
          ),
          const SizedBox(height: 2),
          Text(jobCitiesSummary(job), style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
          const SizedBox(height: 4),
          Text('$leadsText · ${formatServerDateTime(job['created_at'])}',
              style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
          const SizedBox(height: 2),
          Row(
            children: [
              const Text('Credits used: ', style: TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
              Expanded(child: _CreditsCell(job: job, align: TextAlign.left)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(style: _rowButtonStyle(), onPressed: () => onOpen(job), child: Text(jobActionLabel(job))),
              const Spacer(),
              _RowMenu(job: job, busy: busy, onMenu: onMenu),
            ],
          ),
        ],
      ),
    );
  }
}
