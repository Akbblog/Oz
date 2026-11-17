import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/download_helper.dart';
import '../core/error_handler.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/refresh_bus.dart';
import '../providers/scraper_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_shell_common.dart';
import '../widgets/infinity_data_table.dart';
import '../widgets/search_actions.dart';

/// Sort orders of the lead list. The API returns leads in the order they
/// were found; there is no other "newest" ordering.
enum LeadSort { original, name, category, city }

/// Contact filters ("Has phone", ...). None selected = every lead is shown.
enum LeadContact { phone, email, website, address }

bool _has(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s.isNotEmpty && s != 'N/A' && s != 'null';
}

bool leadHasContact(Map<String, dynamic> lead, LeadContact c) {
  switch (c) {
    case LeadContact.phone:
      return _has(lead['phone']);
    case LeadContact.email:
      return _has(lead['email']);
    case LeadContact.website:
      return _has(lead['website']);
    case LeadContact.address:
      return _has(lead['address']) || _has(lead['google_maps_url']);
  }
}

String leadName(Map<String, dynamic> lead) {
  final n = '${lead['business_name'] ?? lead['name'] ?? ''}'.trim();
  return n.isEmpty ? 'Unnamed business' : n;
}

String leadCityLabel(Map<String, dynamic> lead) {
  final city = '${lead['city'] ?? ''}'.trim();
  if (city.isEmpty || city == 'N/A') return '';
  final state = '${lead['state'] ?? ''}'.trim();
  return state.isEmpty || state == 'N/A' ? city : '$city, $state';
}

/// Stored Google Maps URL when it is a real http(s) link, else a maps search
/// for the business name and address.
Uri? leadMapsUri(Map<String, dynamic> lead) {
  final stored = '${lead['google_maps_url'] ?? ''}'.trim();
  if (stored.isNotEmpty) {
    final u = Uri.tryParse(stored);
    if (u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty) return u;
  }
  final address = '${lead['address'] ?? ''}'.trim();
  if (!_has(address)) return null;
  final name = leadName(lead);
  final q = name == 'Unnamed business' ? address : '$name, $address';
  return Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}');
}

/// The leads of a search: search, city filter, contact filters (off by
/// default), sort, cards or table (desktop), selection with CSV/JSON export
/// at every width, and per-lead actions (call, email, website, map, copy).
///
/// * `embedded: true` – body of the search page (`/searches/<id>`): no own
///   header; [leading] widgets scroll above the leads.
/// * otherwise a full page with a simple header (used by the admin screens).
class ResultsScreen extends StatefulWidget {
  final String? jobId;
  final List<Map<String, dynamic>>? overrideResults;
  final String? title;
  final bool showHeader;
  final bool embedded;
  final List<Widget> leading;

  /// Business type, used in export file names.
  final String? category;
  final ApiService? api;

  /// The caller is loading the leads and will pass them as
  /// [overrideResults]: show "Loading leads…" instead of fetching.
  final bool resultsPending;

