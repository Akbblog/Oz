import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../admin_kit.dart';
import '../admin_shell.dart';

/// Product usage: active users, funnel, features, pages and retention.
/// Every section loads on its own, so one failing endpoint never blanks the
/// page.
class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({super.key});

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

/// One independently loaded section.
class _Slot<T> {
  T? data;
  String? error;
  bool loading = true;
}

typedef _Rows = List<Map<String, dynamic>>;

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  static const Map<int, String> _ranges = {
    7: '7 days',
    30: '30 days',
    90: '90 days',
  };

  final ApiService _api = ApiService();
  int _days = 30;
  int _seq = 0;

  final _Slot<Map<String, dynamic>> _sessions = _Slot();
  final _Slot<_Rows> _dau = _Slot();
  final _Slot<_Rows> _credits = _Slot();
  final _Slot<_Rows> _mau = _Slot();
  final _Slot<_Rows> _funnel = _Slot();
  final _Slot<_Rows> _features = _Slot();
  final _Slot<_Rows> _pages = _Slot();
  final _Slot<_Rows> _retention = _Slot();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  // ------------------------------------------------------------- loading

  static _Rows _rowsOf(Object? data) {
    final raw = data is Map ? data['data'] : data;
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _run<T>(_Slot<T> slot, Future<T> Function() fetch) async {
    final seq = _seq;
    setState(() {
      slot.loading = true;
      slot.error = null;
    });
    try {
      final data = await fetch();
      if (!mounted || seq != _seq) return;
      setState(() {
        slot.data = data;
        slot.loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        slot.data = null;
        slot.error = cleanError(e);
        slot.loading = false;
      });
    }
  }

  Future<void> _loadSessions() =>
      _run(_sessions, () => _api.getAnalyticsSessionStats(days: _days));
  Future<void> _loadDau() => _run(
      _dau, () async => _rowsOf(await _api.getAnalyticsDau(days: _days)));
  Future<void> _loadCredits() => _run(_credits,
      () async => _rowsOf(await _api.getAnalyticsCreditPatterns(days: _days)));
  Future<void> _loadMau() =>
      _run(_mau, () => _api.getAnalyticsMau(months: 12));
  Future<void> _loadFunnel() => _run(
      _funnel, () async => _rowsOf(await _api.getAnalyticsFunnel(days: _days)));
  Future<void> _loadFeatures() => _run(_features,
      () async => _rowsOf(await _api.getAnalyticsFeatureAdoption(days: _days)));
  Future<void> _loadPages() =>
      _run(_pages, () => _api.getAnalyticsTopPages(days: _days, limit: 12));
  // Retention needs room for D30 to exist, so never look back less than 60d.
  Future<void> _loadRetention() => _run(_retention,
      () => _api.getAnalyticsRetention(days: math.max(60, _days)));

  void _loadAll() {
    _seq++;
    _loadSessions();
    _loadDau();
    _loadCredits();
    _loadMau();
    _loadFunnel();
    _loadFeatures();
    _loadPages();
    _loadRetention();
  }

  void _setRange(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _loadAll();
  }

  // ------------------------------------------------------------- helpers

  static double _d(Object? v) =>
      v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// "2026-11-26" → "26 Nov 2026" (plain calendar day, no timezone shift).
  static String _day(Object? iso) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch('${iso ?? ''}');
    if (m == null) return '${iso ?? '–'}';
    final month = int.parse(m.group(2)!);
    if (month < 1 || month > 12) return '${iso ?? '–'}';
    return '${int.parse(m.group(3)!)} ${months[month - 1]} ${m.group(1)}';
  }

  /// The API only returns days that had activity; fill the gaps with zeros so
  /// the chart's x axis is a real calendar.
  List<String> _dayLabels() {
    final today = DateTime.now().toUtc();
    final start = DateTime.utc(today.year, today.month, today.day)
        .subtract(Duration(days: _days - 1));
    return [for (var i = 0; i < _days; i++) _iso(start.add(Duration(days: i)))];
  }

  List<double> _fill(List<String> labels, _Rows rows, String key) {
    final byDate = <String, double>{};
    for (final r in rows) {
      final date = '${r['date'] ?? ''}';
      if (date.length >= 10) byDate[date.substring(0, 10)] = _d(r[key]);
    }
    return [for (final l in labels) byDate[l] ?? 0];
  }

  Widget _section<T>(
    _Slot<T> slot, {
    required String title,
    String? subtitle,
    required VoidCallback retry,
    required Widget Function(T data) builder,
    double loadingHeight = 180,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    final data = slot.data;
    Widget child;
    EdgeInsetsGeometry pad = padding;
    if (data != null) {
      child = Opacity(opacity: slot.loading ? 0.55 : 1, child: builder(data));
    } else if (slot.loading) {
      child = ALoading(height: loadingHeight);
      pad = const EdgeInsets.all(16);
    } else {
      child = AErrorBox(slot.error ?? 'Could not load this section.',
          onRetry: retry);
      pad = const EdgeInsets.all(16);
    }
    return APanel(title: title, subtitle: subtitle, padding: pad, child: child);
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    final range =
        ASegmented<int>(options: _ranges, value: _days, onChanged: _setRange);
    final refresh =
        AIconButton(Icons.refresh, 'Refresh', onPressed: _loadAll);
    final scope = 'Last $_days days';

    return AdminScaffold(
      section: AdminSection.analytics,
      title: 'Analytics',
      subtitle: 'How signed-in people use the product',
      actions: wide ? [range, refresh] : [refresh],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!wide) ...[
            Align(alignment: Alignment.centerLeft, child: range),
            const SizedBox(height: 12),
          ],
          _kpis(scope),
          const SizedBox(height: 12),
          _section<_Rows>(
            _dau,
            title: 'Daily active users',
            subtitle: 'Signed-in accounts with any tracked activity, per day (UTC)',
            retry: _loadDau,
            loadingHeight: 230,
            builder: (rows) {
              final labels = _dayLabels();
              return ALineChart(
                labels: labels,
                series: [
                  ASeries('Active users', AC.accent, _fill(labels, rows, 'dau')),
                  ASeries('Sessions', AC.purple,
                      _fill(labels, rows, 'sessions')),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          ASplit(
            left: _section<_Rows>(
              _credits,
              title: 'Credits used vs added',
              subtitle:
                  'From the credit ledger, per day. "Added" includes purchases, signup credits, grants and refunds.',
              retry: _loadCredits,
              loadingHeight: 230,
              builder: (rows) {
                final labels = _dayLabels();
                return ALineChart(
                  labels: labels,
                  series: [
                    ASeries('Used', AC.amber, _fill(labels, rows, 'consumed')),
                    ASeries(
                        'Added', AC.green, _fill(labels, rows, 'purchased')),
                  ],
                );
              },
            ),
            right: _section<_Rows>(
              _mau,
              title: 'Monthly active users',
              subtitle: 'Last 12 months; not affected by the range',
              retry: _loadMau,
              loadingHeight: 230,
              builder: (rows) => ALineChart(
                labels: [for (final r in rows) '${r['month'] ?? ''}'],
                series: [
                  ASeries('Active users', AC.blue,
                      [for (final r in rows) _d(r['mau'])]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ASplit(
            leftFlex: 1,
            rightFlex: 1,
            left: _section<_Rows>(
              _funnel,
              title: 'Conversion funnel',
              subtitle: '$scope · distinct people reaching each step',
              retry: _loadFunnel,
              builder: _funnelBody,
            ),
            right: _section<_Rows>(
              _features,
              title: 'Feature usage',
              subtitle: '$scope · times each tracked feature was opened',
              retry: _loadFeatures,
              builder: (rows) => ABarList(
                items: [
                  for (final r in rows)
                    ABarItem(
                      '${r['feature'] ?? 'Unknown'}  ·  ${fmtInt(r['unique_users'])} users',
                      _d(r['uses']),
                    ),
                ],
                color: AC.purple,
                emptyText: 'No feature usage recorded in this range',
              ),
            ),
          ),
          const SizedBox(height: 12),
          ASplit(
            leftFlex: 1,
            rightFlex: 1,
            left: _section<_Rows>(
              _pages,
              title: 'Top pages',
              subtitle: '$scope · most viewed',
              retry: _loadPages,
              padding: EdgeInsets.zero,
              builder: (rows) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ATable<Map<String, dynamic>>(
                  minWidth: 420,
                  rows: rows,
                  empty: const AEmpty(
                    icon: Icons.article_outlined,
                    title: 'No page views yet',
                    message: 'Page views appear here as people use the app.',
                  ),
                  columns: [
                    ACol('Page', flex: 4, (r) => Text('${r['page'] ?? '–'}',
                        style: AT.mono.copyWith(color: AC.text))),
                    ACol('Views', width: 80, numeric: true,
                        (r) => Text(fmtInt(r['views']))),
                    ACol('Sessions', width: 90, numeric: true,
                        (r) => Text(fmtInt(r['sessions']))),
                    ACol('Users', width: 80, numeric: true,
                        (r) => Text(fmtInt(r['unique_users']))),
                  ],
                ),
              ),
            ),
            right: _section<_Rows>(
              _retention,
              title: 'Retention cohorts',
              subtitle:
                  'Of the people first seen on a day, the share active again 1, 7 and 30 days later',
              retry: _loadRetention,
              padding: EdgeInsets.zero,
              builder: _retentionBody,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpis(String scope) {
    final s = _sessions.data;
    final dau = _dau.data;

    String sv(String key) => s == null ? '–' : fmtInt(s[key]);
    String? sHint(String ok) => s != null
        ? ok
        : (_sessions.loading ? 'Loading…' : 'Could not load');

    String today = '–';
    String peak = '–';
    String? peakHint;
    List<double>? spark;
    if (dau != null) {
      final labels = _dayLabels();
      final values = _fill(labels, dau, 'dau');
      spark = values;
      today = fmtInt(values.isEmpty ? 0 : values.last.round());
      var best = 0;
      for (var i = 1; i < values.length; i++) {
        if (values[i] > values[best]) best = i;
      }
      if (values.isNotEmpty) {
        peak = fmtInt(values[best].round());
        peakHint = values[best] > 0
            ? 'Busiest day: ${_day(labels[best])}'
            : 'No activity in range';
      }
    }
    final dauHint = dau != null
        ? null
        : (_dau.loading ? 'Loading…' : 'Could not load');

    final bounce = s?['bounce_rate_pct'];
    final sessions = _d(s?['total_sessions']);
    final events = _d(s?['total_events']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sessions.error != null && s == null) ...[
          AErrorBox('Session totals: ${_sessions.error}',
              onRetry: _loadSessions),
          const SizedBox(height: 12),
        ],
        AGrid(
          minTileWidth: 190,
          children: [
            AKpi(
              label: 'Active users today',
              value: today,
              icon: Icons.person_outline,
              hint: dauHint ?? 'Signed-in accounts active today (UTC)',
              spark: spark,
            ),
            AKpi(
              label: 'Peak daily users',
              value: peak,
              icon: Icons.trending_up,
              color: AC.purple,
              hint: dauHint ?? peakHint,
            ),
            AKpi(
              label: 'Sessions',
              value: sv('total_sessions'),
              icon: Icons.tab_outlined,
              color: AC.blue,
              hint: sHint('$scope · browser sessions, signed-in or not'),
            ),
            AKpi(
              label: 'Tracked events',
              value: sv('total_events'),
              icon: Icons.bolt_outlined,
              color: AC.amber,
              hint: sHint(sessions > 0
                  ? '${(events / sessions).toStringAsFixed(1)} per session'
                  : 'Page views, clicks and actions'),
            ),
            AKpi(
              label: 'Bounce rate',
              value: s == null
                  ? '–'
                  : (bounce is num ? '${bounce.toStringAsFixed(1)}%' : '–'),
              icon: Icons.exit_to_app,
              color: AC.red,
              hint: sHint(
                  '${fmtInt(s?['bounce_sessions'])} sessions with a single event'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _funnelBody(_Rows rows) {
    if (rows.isEmpty || rows.every((r) => _d(r['count']) == 0)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Text('No funnel activity in this range yet', style: AT.mute),
      );
    }
    final maxV = rows.map((r) => _d(r['count'])).reduce(math.max);
    final first = _d(rows.first['count']);
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AC.raised,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('${i + 1}',
                          style: AT.label.copyWith(color: AC.textDim)),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text('${rows[i]['step'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AT.body),
                    ),
                    Text(fmtInt(rows[i]['count']),
                        style: AT.num.copyWith(fontWeight: FontWeight.w600)),
                    SizedBox(
                      width: 96,
                      child: Text(
                        _dropLabel(rows[i]['drop_off_pct'], i),
                        textAlign: TextAlign.right,
                        style: AT.mute.copyWith(
                          color: _dropColor(rows[i]['drop_off_pct']),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: maxV > 0 ? _d(rows[i]['count']) / maxV : 0,
                    minHeight: 8,
                    backgroundColor: AC.bg,
                    valueColor: AlwaysStoppedAnimation(
                        AC.series[i % AC.series.length]),
                  ),
                ),
              ],
            ),
          ),
        if (first > 0 && rows.length > 1) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Overall: ${(_d(rows.last['count']) * 100 / first).toStringAsFixed(1)}% '
              'of "${rows.first['step']}" reach "${rows.last['step']}".',
              style: AT.mute,
            ),
          ),
        ],
      ],
    );
  }

  static String _dropLabel(Object? pct, int index) {
    if (index == 0) return 'start';
    if (pct is! num) return '–';
    if (pct < 0) return '+${(-pct).toStringAsFixed(1)}% more';
    return '−${pct.toStringAsFixed(1)}% lost';
  }

  static Color _dropColor(Object? pct) {
    if (pct is! num) return AC.textMute;
    if (pct >= 75) return AC.red;
    if (pct >= 40) return AC.amber;
    return AC.textMute;
  }

  Widget _retentionBody(_Rows rows) {
    // Newest cohorts first; a long list is not useful here.
    final shown = rows.reversed.take(14).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: ATable<Map<String, dynamic>>(
        minWidth: 440,
        rows: shown,
        empty: const AEmpty(
          icon: Icons.groups_outlined,
          title: 'No cohorts yet',
          message:
              'Cohorts appear once signed-in people have used the app on more than one day.',
        ),
        columns: [
          ACol('First seen', flex: 3,
              (r) => Text(_day(r['cohort_date']))),
          ACol('People', width: 76, numeric: true,
              (r) => Text(fmtInt(r['cohort_size']))),
          ACol('Day 1', width: 82, numeric: true,
              (r) => _rateCell(r, 'd1_rate', 1)),
          ACol('Day 7', width: 82, numeric: true,
              (r) => _rateCell(r, 'd7_rate', 7)),
          ACol('Day 30', width: 82, numeric: true,
              (r) => _rateCell(r, 'd30_rate', 30)),
        ],
      ),
    );
  }

  /// Percentage cell tinted by value. Cohorts too young to have reached the
  /// day show a dash instead of a misleading 0%.
  Widget _rateCell(Map<String, dynamic> r, String key, int afterDays) {
    final cohort = DateTime.tryParse('${r['cohort_date'] ?? ''}');
    if (cohort != null) {
      final now = DateTime.now().toUtc();
      final age = DateTime.utc(now.year, now.month, now.day)
          .difference(DateTime.utc(cohort.year, cohort.month, cohort.day))
          .inDays;
      if (age < afterDays) {
        return const Tooltip(
          message: 'Too early to measure',
          child: Text('–', style: AT.mute),
        );
      }
    }
    final v = _d(r[key]).clamp(0, 100).toDouble();
    return Container(
      width: 58,
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AC.accent.withValues(alpha: 0.06 + 0.34 * (v / 100)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)}%',
          style: AT.num.copyWith(fontSize: 12)),
    );
  }
}
