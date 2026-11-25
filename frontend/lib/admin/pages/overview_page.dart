import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../admin_kit.dart';
import '../admin_shell.dart';
import 'user_actions.dart';

/// Admin home: what needs a decision, how the selected period went, who is
/// arriving, the latest activity and whether the system is healthy.
///
/// Each block loads on its own, so one slow or failing request never blanks
/// the page, and a failed number is shown as unavailable rather than 0.
class AdminOverviewPage extends StatefulWidget {
  /// Injected in tests; the app uses the default client.
  final ApiService? api;
  const AdminOverviewPage({super.key, this.api});

  @override
  State<AdminOverviewPage> createState() => _AdminOverviewPageState();
}

class _AdminOverviewPageState extends State<AdminOverviewPage> {
  static const _ranges = <String, String>{
    '24h': '24 hours',
    '7d': '7 days',
    '30d': '30 days',
    'all': 'All time',
  };
  static const _rangeDays = {'24h': 1, '7d': 7, '30d': 30, 'all': 365};
  static const _chartDays = {'24h': 7, '7d': 7, '30d': 30, 'all': 90};

  late final ApiService _api = widget.api ?? ApiService();
  String _range = '7d';
  int _seq = 0;

  Map<String, dynamic>? _overview;
  String? _overviewError;
  bool _overviewLoading = true;

  Map<String, dynamic>? _visits; // KPI window
  Map<String, dynamic>? _visitsChart; // chart window
  bool _visitsUnavailable = false;

  List<Map<String, dynamic>>? _credits;
  List<Map<String, dynamic>>? _recentUsers;
  List<Map<String, dynamic>>? _activity;
  String? _activityError;

  Map<String, dynamic>? _health;
  String? _healthError;
  int? _probeMs;
  String? _probeError;
  bool _statusLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _loadAll() {
    _loadRanged();
    _loadLists();
    _loadStatus();
    AdminBadges.instance.refresh(force: true);
  }

