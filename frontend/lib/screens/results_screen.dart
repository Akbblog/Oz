import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/display_url.dart';
import '../core/download_helper.dart';
import '../core/error_handler.dart';
import '../core/lead_selection.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/refresh_bus.dart';
import '../providers/scraper_provider.dart';
import '../services/api_service.dart';
import '../services/crm_api.dart';
import '../widgets/app_shell_common.dart';
import '../widgets/crm/crm_results.dart';
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
      return isOpenableWebsite('${lead['website'] ?? ''}');
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

final RegExp _strongLetter = RegExp(r'\p{L}', unicode: true);
final RegExp _rtlLetter = RegExp('[\u0590-\u08FF\uFB1D-\uFDFF\uFE70-\uFEFF]');

/// Paragraph direction of [text] from its first strong letter (like HTML
/// `dir="auto"`): Arabic/Hebrew/... -> RTL, any other letter -> LTR, no
/// letter -> [fallback].
TextDirection leadTextDirection(String text, {TextDirection fallback = TextDirection.ltr}) {
  final m = _strongLetter.firstMatch(text);
  if (m == null) return fallback;
  return _rtlLetter.hasMatch(m[0]!) ? TextDirection.rtl : TextDirection.ltr;
}

/// [text] wrapped in Unicode first-strong isolates (FSI … PDI) when it has
/// right-to-left letters, so it can be joined with other parts
/// (`Restaurant · <Arabic city>`) without punctuation jumping between runs.
String bidiIsolate(String text) => _rtlLetter.hasMatch(text) ? '\u2068$text\u2069' : text;

/// Plain-text block of [leads] for the clipboard (original website URLs).
String leadsToClipboardText(Iterable<Map<String, dynamic>> leads) {
  final blocks = <String>[];
  for (final l in leads) {
    final lines = <String>[
      leadName(l),
      if (_has(l['category']) || leadCityLabel(l).isNotEmpty)
        [if (_has(l['category'])) '${l['category']}'.trim(), if (leadCityLabel(l).isNotEmpty) leadCityLabel(l)]
            .join(' · '),
      if (_has(l['phone'])) 'Phone: ${'${l['phone']}'.trim()}',
      if (_has(l['email'])) 'Email: ${'${l['email']}'.trim()}',
      if (_has(l['website'])) 'Website: ${'${l['website']}'.trim()}',
      if (_has(l['address'])) 'Address: ${'${l['address']}'.trim()}',
    ];
    blocks.add(lines.join('\n'));
  }
  return blocks.join('\n\n');
}