  const ResultsScreen({
    super.key,
    this.jobId,
    this.overrideResults,
    this.title,
    this.showHeader = true,
    this.embedded = false,
    this.leading = const <Widget>[],
    this.category,
    this.api,
    this.resultsPending = false,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late final ApiService _api = widget.api ?? ApiService();

  bool _loading = false;
  Object? _error;
  List<Map<String, dynamic>> _all = const [];
  String? _loadedJobId;
  bool _downloading = false;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _city = '';
  final Set<LeadContact> _contacts = <LeadContact>{};
  bool _matchAll = false;
  LeadSort _sort = LeadSort.original;
  bool _table = false;
  bool _filtersOpen = false;

  /// Selected leads as indices into [_all].
  Set<int> _selected = <int>{};
  int? _tableSortColumn;
  bool _tableSortAscending = true;

  @override
  void initState() {
    super.initState();
    if (widget.overrideResults != null) {
      _all = widget.overrideResults!;
      _loadedJobId = widget.jobId;
    } else if (widget.resultsPending) {
      _loading = true;
    } else {
      _load();
    }
    if (widget.jobId == null && widget.overrideResults == null) {
      RefreshBus.jobsChanged.addListener(_load);
    }
  }

  @override
  void didUpdateWidget(covariant ResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final jobChanged = widget.jobId != oldWidget.jobId;
    if (jobChanged) {
      _searchController.clear();
      _query = '';
      _city = '';
      _selected = <int>{};
    }
    if (widget.overrideResults != null &&
        (jobChanged || !identical(widget.overrideResults, oldWidget.overrideResults))) {
      _all = widget.overrideResults!;
      _loadedJobId = widget.jobId;
      _error = null;
      _loading = false;
      _selected = <int>{};
    } else if (widget.overrideResults == null && widget.resultsPending) {
      _loading = true;
    } else if (widget.overrideResults == null && (jobChanged || oldWidget.resultsPending)) {
      _load();
    }
  }

  @override
  void dispose() {
    RefreshBus.jobsChanged.removeListener(_load);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = !silent || _all.isEmpty;
      _error = null;
    });
    try {
      var jobId = widget.jobId;
      if (jobId == null) {
        final live = context.read<ScraperProvider>().currentJob;
        if (live != null && live.resultsLoaded && live.results.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _all = live.results;
            _loadedJobId = live.jobId;
            _loading = false;
          });
          return;
        }
        final page = await _api.getJobs(limit: 1);
        final jobs = page['jobs'] as List;
        if (jobs.isEmpty) {
          if (!mounted) return;
          setState(() {
            _all = const [];
            _loading = false;
          });
          return;
        }
        jobId = '${(jobs.first as Map)['job_id']}';
      }
      final leads = await _api.getJobLeads(jobId);
      if (!mounted) return;
      setState(() {
        _all = leads;
        _loadedJobId = jobId;
        _loading = false;
        _selected = <int>{};
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (widget.jobId == null && widget.overrideResults != null) return;
    await _load(silent: true);
  }

  // ----------------------------------------------------------- filtering

  bool get _filtersActive =>
      _query.trim().isNotEmpty || _city.isNotEmpty || _contacts.isNotEmpty || _sort != LeadSort.original;

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _query = '';
      _city = '';
      _contacts.clear();
      _matchAll = false;
      _sort = LeadSort.original;
      _selected = <int>{};
    });
  }

  /// Indices into [_all] of the leads shown, in display order.
  List<int> _visibleIndices() {
    final q = _query.trim().toLowerCase();
    final out = <int>[];
    for (var i = 0; i < _all.length; i++) {
      final lead = _all[i];
      if (q.isNotEmpty) {
        final hay = [
          leadName(lead),
          lead['category'],
          lead['city'],
          lead['state'],
          lead['address'],
          lead['email'],
          lead['phone'],
          lead['website'],
        ].map((v) => '${v ?? ''}'.toLowerCase()).join(' ');
        if (!hay.contains(q)) continue;
      }
      if (_city.isNotEmpty && leadCityLabel(lead) != _city) continue;
      if (_contacts.isNotEmpty) {
        final matches = _contacts.where((c) => leadHasContact(lead, c)).length;
        if (_matchAll ? matches != _contacts.length : matches == 0) continue;
      }
      out.add(i);
    }
    int byText(int a, int b, String Function(Map<String, dynamic>) key) =>
        key(_all[a]).toLowerCase().compareTo(key(_all[b]).toLowerCase());
    switch (_sort) {
      case LeadSort.original:
        break;
      case LeadSort.name:
        out.sort((a, b) => byText(a, b, leadName));
        break;
      case LeadSort.category:
        out.sort((a, b) {
          final c = byText(a, b, (l) => '${l['category'] ?? ''}');
          return c != 0 ? c : byText(a, b, leadName);
        });
        break;
      case LeadSort.city:
        out.sort((a, b) {
          final c = byText(a, b, leadCityLabel);
          return c != 0 ? c : byText(a, b, leadName);
        });
        break;
    }
    return out;
  }

  List<String> _cityOptions() {
    final set = <String>{};
    for (final l in _all) {
      final c = leadCityLabel(l);
      if (c.isNotEmpty) set.add(c);
    }
    return set.toList()..sort();
  }

  static String _sortLabel(LeadSort s) {
    switch (s) {
      case LeadSort.original:
        return 'Original order';
      case LeadSort.name:
        return 'Name A–Z';
      case LeadSort.category:
        return 'Category';
      case LeadSort.city:
        return 'City';
    }
  }

  static String _contactLabel(LeadContact c) {
    switch (c) {
      case LeadContact.phone:
        return 'Has phone';
      case LeadContact.email:
        return 'Has email';
      case LeadContact.website:
        return 'Has website';
      case LeadContact.address:
        return 'Has address';
    }
  }

  // -------------------------------------------------------------- export

  String get _fileBase {
    final id = (widget.jobId ?? _loadedJobId ?? '');
    final shortId = id.length > 8 ? id.substring(0, 8) : id;
    final cat = safeFileNamePart(widget.category ?? (widget.title ?? 'leads'), maxLength: 30);
    return shortId.isEmpty ? 'leads_$cat' : 'leads_${cat}_$shortId';
  }

  List<Map<String, dynamic>> _selectedLeads() =>
      (_selected.toList()..sort()).where((i) => i >= 0 && i < _all.length).map((i) => _all[i]).toList();

  Future<void> _exportCsv(List<Map<String, dynamic>> leads, String suffix) async {
    if (leads.isEmpty) return;
    await saveCsv(leadsToCsv(leads), '${_fileBase}_${suffix}_${fileTimestamp()}', context: context);
  }

  Future<void> _exportJson(List<Map<String, dynamic>> leads, String suffix) async {
    if (leads.isEmpty) return;
    final clean = leads.map((l) => {for (final c in leadCsvColumns) c: l[c] ?? (c == 'business_name' ? l['name'] : null)}).toList();
    await saveJson(jsonEncode(clean), '${_fileBase}_${suffix}_${fileTimestamp()}', context: context);
  }

  Future<void> _downloadExcel() async {
    final id = widget.jobId ?? _loadedJobId;
    if (id == null || _downloading) return;
    setState(() => _downloading = true);
    await downloadSearchExcel(context, _api, id);
    if (mounted) setState(() => _downloading = false);
  }

  // ------------------------------------------------------------- actions

  Future<void> _open(Uri uri, {bool external = true}) async {
    try {
      final ok = await launchUrl(uri, mode: external ? LaunchMode.externalApplication : LaunchMode.platformDefault);
      if (!ok && mounted) showSearchSnack(context, "Couldn't open ${uri.toString()}", error: true);
    } catch (_) {
      if (mounted) showSearchSnack(context, "Couldn't open ${uri.toString()}", error: true);
    }
  }

  void _call(String phone) {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (clean.isEmpty) return;
    _open(Uri(scheme: 'tel', path: clean), external: false);
  }

  void _email(String email) {
    final e = email.trim();
    if (e.isEmpty) return;
    _open(Uri(scheme: 'mailto', path: e), external: false);
  }

  void _website(String website) {
    var w = website.trim();
    if (w.isEmpty) return;
    if (!w.startsWith('http://') && !w.startsWith('https://')) w = 'https://$w';
    final uri = Uri.tryParse(w);
    if (uri != null) _open(uri);
  }

  void _maps(Map<String, dynamic> lead) {
    final uri = leadMapsUri(lead);
    if (uri != null) _open(uri);
  }

  LeadActions get _actions => LeadActions(
        call: _call,
        email: _email,
        website: _website,
        maps: _maps,
        copy: (text, what) => copyWithSnack(context, text),
      );

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final body = _buildScroll(context);
    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: UiTokens.background,
      appBar: widget.showHeader
          ? AppBar(
              backgroundColor: UiTokens.background,
              foregroundColor: UiTokens.text,
              elevation: 0,
              title: Text(
                widget.title ?? 'Leads',
                style: const TextStyle(color: UiTokens.text, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              actions: [
                if (widget.overrideResults == null && (widget.jobId ?? _loadedJobId) != null && _all.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(44, 44)),
                      onPressed: _downloading ? null : _downloadExcel,
                      icon: _downloading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Download Excel'),
                    ),
                  )
                else if (_all.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(44, 44)),
                      onPressed: () => _exportCsv(_all, 'all'),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('CSV'),
                    ),
                  ),
              ],
            )
          : null,
      body: SafeArea(top: !widget.showHeader, bottom: false, child: body),
    );
  }

  Widget _buildScroll(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final phone = width < 600;
      final gutter = phone ? 16.0 : 24.0;
      final side = math.max(gutter, (width - 1200) / 2);
      final canTable = MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;
      final showTable = canTable && _table;
      final visible = _visibleIndices();
      final columns = width >= 1100 ? 3 : (width >= 700 ? 2 : 1);

      final slivers = <Widget>[
        SliverPadding(
          padding: EdgeInsets.fromLTRB(side, phone ? 8 : gutter, side, 0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              for (final w in widget.leading) ...[w, SizedBox(height: phone ? 10 : 16)],
              _buildToolbar(canTable: canTable, visibleCount: visible.length, visible: visible, compact: phone),
              const SizedBox(height: 12),
            ]),
          ),
        ),
      ];

      if (_loading) {
        slivers.add(const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Loading leads…', style: TextStyle(color: UiTokens.textSecondary)),
                ],
              ),
            ),
          ),
        ));
      } else if (_error != null) {
        slivers.add(SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: SliverToBoxAdapter(child: _buildError()),
        ));
      } else if (_all.isEmpty) {
        slivers.add(SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: const SliverToBoxAdapter(
            child: SearchCard(
              child: Text(
                'No leads were saved for this search.',
                style: TextStyle(color: UiTokens.textSecondary, fontSize: 14),
              ),
            ),
          ),
        ));
      } else if (visible.isEmpty) {
        slivers.add(SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: SliverToBoxAdapter(
            child: SearchCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No leads match these filters.',
                      style: TextStyle(color: UiTokens.text, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    style: searchSecondaryButtonStyle(),
                    onPressed: _clearFilters,
                    child: const Text('Clear filters'),
                  ),
                ],
              ),
            ),
          ),
        ));
      } else if (showTable) {
        slivers.add(SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: SliverToBoxAdapter(child: _buildTable(visible)),
        ));
      } else {
        final rows = (visible.length / columns).ceil();
        slivers.add(SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, r) {
                final start = r * columns;
                final items = visible.sublist(start, math.min(start + columns, visible.length));
                Widget card(int i) => LeadCard(
                      lead: _all[i],
                      selected: _selected.contains(i),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _selected.add(i);
                        } else {
                          _selected.remove(i);
                        }
                      }),
                      actions: _actions,
                    );
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: columns == 1
                      ? card(items.first)
                      : IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var k = 0; k < columns; k++) ...[
                                if (k > 0) const SizedBox(width: 12),
                                Expanded(child: k < items.length ? card(items[k]) : const SizedBox.shrink()),
                              ],
                            ],
                          ),
                        ),
                );
              },
              childCount: rows,
            ),
          ),
        ));
      }

      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 32)));

      final scroll = CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: slivers,
      );
      if (widget.jobId == null && widget.overrideResults != null) return scroll;
      return RefreshIndicator(onRefresh: _refresh, child: scroll);
    });
  }

  Widget _buildError() {
    final e = _error;
    final message = e is NotFoundException
        ? 'This search no longer exists.'
        : ErrorHandler.isNetworkError(e)
            ? "We couldn't reach the server. Your leads are safe."
            : "We couldn't load the leads: ${ErrorHandler.getUserFriendlyMessage(e)}";
    return SearchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(color: UiTokens.text, fontSize: 14)),
          const SizedBox(height: 10),
          OutlinedButton(
            style: searchSecondaryButtonStyle(),
            onPressed: () => _load(),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  Widget _chipLabel(String text, bool selected) => Text(
        text,
        style: TextStyle(
          color: selected ? UiTokens.text : UiTokens.textSecondary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      );

  Widget _buildToolbar({
    required bool canTable,
    required int visibleCount,
    required List<int> visible,
    required bool compact,
  }) {
    final cities = _cityOptions();
    final safeCity = cities.contains(_city) ? _city : '';
    final citiesShown = <String>{for (final i in visible) leadCityLabel(_all[i])}..remove('');

    final searchField = TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onChanged: (v) => setState(() {
        _query = v;
        _selected = <int>{};
      }),
      onSubmitted: (v) => setState(() => _query = v),
      style: const TextStyle(color: UiTokens.text, fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search leads by name, phone, city',
        hintStyle: const TextStyle(color: UiTokens.textMuted),
        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: UiTokens.textMuted),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded, size: 18, color: UiTokens.textMuted),
                onPressed: () => setState(() {
                  _searchController.clear();
                  _query = '';
                }),
              ),
        filled: true,
        fillColor: UiTokens.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: UiTokens.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: UiTokens.border)),
      ),
    );

    final cityMenu = PopupMenuButton<String>(
      tooltip: 'Filter by city',
      color: UiTokens.card,
      initialValue: safeCity,
      onSelected: (v) => setState(() {
        _city = v;
        _selected = <int>{};
      }),
      itemBuilder: (_) => [
        CheckedPopupMenuItem<String>(value: '', checked: safeCity.isEmpty, child: const Text('All cities')),
        for (final c in cities) CheckedPopupMenuItem<String>(value: c, checked: safeCity == c, child: Text(c)),
      ],
      child: _MenuButtonFace(
        icon: Icons.location_city_rounded,
        label: safeCity.isEmpty ? 'All cities' : safeCity,
      ),
    );

    final sortMenu = PopupMenuButton<LeadSort>(
      tooltip: 'Sort leads',
      color: UiTokens.card,
      initialValue: _sort,
      onSelected: (v) => setState(() => _sort = v),
      itemBuilder: (_) => [
        for (final s in LeadSort.values)
          CheckedPopupMenuItem<LeadSort>(value: s, checked: _sort == s, child: Text(_sortLabel(s))),
      ],
      child: _MenuButtonFace(icon: Icons.sort_rounded, label: 'Sort: ${_sortLabel(_sort)}'),
    );

    final chips = <Widget>[
      for (final c in LeadContact.values)
        FilterChip(
          label: _chipLabel(_contactLabel(c), _contacts.contains(c)),
          selected: _contacts.contains(c),
          showCheckmark: true,
          checkmarkColor: UiTokens.accent,
          selectedColor: UiTokens.selectedSurface,
          backgroundColor: UiTokens.card,
          side: BorderSide(color: _contacts.contains(c) ? UiTokens.accent : UiTokens.border),
          materialTapTargetSize: MaterialTapTargetSize.padded,
          onSelected: (v) => setState(() {
            if (v) {
              _contacts.add(c);
            } else {
              _contacts.remove(c);
            }
            _selected = <int>{};
          }),
        ),
      if (_contacts.length >= 2) ...[
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text('Match', style: TextStyle(color: UiTokens.textMuted, fontSize: 13)),
        ),
        ChoiceChip(
          label: _chipLabel('Any', !_matchAll),
          selected: !_matchAll,
          showCheckmark: true,
          checkmarkColor: UiTokens.accent,
          selectedColor: UiTokens.selectedSurface,
          backgroundColor: UiTokens.card,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          onSelected: (_) => setState(() => _matchAll = false),
        ),
        ChoiceChip(
          label: _chipLabel('All', _matchAll),
          selected: _matchAll,
          showCheckmark: true,
          checkmarkColor: UiTokens.accent,
          selectedColor: UiTokens.selectedSurface,
          backgroundColor: UiTokens.card,
          materialTapTargetSize: MaterialTapTargetSize.padded,
          onSelected: (_) => setState(() => _matchAll = true),
        ),
      ],
    ];

    final selectedCount = _selected.length;
    final visibleLeads = [for (final i in visible) _all[i]];

    return SearchCard(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth < 560) {
              // Phone: search plus a "Filters" toggle keeps the first lead
              // on the first screen; filters open below when asked for.
              final active = (_city.isNotEmpty ? 1 : 0) + _contacts.length + (_sort != LeadSort.original ? 1 : 0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: searchField),
                      const SizedBox(width: 8),
                      Semantics(
                        expanded: _filtersOpen,
                        child: OutlinedButton.icon(
                          style: searchSecondaryButtonStyle(),
                          onPressed: () => setState(() => _filtersOpen = !_filtersOpen),
                          icon: Icon(_filtersOpen ? Icons.expand_less_rounded : Icons.tune_rounded, size: 18),
                          label: Text(active > 0 ? 'Filters ($active)' : 'Filters'),
                        ),
                      ),
                    ],
                  ),
                  if (_filtersOpen) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [cityMenu, sortMenu]),
                  ],
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: searchField),
                const SizedBox(width: 8),
                cityMenu,
                const SizedBox(width: 8),
                sortMenu,
                if (canTable) ...[
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      foregroundColor: UiTokens.textSecondary,
                      selectedForegroundColor: UiTokens.text,
                      selectedBackgroundColor: UiTokens.selectedSurface,
                      side: const BorderSide(color: UiTokens.border),
                      minimumSize: const Size(44, 44),
                    ),
                    segments: const [
                      ButtonSegment(value: false, icon: Icon(Icons.view_agenda_outlined, size: 18), label: Text('Cards')),
                      ButtonSegment(value: true, icon: Icon(Icons.table_rows_outlined, size: 18), label: Text('Table')),
                    ],
                    selected: {_table},
                    onSelectionChanged: (s) => setState(() {
                      _table = s.first;
                      _tableSortColumn = null;
                    }),
                  ),
                ],
              ],
            );
          }),
          if (!compact || _filtersOpen) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: chips),
          ],
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  _loading
                      ? 'Loading leads…'
                      : visibleCount == _all.length
                          ? 'Showing ${plural(_all.length, 'lead', 'leads')}'
                              '${citiesShown.isEmpty ? '' : ' · ${plural(citiesShown.length, 'city', 'cities')}'}'
                          : 'Showing $visibleCount of ${plural(_all.length, 'lead', 'leads')}',
                  style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13),
                ),
              ),
              if (_filtersActive)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(44, 44)),
                  onPressed: _clearFilters,
                  child: const Text('Clear filters'),
                ),
              if (visible.isNotEmpty && selectedCount == 0 && (!compact || _filtersOpen))
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(44, 44)),
                  onPressed: () => setState(() => _selected = visible.toSet()),
                  child: Text('Select ${plural(visible.length, 'shown lead', 'shown leads')}'),
                ),
            ],
          ),
          if (selectedCount > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: UiTokens.selectedSurface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: UiTokens.accent.withValues(alpha: 0.5)),
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text('${formatCount(selectedCount)} selected',
                        style: const TextStyle(color: UiTokens.text, fontWeight: FontWeight.w700)),
                  ),
                  OutlinedButton.icon(
                    style: searchSecondaryButtonStyle(),
                    onPressed: () => _exportCsv(_selectedLeads(), 'selected'),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Export CSV'),
                  ),
                  OutlinedButton.icon(
                    style: searchSecondaryButtonStyle(),
                    onPressed: () => _exportJson(_selectedLeads(), 'selected'),
                    icon: const Icon(Icons.data_object_rounded, size: 18),
                    label: const Text('Export JSON'),
                  ),
                  if (selectedCount < visibleLeads.length)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(44, 44)),
                      onPressed: () => setState(() => _selected = visible.toSet()),
                      child: const Text('Select all shown'),
                    ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(44, 44)),
                    onPressed: () => setState(() => _selected = <int>{}),
                    child: const Text('Clear selection'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _tableKey(int column) {
    const keys = ['business_name', 'category', 'city', 'phone', 'email', 'website'];
    return column >= 0 && column < keys.length ? keys[column] : null;
  }

  Widget _buildTable(List<int> visible) {
    final ordered = List<int>.from(visible);
    final key = _tableSortColumn == null ? null : _tableKey(_tableSortColumn!);
    if (key != null) {
      String v(int i) => key == 'business_name'
          ? leadName(_all[i]).toLowerCase()
          : key == 'city'
              ? leadCityLabel(_all[i]).toLowerCase()
              : '${_all[i][key] ?? ''}'.toLowerCase();
      ordered.sort((a, b) => _tableSortAscending ? v(a).compareTo(v(b)) : v(b).compareTo(v(a)));
    }
    final rows = [
      for (final i in ordered)
        {
          '_idx': i,
          'business_name': leadName(_all[i]),
          'category': '${_all[i]['category'] ?? ''}',
          'city': leadCityLabel(_all[i]),
          'phone': '${_all[i]['phone'] ?? ''}',
          'email': '${_all[i]['email'] ?? ''}',
          'website': '${_all[i]['website'] ?? ''}',
        },
    ];
    Widget text(Map<String, dynamic> row, String k) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(
            _has(row[k]) ? '${row[k]}' : '—',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: UiTokens.text, fontSize: 13),
          ),
        );
    final selectedDisplay = <int>{
      for (var r = 0; r < rows.length; r++)
        if (_selected.contains(rows[r]['_idx'])) r,
    };
    return InfinityDataTable(
      layoutType: LayoutType.desktopMedium,
      columns: [
        InfinityDataColumn(label: 'Business', keyName: 'business_name', cellBuilder: (r) => text(r, 'business_name')),
        InfinityDataColumn(label: 'Category', keyName: 'category', cellBuilder: (r) => text(r, 'category')),
        InfinityDataColumn(label: 'City', keyName: 'city', cellBuilder: (r) => text(r, 'city')),
        InfinityDataColumn(label: 'Phone', keyName: 'phone', cellBuilder: (r) => text(r, 'phone')),
        InfinityDataColumn(label: 'Email', keyName: 'email', cellBuilder: (r) => text(r, 'email')),
        InfinityDataColumn(label: 'Website', keyName: 'website', cellBuilder: (r) => text(r, 'website')),
        InfinityDataColumn(
          label: 'Actions',
          keyName: 'actions',
          cellBuilder: (r) => LeadActionButtons(lead: _all[r['_idx'] as int], actions: _actions, compact: true),
        ),
      ],
      rows: rows,
      sortable: true,
      sortColumnIndex: _tableSortColumn,
      sortAscending: _tableSortAscending,
      onSort: (column, ascending) => setState(() {
        if (_tableKey(column) == null) return;
        _tableSortColumn = column;
        _tableSortAscending = ascending;
      }),
      showCheckboxes: true,
      selectedRows: selectedDisplay,
      onSelectionChanged: (display) => setState(() {
        final shown = rows.map((r) => r['_idx'] as int).toSet();
        _selected = {
          ..._selected.difference(shown),
          for (final d in display)
            if (d >= 0 && d < rows.length) rows[d]['_idx'] as int,
        };
      }),
    );
  }
}

