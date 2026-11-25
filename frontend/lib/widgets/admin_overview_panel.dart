import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/server_time.dart';
import '../services/api_service.dart';

/// Admin overview with real time windows.
///
/// Before: a "Last 24h" badge sat above lifetime totals, "Active Sessions"
/// showed a hard-coded 0 and "API Health" showed a hard-coded "OK" (neither
/// field existed in the API). Now:
/// * Activity cards are filtered to the selected range (24h / 7d / 30d / all).
/// * "Right now" cards are a labelled current snapshot.
/// * Internal API health comes from /api/admin/health (real dependency checks)
///   and public reachability is measured from this browser; both show
///   Unknown/Unreachable on failure, never a default "OK".
class AdminOverviewPanel extends StatefulWidget {
  final ApiService apiService;
  /// null = could not be loaded (shown as Unavailable, never 0).
  final int? activePromos;
  final int? promoUses;
  final VoidCallback? onOpenSearches;

  const AdminOverviewPanel({
    super.key,
    required this.apiService,
    required this.activePromos,
    required this.promoUses,
    this.onOpenSearches,
  });

  @override
  State<AdminOverviewPanel> createState() => _AdminOverviewPanelState();
}

class _AdminOverviewPanelState extends State<AdminOverviewPanel> {
  static const _ranges = <String, String>{
    '24h': '24 hours',
    '7d': '7 days',
    '30d': '30 days',
    'all': 'All time',
  };

  String _range = '24h';
  // Only the newest request of each kind may update the view, so a slow
  // response for an earlier range (or an earlier re-check) is ignored.
  int _overviewSeq = 0;
  int _statusSeq = 0;
  Map<String, dynamic>? _overview;
  String? _overviewError;
  bool _overviewLoading = true;

  Map<String, dynamic>? _health;
  String? _healthError;
  bool _healthLoading = true;

  int? _probeMs;
  String? _probeError;
  bool _probeLoading = true;
  DateTime? _checkedAt;

  @override
  void initState() {
    super.initState();
    _loadOverview();
    _loadStatus();
  }

  Future<void> _loadOverview() async {
    final range = _range;
    final seq = ++_overviewSeq;
    setState(() {
      _overviewLoading = true;
      _overviewError = null;
    });
    try {
      final data = await widget.apiService.getAdminOverview(range);
      if (!mounted || seq != _overviewSeq || range != _range) return;
      setState(() {
        _overview = data;
        _overviewLoading = false;
      });
    } catch (e) {
      if (!mounted || seq != _overviewSeq || range != _range) return;
      setState(() {
        _overview = null;
        _overviewError = e.toString().replaceFirst('Exception: ', '');
        _overviewLoading = false;
      });
    }
  }

  Future<void> _loadStatus() async {
    final seq = ++_statusSeq;
    bool current() => mounted && seq == _statusSeq;
    setState(() {
      _healthLoading = true;
      _probeLoading = true;
    });
    await Future.wait([
      () async {
        try {
          final h = await widget.apiService.getAdminHealth();
          if (current()) {
            setState(() {
              _health = h;
              _healthError = null;
            });
          }
        } catch (e) {
          if (current()) {
            setState(() {
              _health = null;
              _healthError = e.toString().replaceFirst('Exception: ', '');
            });
          }
        } finally {
          if (current()) setState(() => _healthLoading = false);
        }
      }(),
      () async {
        try {
          final ms = await widget.apiService.probePublicApi();
          if (current()) {
            setState(() {
              _probeMs = ms;
              _probeError = null;
            });
          }
        } catch (e) {
          if (current()) {
            setState(() {
              _probeMs = null;
              _probeError = e.toString().replaceFirst('Exception: ', '');
            });
          }
        } finally {
          if (current()) setState(() => _probeLoading = false);
        }
      }(),
    ]);
    if (current()) setState(() => _checkedAt = DateTime.now());
  }