/// The leads of a search: search, city filter, contact filters (off by
/// default), sort, cards or table (desktop), selection with CSV/JSON export
/// and copy at every width, and per-lead actions (call, email, website, map,
/// copy).
///
/// Selection is a [LeadSelection] keyed by stable lead ids (`lead_id`, else
/// `lead_key`): it survives filtering, sorting, switching cards/table and
/// reloads of the same search, and is cleared when the search changes.
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

  /// CRM actions (state chip per lead, Add selected / Add all, review of
  /// possible matches, "View this search in CRM"). Off by default: the
  /// admin jobs screen reuses this widget without CRM.
  final bool crmEnabled;
  final CrmApi? crmApi;

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
    this.crmEnabled = false,
    this.crmApi,
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

  /// Selected leads of this search (stable ids, independent of filters).
  final LeadSelection _selection = LeadSelection();
  int? _tableSortColumn;
  bool _tableSortAscending = true;

  /// CRM state of this search's leads (null when CRM is off).
  CrmResultsController? _crm;
  int _crmStateFor = -1;

  String? get _crmJobId => widget.jobId ?? _loadedJobId;

  /// Creates/drops the CRM controller for the current search and reloads
  /// the per-lead CRM state when the number of leads changed.
  void _syncCrm() {
    final jobId = _crmJobId;
    if (!widget.crmEnabled || jobId == null) {
      _crm?.removeListener(_onCrmChanged);
      _crm?.dispose();
      _crm = null;
      _crmStateFor = -1;
      return;
    }
    if (_crm == null || _crm!.jobId != jobId) {
      _crm?.removeListener(_onCrmChanged);
      _crm?.dispose();
      _crm = CrmResultsController(jobId: jobId, api: widget.crmApi ?? CrmApi())..addListener(_onCrmChanged);
      _crmStateFor = -1;
    }
    if (_crmStateFor != _all.length) {
      _crmStateFor = _all.length;
      _crm!.loadState();
    }
  }

  void _onCrmChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _addSelectedToCrm() async {
    final crm = _crm;
    if (crm == null) return;
    final ids = _selection.selectedLeadIds(_all);
    if (ids.isEmpty) return;
    final result = await crm.addIds(context, ids);
    if (result == null || !mounted) return;
    // Leads now in the CRM leave the selection; failures stay selected for a retry.
    final done = result.inCrm;
    _selection.deselectAll(_all.where((l) => done.contains(leadIdOf(l))));
  }

  @override
  void initState() {
    super.initState();
    _selection.addListener(_onSelectionChanged);
    _selection.setScope(widget.jobId);
    if (widget.overrideResults != null) {
      _setLeads(widget.overrideResults!, widget.jobId);
    } else if (widget.resultsPending) {
      _loading = true;
    } else {
      _load();
    }
    if (widget.jobId == null && widget.overrideResults == null) {
      RefreshBus.jobsChanged.addListener(_load);
    }
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  /// Shows [leads] of [jobId]; keeps the selection when it is the same
  /// search (selected leads that are gone are dropped).
  void _setLeads(List<Map<String, dynamic>> leads, String? jobId) {
    _all = leads;
    _loadedJobId = jobId;
    _selection.setScope(jobId);
    _selection.attach(leads);
    _syncCrm();
  }

  @override
  void didUpdateWidget(covariant ResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.crmEnabled != oldWidget.crmEnabled) _syncCrm();
    final jobChanged = widget.jobId != oldWidget.jobId;
    if (jobChanged) {
      _searchController.clear();
      _query = '';
      _city = '';
      _selection.setScope(widget.jobId);
    }
    if (widget.overrideResults != null &&
        (jobChanged || !identical(widget.overrideResults, oldWidget.overrideResults))) {
      _setLeads(widget.overrideResults!, widget.jobId);
      _error = null;
      _loading = false;
    } else if (widget.overrideResults == null && widget.resultsPending) {
      _loading = true;
    } else if (widget.overrideResults == null && (jobChanged || oldWidget.resultsPending)) {
      _load();
    }
  }

  @override
  void dispose() {
    RefreshBus.jobsChanged.removeListener(_load);
    _crm?.removeListener(_onCrmChanged);
    _crm?.dispose();
    _selection.removeListener(_onSelectionChanged);
    _selection.dispose();
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
            _setLeads(live.results, live.jobId);
            _loading = false;
          });
          return;
        }
        final page = await _api.getJobs(limit: 1);
        final jobs = page['jobs'] as List;
        if (jobs.isEmpty) {
          if (!mounted) return;
          setState(() {
            _setLeads(const [], null);
            _loading = false;
          });
          return;
        }
        jobId = '${(jobs.first as Map)['job_id']}';
      }
      final leads = await _api.getJobLeads(jobId);
      if (!mounted) return;
      setState(() {
        _setLeads(leads, jobId);
        _loading = false;
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

  /// Clears search, filters and sort. The selection is kept.
  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _query = '';
      _city = '';
      _contacts.clear();
      _matchAll = false;
      _sort = LeadSort.original;
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

  /// Selected leads in list order (hidden-by-filter ones included).
  List<Map<String, dynamic>> _selectedLeads() => _selection.selectedLeads(_all);

  Future<void> _exportCsv(List<Map<String, dynamic>> leads, String suffix) async {
    if (leads.isEmpty) return;
    await saveCsv(leadsToCsv(leads), '${_fileBase}_${suffix}_${fileTimestamp()}', context: context);
  }

  Future<void> _exportJson(List<Map<String, dynamic>> leads, String suffix) async {
    if (leads.isEmpty) return;
    final clean = leads
        .map((l) => {for (final c in leadCsvColumns) c: l[c] ?? (c == 'business_name' ? l['name'] : null)})
        .toList();
    await saveJson(jsonEncode(clean), '${_fileBase}_${suffix}_${fileTimestamp()}', context: context);
  }

  Future<void> _copyLeads(List<Map<String, dynamic>> leads) async {
    if (leads.isEmpty) return;
    await copyWithSnack(
      context,
      leadsToClipboardText(leads),
      message: 'Copied ${plural(leads.length, 'lead', 'leads')}',
    );
  }

  Future<void> _downloadExcel() async {
    final id = widget.jobId ?? _loadedJobId;
    if (id == null || _downloading) return;
    setState(() => _downloading = true);
    await downloadSearchExcel(context, _api, id);
    if (mounted) setState(() => _downloading = false);
  }

  // ------------------------------------------------------------- actions

  Future<void> _open(Uri uri, {bool external = true, String? label}) async {
    final what = label ?? uri.toString();
    try {
      final ok = await launchUrl(uri, mode: external ? LaunchMode.externalApplication : LaunchMode.platformDefault);
      if (!ok && mounted) showSearchSnack(context, "Couldn't open $what", error: true);
    } catch (_) {
      if (mounted) showSearchSnack(context, "Couldn't open $what", error: true);
    }
  }

  void _call(String phone) {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (clean.isEmpty) return;
    _open(Uri(scheme: 'tel', path: clean), external: false, label: phone);
  }

  void _email(String email) {
    final e = email.trim();
    if (e.isEmpty) return;
    _open(Uri(scheme: 'mailto', path: e), external: false, label: e);
  }

  /// Opens the ORIGINAL website value (only http/https).
  void _website(String website) {
    final uri = websiteLaunchUri(website);
    if (uri == null) {
      showSearchSnack(context, "This website address can't be opened.", error: true);
      return;
    }
    _open(uri, label: displayWebsite(website));
  }

  void _maps(Map<String, dynamic> lead) {
    final uri = leadMapsUri(lead);
    if (uri != null) _open(uri, label: 'Google Maps');
  }

  LeadActions get _actions => LeadActions(
        call: _call,
        email: _email,
        website: _website,
        maps: _maps,
        copy: (text, what) => copyWithSnack(context, text, message: 'Copied $what'),
      );

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final body = _buildBody(context);
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
                      style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
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
                      style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
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

  Widget _buildBody(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final phone = width < 600;
      final gutter = phone ? 16.0 : 24.0;
      final side = math.max(gutter, (width - 1200) / 2);
      final visible = _visibleIndices();
      final scroll = _buildScroll(context, width: width, phone: phone, gutter: gutter, side: side, visible: visible);
      if (_selection.isEmpty || _loading || _error != null || _all.isEmpty) return scroll;
      return Column(
        children: [
          Expanded(child: scroll),
          _buildSelectionBar(visible: visible, side: side, compact: phone),
        ],
      );
    });
  }

  Widget _buildScroll(
    BuildContext context, {
    required double width,
    required bool phone,
    required double gutter,
    required double side,
    required List<int> visible,
  }) {
    final canTable = MediaQuery.sizeOf(context).width >= AppBreakpoints.tablet;
    final showTable = canTable && _table;
    final columns = width >= 1100 ? 3 : (width >= 700 ? 2 : 1);

    final slivers = <Widget>[
      SliverPadding(
        padding: EdgeInsets.fromLTRB(side, phone ? 8 : gutter, side, 0),
        sliver: SliverList(
          delegate: SliverChildListDelegate([
            for (final w in widget.leading) ...[w, SizedBox(height: phone ? 10 : 16)],
            if (_crm != null && !_loading && _error == null && _all.isNotEmpty) ...[
              CrmResultsStrip(controller: _crm!, leads: _all),
              SizedBox(height: phone ? 10 : 12),
            ],
            _buildToolbar(canTable: canTable, visible: visible, compact: phone),
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
              Widget card(int i) {
                final lead = _all[i];
                return LeadCard(
                  key: ValueKey(_selection.idOf(lead)),
                  lead: lead,
                  selected: _selection.isSelected(lead),
                  onSelected: (v) => _selection.toggle(lead, v),
                  actions: _actions,
                  footer: _crm == null ? null : CrmLeadChip(lead: lead, controller: _crm!),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: columns == 1
                    ? card(items.first)
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var k = 0; k < columns; k++) ...[
                            if (k > 0) const SizedBox(width: 12),
                            Expanded(child: k < items.length ? card(items[k]) : const SizedBox.shrink()),
                          ],
                        ],
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
    required List<int> visible,
    required bool compact,
  }) {
    final cities = _cityOptions();
    final safeCity = cities.contains(_city) ? _city : '';
    final citiesShown = <String>{for (final i in visible) leadCityLabel(_all[i])}..remove('');
    final visibleCount = visible.length;

    final searchField = TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onChanged: (v) => setState(() => _query = v),
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
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: UiTokens.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: UiTokens.border)),
      ),
    );

    final cityMenu = PopupMenuButton<String>(
      tooltip: 'Filter by city',
      color: UiTokens.card,
      initialValue: safeCity,
      onSelected: (v) => setState(() => _city = v),
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
          }),
        ),
      if (_contacts.length >= 2) ...[
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text('Match', style: TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
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

    final visibleLeads = [for (final i in visible) _all[i]];
    final shownState = _selection.stateOf(visibleLeads);

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
                Flexible(child: cityMenu),
                const SizedBox(width: 8),
                Flexible(child: sortMenu),
                if (canTable) ...[
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      foregroundColor: UiTokens.textSecondary,
                      selectedForegroundColor: UiTokens.text,
                      selectedBackgroundColor: UiTokens.selectedSurface,
                      side: const BorderSide(color: UiTokens.border),
                      minimumSize: const Size(48, 48),
                    ),
                    segments: const [
                      ButtonSegment(
                          value: false, icon: Icon(Icons.view_agenda_outlined, size: 18), label: Text('Cards')),
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
              if (!_loading && visible.isNotEmpty)
                _SelectShownCheckbox(
                  state: shownState,
                  count: visibleCount,
                  onChanged: (select) =>
                      select ? _selection.selectAll(visibleLeads) : _selection.deselectAll(visibleLeads),
                ),
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
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                  onPressed: _clearFilters,
                  child: const Text('Clear filters'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Sticky bar under the leads while something is selected: counts and
  /// the bulk actions (export CSV/JSON, copy) for the selected leads.
  Widget _buildSelectionBar({required List<int> visible, required double side, required bool compact}) {
    final visibleLeads = [for (final i in visible) _all[i]];
    final selected = _selection.count;
    final shownSelected = _selection.countIn(visibleLeads);
    final summary = leadSelectionSummary(
      selected: selected,
      shown: visible.length,
      total: _all.length,
      hiddenSelected: selected - shownSelected,
    );
    final buttonStyle = searchSecondaryButtonStyle().copyWith(
      minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: compact ? 10 : 14)),
    );
    final linkStyle = TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48));
    return Material(
      color: UiTokens.card,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: UiTokens.accent, width: 1))),
          padding: EdgeInsets.fromLTRB(side, 8, side, 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(summary,
                    style: const TextStyle(color: UiTokens.text, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              if (_crm != null) ..._crmSelectionActions(selected, compact),
              OutlinedButton.icon(
                style: buttonStyle,
                onPressed: () => _exportCsv(_selectedLeads(), 'selected'),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text('Export CSV',
                    semanticsLabel: 'Export ${plural(selected, 'selected lead', 'selected leads')} as CSV'),
              ),
              OutlinedButton.icon(
                style: buttonStyle,
                onPressed: () => _exportJson(_selectedLeads(), 'selected'),
                icon: const Icon(Icons.data_object_rounded, size: 18),
                label: Text('Export JSON',
                    semanticsLabel: 'Export ${plural(selected, 'selected lead', 'selected leads')} as JSON'),
              ),
              OutlinedButton.icon(
                style: buttonStyle,
                onPressed: () => _copyLeads(_selectedLeads()),
                icon: const Icon(Icons.content_copy_rounded, size: 18),
                label: Text('Copy',
                    semanticsLabel: 'Copy details of ${plural(selected, 'selected lead', 'selected leads')}'),
              ),
              if (shownSelected < visibleLeads.length)
                TextButton(
                  style: linkStyle,
                  onPressed: () => _selection.selectAll(visibleLeads),
                  child: const Text('Select all shown'),
                ),
              TextButton(
                style: linkStyle,
                onPressed: _selection.clear,
                child: const Text('Clear selection'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Add selected to CRM" (disabled with the reason when a selected lead
  /// has no saved `lead_id`).
  List<Widget> _crmSelectionActions(int selected, bool compact) {
    final crm = _crm!;
    final without = _selection.selectedWithoutLeadId(_all);
    final ids = _selection.selectedLeadIds(_all);
    final reason = without > 0
        ? "${plural(without, 'selected lead is', 'selected leads are')} not saved yet and can't be added to the CRM. "
            'Deselect ${without == 1 ? 'it' : 'them'} to add the rest.'
        : null;
    return [
      FilledButton.icon(
        style: searchPrimaryButtonStyle().copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: compact ? 10 : 14)),
        ),
        onPressed: crm.busy || reason != null || ids.isEmpty ? null : _addSelectedToCrm,
        icon: const Icon(Icons.playlist_add_rounded, size: 18),
        label: Text('Add selected to CRM',
            semanticsLabel: reason ?? 'Add ${plural(selected, 'selected lead', 'selected leads')} to CRM'),
      ),
      if (reason != null)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(reason, style: const TextStyle(color: UiTokens.partialFg, fontSize: 13)),
        ),
    ];
  }

  static const List<String> _tableKeys = ['business_name', 'category', 'city', 'phone', 'email', 'website'];

  Widget _buildTable(List<int> visible) {
    final ordered = List<int>.from(visible);
    final sortCol = _tableSortColumn;
    final key = sortCol == null || sortCol < 0 || sortCol >= _tableKeys.length ? null : _tableKeys[sortCol];
    if (key != null) {
      String v(int i) => key == 'business_name'
          ? leadName(_all[i]).toLowerCase()
          : key == 'city'
              ? leadCityLabel(_all[i]).toLowerCase()
              : key == 'website'
                  ? displayWebsite('${_all[i]['website'] ?? ''}')
                  : '${_all[i][key] ?? ''}'.toLowerCase();
      ordered.sort((a, b) => _tableSortAscending ? v(a).compareTo(v(b)) : v(b).compareTo(v(a)));
    }
    final shownLeads = [for (final i in ordered) _all[i]];

    Widget text(String value, {int maxLines = 1, bool ltr = false, double maxWidth = 240}) {
      final shown = _has(value) ? value : '—';
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          shown,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textDirection: ltr ? TextDirection.ltr : leadTextDirection(shown),
          style: const TextStyle(color: UiTokens.text, fontSize: 13),
        ),
      );
    }

    void sort(int column, bool ascending) => setState(() {
          _tableSortColumn = column - 1; // column 0 is the checkbox
          _tableSortAscending = ascending;
        });

    DataColumn col(String label) => DataColumn(label: Text(label), onSort: sort);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(UiTokens.radius),
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          sortColumnIndex: _tableSortColumn == null ? null : _tableSortColumn! + 1,
          sortAscending: _tableSortAscending,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 60,
          headingRowHeight: 52,
          columnSpacing: 20,
          headingRowColor: WidgetStateProperty.all(AppColors.primaryBlue),
          headingTextStyle: AppTypography.labelLarge.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          dividerThickness: 0.5,
          columns: [
            DataColumn(
              label: _SelectShownCheckbox(
                state: _selection.stateOf(shownLeads),
                count: shownLeads.length,
                compact: true,
                onChanged: (select) => select ? _selection.selectAll(shownLeads) : _selection.deselectAll(shownLeads),
              ),
            ),
            col('Business'),
            col('Category'),
            col('City'),
            col('Phone'),
            col('Email'),
            col('Website'),
            if (_crm != null) const DataColumn(label: Text('CRM')),
            const DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final lead in shownLeads)
              DataRow(
                key: ValueKey(_selection.idOf(lead)),
                selected: _selection.isSelected(lead),
                color: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) return UiTokens.selectedSurface;
                  if (states.contains(WidgetState.hovered)) return AppColors.primaryBlue.withValues(alpha: 0.08);
                  return Colors.transparent;
                }),
                cells: [
                  DataCell(Checkbox(
                    value: _selection.isSelected(lead),
                    onChanged: (v) => _selection.toggle(lead, v ?? false),
                    semanticLabel: 'Select ${leadName(lead)}',
                  )),
                  DataCell(Tooltip(
                    message: leadName(lead),
                    excludeFromSemantics: true,
                    waitDuration: const Duration(milliseconds: 600),
                    child: text(leadName(lead), maxLines: 2, maxWidth: 260),
                  )),
                  DataCell(text('${lead['category'] ?? ''}'.trim(), maxWidth: 180)),
                  DataCell(text(leadCityLabel(lead), maxWidth: 200)),
                  DataCell(text('${lead['phone'] ?? ''}'.trim(), ltr: true, maxWidth: 170)),
                  DataCell(text('${lead['email'] ?? ''}'.trim(), ltr: true, maxWidth: 220)),
                  DataCell(
                    isOpenableWebsite('${lead['website'] ?? ''}')
                        ? LeadWebsiteLink(
                            website: '${lead['website']}',
                            onOpen: _website,
                            maxWidth: 220,
                          )
                        : text(''),
                  ),
                  if (_crm != null) DataCell(CrmLeadChip(lead: lead, controller: _crm!, compact: true)),
                  DataCell(LeadActionButtons(lead: lead, actions: _actions, compact: true)),
                ],
              ),
          ],
        ),
      ),
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
      constraints: const BoxConstraints(minHeight: 48),
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
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: UiTokens.text, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down_rounded, color: UiTokens.textSecondary),
        ],
      ),
    );
  }
}