class _MenuButtonFace extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuButtonFace({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: UiTokens.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: UiTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: UiTokens.textSecondary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: UiTokens.text, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down_rounded, color: UiTokens.textSecondary),
        ],
      ),
    );
  }
}

/// Callbacks for the per-lead actions.
class LeadActions {
  final void Function(String phone) call;
  final void Function(String email) email;
  final void Function(String website) website;
  final void Function(Map<String, dynamic> lead) maps;
  final void Function(String text, String what) copy;

  const LeadActions({
    required this.call,
    required this.email,
    required this.website,
    required this.maps,
    required this.copy,
  });
}

/// Call / Email / Website / Map buttons plus a "Copy…" menu. Only actions
/// that have data are shown.
class LeadActionButtons extends StatelessWidget {
  final Map<String, dynamic> lead;
  final LeadActions actions;
  final bool compact;

  const LeadActionButtons({super.key, required this.lead, required this.actions, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final name = leadName(lead);
    final phone = '${lead['phone'] ?? ''}'.trim();
    final email = '${lead['email'] ?? ''}'.trim();
    final website = '${lead['website'] ?? ''}'.trim();
    final address = '${lead['address'] ?? ''}'.trim();
    final hasMap = leadMapsUri(lead) != null;
    final size = compact ? 40.0 : 44.0;
    final style = IconButton.styleFrom(
      foregroundColor: UiTokens.accent,
      minimumSize: Size(size, size),
      padding: EdgeInsets.zero,
    );
    final copyItems = <PopupMenuEntry<String>>[
      if (_has(phone)) const PopupMenuItem(value: 'phone', child: Text('Copy phone')),
      if (_has(email)) const PopupMenuItem(value: 'email', child: Text('Copy email')),
      if (_has(website)) const PopupMenuItem(value: 'website', child: Text('Copy website')),
      if (_has(address)) const PopupMenuItem(value: 'address', child: Text('Copy address')),
      const PopupMenuItem(value: 'name', child: Text('Copy business name')),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_has(phone))
          IconButton(
            style: style,
            tooltip: 'Call $name',
            onPressed: () => actions.call(phone),
            icon: const Icon(Icons.call_rounded, size: 20),
          ),
        if (_has(email))
          IconButton(
            style: style,
            tooltip: 'Email $name',
            onPressed: () => actions.email(email),
            icon: const Icon(Icons.email_outlined, size: 20),
          ),
        if (_has(website))
          IconButton(
            style: style,
            tooltip: 'Open website of $name',
            onPressed: () => actions.website(website),
            icon: const Icon(Icons.language_rounded, size: 20),
          ),
        if (hasMap)
          IconButton(
            style: style,
            tooltip: 'Open $name in Google Maps',
            onPressed: () => actions.maps(lead),
            icon: const Icon(Icons.place_outlined, size: 20),
          ),
        PopupMenuButton<String>(
          tooltip: 'Copy details of $name',
          color: UiTokens.card,
          icon: const Icon(Icons.content_copy_rounded, size: 18, color: UiTokens.textSecondary),
          onSelected: (v) {
            switch (v) {
              case 'phone':
                actions.copy(phone, 'phone');
                break;
              case 'email':
                actions.copy(email, 'email');
                break;
              case 'website':
                actions.copy(website, 'website');
                break;
              case 'address':
                actions.copy(address, 'address');
                break;
              case 'name':
                actions.copy(name, 'name');
                break;
            }
          },
          itemBuilder: (_) => copyItems,
        ),
      ],
    );
  }
}

