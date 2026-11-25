import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../admin_kit.dart';
import '../admin_shell.dart';

/// Visitors: who opened the site, where they came from and what they looked
/// at. One row per browser session, signed-in or not.
class AdminVisitorsPage extends StatefulWidget {
  const AdminVisitorsPage({super.key});

  @override
  State<AdminVisitorsPage> createState() => _AdminVisitorsPageState();
}

class _AdminVisitorsPageState extends State<AdminVisitorsPage> {
  static const int _pageSize = 50;
  static const Map<int, String> _ranges = {
    1: 'Today',
    7: '7 days',
    30: '30 days',
    90: '90 days',
  };
  static const Map<String, String> _kinds = {
    'all': 'All',
    'anonymous': 'Anonymous',
    'user': 'Signed-in',
    'bot': 'Bots',
  };

  final ApiService _api = ApiService();
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;

  int _days = 7;

  // Summary
  int _summarySeq = 0;
  Map<String, dynamic>? _summary;
  String? _summaryError;
  bool _summaryLoading = true;

  // Visits list
  int _listSeq = 0;
  List<Map<String, dynamic>> _visits = [];
  int _total = 0;
  int _offset = 0;
  String? _listError;
  bool _listLoading = true;
  String _kind = 'all';
  String? _source;
  String _query = '';

  // Live sessions (seen in the last 5 minutes), refreshed automatically.
  static const Duration _liveEvery = Duration(seconds: 20);
  Timer? _liveTimer;
  List<Map<String, dynamic>>? _live;
  String? _liveError;
  DateTime? _liveAt;