/// "Select all N shown" checkbox (tri-state: some shown selected = dash).
class _SelectShownCheckbox extends StatelessWidget {
  final bool? state;
  final int count;
  final bool compact;
  final ValueChanged<bool> onChanged;

  const _SelectShownCheckbox({
    required this.state,
    required this.count,
    required this.onChanged,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // Tapping a partly selected box selects all shown (not none).
    void change() => onChanged(state != true);
    final label = state == true
        ? 'Deselect ${plural(count, 'shown lead', 'shown leads')}'
        : 'Select ${plural(count, 'shown lead', 'shown leads')}';
    final box = Checkbox(
      tristate: true,
      value: state,
      onChanged: (_) => change(),
      semanticLabel: compact ? label : null,
      side: const BorderSide(color: UiTokens.textSecondary, width: 2),
      activeColor: UiTokens.accent,
      checkColor: UiTokens.background,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    if (compact) return box;
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: change,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeFocus(child: box),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(label,
                      style: const TextStyle(color: UiTokens.accent, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Callbacks for the per-lead actions. [website] receives the ORIGINAL
/// website value; [copy] receives the text to copy and what it is.
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

/// Text-button style of the lead actions: 48×48 minimum target and a
/// visible 2 px outline when focused from the keyboard.
ButtonStyle _leadActionStyle({bool iconOnly = false}) => TextButton.styleFrom(
      foregroundColor: UiTokens.accent,
      minimumSize: const Size(48, 48),
      padding: EdgeInsets.symmetric(horizontal: iconOnly ? 0 : 12),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ).copyWith(
      side: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused) ? const BorderSide(color: UiTokens.accent, width: 2) : null,
      ),
    );

/// Call / Email / Website / Map buttons plus a "Copy" menu. Only actions
/// that have data are shown (no dead buttons).
///
/// Cards: icon + visible label ("Call", "Email", "Website", "Map", "Copy"),
/// wrapping onto more lines on narrow screens. [compact] (table cells):
/// icon-only buttons, each with a tooltip and a screen-reader label.
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
    final canOpenWebsite = isOpenableWebsite(website);
    final site = canOpenWebsite ? displayWebsite(website) : '';

    Widget action({
      required IconData icon,
      required String label,
      required String semantics,
      required String tooltip,
      required VoidCallback onPressed,
    }) {
      if (compact) {
        return IconButton(
          style: IconButton.styleFrom(
                  foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48), padding: EdgeInsets.zero)
              .copyWith(side: _leadActionStyle().side),
          tooltip: semantics,
          onPressed: onPressed,
          icon: Icon(icon, size: 20),
        );
      }
      return Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 500),
        child: TextButton.icon(
          style: _leadActionStyle(),
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(label, semanticsLabel: semantics),
        ),
      );
    }