/// One lead (cards view, every width).
class LeadCard extends StatelessWidget {
  final Map<String, dynamic> lead;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final LeadActions actions;

  const LeadCard({
    super.key,
    required this.lead,
    required this.selected,
    required this.onSelected,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final name = leadName(lead);
    final category = '${lead['category'] ?? ''}'.trim();
    final city = leadCityLabel(lead);
    final address = '${lead['address'] ?? ''}'.trim();
    final phone = '${lead['phone'] ?? ''}'.trim();
    final email = '${lead['email'] ?? ''}'.trim();
    final website = '${lead['website'] ?? ''}'.trim();

    Widget line(IconData icon, String text, {Color color = UiTokens.textSecondary}) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 15, color: UiTokens.textMuted),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontSize: 13.5)),
              ),
            ],
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: selected ? UiTokens.selectedSurface : UiTokens.card,
        borderRadius: BorderRadius.circular(UiTokens.radius),
        border: Border.all(color: selected ? UiTokens.accent : UiTokens.border),
      ),
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: (v) => onSelected(v ?? false),
                semanticLabel: 'Select $name',
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: UiTokens.text, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      if (_has(category) || city.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            [if (_has(category)) category, if (city.isNotEmpty) city].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13),
                          ),
                        ),
                      if (_has(phone)) line(Icons.call_outlined, phone, color: UiTokens.text),
                      if (_has(email)) line(Icons.email_outlined, email),
                      if (_has(website)) line(Icons.language_rounded, website),
                      if (_has(address)) line(Icons.place_outlined, address),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: LeadActionButtons(lead: lead, actions: actions),
          ),
        ],
      ),
    );
  }
}
