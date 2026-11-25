import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../admin_kit.dart';
import '../admin_shell.dart';

/// Revenue: money received, subscriptions, and every recent payment attempt.
class AdminRevenuePage extends StatefulWidget {
  const AdminRevenuePage({super.key});

  @override
  State<AdminRevenuePage> createState() => _AdminRevenuePageState();
}

class _AdminRevenuePageState extends State<AdminRevenuePage> {
  final ApiService _api = ApiService();
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _dashboard;

  // Secondary requests fail independently of the main dashboard.
  List<Map<String, dynamic>>? _mrrSeries;
  String? _mrrError;
  Map<String, dynamic>? _churn;
  String? _churnError;

  String _status = 'all';
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });

    Map<String, dynamic>? dashboard;
    String? error;
    List<Map<String, dynamic>>? series;
    String? mrrError;
    Map<String, dynamic>? churn;
    String? churnError;

    await Future.wait([
      () async {
        try {
          dashboard =
              Map<String, dynamic>.from(await _api.getAdminRevenueDashboard());
        } catch (e) {
          error = cleanError(e);
        }
      }(),
      () async {
        try {
          final mrr = await _api.getAdminMrr();
          series = _rows(mrr['series']);
        } catch (e) {
          mrrError = cleanError(e);
        }
      }(),
      () async {
        try {
          churn = await _api.getAdminChurn();
        } catch (e) {
          churnError = cleanError(e);
        }
      }(),
    ]);

    if (!mounted || seq != _seq) return;
    setState(() {
      _dashboard = dashboard;
      _error = error;
      _mrrSeries = series;
      _mrrError = mrrError;
      _churn = churn;
      _churnError = churnError;
      _loading = false;
    });
  }

  static List<Map<String, dynamic>> _rows(Object? raw) {
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static num _n(Object? v) => v is num ? v : (num.tryParse('${v ?? ''}') ?? 0);

  /// Buckets a provider status into the four filter groups.
  static String _bucket(Object? raw) {
    final s = '${raw ?? ''}'.trim().toLowerCase();
    if (s == 'completed' || s == 'success' || s == 'paid') return 'completed';
    if (s == 'failed' || s == 'failure' || s == 'error' || s == 'cancelled' || s == 'canceled' || s == 'expired') {
      return 'failed';
    }
    return 'pending';
  }

  static String _amount(Map<String, dynamic> t) {
    final cur = '${t['currency'] ?? 'USD'}'.trim().toUpperCase();
    if (cur.isEmpty || cur == 'USD') return fmtMoney(t['amount_cents']);
    return '${fmtMoney(t['amount_cents'], symbol: '')} $cur';
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      section: AdminSection.revenue,
      title: 'Revenue',
      subtitle: 'Live payments, subscriptions and recent transactions',
      actions: [
        AIconButton(Icons.refresh, 'Refresh', onPressed: _loading ? null : _load),
      ],
      child: _body(),
    );
  }

  Widget _body() {
    if (_loading && _dashboard == null) return const ALoading(height: 320);
    if (_dashboard == null) {
      return AErrorBox(
        'Revenue could not be loaded: ${_error ?? 'unknown error'}',
        onRetry: _load,
      );
    }
    final d = _dashboard!;
    final txns = _rows(d['recent_transactions']);
    final counts = <String, int>{
      'all': txns.length,
      'completed': 0,
      'failed': 0,
      'pending': 0,
    };
    for (final t in txns) {
      final b = _bucket(t['status']);
      counts[b] = (counts[b] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          AErrorBox('Showing the last loaded figures. Refresh failed: $_error',
              onRetry: _load),
          const SizedBox(height: 12),
        ],
        _kpis(d, txns, counts),
        const SizedBox(height: 12),
        ASplit(
          left: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _mrrPanel(),
              const SizedBox(height: 12),
              _transactionsPanel(txns, counts),
            ],
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _topCustomersPanel(_rows(d['top_customers'])),
              const SizedBox(height: 12),
              _funnelPanel(d['conversion_funnel']),
              const SizedBox(height: 12),
              _churnPanel(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kpis(Map<String, dynamic> d, List<Map<String, dynamic>> txns,
      Map<String, int> counts) {
    final total = txns.length;
    final completed = counts['completed'] ?? 0;
    final failed = counts['failed'] ?? 0;
    return AGrid(
      minTileWidth: 190,
      children: [
        AKpi(
          label: 'Today',
          value: fmtMoney(d['revenue_today_cents']),
          icon: Icons.today,
          color: AC.accent,
          hint: 'Live payments since 00:00 UTC',
        ),
        AKpi(
          label: 'Last 7 days',
          value: fmtMoney(d['revenue_last_7d_cents']),
          icon: Icons.date_range,
          color: AC.green,
          hint: 'Live payments',
        ),
        AKpi(
          label: 'Last 30 days',
          value: fmtMoney(d['revenue_last_30d_cents']),
          icon: Icons.calendar_month,
          color: AC.amber,
          hint: 'Live payments',
        ),
        AKpi(
          label: 'MRR (estimated)',
          value: fmtMoney(d['mrr_cents']),
          icon: Icons.trending_up,
          color: AC.purple,
          hint: 'Per month. Yearly plans divided by 12.',
        ),
        AKpi(
          label: 'Active subscriptions',
          value: fmtInt(d['active_subscriptions']),
          icon: Icons.subscriptions_outlined,
          color: AC.blue,
          hint: 'Active or trialing now',
        ),
        AKpi(
          label: 'Payment success rate',
          value: total == 0 ? '–' : '${(completed * 100 / total).round()}%',
          icon: Icons.verified_outlined,
          color: AC.green,
          hint: total == 0
              ? 'No recent transactions'
              : '$completed of $total recent transactions completed',
        ),
        AKpi(
          label: 'Failed payments',
          value: fmtInt(failed),
          icon: Icons.error_outline,
          color: failed > 0 ? AC.red : AC.grey,
          hint: 'Among the last $total transactions',
          onTap: failed > 0 ? () => setState(() => _status = 'failed') : null,
        ),
      ],
    );
  }

  Widget _mrrPanel() {
    Widget child;
    if (_mrrSeries == null) {
      child = AErrorBox(
          'MRR history could not be loaded: ${_mrrError ?? 'unknown error'}',
          onRetry: _load);
    } else {
      final s = _mrrSeries!;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ALineChart(
            labels: [for (final p in s) '${p['month'] ?? ''}'],
            series: [
              ASeries('MRR', AC.purple,
                  [for (final p in s) _n(p['mrr_cents']).toDouble() / 100.0]),
            ],
            format: (v) => fmtMoney((v * 100).round()),
            height: 180,
          ),
          const SizedBox(height: 8),
          const Text(
            'Past months repeat the current MRR until subscription history is recorded.',
            style: AT.mute,
          ),
        ],
      );
    }
    return APanel(
      title: 'MRR (estimated)',
      subtitle: 'US dollars per month. Yearly plans normalised to monthly.',
      child: child,
    );
  }

  Widget _transactionsPanel(
      List<Map<String, dynamic>> txns, Map<String, int> counts) {
    final q = _search.text.trim().toLowerCase();
    final rows = txns.where((t) {
      if (_status != 'all' && _bucket(t['status']) != _status) return false;
      if (q.isEmpty) return true;
      return '${t['username'] ?? ''}'.toLowerCase().contains(q) ||
          '${t['email'] ?? ''}'.toLowerCase().contains(q) ||
          '${t['transaction_id'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    return APanel(
      title: 'Recent transactions',
      subtitle:
          'Test (sandbox) payments are listed here but never counted as revenue.',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ASegmented<String>(
                  options: const {
                    'all': 'All',
                    'completed': 'Completed',
                    'failed': 'Failed',
                    'pending': 'Pending',
                  },
                  counts: counts,
                  value: _status,
                  onChanged: (v) => setState(() => _status = v),
                ),
                SizedBox(
                  width: 280,
                  child: ASearchField(
                    controller: _search,
                    hint: 'User, email or transaction ID',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AC.border),
          ATable<Map<String, dynamic>>(
            minWidth: 780,
            rows: rows,
            onRowTap: _openTransaction,
            empty: AEmpty(
              icon: Icons.receipt_long_outlined,
              title: txns.isEmpty
                  ? 'No transactions yet'
                  : 'No transactions match these filters',
              message: txns.isEmpty
                  ? 'Payment attempts appear here as soon as someone checks out.'
                  : null,
            ),
            columns: [
              ACol('When', width: 150, (t) => Tooltip(
                    message: fmtDateTime(t['created_at']),
                    child: Text(timeAgo(t['created_at'])),
                  )),
              ACol('Customer', flex: 3, (t) => ATwoLine(
                    '${t['username'] ?? 'User #${t['user_id'] ?? '?'}'}',
                    secondary: '${t['email'] ?? ''}',
                  )),
              ACol('Provider', width: 110,
                  (t) => Text('${t['payment_provider'] ?? '–'}')),
              ACol('Amount', width: 120, numeric: true,
                  (t) => Text(_amount(t))),
              ACol('Status', width: 130, (t) => statusPill(t['status'])),
              ACol('Transaction ID', flex: 2, (t) => Text(
                    '${t['transaction_id'] ?? '–'}',
                    style: AT.mono,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )),
            ],
          ),
          if (txns.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Text(
                'Showing ${rows.length} of the ${txns.length} most recent transactions.',
                style: AT.mute,
              ),
            ),
        ],
      ),
    );
  }

  void _openTransaction(Map<String, dynamic> t) {
    final id = '${t['transaction_id'] ?? ''}';
    showADialog<void>(
      context,
      title: 'Transaction',
      subtitle: fmtDateTime(t['created_at']),
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AField('Transaction ID', value: id, copyable: true, mono: true),
          AField('Status', child: Align(
              alignment: Alignment.centerLeft, child: statusPill(t['status']))),
          AField('Amount', value: _amount(t)),
          AField('Currency', value: '${t['currency'] ?? ''}'.toUpperCase()),
          AField('Provider', value: '${t['payment_provider'] ?? ''}'),
          AField('Customer', value: '${t['username'] ?? ''}'),
          AField('Email', value: '${t['email'] ?? ''}', copyable: true),
          AField('User ID', value: '${t['user_id'] ?? ''}'),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AButton('Copy ID', icon: Icons.copy_rounded, onPressed: id.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: id));
                      aToast(ctx, 'Transaction ID copied');
                    }),
              const SizedBox(width: 8),
              AButton('Close',
                  kind: AButtonKind.primary,
                  onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _topCustomersPanel(List<Map<String, dynamic>> all) {
    final paying = all.where((c) => _n(c['spent_cents']) > 0).toList();
    return APanel(
      title: 'Top customers',
      subtitle: 'By completed payments, all time',
      padding: paying.isEmpty ? const EdgeInsets.all(16) : const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: paying.isEmpty
          ? const AEmpty(
              icon: Icons.emoji_events_outlined,
              title: 'No paying customers yet',
              message: 'Customers are ranked here after their first completed payment.',
            )
          : Column(
              children: [
                for (var i = 0; i < paying.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          child: Text('${i + 1}', style: AT.mute),
                        ),
                        Expanded(
                          child: ATwoLine(
                            '${paying[i]['username'] ?? 'User #${paying[i]['user_id']}'}',
                            secondary: '${paying[i]['email'] ?? ''}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(fmtMoney(paying[i]['spent_cents']),
                                style: AT.num
                                    .copyWith(fontWeight: FontWeight.w600)),
                            Text(
                                '${fmtInt(paying[i]['credits_purchased'])} credits',
                                style: AT.mute),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _funnelPanel(Object? raw) {
    Widget child;
    if (raw is! Map) {
      child = const Text('Not available', style: AT.mute);
    } else {
      final registered = _n(raw['registered_users']);
      final approved = _n(raw['approved_users']);
      final purchasers = _n(raw['purchasers']);
      String pct(num part, num whole) =>
          whole > 0 ? '${(part * 100 / whole).toStringAsFixed(1)}%' : '–';
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ABarList(
            color: AC.accent,
            items: [
              ABarItem('Registered users', registered),
              ABarItem('Approved users', approved),
              ABarItem('Paying customers', purchasers),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Approval rate ${pct(approved, registered)} · '
            'approved users who paid ${pct(purchasers, approved)}. '
            'Bars are relative to registered users; test payments excluded.',
            style: AT.mute,
          ),
        ],
      );
    }
    return APanel(
      title: 'Conversion funnel',
      subtitle: 'All time, number of accounts',
      child: child,
    );
  }

  Widget _churnPanel() {
    Widget child;
    if (_churn == null) {
      child = AErrorBox(
          'Churn could not be loaded: ${_churnError ?? 'unknown error'}',
          onRetry: _load);
    } else {
      final c = _churn!;
      final canceled = _n(c['canceled_last_30d']);
      final active = _n(c['active']);
      final rate = _n(c['churn_rate']) * 100;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AField('Churn rate',
              value: (active + canceled) == 0
                  ? 'No subscriptions yet'
                  : '${rate.toStringAsFixed(1)}%'),
          AField('Cancelled', value: '${fmtInt(canceled)} in the last 30 days'),
          AField('Active now', value: '${fmtInt(active)} subscriptions'),
          const SizedBox(height: 4),
          const Text(
            'Approximate: cancellations in the last 30 days ÷ (active + cancelled).',
            style: AT.mute,
          ),
        ],
      );
    }
    return APanel(
      title: 'Subscription churn',
      subtitle: 'Last 30 days',
      child: child,
    );
  }
}
