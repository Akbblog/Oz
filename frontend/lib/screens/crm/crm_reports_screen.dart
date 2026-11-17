import 'package:flutter/material.dart';

import '../../core/crm/crm_filters.dart';
import '../../core/crm/crm_format.dart';
import '../../services/crm_api.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/crm/crm_widgets.dart';

/// Date ranges of the reports (`/crm/reports?range=`).
const List<String> crmReportRanges = ['7d', '30d', '90d', 'month', 'all'];

String crmReportRangeLabel(String r) {
  switch (r) {
    case '7d':
      return 'Last 7 days';
    case '90d':
      return 'Last 90 days';
    case 'month':
      return 'This month';
    case 'all':
      return 'All time';
    default:
      return 'Last 30 days';
  }
}

/// Local `[from, to]` dates (inclusive) of a range; nulls = unbounded.
(DateTime?, DateTime?) crmReportRange(String r, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toLocal();
  final today = DateTime(n.year, n.month, n.day);
  switch (r) {
    case '7d':
      return (today.subtract(const Duration(days: 6)), today);
    case '90d':
      return (today.subtract(const Duration(days: 89)), today);
    case 'month':
      return (DateTime(n.year, n.month), today);
    case 'all':
      return (null, null);
    default:
      return (today.subtract(const Duration(days: 29)), today);
  }
}

/// Shown next to each metric when the server sends no definition.
const Map<String, String> crmDefaultDefinitions = {
  'imported_companies': 'Unique businesses added from search results in the period. Repeat links are not counted again.',
  'open_leads': 'Records of type lead that are open at the end of the period.',
  'opportunities': 'Records converted to, or created as, opportunities.',
  'won': 'Records marked won in the period.',
  'lost': 'Records marked lost in the period.',
  'won_rate': 'Won opportunities divided by opportunities closed won or lost in the period.',
  'overdue_activities': 'Open activities whose due time has passed.',
  'activities_completed': 'Activities marked done in the period.',
  'records_without_value': 'Open opportunities without a deal value (left out of value totals).',
  'value_by_currency': 'Sum of entered deal values per currency. Currencies are never converted or added together.',
};

/// True when the report has nothing to show (no fake numbers).
bool crmReportIsEmpty(Map<String, dynamic> r) {
  const counters = [
    'imported_companies',
    'open_leads',
    'opportunities',
    'won',
    'lost',
    'overdue_activities',
    'activities_completed',
  ];
  final anyCount = counters.any((k) => crmInt(r[k]) > 0);
  final anyList = ['by_stage', 'by_source', 'lost_reasons', 'value_by_currency']
      .any((k) => crmList(r[k]).any((e) => crmInt(e['count']) > 0 || crmNum(e['open_total']) != null || crmNum(e['won_total']) != null));
  return !anyCount && !anyList;
}

/// CRM reports (`/crm/reports`): counts with their definitions beside
/// them, a date range, currencies kept apart, and "No data yet" when the
/// workspace has nothing to report.
class CrmReportsScreen extends StatefulWidget {
  final Map<String, String> initialQuery;
  final CrmApi? api;

  const CrmReportsScreen({super.key, this.initialQuery = const {}, this.api});

  @override
  State<CrmReportsScreen> createState() => _CrmReportsScreenState();
}