  void _setRange(String r) {
    if (r == _range) return;
    setState(() => _range = r);
    _loadOverview();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rangeHeader(),
        const SizedBox(height: AppSpacing.sm),
        _activitySection(),
        const SizedBox(height: AppSpacing.lg),
        _snapshotSection(),
        const SizedBox(height: AppSpacing.lg),
        _statusSection(),
      ],
    );
  }

  Widget _rangeHeader() {
    final w = _overview?['window'] as Map?;
    String? span;
    if (w != null) {
      final start = parseServerTimeLocal(w['start']);
      final end = parseServerTimeLocal(w['end']);
      span = start == null
          ? 'Everything recorded up to ${_fmtDate(end)}'
          : '${_fmtDate(start)} → ${_fmtDate(end)}';
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Overview',
                style: AppTypography.titleMedium.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            if (span != null)
              Text(span,
                  key: const Key('overview-window-span'),
                  style:
                      AppTypography.labelSmall.copyWith(color: Colors.white54)),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in _ranges.entries)
              ChoiceChip(
                key: Key('range-${e.key}'),
                label: Text(e.value),
                selected: _range == e.key,
                onSelected: (_) => _setRange(e.key),
                selectedColor: AppColors.brandPurple.withValues(alpha: 0.35),
                backgroundColor: AppColors.surfaceDark,
                labelStyle: AppTypography.labelSmall.copyWith(
                    color: _range == e.key ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w600),
                side: const BorderSide(color: AppColors.elevatedCardDark),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(),
              style: AppTypography.labelSmall
                  .copyWith(color: Colors.white60, letterSpacing: 1.1)),
          Text(subtitle,
              style: AppTypography.labelSmall.copyWith(color: Colors.white38)),
        ],
      ),
    );
  }

  Widget _activitySection() {
    final label = _ranges[_range]!;
    final scope =
        _range == 'all' ? 'All time' : 'Last $label';
    if (_overviewLoading && _overview == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Activity · $scope', 'Loading…'),
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(
                child: CircularProgressIndicator(
                    key: Key('overview-loading'),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.brandPurple))),
          ),
        ],
      );
    }
    if (_overview == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Activity · $scope', 'Filtered to the selected range'),
          _errorCard("Couldn't load activity for this range.",
              _overviewError, _loadOverview,
              key: const Key('overview-error')),
        ],
      );
    }
    final m = Map<String, dynamic>.from(_overview!['metrics'] ?? const {});
    final defs = Map<String, dynamic>.from(_overview!['definitions'] ?? const {});
    final byStatus = m['searches_by_status'] is Map
        ? Map<String, dynamic>.from(m['searches_by_status'])
        : null;
    String? statusLine;
    if (byStatus != null && byStatus.isNotEmpty) {
      statusLine = byStatus.entries.map((e) => '${e.value} ${e.key}').join(' · ');
    }
    final cards = <_Card>[
      _Card('New users', m['new_users'], Icons.person_add_alt_1,
          AppColors.brandPurple, 'Accounts created in range.',
          tip: defs['new_users']),
      _Card('Active users', m['active_users'], Icons.how_to_reg,
          AppColors.blue, 'Accounts with a sign-in, search or other audited action in range. Not live sessions.',
          tip: defs['active_users']),
      _Card('Searches started', m['searches_started'], Icons.travel_explore,
          AppColors.blue, statusLine ?? 'Searches created in range.',
          tip: defs['searches_started'], onTap: widget.onOpenSearches),
      _Card('Leads delivered', m['leads_delivered'], Icons.checklist,
          AppColors.successGreen, 'Leads stored for searches started in range.',
          tip: defs['leads_delivered']),
      _Card('Search charges', m['credits_charged_gross'],
          Icons.south_east, AppColors.warningYellow,
          'Charged when searches started, before refunds.',
          tip: defs['credits_charged_gross']),
      _Card('Search refunds', m['credits_refunded'], Icons.undo,
          AppColors.successGreen, 'Refunds for undelivered work.',
          tip: defs['credits_refunded']),
      _Card('Net search usage', m['credits_charged_net'], Icons.payments,
          AppColors.brandOrange, 'Search charges minus search refunds.',
          tip: defs['credits_charged_net']),
      _Card('Paid credits', m['paid_credits'], Icons.add_card,
          AppColors.successGreen, 'Completed live payments, each counted once.',
          tip: defs['paid_credits']),
      _Card('Free signup credits', m['starting_credits'], Icons.redeem,
          AppColors.infoBlue, 'Granted on approval. Not purchases.',
          tip: defs['starting_credits']),
      _Card('Staff grants', m['admin_grants'], Icons.volunteer_activism,
          AppColors.brandPurple, 'Credits added by staff.',
          tip: defs['admin_grants']),
      if (m['sandbox_test_credits'] == null ||
          (m['sandbox_test_credits'] as num) > 0)
        _Card('Sandbox test credits', m['sandbox_test_credits'], Icons.science,
            AppColors.warningYellow, 'Test payments. No money charged.',
            tip: defs['sandbox_test_credits']),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Activity · $scope',
            _overviewLoading ? 'Updating…' : 'Filtered to the selected range'),
        _grid(cards),
      ],
    );
  }

  Widget _snapshotSection() {
    final s = _overview == null
        ? null
        : Map<String, dynamic>.from(_overview!['snapshot'] ?? const {});
    final cards = <_Card>[
      _Card('Total users', s?['total_users'], Icons.group, AppColors.brandPurple,
          'All accounts.'),
      _Card('Pending approval', s?['pending_users'], Icons.pending_actions,
          AppColors.warningYellow, 'Accounts waiting for approval.'),
      _Card('Credits in circulation', s?['credits_in_circulation'],
          Icons.account_balance_wallet, AppColors.purple,
          'Sum of all current balances.'),
      _Card('Searches in progress', s?['searches_in_progress'],
          Icons.autorenew, AppColors.blue, 'Pending or running now.'),
      _Card('Credit requests', s?['pending_credit_requests'],
          Icons.request_quote, AppColors.amber, 'Awaiting review.'),
      _Card('Active promos', widget.activePromos,
          Icons.confirmation_number_rounded, AppColors.amber,
          'Promo codes switched on.'),
      _Card('Promo uses', widget.promoUses, Icons.local_offer_rounded,
          AppColors.brandOrange, 'All-time uses across all codes.'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Right now', 'Current values; not affected by the range'),
        _grid(cards),
      ],
    );
  }

  Widget _statusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _sectionTitle(
                  'System status',
                  _checkedAt == null
                      ? 'Checking…'
                      : 'Checked ${_fmtTime(_checkedAt!)}'),
            ),
            IconButton(
              tooltip: 'Re-check',
              onPressed:
                  _healthLoading || _probeLoading ? null : () => _loadStatus(),
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white54),
            ),
          ],
        ),
        LayoutBuilder(builder: (context, c) {
          final two = c.maxWidth >= 640;
          final w = two ? (c.maxWidth - AppSpacing.sm) / 2 : c.maxWidth;
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              SizedBox(width: w, child: _healthCard()),
              SizedBox(width: w, child: _probeCard()),
            ],
          );
        }),
      ],
    );
  }

  Widget _healthCard() {
    if (_healthLoading && _health == null) {
      return _statusShell('Internal API health', 'Checking…', Colors.white54,
          Icons.health_and_safety_outlined, const []);
    }
    if (_health == null) {
      return _statusShell(
        'Internal API health',
        'Unknown',
        Colors.white54,
        Icons.help_outline,
        [
          'The health check could not be fetched, so the backend status is unknown.',
          if (_healthError != null) _healthError!,
        ],
        key: const Key('health-unknown'),
      );
    }
    final status = _health!['status']?.toString() ?? 'unknown';
    final checks = Map<String, dynamic>.from(_health!['checks'] ?? const {});
    String line(String name, String key) {
      final c = checks[key] is Map ? Map<String, dynamic>.from(checks[key]) : null;
      if (c == null) return '$name: unknown';
      final st = c['status'] ?? 'unknown';
      final extra = <String>[];
      if (c['latency_ms'] != null) extra.add('${c['latency_ms']} ms');
      if (c['applied'] != null) extra.add('v${c['applied']}');
      if (c['last_pass_seconds_ago'] != null) {
        extra.add('last pass ${c['last_pass_seconds_ago']}s ago');
      }
      if (c['detail'] != null && st != 'ok') extra.add('${c['detail']}');
      return '$name: $st${extra.isEmpty ? '' : ' (${extra.join(', ')})'}';
    }

    return _statusShell(
      'Internal API health',
      _statusWord(status),
      _statusColor(status),
      Icons.health_and_safety_outlined,
      [
        line('Database', 'database'),
        line('Schema migrations', 'migrations'),
        line('Search runner', 'job_runner'),
        line('Tunnel connector', 'tunnel_connector'),
      ],
      key: Key('health-$status'),
    );
  }

  Widget _probeCard() {
    const desc =
        'Measured from this browser: /api on this site → Cloudflare tunnel → backend.';
    if (_probeLoading && _probeMs == null && _probeError == null) {
      return _statusShell('Public API reachability', 'Checking…',
          Colors.white54, Icons.public, const [desc]);
    }
    if (_probeMs == null) {
      return _statusShell(
        'Public API reachability',
        'Unreachable',
        AppColors.dangerRed,
        Icons.public_off,
        [desc, if (_probeError != null) _probeError!],
        key: const Key('probe-unreachable'),
      );
    }
    return _statusShell(
      'Public API reachability',
      'Reachable · $_probeMs ms',
      AppColors.successGreen,
      Icons.public,
      const [desc],
      key: const Key('probe-ok'),
    );
  }

  // ---------------------------------------------------------------- pieces

  Widget _grid(List<_Card> cards) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final cols = w >= 1200
          ? 6
          : w >= 900
              ? 4
              : w >= 560
                  ? 3
                  : 2;
      final tile = (w - (cols - 1) * AppSpacing.sm) / cols;
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final card in cards) SizedBox(width: tile, child: _card(card)),
        ],
      );
    });
  }

  Widget _card(_Card c) {
    final unavailable = c.value == null;
    final body = Container(
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.elevatedCardDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: c.color.withValues(alpha: 0.15),
                borderRadius: AppSpacing.borderRadiusSm,
              ),
              child: Icon(c.icon, color: c.color, size: 16),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSmall.copyWith(
                      color: Colors.white70, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            unavailable
                ? (_overviewLoading ? '…' : 'Unavailable')
                : _fmtNum(c.value),
            style: unavailable
                ? AppTypography.titleSmall.copyWith(color: Colors.white38)
                : AppTypography.headlineSmall.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(c.definition,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall
                  .copyWith(color: Colors.white38, height: 1.25)),
        ],
      ),
    );
    Widget out = body;
    if (c.tip != null && '${c.tip}'.isNotEmpty) {
      out = Tooltip(message: '${c.tip}', waitDuration: const Duration(milliseconds: 400), child: out);
    }
    if (c.onTap != null) {
      out = InkWell(
          onTap: c.onTap, borderRadius: AppSpacing.borderRadiusLg, child: out);
    }
    return out;
  }

  Widget _statusShell(String title, String value, Color color, IconData icon,
      List<String> lines,
      {Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(title,
                  style: AppTypography.labelSmall.copyWith(
                      color: Colors.white70, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 4),
          Text(value,
              style: AppTypography.titleMedium
                  .copyWith(color: color, fontWeight: FontWeight.w700)),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(l,
                  style: AppTypography.labelSmall
                      .copyWith(color: Colors.white54, height: 1.3)),
            ),
        ],
      ),
    );
  }

  Widget _errorCard(String title, String? detail, VoidCallback onRetry,
      {Key? key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.dangerRed.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline, color: AppColors.dangerRed),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: AppTypography.bodyMedium.copyWith(color: Colors.white)),
              if (detail != null)
                Text(detail,
                    style: AppTypography.labelSmall
                        .copyWith(color: Colors.white54)),
            ],
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]),
    );
  }

  static String _statusWord(String s) {
    switch (s) {
      case 'ok':
        return 'OK';
      case 'degraded':
        return 'Degraded';
      case 'failing':
        return 'Failing';
      case 'missing':
        return 'Missing';
      case 'stale':
        return 'Stale';
      case 'down':
        return 'Down';
      default:
        return 'Unknown';
    }
  }

  static Color _statusColor(String s) {
    switch (s) {
      case 'ok':
        return AppColors.successGreen;
      case 'degraded':
      case 'stale':
      case 'missing':
      case 'failing':
        return AppColors.warningYellow;
      case 'down':
        return AppColors.dangerRed;
      default:
        return Colors.white54;
    }
  }

  static String _fmtNum(dynamic v) {
    if (v is! num) return '$v';
    final s = v.toInt().abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}$b';
  }

  static String _two(int x) => x.toString().padLeft(2, '0');

  static String _fmtDate(DateTime? d) => d == null
      ? '—'
      : '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

  static String _fmtTime(DateTime d) =>
      '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

class _Card {
  final String title;
  final dynamic value;
  final IconData icon;
  final Color color;
  final String definition;
  final dynamic tip;
  final VoidCallback? onTap;

  _Card(this.title, this.value, this.icon, this.color, this.definition,
      {this.tip, this.onTap});
}
