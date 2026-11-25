import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/server_time.dart';
import '../services/api_service.dart';

/// Admin view of one account's credits: classified totals, a reconciliation
/// flag and the paginated ledger. Replaces the old "KPIs" modal whose
/// "Credits Purchased" counted free credits and admin grants, and whose
/// "Credits Used" ignored refunds (docs/ADMIN_CREDIT_REPORTING.md).
class AdminCreditAccountDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String username;
  final int pageSize;

  const AdminCreditAccountDialog({
    super.key,
    required this.apiService,
    required this.userId,
    required this.username,
    this.pageSize = 25,
  });

  @override
  State<AdminCreditAccountDialog> createState() =>
      _AdminCreditAccountDialogState();
}

class _AdminCreditAccountDialogState extends State<AdminCreditAccountDialog> {
  Map<String, dynamic>? _report;
  Map<String, dynamic>? _kpis;
  String? _error;
  bool _loading = true;
  bool _paging = false;
  int _page = 1;
  int _requestSeq = 0; // only the newest request may update the view

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? page}) async {
    final target = page ?? _page;
    final seq = ++_requestSeq;
    setState(() {
      if (_report == null) {
        _loading = true;
      } else {
        _paging = true;
      }
      _error = null;
    });
    try {
      final report = await widget.apiService.getUserCreditReport(widget.userId,
          page: target, pageSize: widget.pageSize);
      Map<String, dynamic>? kpis = _kpis;
      if (kpis == null) {
        try {
          kpis = await widget.apiService.getUserKpis(widget.userId);
        } catch (_) {
          kpis = null; // activity dates are optional; credits still render
        }
      }
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _report = report;
        _kpis = kpis;
        _page = (report['pagination']?['page'] as num?)?.toInt() ?? target;
        _loading = false;
        _paging = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
        _paging = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final narrow = size.width < 640;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
          horizontal: narrow ? 8 : 24, vertical: narrow ? 12 : 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 960,
          maxHeight: size.height * (narrow ? 0.96 : 0.9),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(color: AppColors.elevatedCardDark),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              const Divider(height: 1, color: AppColors.elevatedCardDark),
              Flexible(child: _body(narrow)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              color: AppColors.brandPurple, size: 22),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Credit account · ${widget.username}',
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleMedium.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _paging ? null : () => _load(),
            icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _body(bool narrow) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(
          child: CircularProgressIndicator(
            key: Key('credit-account-loading'),
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandPurple),
          ),
        ),
      );
    }
    if (_report == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.dangerRed),
            const SizedBox(height: AppSpacing.xs),
            Text("Couldn't load this account's credit history.",
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: Colors.white)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall
                        .copyWith(color: Colors.white54)),
              ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () => _load(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Try again'),
            ),
          ],
        ),
      );
    }
    final r = _report!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _reconciliationBanner(Map<String, dynamic>.from(r['reconciliation'] ?? const {})),
          const SizedBox(height: AppSpacing.md),
          _summary(Map<String, dynamic>.from(r['summary'] ?? const {}),
              Map<String, dynamic>.from(r['definitions'] ?? const {}), narrow),
          const SizedBox(height: AppSpacing.lg),
          _history(r, narrow),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- banner

  Widget _reconciliationBanner(Map<String, dynamic> rec) {
    final status = rec['status']?.toString() ?? 'unknown';
    final sum = _n(rec['ledger_sum']);
    final bal = _n(rec['current_balance']);
    late final Color color;
    late final IconData icon;
    late final String title;
    late final String detail;
    switch (status) {
      case 'reconciled':
        color = AppColors.successGreen;
        icon = Icons.verified_outlined;
        title = 'History reconciles to the current balance';
        detail =
            'Starting from 0, the ledger entries sum to ${_fmt(sum)} = current balance ${_fmt(bal)}, '
            'and every running balance matches the entry before it.';
        break;
      case 'no_history':
        color = Colors.white54;
        icon = Icons.info_outline;
        title = 'No credit activity yet';
        detail = 'Balance is 0 and there are no ledger entries.';
        break;
      case 'mismatch':
        color = AppColors.dangerRed;
        icon = Icons.report_gmailerrorred_outlined;
        title = 'History does NOT reconcile';
        final diff = _n(rec['difference']);
        final breaks = _n(rec['chain_breaks']);
        final parts = <String>[];
        if (diff != 0) {
          parts.add(
              'Ledger sums to ${_fmt(sum)} but the balance is ${_fmt(bal)} '
              '(${diff > 0 ? '+' : ''}${_fmt(diff)} not explained by any entry).');
        }
        if (breaks > 0) {
          final first = rec['first_chain_break'];
          parts.add('$breaks running-balance break${breaks == 1 ? '' : 's'}'
              '${first is Map ? ', first at entry #${first['entry_id']} (expected ${first['expected_balance_after']}, recorded ${first['recorded_balance_after']})' : ''}.');
        }
        detail = parts.join(' ');
        break;
      default:
        color = Colors.white54;
        icon = Icons.help_outline;
        title = 'Reconciliation unavailable';
        detail = 'The server did not return a reconciliation result for this history.';
    }
    return Container(
      key: Key('reconciliation-$status'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTypography.titleSmall.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(detail,
                    style: AppTypography.bodySmall
                        .copyWith(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- summary

  Widget _summary(
      Map<String, dynamic> s, Map<String, dynamic> defs, bool narrow) {
    String def(String key, String fallback) =>
        (defs[key]?.toString().trim().isNotEmpty ?? false)
            ? defs[key].toString()
            : fallback;
    // Shown when non-zero, and always when the value is unavailable.
    bool show(String key) => s[key] == null || _n(s[key]) != 0;

    // The six headline figures, always in this order.
    final headline = <_Figure>[
      _Figure('Free signup credits', s['starting_credits'],
          'Granted on approval. Not a purchase.', AppColors.infoBlue),
      _Figure('Paid credits', s['paid_credits'],
          'Completed live payments, each counted once.', AppColors.successGreen),
      _Figure('Search charges', s['job_charges_gross'],
          'Charged when searches started, before refunds.',
          AppColors.warningYellow),
      _Figure('Search refunds', s['job_refunds'],
          'Returned for work a search did not deliver.', AppColors.successGreen),
      _Figure('Net search usage', s['job_charges_net'],
          'Search charges minus search refunds.', AppColors.brandOrange),
      _Figure('Current balance', s['current_balance'],
          'Balance in the same snapshot as the history.', Colors.white),
    ];
    final other = <_Figure>[
      _Figure('Staff grants', s['admin_grants'], def('admin_grants', ''),
          AppColors.brandPurple),
      if (show('sandbox_test_credits'))
        _Figure('Sandbox test credits (not paid)', s['sandbox_test_credits'],
            def('sandbox_test_credits', ''), AppColors.warningYellow),
      if (show('unverified_payment_credits'))
        _Figure('Unmatched payment credits', s['unverified_payment_credits'],
            def('unverified_payment_credits', ''), AppColors.dangerRed),
      if (show('promo_bonus_credits'))
        _Figure('Promo / referral bonuses', s['promo_bonus_credits'],
            'Promo codes and referral rewards.', AppColors.amber),
      if (show('subscription_credits'))
        _Figure('Subscription allocations', s['subscription_credits'],
            'Credits added by subscription renewals.', AppColors.amber),
      if (show('other_credits'))
        _Figure('Other credits (unclassified)', s['other_credits'],
            'Credit entries that match no known source.', AppColors.dangerRed),
      if (show('other_debits'))
        _Figure('Other debits (unclassified)', s['other_debits'],
            'Debit entries not tied to a search.', AppColors.dangerRed),
    ];
    final perLead = s['net_credits_per_lead_on_file'];
    final deleted = _n(s['charged_searches_since_deleted']);
    final onFile = s['searches_on_file'] == null || s['leads_on_file'] == null
        ? null
        : '${_fmt(_n(s['searches_on_file']))} / ${_fmt(_n(s['leads_on_file']))}';
    final usage = <_Figure>[
      _Figure(
          'Searches / leads on file',
          onFile,
          deleted > 0
              ? '$deleted charged search${deleted == 1 ? ' was' : 'es were'} later deleted and ${deleted == 1 ? 'is' : 'are'} not counted here.'
              : 'Searches that still exist and the leads they hold.',
          AppColors.blue),
      _Figure(
          'Net credits per lead',
          perLead == null ? '—' : (perLead as num).toStringAsFixed(2),
          perLead == null
              ? 'No leads on file, so there is nothing to divide by.'
              : def('net_credits_per_lead_on_file', ''),
          AppColors.blue),
      _Figure('Last sign-in', _kpis == null ? null : _date(_kpis!['last_login']),
          'users.last_login', Colors.white54),
      _Figure(
          'Last audited activity',
          _kpis == null ? null : _date(_kpis!['last_activity']),
          'Most recent audit event by this account.',
          Colors.white54),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _group('Credits', headline, narrow, wideCols: 6),
        const SizedBox(height: AppSpacing.sm),
        _group('Other credit sources (kept separate)', other, narrow),
        const SizedBox(height: AppSpacing.sm),
        _group('Usage and activity', usage, narrow),
      ],
    );
  }

  Widget _group(String title, List<_Figure> figures, bool narrow,
      {int wideCols = 3}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title.toUpperCase(),
            style: AppTypography.labelSmall
                .copyWith(color: Colors.white54, letterSpacing: 1.1)),
        const SizedBox(height: 6),
        LayoutBuilder(builder: (context, c) {
          final cols = narrow
              ? 2
              : (c.maxWidth > 760 ? wideCols : (wideCols > 3 ? 3 : 2));
          final w = (c.maxWidth - (cols - 1) * AppSpacing.xs) / cols;
          return Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final f in figures) SizedBox(width: w, child: _tile(f)),
            ],
          );
        }),
      ],
    );
  }

  Widget _tile(_Figure f) {
    final v = f.value;
    final unavailable = v == null;
    final text = unavailable
        ? 'Unavailable'
        : v is num
            ? _fmt(v.toInt())
            : '$v';
    return Container(
      key: Key('figure-${f.label}'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.elevatedCardDark.withValues(alpha: 0.35),
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border(left: BorderSide(color: f.color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.label,
              style: AppTypography.bodySmall.copyWith(color: Colors.white70)),
          const SizedBox(height: 2),
          Text(text,
              key: Key('figure-value-${f.label}'),
              style: unavailable
                  ? AppTypography.titleSmall.copyWith(color: Colors.white38)
                  : AppTypography.titleMedium.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w700)),
          if (f.definition.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(f.definition,
                style: AppTypography.labelSmall
                    .copyWith(color: Colors.white38, height: 1.3)),
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------- history

  Widget _history(Map<String, dynamic> r, bool narrow) {
    final items = List<Map<String, dynamic>>.from(
        (r['transactions'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e)));
    final p = Map<String, dynamic>.from(r['pagination'] ?? const {});
    final total = _n(p['total']);
    final pages = _n(p['pages']).clamp(1, 1 << 30);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                  'Transaction history · ${_fmt(total)} entr${total == 1 ? 'y' : 'ies'}',
                  style: AppTypography.titleSmall.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            if (_paging)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        const SizedBox(height: 4),
        Text('Newest first. Balance after = users.credit_balance right after the entry was written.',
            style: AppTypography.labelSmall.copyWith(color: Colors.white38)),
        const SizedBox(height: AppSpacing.xs),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text("Couldn't load that page: $_error",
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.dangerRed)),
          ),
        if (items.isEmpty)
          Container(
            key: const Key('credit-history-empty'),
            padding: const EdgeInsets.all(AppSpacing.md),
            alignment: Alignment.center,
            child: Text('No ledger entries for this account.',
                style:
                    AppTypography.bodySmall.copyWith(color: Colors.white54)),
          )
        else ...[
          if (!narrow) _tableHeader(),
          for (final t in items) narrow ? _rowCard(t) : _rowWide(t),
        ],
        if (pages > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Newer entries',
                onPressed: _page > 1
                    ? () => _load(page: _page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
                color: Colors.white70,
              ),
              Text('Page $_page of $pages',
                  key: const Key('credit-history-page'),
                  style:
                      AppTypography.bodySmall.copyWith(color: Colors.white70)),
              IconButton(
                tooltip: 'Older entries',
                onPressed: _page < pages
                    ? () => _load(page: _page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
                color: Colors.white70,
              ),
            ],
          ),
        ],
      ],
    );
  }

  static const _colDate = 132.0;
  static const _colType = 170.0;
  static const _colAmt = 80.0;
  static const _colGap = 16.0;
  static const _colBal = 104.0;

  Widget _tableHeader() {
    TextStyle h = AppTypography.labelSmall
        .copyWith(color: Colors.white54, letterSpacing: 0.6);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Row(children: [
        SizedBox(width: _colDate, child: Text('DATE', style: h)),
        SizedBox(width: _colType, child: Text('TYPE', style: h)),
        SizedBox(
            width: _colAmt,
            child: Text('AMOUNT', style: h, textAlign: TextAlign.right)),
        const SizedBox(width: _colGap),
        SizedBox(
            width: _colBal,
            child: Text('BALANCE AFTER', style: h, textAlign: TextAlign.right)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text('REASON / SOURCE', style: h)),
      ]),
    );
  }

  Widget _rowWide(Map<String, dynamic> t) {
    return Container(
      key: Key('ledger-row-${t['id']}'),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: const BoxDecoration(
        border:
            Border(top: BorderSide(color: AppColors.elevatedCardDark, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: _colDate,
              child: Text(_date(t['created_at']),
                  style: AppTypography.bodySmall
                      .copyWith(color: Colors.white70))),
          SizedBox(width: _colType, child: _typeChip(t)),
          SizedBox(width: _colAmt, child: _amount(t, TextAlign.right)),
          const SizedBox(width: _colGap),
          SizedBox(width: _colBal, child: _balance(t, TextAlign.right)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _source(t)),
        ],
      ),
    );
  }

  Widget _rowCard(Map<String, dynamic> t) {
    return Container(
      key: Key('ledger-row-${t['id']}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.elevatedCardDark.withValues(alpha: 0.3),
        borderRadius: AppSpacing.borderRadiusSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: _typeChip(t)),
            _amount(t, TextAlign.right),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Text(_date(t['created_at']),
                  style: AppTypography.labelSmall
                      .copyWith(color: Colors.white54)),
            ),
            Text('Balance ',
                style:
                    AppTypography.labelSmall.copyWith(color: Colors.white54)),
            _balance(t, TextAlign.right),
          ]),
          const SizedBox(height: 4),
          _source(t),
        ],
      ),
    );
  }

  Color _catColor(String cat) {
    switch (cat) {
      case 'purchase':
        return AppColors.successGreen;
      case 'starting_credits':
        return AppColors.infoBlue;
      case 'admin_grant':
        return AppColors.brandPurple;
      case 'job_charge':
        return AppColors.warningYellow;
      case 'job_refund':
        return AppColors.successGreen;
      case 'sandbox_test':
        return AppColors.warningYellow;
      case 'purchase_unverified':
      case 'other_credit':
      case 'other_debit':
        return AppColors.dangerRed;
      default:
        return AppColors.amber;
    }
  }

  Widget _typeChip(Map<String, dynamic> t) {
    final cat = t['category']?.toString() ?? '';
    final c = _catColor(cat);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: AppSpacing.borderRadiusSm,
        ),
        child: Text(t['category_label']?.toString() ?? cat,
            style: AppTypography.labelSmall
                .copyWith(color: c, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _amount(Map<String, dynamic> t, TextAlign align) {
    final a = _n(t['amount']);
    return Text('${a > 0 ? '+' : a < 0 ? '−' : ''}${_fmt(a.abs())}',
        textAlign: align,
        style: AppTypography.bodyMedium.copyWith(
            color: a >= 0 ? AppColors.successGreen : Colors.white,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()]));
  }

  Widget _balance(Map<String, dynamic> t, TextAlign align) {
    final ok = t['chain_ok'] == true;
    final text = Text(
        t['balance_after'] == null ? '—' : _fmt(_n(t['balance_after'])),
        textAlign: align,
        style: AppTypography.bodyMedium.copyWith(
            color: ok ? Colors.white70 : AppColors.dangerRed,
            fontFeatures: const [FontFeature.tabularFigures()]));
    if (ok) return text;
    return Tooltip(
      message:
          'Running balance break: expected ${t['expected_balance_after']} from the previous entry',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 14, color: AppColors.dangerRed),
          const SizedBox(width: 2),
          Flexible(child: text),
        ],
      ),
    );
  }

  Widget _source(Map<String, dynamic> t) {
    final job = t['job'] is Map ? Map<String, dynamic>.from(t['job']) : null;
    final pay =
        t['payment'] is Map ? Map<String, dynamic>.from(t['payment']) : null;
    final by = t['granted_by'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          (t['reason']?.toString().trim().isNotEmpty ?? false)
              ? t['reason'].toString()
              : '—',
          style: AppTypography.bodySmall.copyWith(color: Colors.white70),
        ),
        if (by != null || job != null || pay != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              if (by != null) _pill(Icons.person_outline, 'by $by', null),
              if (job != null)
                _pill(
                  Icons.travel_explore,
                  job['exists'] == true
                      ? 'Search ${_short(job['job_id'])} · ${job['status']}'
                      : 'Search ${_short(job['job_id'])} · deleted',
                  () => _showJob(job),
                ),
              if (pay != null)
                _pill(
                  Icons.receipt_long_outlined,
                  'Payment #${pay['id']} · ${pay['environment']} · ${pay['status']}',
                  () => _showPayment(pay),
                ),
            ]),
          ),
      ],
    );
  }

  Widget _pill(IconData icon, String label, VoidCallback? onTap) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.elevatedCardDark),
        borderRadius: AppSpacing.borderRadiusSm,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: onTap == null ? Colors.white38 : AppColors.infoBlue),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                  color: onTap == null ? Colors.white54 : AppColors.infoBlue,
                  decoration: onTap == null ? null : TextDecoration.underline,
                  decorationColor: AppColors.infoBlue)),
        ),
      ]),
    );
    if (onTap == null) return child;
    return InkWell(
        onTap: onTap, borderRadius: AppSpacing.borderRadiusSm, child: child);
  }

  void _showJob(Map<String, dynamic> job) {
    final exists = job['exists'] == true;
    _detailSheet('Search ${_short(job['job_id'])}', [
      ['Search ID', job['job_id']?.toString() ?? '—'],
      if (!exists)
        ['Status', 'Deleted by the user after it was charged'],
      if (exists) ...[
        ['Status', '${job['status']}'],
        ['Category', '${job['category']}'],
        ['Leads on file', _fmt(_n(job['leads']))],
        ['Charged', _fmt(_n(job['credit_charged']))],
        ['Refunded', _fmt(_n(job['credit_refunded']))],
        [
          'Net cost',
          _fmt(_n(job['credit_charged']) - _n(job['credit_refunded']))
        ],
      ],
    ], copy: job['job_id']?.toString());
  }

  void _showPayment(Map<String, dynamic> pay) {
    final cents = _n(pay['amount_cents']);
    _detailSheet('Payment #${pay['id']}', [
      ['Provider', '${pay['provider']}'],
      ['Environment', '${pay['environment']}'],
      ['Status', '${pay['status']}'],
      ['Credits', _fmt(_n(pay['credits']))],
      [
        'Amount',
        '${(cents / 100).toStringAsFixed(2)} ${pay['currency'] ?? ''}'.trim()
      ],
      if (pay['environment'] == 'sandbox')
        ['Note', 'Sandbox test payment: no money was charged.'],
    ]);
  }

  void _detailSheet(String title, List<List<String>> rows, {String? copy}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text(title,
            style: AppTypography.titleMedium.copyWith(color: Colors.white)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 110,
                          child: Text(r[0],
                              style: AppTypography.bodySmall
                                  .copyWith(color: Colors.white54))),
                      Expanded(
                          child: SelectableText(r[1],
                              style: AppTypography.bodySmall
                                  .copyWith(color: Colors.white))),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (copy != null)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: copy));
                Navigator.pop(ctx);
              },
              child: const Text('Copy ID'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- helpers

  static int _n(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static String _fmt(int v) {
    final s = v.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '${v < 0 ? '-' : ''}$b';
  }

  static String _short(dynamic id) {
    final s = '$id';
    return s.length > 8 ? s.substring(0, 8) : s;
  }

  static String _date(dynamic v) {
    final dt = parseServerTimeLocal(v);
    if (dt == null) return v == null ? 'Never' : '$v';
    String two(int x) => x.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

class _Figure {
  final String label;
  final dynamic value;
  final String definition;
  final Color color;

  _Figure(this.label, this.value, this.definition, this.color);
}