class _CrmReportsScreenState extends State<CrmReportsScreen> {
  late final CrmApi _api = crmApiOf(context, widget.api);
  late String _range = crmReportRanges.contains(widget.initialQuery['range']) ? widget.initialQuery['range']! : '30d';
  bool _loading = true;
  Object? _error;
  Map<String, dynamic> _r = const {};
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final (from, to) = crmReportRange(_range);
      final r = await _api.getReports(from: from, to: to);
      if (!mounted || generation != _generation) return;
      setState(() {
        _r = r;
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

  String _def(String key) {
    final d = crmMap(_r['definitions'])[key];
    final s = crmStr(d is Map ? d['text'] ?? d['definition'] : d);
    return s.isNotEmpty ? s : (crmDefaultDefinitions[key] ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return CrmPageBody(
      tab: CrmTab.reports,
      child: LayoutBuilder(builder: (context, constraints) {
        return ListView(
          padding: crmPagePadding(constraints.maxWidth),
          children: [
            CrmContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    CrmMenu<String>(
                      tooltip: 'Report period',
                      icon: Icons.date_range_rounded,
                      label: crmReportRangeLabel(_range),
                      value: _range,
                      values: crmReportRanges,
                      labelOf: crmReportRangeLabel,
                      onSelected: (v) {
                        if (v == _range) return;
                        setState(() => _range = v);
                        crmReplaceUrl(crmRoute('/crm/reports', v == '30d' ? const {} : {'range': v}));
                        _load();
                      },
                    ),
                    Text(_rangeText(), style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
                  ]),
                  const SizedBox(height: 12),
                  _body(constraints.maxWidth),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  String _rangeText() {
    final (from, to) = crmReportRange(_range);
    if (from == null || to == null) return 'Everything in your CRM';
    return '${crmDateLabel(crmDateParam(from))} – ${crmDateLabel(crmDateParam(to))} (your local dates)';
  }

  Widget _body(double width) {
    if (_loading && _r.isEmpty) return const CrmLoading(label: 'Loading reports…');
    if (_error != null) return CrmErrorView(error: _error, onRetry: _load, what: 'your reports');
    if (crmReportIsEmpty(_r)) {
      return CrmEmptyView(
        title: 'No data yet',
        icon: Icons.insights_outlined,
        body: _range == 'all'
            ? 'Reports fill in as you add businesses to your CRM and work on them.'
            : 'Nothing happened in your CRM in this period. Try a longer period.',
        actions: [
          if (_range != 'all')
            OutlinedButton(
              style: searchSecondaryButtonStyle(),
              onPressed: () {
                setState(() => _range = 'all');
                crmReplaceUrl('/crm/reports?range=all');
                _load();
              },
              child: const Text('Show all time'),
            ),
        ],
      );
    }

    final rate = crmMap(_r['won_rate']);
    final rateValue = crmNum(rate['value']);
    final rateText = rateValue == null
        ? '—'
        : '${(rateValue <= 1 ? rateValue * 100 : rateValue).toStringAsFixed(0)}%';
    final rateSub = crmInt(rate['denominator']) == 0
        ? 'No opportunities closed in this period'
        : '${formatCount(crmInt(rate['numerator']))} won of ${formatCount(crmInt(rate['denominator']))} closed';

    final metrics = <Widget>[
      _metric('Imported businesses', formatCount(crmInt(_r['imported_companies'])), 'imported_companies'),
      _metric('Open leads', formatCount(crmInt(_r['open_leads'])), 'open_leads'),
      _metric('Opportunities', formatCount(crmInt(_r['opportunities'])), 'opportunities'),
      _metric('Won', formatCount(crmInt(_r['won'])), 'won'),
      _metric('Lost', formatCount(crmInt(_r['lost'])), 'lost'),
      _metric('Won rate', rateText, 'won_rate', sub: rateSub),
      _metric('Overdue follow-ups', formatCount(crmInt(_r['overdue_activities'])), 'overdue_activities'),
      _metric('Activities completed', formatCount(crmInt(_r['activities_completed'])), 'activities_completed'),
    ];
    final cols = width >= 1000 ? 4 : (width >= 640 ? 2 : 1);
    final grid = <Widget>[];
    for (var i = 0; i < metrics.length; i += cols) {
      final row = metrics.sublist(i, (i + cols).clamp(0, metrics.length));
      grid.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: cols == 1
            ? row.first
            : IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (var k = 0; k < cols; k++) ...[
                    if (k > 0) const SizedBox(width: 12),
                    Expanded(child: k < row.length ? row[k] : const SizedBox.shrink()),
                  ],
                ]),
              ),
      ));
    }

    final currencies = crmList(_r['value_by_currency']);
    final noValue = crmInt(_r['records_without_value']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...grid,
        _listCard(
          'Deal value by currency',
          _def('value_by_currency'),
          currencies.isEmpty
              ? null
              : [
                  for (final c in currencies)
                    _line(
                      crmStr(c['currency']).toUpperCase(),
                      'Open ${crmNum(c['open_total']) == null ? '—' : crmMoney(c['open_total'], c['currency'])} · '
                          'Won ${crmNum(c['won_total']) == null ? '—' : crmMoney(c['won_total'], c['currency'])}',
                    ),
                ],
          footer: noValue > 0 ? '${plural(noValue, 'open record has', 'open records have')} no value and ${noValue == 1 ? 'is' : 'are'} not in these totals.' : null,
        ),
        _listCard('Records by stage', 'Open records in each stage now.',
            _countLines(crmList(_r['by_stage']), (e) => crmStr(crmMap(e['stage'])['name']).isNotEmpty ? crmStr(crmMap(e['stage'])['name']) : crmStr(e['stage']))),
        _listCard('Records by source search', 'Businesses imported per search (business type).',
            _countLines(crmList(_r['by_source']), (e) => crmStr(e['category']).isEmpty ? 'Search' : crmStr(e['category']))),
        _listCard('Lost reasons', 'Reasons given when records were marked lost in the period.',
            _countLines(crmList(_r['lost_reasons']), (e) => crmStr(e['name']))),
      ],
    );
  }

  List<Widget>? _countLines(List<Map<String, dynamic>> items, String Function(Map<String, dynamic>) label) {
    final rows = items.where((e) => crmInt(e['count']) > 0).toList();
    if (rows.isEmpty) return null;
    return [for (final e in rows) _line(label(e), formatCount(crmInt(e['count'])))];
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: UiTokens.text, fontSize: 14))),
          Text(value, style: const TextStyle(color: UiTokens.text, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _metric(String title, String value, String key, {String? sub}) {
    final def = _def(key);
    return Semantics(
      container: true,
      label: '$title: $value${sub == null ? '' : ', $sub'}. $def',
      excludeSemantics: true,
      child: SearchCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: UiTokens.text, fontSize: 26, fontWeight: FontWeight.w700)),
            if (sub != null) Text(sub, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 12.5)),
            const SizedBox(height: 6),
            Text(def, style: const TextStyle(color: UiTokens.textMuted, fontSize: 12, height: 1.35)),
          ],
        ),
      ),
    );
  }

  Widget _listCard(String title, String definition, List<Widget>? lines, {String? footer}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SearchCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CrmSectionTitle(title),
              Text(definition, style: const TextStyle(color: UiTokens.textMuted, fontSize: 12, height: 1.35)),
              const SizedBox(height: 8),
              if (lines == null)
                const Text('No data yet', style: TextStyle(color: UiTokens.textSecondary, fontSize: 13.5))
              else
                ...lines,
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(footer, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 12.5)),
                ),
            ],
          ),
        ),
      );
}