    final buttons = <Widget>[
      if (_has(phone))
        action(
          icon: Icons.call_rounded,
          label: 'Call',
          semantics: 'Call $name, $phone',
          tooltip: 'Call $phone',
          onPressed: () => actions.call(phone),
        ),
      if (_has(email))
        action(
          icon: Icons.email_outlined,
          label: 'Email',
          semantics: 'Email $name, $email',
          tooltip: 'Email $email',
          onPressed: () => actions.email(email),
        ),
      if (canOpenWebsite)
        action(
          icon: Icons.language_rounded,
          label: 'Website',
          semantics: 'Open website $site',
          tooltip: _shorten(website),
          onPressed: () => actions.website(website),
        ),
      if (hasMap)
        action(
          icon: Icons.place_outlined,
          label: 'Map',
          semantics: 'Open $name in Google Maps',
          tooltip: 'Open in Google Maps',
          onPressed: () => actions.maps(lead),
        ),
      _CopyMenu(
        name: name,
        compact: compact,
        items: [
          if (_has(phone)) ('Copy phone', () => actions.copy(phone, 'phone')),
          if (_has(email)) ('Copy email', () => actions.copy(email, 'email')),
          if (_has(website)) ('Copy website', () => actions.copy(website, 'website')),
          if (_has(address)) ('Copy address', () => actions.copy(address, 'address')),
          ('Copy business name', () => actions.copy(name, 'name')),
          ('Copy all details', () => actions.copy(leadsToClipboardText([lead]), 'details')),
        ],
      ),
    ];
    if (compact) return Row(mainAxisSize: MainAxisSize.min, children: buttons);
    return Wrap(spacing: 2, runSpacing: 0, children: buttons);
  }
}