  @override
  void initState() {
    super.initState();
    _loadSummary();
    _loadVisits();
    _loadLive();
    _liveTimer = Timer.periodic(_liveEvery, (_) {
      // Only while this page is the one on screen.
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) _loadLive();
    });
  }

  Future<void> _loadLive() async {
    try {
      final data = await _api.getAdminVisitors(live: true, limit: 50);
      if (!mounted) return;
      final raw = data['visits'];
      setState(() {
        _live = raw is List
            ? raw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[];
        _liveError = null;
        _liveAt = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _liveError = cleanError(e));
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- loading

  Future<void> _loadSummary() async {
    final seq = ++_summarySeq;
    setState(() {
      _summaryLoading = true;
      _summaryError = null;
    });
    try {
      final data = await _api.getAdminVisitorsSummary(days: _days);
      if (!mounted || seq != _summarySeq) return;
      setState(() {
        _summary = data;
        _summaryLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _summarySeq) return;
      setState(() {
        _summary = null;
        _summaryError = cleanError(e);
        _summaryLoading = false;
      });
    }
  }

  Future<void> _loadVisits({bool reset = false}) async {
    if (reset) _offset = 0;
    final seq = ++_listSeq;
    setState(() {
      _listLoading = true;
      _listError = null;
    });
    try {
      final data = await _api.getAdminVisitors(
        days: _days,
        limit: _pageSize,
        offset: _offset,
        q: _query,
        kind: _kind,
        source: _source,
      );
      if (!mounted || seq != _listSeq) return;
      final raw = data['visits'];
      final rows = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _visits = rows;
        _total = _int(data['total']) ?? rows.length;
        _listLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _listSeq) return;
      setState(() {
        _visits = [];
        _total = 0;
        _listError = cleanError(e);
        _listLoading = false;
      });
    }
  }

  void _setRange(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _loadSummary();
    _loadVisits(reset: true);
  }

  void _refresh() {
    _loadSummary();
    _loadVisits();
    _loadLive();
  }

  Widget _livePanel() {
    final live = _live;
    final humans = (live ?? const <Map<String, dynamic>>[])
        .where((v) => v['is_bot'] != true)
        .toList();
    final at = _liveAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return APanel(
      title: live == null
          ? 'Live now'
          : 'Live now · ${humans.length} ${humans.length == 1 ? 'person' : 'people'} on the site',
      subtitle: at == null
          ? 'Sessions active in the last 5 minutes'
          : 'Active in the last 5 minutes · updates every 20 s · last checked ${two(at.hour)}:${two(at.minute)}:${two(at.second)}',
      trailing: Container(
        width: 9,
        height: 9,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: _liveError != null
              ? AC.red
              : (humans.isEmpty ? AC.grey : AC.green),
          shape: BoxShape.circle,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: _liveError != null && live == null
          ? Padding(
              padding: const EdgeInsets.all(8),
              child: AErrorBox(_liveError!, onRetry: _loadLive),
            )
          : live == null
              ? const ALoading(height: 80)
              : humans.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                      child: Text(
                          'Nobody is on the site right now. This list fills in by itself when someone arrives.',
                          style: AT.mute),
                    )
                  : Column(
                      children: [for (final v in humans) _liveRow(v)],
                    ),
    );
  }

  Widget _liveRow(Map<String, dynamic> v) {
    final name = _s(v['username']);
    final loc = _location(v);
    final flag = flagEmoji(v['country']);
    final page = _s(v['exit_path']).isEmpty ? _s(v['landing_path']) : _s(v['exit_path']);
    return InkWell(
      onTap: () => _openVisit(v),
      borderRadius: BorderRadius.circular(8),
      hoverColor: AC.hover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: AC.green, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: ATwoLine(
                name.isEmpty ? 'Anonymous visitor' : name,
                secondary: [
                  if (flag.isNotEmpty || loc.isNotEmpty) '$flag $loc'.trim(),
                  _s(v['ip_address']),
                ].where((e) => e.isNotEmpty).join(' · '),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 3,
              child: ATwoLine(
                'On ${page.isEmpty ? '/' : page}',
                secondary:
                    '${fmtInt(v['page_count'] ?? 1)} page(s) · here for ${fmtDuration(v['duration_seconds'])}',
              ),
            ),
            const SizedBox(width: 10),
            Icon(_deviceIcon(v['device_type']), size: 16, color: AC.textMute),
            const SizedBox(width: 10),
            SizedBox(
              width: 76,
              child: Text(timeAgo(v['last_seen_at']),
                  textAlign: TextAlign.right, style: AT.mute),
            ),
          ],
        ),
      ),
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _applySearch(value));
  }

  void _applySearch(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q == _query) return;
    _query = q;
    _loadVisits(reset: true);
  }

  // ------------------------------------------------------------- helpers

  static int? _int(Object? v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}');

  static String _s(Object? v) => '${v ?? ''}'.trim();

  static bool _notDeployed(String? message) {
    final m = (message ?? '').toLowerCase();
    return m.contains('404') || m.contains('not found');
  }

  static Color _sourceColor(String source) {
    switch (source.toLowerCase()) {
      case 'search':
        return AC.blue;
      case 'social':
        return AC.purple;
      case 'campaign':
        return AC.amber;
      case 'referral':
        return AC.green;
      case 'direct':
        return AC.accent;
      default:
        return AC.grey;
    }
  }

  static String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static IconData _deviceIcon(Object? type) {
    switch (_s(type).toLowerCase()) {
      case 'mobile':
        return Icons.smartphone;
      case 'tablet':
        return Icons.tablet_mac;
      case 'bot':
        return Icons.smart_toy_outlined;
      default:
        return Icons.desktop_windows_outlined;
    }
  }

  static String _location(Map<String, dynamic> v) {
    final parts = [_s(v['city']), _s(v['region']), _s(v['country'])]
        .where((p) => p.isNotEmpty)
        .toList();
    // Region often repeats the city or is a bare code; keep city + country.
    if (parts.length == 3) parts.removeAt(1);
    return parts.join(', ');
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final range = ASegmented<int>(
      options: _ranges,
      value: _days,
      onChanged: _setRange,
    );
    final refresh =
        AIconButton(Icons.refresh, 'Refresh', onPressed: _refresh);

    return AdminScaffold(
      section: AdminSection.visitors,
      title: 'Visitors',
      subtitle:
          'Who opened the site, where they came from and what they looked at',
      actions: wide ? [range, refresh] : [refresh],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!wide) ...[
            Align(alignment: Alignment.centerLeft, child: range),
            const SizedBox(height: 12),
          ],
          if (_summary != null || _live != null) ...[
            _livePanel(),
            const SizedBox(height: 12),
          ],
          ..._summarySection(),
          const SizedBox(height: 12),
          _visitsPanel(),
        ],
      ),
    );
  }

  List<Widget> _summarySection() {
    if (_summary == null) {
      if (_summaryLoading) {
        return const [APanel(child: ALoading(height: 220))];
      }
      if (_notDeployed(_summaryError)) {
        return [
          APanel(
            child: AEmpty(
              icon: Icons.public_off,
              title: 'Visitor tracking is not live yet',
              message:
                  'Visits start being collected once the backend update is deployed. '
                  'Nothing has been lost: there is simply no data before that point.',
              action: AButton('Check again',
                  icon: Icons.refresh, onPressed: _refresh),
            ),
          ),
        ];
      }
      return [
        AErrorBox(_summaryError ?? 'Could not load the visitor summary.',
            onRetry: _loadSummary),
      ];
    }

    final s = _summary!;
    final t = s['totals'] is Map
        ? Map<String, dynamic>.from(s['totals'])
        : <String, dynamic>{};
    final series = s['series'] is List
        ? (s['series'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    double d(Object? v) => v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
    final visitsSeries = series.map((r) => d(r['visits'])).toList();
    final uniqueSeries = series.map((r) => d(r['unique_visitors'])).toList();
    final avgPages = t['avg_pages'];
    final scope = _days == 1 ? 'today' : 'in the last $_days days';

    return [
      AGrid(
        minTileWidth: 150,
        children: [
          AKpi(
            label: 'Visits',
            value: fmtInt(t['visits']),
            icon: Icons.login,
            hint: 'Browser sessions $scope',
            spark: visitsSeries.length > 1 ? visitsSeries : null,
          ),
          AKpi(
            label: 'Unique visitors',
            value: fmtInt(t['unique_visitors']),
            icon: Icons.person_outline,
            color: AC.purple,
            hint: '${fmtInt(t['unique_ips'])} distinct IP addresses',
            spark: uniqueSeries.length > 1 ? uniqueSeries : null,
          ),
          AKpi(
            label: 'Signed-in',
            value: fmtInt(t['signed_in']),
            icon: Icons.verified_user_outlined,
            color: AC.green,
            hint: 'Visits by a logged-in account',
          ),
          AKpi(
            label: 'Anonymous',
            value: fmtInt(t['anonymous']),
            icon: Icons.visibility_outlined,
            color: AC.blue,
            hint: 'Visits without signing in',
          ),
          AKpi(
            label: 'Active now',
            value: fmtInt(t['active_now']),
            icon: Icons.sensors,
            color: AC.green,
            hint: 'People seen in the last 5 minutes',
          ),
          AKpi(
            label: 'Pages per visit',
            value: avgPages is num
                ? avgPages.toStringAsFixed(1)
                : (avgPages == null ? '–' : '$avgPages'),
            icon: Icons.layers_outlined,
            color: AC.amber,
            hint: '${fmtInt(t['page_views'])} page views in total',
          ),
          AKpi(
            label: 'New vs returning',
            value:
                '${fmtInt(t['new_visitors'])} / ${fmtInt(t['returning_visitors'])}',
            icon: Icons.repeat,
            color: AC.accent,
            hint: 'First-time visitors / people who came back',
          ),
          AKpi(
            label: 'Bots filtered',
            value: fmtInt(t['bots']),
            icon: Icons.smart_toy_outlined,
            color: AC.grey,
            hint: 'Crawlers, left out of every other number',
          ),
        ],
      ),
      const SizedBox(height: 12),
      APanel(
        title: 'Visits over time',
        subtitle: 'Per day, bots excluded',
        trailing: _summaryLoading
            ? const Padding(
                padding: EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AC.accent),
                ),
              )
            : null,
        child: ALineChart(
          labels: series.map((r) => _s(r['date'])).toList(),
          series: [
            ASeries('Visits', AC.accent, visitsSeries),
            ASeries('Unique visitors', AC.purple, uniqueSeries),
          ],
        ),
      ),
      const SizedBox(height: 12),
      AGrid(
        minTileWidth: 300,
        children: [
          APanel(
            title: 'Traffic sources',
            subtitle: 'How visits arrived',
            child: ABarList(
              items: ABarList.fromRows(s['top_sources'])
                  .map((e) => ABarItem(_cap(e.label), e.value))
                  .toList(),
            ),
          ),
          APanel(
            title: 'Referring sites',
            subtitle: 'Sites that linked here',
            child: ABarList(
              items: ABarList.fromRows(s['top_referrers']),
              color: AC.green,
              emptyText: 'No referring sites in this range',
            ),
          ),
          APanel(
            title: 'Countries',
            subtitle: 'From the visitor IP address',
            child: ABarList(
              items: ABarList.fromRows(s['top_countries'], leading: flagEmoji),
              color: AC.blue,
              emptyText: 'No location data in this range',
            ),
          ),
          APanel(
            title: 'Landing pages',
            subtitle: 'First page of each visit',
            child: ABarList(
              items: ABarList.fromRows(s['top_pages']),
              color: AC.purple,
            ),
          ),
          APanel(
            title: 'Devices',
            child: ABarList(
              items: ABarList.fromRows(s['devices'])
                  .map((e) => ABarItem(_cap(e.label), e.value))
                  .toList(),
              color: AC.amber,
            ),
          ),
          APanel(
            title: 'Browsers',
            child: ABarList(
              items: ABarList.fromRows(s['browsers']),
              color: AC.accent,
            ),
          ),
        ],
      ),
    ];
  }

  Widget _visitsPanel() {
    final sources = <String, String>{};
    final top = _summary?['top_sources'];
    if (top is List) {
      for (final r in top) {
        if (r is Map) {
          final label = _s(r['label']);
          if (label.isNotEmpty) sources[label] = _cap(label);
        }
      }
    }
    if (_source != null && !sources.containsKey(_source)) {
      sources[_source!] = _cap(_source!);
    }

    Widget body;
    if (_listError != null) {
      body = Padding(
        padding: const EdgeInsets.all(12),
        child: _notDeployed(_listError)
            ? const AEmpty(
                icon: Icons.public_off,
                title: 'No visit list yet',
                message:
                    'The visit list appears once the backend update is live.',
              )
            : AErrorBox(_listError!, onRetry: _loadVisits),
      );
    } else if (_listLoading && _visits.isEmpty) {
      body = const ALoading(height: 200);
    } else {
      body = Opacity(
        opacity: _listLoading ? 0.55 : 1,
        child: ATable<Map<String, dynamic>>(
          minWidth: 1080,
          rows: _visits,
          onRowTap: _openVisit,
          empty: AEmpty(
            icon: Icons.travel_explore,
            title: 'No visits match',
            message: _query.isNotEmpty || _kind != 'all' || _source != null
                ? 'Try clearing the search or filters, or pick a longer range.'
                : 'Nobody has opened the site in this range yet.',
          ),
          columns: [
            ACol('When', width: 150, (v) => ATwoLine(
                  timeAgo(v['last_seen_at']),
                  secondary: fmtDateTime(v['first_seen_at']),
                )),
            ACol('Visitor', flex: 3, (v) {
              final name = _s(v['username']);
              final bot = v['is_bot'] == true;
              return ATwoLine(
                bot ? 'Bot' : (name.isEmpty ? 'Anonymous' : name),
                secondary: bot
                    ? _s(v['browser'])
                    : (v['is_returning'] == true ? 'Returning' : 'New'),
                leading: name.isEmpty
                    ? Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                            color: AC.raised, shape: BoxShape.circle),
                        child: Icon(
                            bot
                                ? Icons.smart_toy_outlined
                                : Icons.person_outline,
                            size: 15,
                            color: AC.textMute),
                      )
                    : AAvatar(name, size: 28),
              );
            }),
            ACol('IP address', width: 150, (v) => Text(
                  _s(v['ip_address']).isEmpty ? '–' : _s(v['ip_address']),
                  style: AT.mono.copyWith(color: AC.text),
                )),
            ACol('Location', flex: 3, (v) {
              final loc = _location(v);
              final flag = flagEmoji(v['country']);
              return Text(
                loc.isEmpty ? '–' : (flag.isEmpty ? loc : '$flag  $loc'),
                style: loc.isEmpty ? AT.mute : AT.body,
              );
            }),
            ACol('Source', flex: 3, (v) {
              final src = _s(v['source']);
              final sub = _s(v['referrer_host']).isNotEmpty
                  ? _s(v['referrer_host'])
                  : _s(v['utm_campaign']);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  APill(src.isEmpty ? 'Unknown' : _cap(src),
                      _sourceColor(src)),
                  if (sub.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AT.mute),
                    ),
                ],
              );
            }),
            ACol('Landing page', flex: 3, (v) => Text(
                  _s(v['landing_path']).isEmpty ? '–' : _s(v['landing_path']),
                  style: AT.mono.copyWith(color: AC.textDim),
                )),
            ACol('Pages', width: 70, numeric: true,
                (v) => Text(fmtInt(v['page_count']))),
            ACol('Device', flex: 3, (v) {
              final label = [_s(v['browser']), _s(v['os'])]
                  .where((p) => p.isNotEmpty)
                  .join(' · ');
              return Row(
                children: [
                  Icon(_deviceIcon(v['device_type']),
                      size: 15, color: AC.textMute),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(label.isEmpty ? '–' : label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AT.small),
                  ),
                ],
              );
            }),
          ],
        ),
      );
    }

    return APanel(
      title: 'Visits',
      subtitle: _listError == null && !_listLoading
          ? '${fmtInt(_total)} in range · newest first'
          : 'Newest first',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: ASearchField(
                    controller: _search,
                    hint: 'Search IP, user, referrer, page, city',
                    onChanged: _onSearchChanged,
                    onSubmitted: _applySearch,
                  ),
                ),
                ASegmented<String>(
                  options: _kinds,
                  value: _kind,
                  onChanged: (k) {
                    setState(() => _kind = k);
                    _loadVisits(reset: true);
                  },
                ),
                ADropdown<String>(
                  value: _source,
                  hint: 'All sources',
                  items: sources,
                  onChanged: (v) {
                    setState(() => _source = v);
                    _loadVisits(reset: true);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AC.border),
          body,
          if (_listError == null && _total > 0) ...[
            const Divider(height: 1, color: AC.border),
            APager(
              offset: _offset,
              limit: _pageSize,
              total: _total,
              onOffset: (o) {
                _offset = o;
                _loadVisits();
              },
            ),
          ],
        ],
      ),
    );
  }

  void _openVisit(Map<String, dynamic> visit) {
    showASheet<void>(
      context,
      width: 600,
      builder: (ctx) => _VisitSheet(api: _api, summary: visit),
    );
  }
}