  Future<void> _loadRanged() async {
    final seq = ++_seq;
    final range = _range;
    bool live() => mounted && seq == _seq;
    setState(() {
      _overviewLoading = true;
      _overviewError = null;
    });

    () async {
      try {
        final d = await _api.getAdminOverview(range);
        if (live()) {
          setState(() {
            _overview = d;
            _overviewLoading = false;
          });
        }
      } catch (e) {
        if (live()) {
          setState(() {
            _overview = null;
            _overviewError = cleanError(e);
            _overviewLoading = false;
          });
        }
      }
    }();

    () async {
      try {
        final kpiDays = _rangeDays[range]!;
        final chartDays = _chartDays[range]!;
        final kpi = await _api.getAdminVisitorsSummary(days: kpiDays);
        final chart = chartDays == kpiDays
            ? kpi
            : await _api.getAdminVisitorsSummary(days: chartDays);
        if (live()) {
          setState(() {
            _visits = kpi;
            _visitsChart = chart;
            _visitsUnavailable = false;
          });
        }
      } catch (_) {
        if (live()) {
          setState(() {
            _visits = null;
            _visitsChart = null;
            _visitsUnavailable = true;
          });
        }
      }
    }();

    () async {
      try {
        final d = await _api.getAnalyticsCreditPatterns(days: _chartDays[range]!);
        final rows = (d['data'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (live()) setState(() => _credits = rows);
      } catch (_) {
        if (live()) setState(() => _credits = const []);
      }
    }();
  }

  Future<void> _loadLists() async {
    () async {
      try {
        final users = await _api.getAllUsers();
        users.sort((a, b) =>
            '${b['created_at'] ?? ''}'.compareTo('${a['created_at'] ?? ''}'));
        if (mounted) setState(() => _recentUsers = users.take(6).toList());
      } catch (_) {
        if (mounted) setState(() => _recentUsers = const []);
      }
    }();
    () async {
      try {
        final d = await _api.getActivityFeed(limit: 8);
        if (mounted) {
          setState(() {
            _activity =
                List<Map<String, dynamic>>.from(d['events'] ?? const []);
            _activityError = null;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _activityError = cleanError(e));
      }
    }();
  }

  Future<void> _loadStatus() async {
    setState(() => _statusLoading = true);
    await Future.wait([
      () async {
        try {
          final h = await _api.getAdminHealth();
          if (mounted) {
            setState(() {
              _health = h;
              _healthError = null;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _health = null;
              _healthError = cleanError(e);
            });
          }
        }
      }(),
      () async {
        try {
          final ms = await _api.probePublicApi();
          if (mounted) {
            setState(() {
              _probeMs = ms;
              _probeError = null;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _probeMs = null;
              _probeError = cleanError(e);
            });
          }
        }
      }(),
    ]);
    if (mounted) setState(() => _statusLoading = false);
  }

  void _go(String route) => Navigator.of(context).pushNamed(route);

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final rangeControl = ASegmented<String>(
      value: _range,
      options: _ranges,
      onChanged: (v) {
        setState(() => _range = v);
        _loadRanged();
      },
    );
    return AdminScaffold(
      section: AdminSection.overview,
      title: 'Overview',
      subtitle: _windowLabel(),
      actions: [
        if (wide) rangeControl,
        AIconButton(Icons.refresh, 'Refresh everything', onPressed: _loadAll),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!wide) ...[
            Align(alignment: Alignment.centerLeft, child: rangeControl),
            const SizedBox(height: 12),
          ],
          _attention(),
          _periodKpis(),
          const SizedBox(height: 12),
          ASplit(left: _trafficPanel(), right: _nowPanel()),
          const SizedBox(height: 12),
          ASplit(left: _creditsPanel(), right: _creditMovesPanel()),
          const SizedBox(height: 12),
          ASplit(
            leftFlex: 1,
            rightFlex: 1,
            left: _recentUsersPanel(),
            right: _activityPanel(),
          ),
          const SizedBox(height: 12),
          _statusPanel(),
        ],
      ),
    );
  }

  String _windowLabel() {
    final scope = _range == 'all' ? 'All time' : 'Last ${_ranges[_range]}';
    final w = _overview?['window'];
    if (w is Map && w['start'] != null && w['end'] != null) {
      return '$scope · ${fmtDateTime(w['start'])} to ${fmtDateTime(w['end'])}';
    }
    return scope;
  }

  Map<String, dynamic> get _metrics =>
      Map<String, dynamic>.from(_overview?['metrics'] ?? const {});
  Map<String, dynamic> get _snapshot =>
      Map<String, dynamic>.from(_overview?['snapshot'] ?? const {});
  Map<String, dynamic> get _defs =>
      Map<String, dynamic>.from(_overview?['definitions'] ?? const {});

  String _v(Object? value) {
    if (_overviewLoading && _overview == null) return '…';
    return value == null ? 'Unavailable' : fmtInt(value);
  }

  // -------------------------------------------------------------- attention

  Widget _attention() {
    final s = _snapshot;
    final m = _metrics;
    final items = <Widget>[];
    final pending = (s['pending_users'] as num?)?.toInt() ?? 0;
    final requests = (s['pending_credit_requests'] as num?)?.toInt() ?? 0;
    final byStatus = m['searches_by_status'];
    final failed = byStatus is Map ? (byStatus['failed'] as num?)?.toInt() ?? 0 : 0;
    final healthStatus = '${_health?['status'] ?? ''}';

    if (pending > 0) {
      items.add(_attn(Icons.how_to_reg, AC.amber,
          '$pending account${pending == 1 ? '' : 's'} waiting for approval',
          'Review', () => _go('/admin/users?status=pending')));
    }
    if (requests > 0) {
      items.add(_attn(Icons.request_quote_outlined, AC.amber,
          '$requests credit request${requests == 1 ? '' : 's'} to review',
          'Open', () => _go('/admin/credits')));
    }
    if (failed > 0) {
      items.add(_attn(Icons.error_outline, AC.red,
          '$failed search${failed == 1 ? '' : 'es'} failed in this period',
          'See searches', () => _go('/admin/searches')));
    }
    if (_healthError != null ||
        (healthStatus.isNotEmpty && healthStatus != 'ok') ||
        _probeError != null) {
      items.add(_attn(Icons.monitor_heart_outlined, AC.red,
          'System status needs a look (see the panel below)', 'Re-check', _loadStatus));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AGrid(minTileWidth: 300, gap: 10, children: items),
    );
  }

  Widget _attn(IconData icon, Color color, String text, String cta,
      VoidCallback onTap) {
    return Material(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(text,
                      style: AT.body.copyWith(fontWeight: FontWeight.w600))),
              Text(cta,
                  style: TextStyle(
                      color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
              Icon(Icons.chevron_right, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- KPIs

  Widget _periodKpis() {
    if (_overviewError != null) {
      return KeyedSubtree(
        key: const Key('overview-error'),
        child: AErrorBox('Period figures could not be loaded: $_overviewError',
            onRetry: _loadRanged),
      );
    }
    final m = _metrics;
    final d = _defs;
    final byStatus = m['searches_by_status'];
    final statusLine = byStatus is Map && byStatus.isNotEmpty
        ? byStatus.entries.map((e) => '${e.value} ${e.key}').join(' · ')
        : 'Searches created in this period';
    final vt = _visits?['totals'];
    final visitSpark = (_visitsChart?['series'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => ((e['visits'] ?? 0) as num).toDouble())
        .toList();

    return AGrid(
      minTileWidth: 168,
      children: [
        AKpi(
          label: 'Visitors',
          value: _visitsUnavailable
              ? 'Unavailable'
              : (vt is Map ? fmtInt(vt['unique_visitors']) : '…'),
          icon: Icons.public,
          color: AC.accent,
          hint: _visitsUnavailable
              ? 'Visitor tracking is not reporting yet'
              : (vt is Map
                  ? '${fmtInt(vt['visits'])} visits · ${fmtInt(vt['active_now'])} on the site now'
                  : 'People who opened the site'),
          spark: visitSpark.length > 1 ? visitSpark : null,
          onTap: () => _go('/admin/visitors'),
        ),
        AKpi(
          label: 'New users',
          value: _v(m['new_users']),
          icon: Icons.person_add_alt_1,
          color: AC.purple,
          hint: 'Accounts created in this period',
          tooltip: d['new_users']?.toString(),
          onTap: () => _go('/admin/users'),
        ),
        AKpi(
          label: 'Active users',
          value: _v(m['active_users']),
          icon: Icons.how_to_reg,
          color: AC.blue,
          hint: 'Signed in, searched or acted',
          tooltip: d['active_users']?.toString(),
        ),
        AKpi(
          label: 'Searches started',
          value: _v(m['searches_started']),
          icon: Icons.travel_explore,
          color: AC.blue,
          hint: statusLine,
          tooltip: d['searches_started']?.toString(),
          onTap: () => _go('/admin/searches'),
        ),
        AKpi(
          label: 'Leads delivered',
          value: _v(m['leads_delivered']),
          icon: Icons.checklist,
          color: AC.green,
          hint: 'Stored for searches in this period',
          tooltip: d['leads_delivered']?.toString(),
        ),
        AKpi(
          label: 'Net search usage',
          value: _v(m['credits_charged_net']),
          icon: Icons.bolt,
          color: AC.amber,
          hint: 'Credits charged for searches minus refunds',
          tooltip: d['credits_charged_net']?.toString(),
        ),
        AKpi(
          label: 'Paid credits',
          value: _v(m['paid_credits']),
          icon: Icons.add_card,
          color: AC.green,
          hint: 'Completed live payments, each counted once',
          tooltip: d['paid_credits']?.toString(),
          onTap: () => _go('/admin/revenue'),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- panels

  Widget _trafficPanel() {
    final series = (_visitsChart?['series'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final days = _chartDays[_range]!;
    return APanel(
      title: 'Traffic',
      subtitle: 'Visits and unique visitors per day, last $days days',
      trailing: AButton('All visitors',
          kind: AButtonKind.ghost,
          icon: Icons.arrow_forward,
          onPressed: () => _go('/admin/visitors')),
      child: _visitsUnavailable
          ? const AEmpty(
              icon: Icons.public_off,
              title: 'No visitor data yet',
              message:
                  'Visits are recorded from the moment the tracking update is live. Check back after the first visitors arrive.',
            )
          : _visitsChart == null
              ? const ALoading(height: 230)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ALineChart(
                      height: 190,
                      labels: [for (final r in series) '${r['date']}'],
                      series: [
                        ASeries('Visits', AC.accent, [
                          for (final r in series)
                            ((r['visits'] ?? 0) as num).toDouble()
                        ]),
                        ASeries('Unique visitors', AC.purple, [
                          for (final r in series)
                            ((r['unique_visitors'] ?? 0) as num).toDouble()
                        ]),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('TOP SOURCES', style: AT.label),
                    const SizedBox(height: 4),
                    ABarList(
                      items: ABarList.fromRows(_visitsChart?['top_sources'])
                          .take(4)
                          .map((e) => ABarItem(cap(e.label), e.value))
                          .toList(),
                    ),
                  ],
                ),
    );
  }

  Widget _nowPanel() {
    final s = _snapshot;
    Widget row(String label, Object? value, IconData icon, Color color,
        {String? route}) {
      return InkWell(
        onTap: route == null ? null : () => _go(route),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: AT.bodyDim)),
              Text(_v(value),
                  style: AT.num.copyWith(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              if (route != null)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child:
                      Icon(Icons.chevron_right, size: 15, color: AC.textMute),
                ),
            ],
          ),
        ),
      );
    }

    final vt = _visits?['totals'];
    return APanel(
      title: 'Right now',
      subtitle: 'Current values, not affected by the period',
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          row('On the site (last 5 min)',
              vt is Map ? vt['active_now'] : null, Icons.sensors, AC.green,
              route: '/admin/visitors'),
          const Divider(height: 1, color: AC.border),
          row('Total users', s['total_users'], Icons.group_outlined, AC.purple,
              route: '/admin/users'),
          const Divider(height: 1, color: AC.border),
          row('Waiting for approval', s['pending_users'],
              Icons.pending_actions, AC.amber,
              route: '/admin/users?status=pending'),
          const Divider(height: 1, color: AC.border),
          row('Credit requests', s['pending_credit_requests'],
              Icons.request_quote_outlined, AC.amber,
              route: '/admin/credits'),
          const Divider(height: 1, color: AC.border),
          row('Searches in progress', s['searches_in_progress'],
              Icons.autorenew, AC.blue,
              route: '/admin/searches'),
          const Divider(height: 1, color: AC.border),
          row('Credits in circulation', s['credits_in_circulation'],
              Icons.toll, AC.accent),
        ],
      ),
    );
  }

  Widget _recentUsersPanel() {
    final users = _recentUsers;
    return APanel(
      title: 'Newest accounts',
      trailing: AButton('All users',
          kind: AButtonKind.ghost,
          icon: Icons.arrow_forward,
          onPressed: () => _go('/admin/users')),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: users == null
          ? const ALoading()
          : users.isEmpty
              ? const AEmpty(
                  icon: Icons.group_outlined, title: 'No accounts yet')
              : Column(
                  children: [
                    for (final u in users)
                      InkWell(
                        onTap: () => _go('/admin/users?user=${u['id']}'),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: ATwoLine('${u['username'] ?? 'Unknown'}',
                                    secondary:
                                        '${u['email'] ?? ''} · joined ${timeAgo(u['created_at'])}',
                                    leading:
                                        AAvatar('${u['username'] ?? '?'}')),
                              ),
                              const SizedBox(width: 8),
                              APill(userStateLabel(userState(u)),
                                  userStateColor(userState(u)),
                                  dot: true),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _activityPanel() {
    final events = _activity;
    return APanel(
      title: 'Latest activity',
      trailing: AButton('Activity log',
          kind: AButtonKind.ghost,
          icon: Icons.arrow_forward,
          onPressed: () => _go('/admin/activity')),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: _activityError != null
          ? AErrorBox(_activityError!, onRetry: _loadLists)
          : events == null
              ? const ALoading()
              : events.isEmpty
                  ? const AEmpty(icon: Icons.history, title: 'No activity yet')
                  : Column(
                      children: [
                        for (final e in events)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: e['status'] == 'success'
                                          ? AC.green
                                          : AC.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text.rich(
                                        TextSpan(children: [
                                          TextSpan(
                                              text:
                                                  '${e['actor_username'] ?? 'System'}  ',
                                              style: AT.body.copyWith(
                                                  fontWeight: FontWeight.w600)),
                                          TextSpan(
                                              text: '${e['action'] ?? ''}',
                                              style: AT.bodyDim),
                                        ]),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        [
                                          timeAgo(e['created_at']),
                                          if ('${e['ip_address'] ?? ''}'
                                              .isNotEmpty)
                                            'IP ${e['ip_address']}',
                                        ].join(' · '),
                                        style: AT.mute,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
    );
  }

  Widget _creditsPanel() {
    final rows = _credits;
    final days = _chartDays[_range]!;
    return APanel(
      title: 'Credits',
      subtitle:
          'Used by searches vs added to accounts per day, last $days days',
      child: rows == null
          ? const ALoading(height: 200)
          : ALineChart(
              height: 190,
              labels: [for (final r in rows) '${r['date']}'],
              series: [
                ASeries('Used', AC.amber, [
                  for (final r in rows) ((r['consumed'] ?? 0) as num).toDouble()
                ]),
                ASeries('Added', AC.green, [
                  for (final r in rows)
                    ((r['purchased'] ?? 0) as num).toDouble()
                ]),
              ],
            ),
    );
  }

  /// Where credits came from and went in the period, each figure on its own
  /// line (never merged: a paid credit is not a free one, a charge is not net).
  Widget _creditMovesPanel() {
    final m = _metrics;
    final d = _defs;
    Widget row(String label, String key, Color color, String note,
        {bool strong = false}) {
      final line = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: strong
                          ? AT.body.copyWith(fontWeight: FontWeight.w700)
                          : AT.body),
                  Text(note, style: AT.mute),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_v(m[key]),
                key: Key('credit-$key'),
                style: AT.num.copyWith(
                    fontSize: 15,
                    fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
                    color: m[key] == null && !_overviewLoading
                        ? AC.textMute
                        : AC.text)),
          ],
        ),
      );
      final tip = d[key]?.toString() ?? '';
      return tip.isEmpty
          ? line
          : Tooltip(
              message: tip,
              waitDuration: const Duration(milliseconds: 500),
              child: line);
    }

    const div = Divider(height: 1, color: AC.border);
    final sandbox = m['sandbox_test_credits'];
    return APanel(
      title: 'Credit movements',
      subtitle: _range == 'all' ? 'All time' : 'Last ${_ranges[_range]}',
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: _overviewError != null
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Unavailable for this period.', style: AT.mute),
            )
          : Column(
              children: [
                row('Search charges', 'credits_charged_gross', AC.amber,
                    'Charged when searches started, before refunds'),
                div,
                row('Search refunds', 'credits_refunded', AC.green,
                    'Returned for work that was not delivered'),
                div,
                row('Net search usage', 'credits_charged_net', AC.accent,
                    'Charges minus refunds',
                    strong: true),
                div,
                row('Paid credits', 'paid_credits', AC.green,
                    'Completed live payments'),
                div,
                row('Free signup credits', 'starting_credits', AC.blue,
                    'Granted on approval, not purchases'),
                div,
                row('Staff grants', 'admin_grants', AC.purple,
                    'Added by staff'),
                if (sandbox == null || (sandbox is num && sandbox > 0)) ...[
                  div,
                  row('Sandbox test credits', 'sandbox_test_credits',
                      AC.yellow, 'Test payments, no money charged'),
                ],
              ],
            ),
    );
  }

  Widget _statusPanel() {
    Widget line(String label, String value, Color color, {Key? key}) => Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(label, style: AT.bodyDim)),
              Flexible(
                child: Text(value,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AT.body.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    Color c(Object? st) => switch ('$st') {
          'ok' => AC.green,
          'degraded' => AC.amber,
          'unknown' || 'null' => AC.grey,
          _ => AC.red,
        };

    final checks = Map<String, dynamic>.from(_health?['checks'] ?? const {});
    Widget check(String label, String key) {
      final raw = checks[key];
      if (raw is! Map) return line(label, 'Unknown', AC.grey);
      final st = raw['status'] ?? 'unknown';
      final extra = <String>[
        '$st'.toUpperCase(),
        if (raw['latency_ms'] != null) '${raw['latency_ms']} ms',
        if (raw['applied'] != null) 'v${raw['applied']}',
        if (raw['last_pass_seconds_ago'] != null)
          'last pass ${raw['last_pass_seconds_ago']}s ago',
        if (raw['detail'] != null && st != 'ok') '${raw['detail']}',
      ];
      return line(label, extra.join(' · '), c(st));
    }

    final overall = _healthError != null
        ? 'unknown'
        : (_health == null ? 'checking' : '${_health!['status'] ?? 'unknown'}');
    return APanel(
      key: Key('health-$overall'),
      title: 'System status',
      subtitle: _statusLoading
          ? 'Checking…'
          : 'Backend reports: ${overall.toUpperCase()}',
      trailing: AIconButton(Icons.refresh, 'Check again',
          onPressed: _statusLoading ? null : _loadStatus),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(
        children: [
          line(
            'Public site → API',
            _probeError != null
                ? 'Unreachable · $_probeError'
                : (_probeMs == null ? 'Checking…' : 'Reachable · $_probeMs ms'),
            _probeError != null
                ? AC.red
                : (_probeMs == null ? AC.grey : AC.green),
            key: _probeError != null
                ? const Key('probe-unreachable')
                : (_probeMs != null ? const Key('probe-ok') : null),
          ),
          const Divider(height: 1, color: AC.border),
          if (_healthError != null)
            line('Backend health', 'Unknown ($_healthError)', AC.grey)
          else if (_health == null)
            line('Backend health', 'Checking…', AC.grey)
          else ...[
            check('Database', 'database'),
            const Divider(height: 1, color: AC.border),
            check('Schema migrations', 'migrations'),
            const Divider(height: 1, color: AC.border),
            check('Search runner', 'job_runner'),
            const Divider(height: 1, color: AC.border),
            check('Tunnel connector', 'tunnel_connector'),
          ],
        ],
      ),
    );
  }
}