String _shorten(String s, [int max = 140]) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

class _CopyMenu extends StatelessWidget {
  final String name;
  final bool compact;
  final List<(String, VoidCallback)> items;

  const _CopyMenu({required this.name, required this.compact, required this.items});

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      style: const MenuStyle(backgroundColor: WidgetStatePropertyAll(UiTokens.card)),
      menuChildren: [
        for (final (label, onPressed) in items)
          MenuItemButton(
            style: MenuItemButton.styleFrom(foregroundColor: UiTokens.text, minimumSize: const Size(0, 48)),
            onPressed: onPressed,
            child: Text(label),
          ),
      ],
      builder: (context, controller, _) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        final semantics = 'Copy details of $name';
        if (compact) {
          return IconButton(
            style: IconButton.styleFrom(
                    foregroundColor: UiTokens.textSecondary, minimumSize: const Size(48, 48), padding: EdgeInsets.zero)
                .copyWith(side: _leadActionStyle().side),
            tooltip: semantics,
            onPressed: toggle,
            icon: const Icon(Icons.content_copy_rounded, size: 18),
          );
        }
        return TextButton.icon(
          style: _leadActionStyle(),
          onPressed: toggle,
          icon: const Icon(Icons.content_copy_rounded, size: 18),
          label: Text('Copy', semanticsLabel: semantics),
        );
      },
    );
  }
}