// ------------------------------------------------------------ detail sheet

class _VisitSheet extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> summary;
  const _VisitSheet({required this.api, required this.summary});

  @override
  State<_VisitSheet> createState() => _VisitSheetState();
}

class _VisitSheetState extends State<_VisitSheet> {
  late Map<String, dynamic> _visit = widget.summary;
  List<Map<String, dynamic>> _pages = [];
  List<Map<String, dynamic>> _others = [];
  bool _loading = true;
  String? _error;

  static String _s(Object? v) => '${v ?? ''}'.trim();

  @override
  void initState() {
    super.initState();
    _load();
  }

  static List<Map<String, dynamic>> _rows(Object? raw) => raw is List
      ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  Future<void> _load() async {
    final id = _s(widget.summary['session_id']);
    if (id.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.api.getAdminVisit(id);
      if (!mounted) return;
      setState(() {
        if (data['visit'] is Map) {
          _visit = Map<String, dynamic>.from(data['visit']);
        }
        _pages = _rows(data['pages']);
        _others = _rows(data['other_visits']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = cleanError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _visit;
    final name = _s(v['username']);
    final bot = v['is_bot'] == true;
    final who = bot ? 'Bot' : (name.isEmpty ? 'Anonymous visitor' : name);
    final userId = v['user_id'];
    final flag = flagEmoji(v['country']);
    final loc = _AdminVisitorsPageState._location(v);
    final screen = (v['screen_w'] != null && v['screen_h'] != null)
        ? '${v['screen_w']} × ${v['screen_h']}'
        : '';
    final src = _s(v['source']);

    return ASheetFrame(
      title: Row(
        children: [
          name.isEmpty
              ? Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                      color: AC.raised, shape: BoxShape.circle),
                  child: Icon(
                      bot ? Icons.smart_toy_outlined : Icons.person_outline,
                      size: 18,
                      color: AC.textMute),
                )
              : AAvatar(name, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(who,
                    style: AT.h2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  [
                    if (_s(v['ip_address']).isNotEmpty) _s(v['ip_address']),
                    timeAgo(v['last_seen_at']),
                  ].join(' · '),
                  style: AT.mute,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      footer: userId == null
          ? null
          : Align(
              alignment: Alignment.centerRight,
              child: AButton(
                'Open user',
                icon: Icons.open_in_new,
                kind: AButtonKind.primary,
                onPressed: () {
                  final nav = Navigator.of(context);
                  nav.pop();
                  nav.pushNamed('/admin/users?user=$userId');
                },
              ),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              APill(
                  src.isEmpty
                      ? 'Unknown source'
                      : _AdminVisitorsPageState._cap(src),
                  _AdminVisitorsPageState._sourceColor(src)),
              if (bot)
                const APill('Bot', AC.grey)
              else
                APill(v['is_returning'] == true ? 'Returning' : 'New visitor',
                    v['is_returning'] == true ? AC.purple : AC.green),
              APill(name.isEmpty ? 'Not signed in' : 'Signed in',
                  name.isEmpty ? AC.grey : AC.green),
            ],
          ),
          const ASectionLabel('Who'),
          AField('Visitor', value: who),
          if (userId != null) AField('User ID', value: '$userId', mono: true),
          AField('IP address',
              value: _s(v['ip_address']), copyable: true, mono: true),
          AField('Location',
              value: loc.isEmpty ? '' : (flag.isEmpty ? loc : '$flag  $loc')),
          AField('Language', value: _s(v['language'])),
          AField('Timezone', value: _s(v['timezone'])),
          const ASectionLabel('Where they came from'),
          AField('Source',
              value: src.isEmpty ? '' : _AdminVisitorsPageState._cap(src)),
          AField('Referring site', value: _s(v['referrer_host'])),
          AField('Referrer URL', value: _s(v['referrer']), copyable: true),
          AField('UTM source', value: _s(v['utm_source'])),
          AField('UTM medium', value: _s(v['utm_medium'])),
          AField('UTM campaign', value: _s(v['utm_campaign'])),
          const ASectionLabel('This visit'),
          AField('First seen', value: fmtDateTime(v['first_seen_at'])),
          AField('Last seen', value: fmtDateTime(v['last_seen_at'])),
          AField('Time on site', value: fmtDuration(v['duration_seconds'])),
          AField('Pages viewed', value: fmtInt(v['page_count'])),
          AField('Landing page', value: _s(v['landing_path']), mono: true),
          AField('Last page', value: _s(v['exit_path']), mono: true),
          const ASectionLabel('Device'),
          AField('Device',
              value: _AdminVisitorsPageState._cap(_s(v['device_type']))),
          AField('Browser', value: _s(v['browser'])),
          AField('Operating system', value: _s(v['os'])),
          AField('Screen', value: screen),
          AField('User agent', value: _s(v['user_agent']), copyable: true),
          const ASectionLabel('Identifiers'),
          AField('Visitor ID',
              value: _s(v['visitor_id']), copyable: true, mono: true),
          AField('Session ID',
              value: _s(v['session_id']), copyable: true, mono: true),
          const ASectionLabel('Pages viewed'),
          if (_loading)
            const ALoading(height: 80)
          else if (_error != null)
            AErrorBox(_error!, onRetry: _load)
          else if (_pages.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No page-by-page trail was recorded for this visit.',
                  style: AT.mute),
            )
          else
            for (var i = 0; i < _pages.length; i++)
              _pageRow(_pages[i], i == _pages.length - 1),
          if (!_loading && _error == null) ...[
            const ASectionLabel('Earlier visits from this visitor'),
            if (_others.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('This is the only visit on record.', style: AT.mute),
              )
            else
              for (final o in _others) _otherRow(o),
          ],
        ],
      ),
    );
  }

  Widget _pageRow(Map<String, dynamic> p, bool last) {
    final event = _s(p['event_name']);
    final page = _s(p['page']);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                const SizedBox(height: 6),
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                      color: AC.accent, shape: BoxShape.circle),
                ),
                if (!last)
                  Expanded(child: Container(width: 1, color: AC.border)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(page.isEmpty ? '(no page)' : page,
                      style: AT.mono.copyWith(color: AC.text)),
                  Text(
                    [
                      if (event.isNotEmpty && event != 'page_view')
                        event.replaceAll('_', ' '),
                      fmtDateTime(p['created_at']),
                    ].join(' · '),
                    style: AT.mute,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _otherRow(Map<String, dynamic> o) {
    final src = _s(o['source']);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AC.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AC.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmtDateTime(o['first_seen_at']), style: AT.body),
                Text(
                  [
                    if (_s(o['landing_path']).isNotEmpty) _s(o['landing_path']),
                    '${fmtInt(o['page_count'])} pages',
                    if (_s(o['ip_address']).isNotEmpty) _s(o['ip_address']),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AT.mute,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          APill(
              src.isEmpty ? 'Unknown' : _AdminVisitorsPageState._cap(src),
              _AdminVisitorsPageState._sourceColor(src)),
        ],
      ),
    );
  }
}