/// A lead's website as a link: the clean name ([displayWebsite]) as text,
/// the ORIGINAL value opened on tap, the full address in the tooltip, and
/// "Open website example.com" for screen readers.
class LeadWebsiteLink extends StatelessWidget {
  final String website;
  final ValueChanged<String> onOpen;
  final double? maxWidth;
  final bool showIcon;

  const LeadWebsiteLink({
    super.key,
    required this.website,
    required this.onOpen,
    this.maxWidth,
    this.showIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    final site = displayWebsite(website);
    if (site.isEmpty) return const SizedBox.shrink();
    Widget label = Text(
      site,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textDirection: TextDirection.ltr,
      style: const TextStyle(
        color: UiTokens.accent,
        fontSize: 13.5,
        decoration: TextDecoration.underline,
        decorationColor: UiTokens.accent,
      ),
    );
    if (maxWidth != null) label = ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth!), child: label);
    return Semantics(
      link: true,
      label: 'Open website $site',
      excludeSemantics: true,
      onTap: () => onOpen(website),
      child: Tooltip(
        message: _shorten(website),
        excludeFromSemantics: true,
        waitDuration: const Duration(milliseconds: 500),
        child: TextButton(
          style: _leadActionStyle().copyWith(
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
            alignment: AlignmentDirectional.centerStart,
          ),
          onPressed: () => onOpen(website),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showIcon) ...[
                const Icon(Icons.language_rounded, size: 15, color: UiTokens.textSecondary),
                const SizedBox(width: 6),
              ],
              Flexible(child: label),
            ],
          ),
        ),
      ),
    );
  }
}

/// A long address: at most [maxLines] lines with an ellipsis and a
/// "Show full address" toggle when it does not fit. The paragraph
/// direction follows the text (Arabic addresses read right-to-left), and
/// screen readers always get the full address.
class LeadAddressText extends StatefulWidget {
  final String address;
  final int maxLines;
  final TextStyle style;

  const LeadAddressText({
    super.key,
    required this.address,
    this.maxLines = 3,
    this.style = const TextStyle(color: UiTokens.textSecondary, fontSize: 13.5, height: 1.35),
  });

  @override
  State<LeadAddressText> createState() => _LeadAddressTextState();
}

class _LeadAddressTextState extends State<LeadAddressText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final dir = leadTextDirection(widget.address);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, c) {
      final painter = TextPainter(
        text: TextSpan(text: widget.address, style: widget.style),
        textDirection: dir,
        maxLines: widget.maxLines,
        textScaler: scaler,
      )..layout(maxWidth: c.maxWidth.isFinite ? c.maxWidth : double.infinity);
      final overflows = painter.didExceedMaxLines;
      painter.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.address,
            textDirection: dir,
            textAlign: TextAlign.start,
            maxLines: _expanded ? null : widget.maxLines,
            overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: widget.style,
          ),
          if (overflows || _expanded)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                style: _leadActionStyle().copyWith(
                  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
                  textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? 'Show less' : 'Show full address'),
              ),
            ),
        ],
      );
    });
  }
}

/// One lead (cards view, every width).
class LeadCard extends StatelessWidget {
  final Map<String, dynamic> lead;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final LeadActions actions;

  /// Optional extra row under the actions (the CRM state chip).
  final Widget? footer;

  const LeadCard({
    super.key,
    required this.lead,
    required this.selected,
    required this.onSelected,
    required this.actions,
    this.footer,
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
    final canOpenWebsite = isOpenableWebsite(website);
    final noContact = !_has(phone) && !_has(email) && !canOpenWebsite;
    final meta = [if (_has(category)) bidiIsolate(category), if (city.isNotEmpty) bidiIsolate(city)].join(' · ');

    Widget line(IconData icon, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: ExcludeSemantics(child: Icon(icon, size: 16, color: UiTokens.textSecondary)),
              ),
              const SizedBox(width: 9),
              Expanded(child: child),
            ],
          ),
        );

    Widget plain(String text, {Color color = UiTokens.textSecondary, String? semantics}) => Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.ltr,
          semanticsLabel: semantics,
          style: TextStyle(color: color, fontSize: 13, height: 1.25),
        );

    return Container(
      decoration: BoxDecoration(
        color: selected ? UiTokens.selectedSurface : UiTokens.card,
        borderRadius: BorderRadius.circular(UiTokens.radius),
        border: Border.all(color: selected ? UiTokens.accent : UiTokens.border),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
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
                side: const BorderSide(color: UiTokens.textSecondary, width: 2),
                activeColor: UiTokens.accent,
                checkColor: UiTokens.background,
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Tooltip(
                        message: name,
                        excludeFromSemantics: true,
                        waitDuration: const Duration(milliseconds: 800),
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textDirection: leadTextDirection(name),
                          style: const TextStyle(color: UiTokens.text, fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            meta,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textDirection: leadTextDirection(meta),
                            style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13),
                          ),
                        ),
                      if (_has(phone))
                        line(
                            Icons.call_outlined,
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPress: () => actions.copy(phone, 'phone'),
                              child:
                                  plain(phone, color: UiTokens.text, semantics: 'Phone $phone. Press and hold to copy'),
                            )),
                      if (_has(email))
                        line(
                            Icons.email_outlined,
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPress: () => actions.copy(email, 'email'),
                              child: plain(email, semantics: 'Email $email. Press and hold to copy'),
                            )),
                      if (canOpenWebsite)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: InkWell(
                              onTap: () => actions.website(website),
                              borderRadius: BorderRadius.circular(4),
                              child: Row(children: [
                                const Icon(Icons.language_rounded, size: 16, color: UiTokens.textSecondary),
                                const SizedBox(width: 9),
                                Expanded(
                                    child: Text(displayWebsite(website),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: UiTokens.accent,
                                            fontSize: 13,
                                            decoration: TextDecoration.underline))),
                              ]),
                            ),
                          ),
                        ),
                      if (_has(address)) line(Icons.place_outlined, LeadAddressText(address: address)),
                      if (noContact)
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            'No phone, email or website listed',
                            style: TextStyle(color: UiTokens.textSecondary, fontSize: 13, fontStyle: FontStyle.italic),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: UiTokens.border),
          Padding(
            padding: const EdgeInsets.only(left: 44, top: 2),
            child: LeadActionButtons(lead: lead, actions: actions),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(left: 44),
              child: Align(alignment: AlignmentDirectional.centerStart, child: footer!),
            ),
        ],
      ),
    );
  }
}
