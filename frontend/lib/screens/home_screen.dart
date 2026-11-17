import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/refresh_bus.dart';
import '../core/utils/server_time.dart';
import '../providers/active_searches_provider.dart';
import '../providers/credit_provider.dart';
import '../providers/scraper_provider.dart';
import '../providers/search_setup_provider.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../widgets/app_shell.dart';

/// Home (plan §6.1, mockup 01_home): primary action, the running search (if
/// any), the balance and the last five searches with their next step.
///
/// Page body only; shown inside [AppShell] by the router.
class HomeScreen extends StatefulWidget {
  /// Injectable for tests.
  final ApiService? api;

  const HomeScreen({super.key, this.api});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _recentLimit = 5;
  static const int _monthlyMaxTotal = 100;

  late final ApiService _api = widget.api ?? ApiService();

  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _jobs = const [];
  int _total = 0;
  _MonthSummary? _month;
  int _loadGeneration = 0;
  int _lastActiveCount = -1;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.page('/home');
    RefreshBus.jobsChanged.addListener(_onJobsChanged);
    unawaited(CreditProvider.instance.loadConfig());
    _load();
  }

  @override
  void dispose() {
    RefreshBus.jobsChanged.removeListener(_onJobsChanged);
    super.dispose();
  }

  void _onJobsChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    final generation = ++_loadGeneration;
    if (!silent || _error != null) {
      setState(() {
        _loading = _jobs.isEmpty;
        _error = null;
      });
    }
    try {
      final page = await _api.getJobs(limit: _recentLimit);
      if (!mounted || generation != _loadGeneration) return;
      final jobs = List<Map<String, dynamic>>.from(page['jobs'] as List);
      final total = (page['total'] as num?)?.toInt() ?? jobs.length;
      setState(() {
        _jobs = jobs;
        _total = total;
        _loading = false;
        _error = null;
      });
      unawaited(_loadMonth(generation, jobs, total));
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  /// "This month" is shown only when it can be exact: the user has at most
  /// 100 searches and all of this month's searches were fetched.
  Future<void> _loadMonth(int generation, List<Map<String, dynamic>> recent, int total) async {
    if (total > _monthlyMaxTotal) {
      if (mounted) setState(() => _month = null);
      return;
    }
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month);
    var jobs = recent;
    final coversAll = recent.length >= total;
    final oldest = recent.isEmpty ? null : parseServerTimeLocal(recent.last['created_at']);
    final coversMonth = oldest != null && oldest.isBefore(monthStart);
    if (!coversAll && !coversMonth) {
      try {
        final page = await _api.getJobs(limit: _monthlyMaxTotal);
        jobs = List<Map<String, dynamic>>.from(page['jobs'] as List);
        final t = (page['total'] as num?)?.toInt() ?? jobs.length;
        if (t > _monthlyMaxTotal || jobs.length < t) {
          if (mounted && generation == _loadGeneration) setState(() => _month = null);
          return;
        }
      } catch (_) {
        if (mounted && generation == _loadGeneration) setState(() => _month = null);
        return;
      }
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() => _month = _MonthSummary.from(jobs, monthStart));
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _load(silent: true),
      CreditProvider.instance.refresh(),
      context.read<ActiveSearchesProvider>().refresh(),
    ]);
  }

  void _openSearch(Map<String, dynamic> job) {
    Navigator.of(context).pushNamed('/searches/${job['job_id']}');
  }

  void _runAgain(Map<String, dynamic> job) {
    context.read<SearchSetupProvider>().loadFromJob(job);
    Navigator.of(context).pushNamed('/find/details');
  }

  @override
  Widget build(BuildContext context) {
    final active = context.watch<ActiveSearchesProvider>();
    // A search finished or started: refresh the recent list.
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
      final firstVisit = !_loading && _error == null && _total == 0 && !active.hasActive;
      final runningJobs = _runningJobs(active);

      final children = <Widget>[
        if (firstVisit)
          const _EmptyState()
        else
          _Hero(
            lastJob: _jobs.isEmpty ? null : _jobs.first,
            onRunAgain: _runAgain,
            phone: phone,
          ),
        const SizedBox(height: 16),
        _RunningAndCredits(
          running: runningJobs,
          serverNow: active.serverNow,
          phone: phone,
          onOpen: _openSearch,
        ),
        if (!firstVisit) ...[
          const SizedBox(height: 16),
          _RecentSearches(
            loading: _loading,
            error: _error,
            // Running rows use the same live numbers as the Running now card.
            jobs: _withLiveCounts(_jobs, runningJobs),
            table: width >= 760,
            onRetry: _load,
            onRefresh: () => _load(silent: true),
            onOpen: _openSearch,
          ),
          if (_month != null && _error == null) ...[
            const SizedBox(height: 12),
            Text(
              _month!.label,
              style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13),
            ),
          ],
        ],
      ];

      return RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: EdgeInsets.all(pad),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Active searches, with the followed job's fresher counters.
  static List<Map<String, dynamic>> _withLiveCounts(
    List<Map<String, dynamic>> jobs,
    List<Map<String, dynamic>> live,
  ) {
    if (live.isEmpty) return jobs;
    final byId = {for (final j in live) '${j['job_id']}': j};
    return jobs.map((j) {
      final l = byId['${j['job_id']}'];
      if (l == null) return j;
      return {
        ...j,
        for (final k in const ['status', 'completed_cities', 'total_cities', 'result_count', 'credit_charged'])
          if (l[k] != null) k: l[k],
      };
    }).toList();
  }

  List<Map<String, dynamic>> _runningJobs(ActiveSearchesProvider active) {
    final followed = context.watch<ScraperProvider>().currentJob;
    return active.jobs.map((j) {
      if (followed != null && followed.jobId == '${j['job_id']}' && followed.isActive) {
        return {
          ...j,
          'status': followed.isQueued ? 'pending' : 'running',
          'completed_cities': followed.completedCities,
          'total_cities': followed.totalCities,
          'result_count': followed.resultCount,
        };
      }
      return j;
    }).toList();
  }
}

// ------------------------------------------------------------------ cards

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Card({required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: UiTokens.card,
        borderRadius: BorderRadius.circular(UiTokens.radius),
        border: Border.all(color: UiTokens.border),
      ),
      child: child,
    );
  }
}

ButtonStyle _primaryStyle() => FilledButton.styleFrom(
      backgroundColor: UiTokens.primary,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );

ButtonStyle _secondaryStyle() => OutlinedButton.styleFrom(
      foregroundColor: UiTokens.text,
      side: const BorderSide(color: UiTokens.border),
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    );

class _Hero extends StatelessWidget {
  final Map<String, dynamic>? lastJob;
  final void Function(Map<String, dynamic>) onRunAgain;
  final bool phone;

  const _Hero({required this.lastJob, required this.onRunAgain, required this.phone});

  static String runAgainLabel(Map<String, dynamic> job) {
    final category = jobCategory(job);
    final cities = jobCities(job);
    final place = jobRegion(job) ??
        (cities.isNotEmpty ? SearchSetupProvider.cityNameOf(cities.first) : null);
    return place == null ? 'Run "$category" again' : 'Run "$category · $place" again';
  }

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      FilledButton.icon(
        style: _primaryStyle(),
        onPressed: () => Navigator.of(context).pushNamed('/find'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Find leads'),
      ),
      if (lastJob != null)
        OutlinedButton(
          style: _secondaryStyle(),
          onPressed: () => onRunAgain(lastJob!),
          child: Text(runAgainLabel(lastJob!), overflow: TextOverflow.ellipsis),
        ),
    ];
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: const Text(
            'Find business leads',
            style: TextStyle(color: UiTokens.text, fontSize: 24, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Choose a country, cities and a business type. You see the maximum '
          'cost before anything is charged.',
          style: TextStyle(color: UiTokens.textSecondary, fontSize: 15, height: 1.4),
        ),
      ],
    );
    return _Card(
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, children: buttons),
              ],
            )
          : Wrap(
              spacing: 24,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: text),
                Wrap(spacing: 12, runSpacing: 12, children: buttons),
              ],
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: const Text(
              'Find your first leads',
              style: TextStyle(color: UiTokens.text, fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Pick a country and cities, choose a business type, and we'll collect "
            'names, phones and websites from Google Maps.',
            style: TextStyle(color: UiTokens.textSecondary, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: _primaryStyle(),
            onPressed: () => Navigator.of(context).pushNamed('/find'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Find leads'),
          ),
        ],
      ),
    );
  }
}

class _RunningAndCredits extends StatelessWidget {
  final List<Map<String, dynamic>> running;
  final DateTime serverNow;
  final bool phone;
  final void Function(Map<String, dynamic>) onOpen;

  const _RunningAndCredits({
    required this.running,
    required this.serverNow,
    required this.phone,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final runningCards = [
      for (final job in running) _RunningCard(job: job, serverNow: serverNow, onOpen: onOpen),
    ];
    const credits = _CreditsCard();
    if (phone || runningCards.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in runningCards) ...[c, const SizedBox(height: 16)],
          if (runningCards.isEmpty && !phone)
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: credits,
              ),
            )
          else
            credits,
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < runningCards.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  Expanded(child: runningCards[i]),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(child: credits),
        ],
      ),
    );
  }
}

class _RunningCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final DateTime serverNow;
  final void Function(Map<String, dynamic>) onOpen;

  const _RunningCard({required this.job, required this.serverNow, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final queued = '${job['status']}' == 'pending';
    final done = jobInt(job, 'completed_cities');
    final total = jobInt(job, 'total_cities');
    final leads = jobInt(job, 'result_count');
    final created = parseServerTime(job['created_at']);
    final started = created == null ? null : formatAgo(serverNow.difference(created));
    final progressLine = queued
        ? 'Waiting for a free search slot.'
        : [
            '$done of $total cities done',
            '${formatCount(leads)} ${leads == 1 ? 'lead' : 'leads'} so far',
            if (started != null) 'started $started',
          ].join(' · ');

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Running now',
                  style: TextStyle(
                    color: UiTokens.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SearchStatusBadge(job: job),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: jobCategory(job),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: ' · ${jobCitiesInPlace(job)}'),
            ]),
            style: const TextStyle(color: UiTokens.text, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(progressLine, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
          const SizedBox(height: 12),
          Semantics(
            label: '$done of $total cities done',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: total > 0 ? (done / total).clamp(0.0, 1.0) : 0,
                minHeight: 8,
                backgroundColor: UiTokens.border,
                valueColor: const AlwaysStoppedAnimation(UiTokens.searchingFg),
              ),
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            style: _secondaryStyle(),
            onPressed: () => onOpen(job),
            child: const Text('View progress'),
          ),
        ],
      ),
    );
  }
}

class _CreditsCard extends StatelessWidget {
  const _CreditsCard();

  @override
  Widget build(BuildContext context) {
    final credits = context.watch<CreditProvider>();
    final min = credits.minJobCost;
    final low = credits.hasValue && min != null && credits.balance < min;

    Widget balance;
    if (credits.hasValue) {
      balance = Text(
        formatCount(credits.balance),
        style: const TextStyle(color: UiTokens.text, fontSize: 28, fontWeight: FontWeight.w700),
      );
    } else if (credits.error != null && !credits.refreshing) {
      balance = Row(
        children: [
          const Flexible(
            child: Text(
              "We couldn't load your balance.",
              style: TextStyle(color: UiTokens.textSecondary, fontSize: 14),
            ),
          ),
          TextButton(
            onPressed: () => CreditProvider.instance.refresh(),
            child: const Text('Try again'),
          ),
        ],
      );
    } else {
      balance = const SizedBox(
        height: 34,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Credits',
            style: TextStyle(color: UiTokens.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          balance,
          if (low) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1),
                  child: Icon(Icons.warning_amber_rounded, size: 18, color: UiTokens.partialFg),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Not enough for a search — the smallest search costs '
                    '${formatCount(min)} credits.',
                    style: const TextStyle(color: UiTokens.partialFg, fontSize: 13, height: 1.35),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: _primaryStyle(),
              onPressed: () => AppNav.go(context, '/credits'),
              child: const Text('Get credits'),
            ),
          ] else ...[
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: UiTokens.accent,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 44),
                textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              onPressed: () => AppNav.go(context, '/credits'),
              child: const Text('Get credits ›'),
            ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------- recent searches

class _RecentSearches extends StatelessWidget {
  final bool loading;
  final Object? error;
  final List<Map<String, dynamic>> jobs;
  final bool table;
  final VoidCallback onRetry;
  final VoidCallback onRefresh;
  final void Function(Map<String, dynamic>) onOpen;

  const _RecentSearches({
    required this.loading,
    required this.error,
    required this.jobs,
    required this.table,
    required this.onRetry,
    required this.onRefresh,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (error != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "We couldn't load your searches. Your data is safe.",
              style: TextStyle(color: UiTokens.text, fontSize: 14),
            ),
            const SizedBox(height: 10),
            OutlinedButton(style: _secondaryStyle(), onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      );
    } else if (jobs.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No searches yet.', style: TextStyle(color: UiTokens.textSecondary)),
      );
    } else if (table) {
      body = _RecentTable(jobs: jobs, onOpen: onOpen);
    } else {
      body = Column(
        children: [
          for (var i = 0; i < jobs.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: UiTokens.border),
            _RecentRow(job: jobs[i], onOpen: onOpen),
          ],
        ],
      );
    }

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: const Text(
                    'Recent searches',
                    style: TextStyle(color: UiTokens.text, fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: loading ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded, color: UiTokens.textSecondary),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: UiTokens.accent,
                  minimumSize: const Size(0, 44),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: () => AppNav.go(context, '/searches'),
                child: const Text('All searches ›'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          body,
        ],
      ),
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
        if (note != null)
          TextSpan(text: ' $note', style: const TextStyle(color: UiTokens.textMuted, fontSize: 12)),
      ]),
      textAlign: align,
      style: const TextStyle(color: UiTokens.text, fontSize: 14),
    );
  }
}

class _RecentTable extends StatelessWidget {
  final List<Map<String, dynamic>> jobs;
  final void Function(Map<String, dynamic>) onOpen;

  const _RecentTable({required this.jobs, required this.onOpen});

  static const _head = TextStyle(color: UiTokens.textSecondary, fontSize: 12, fontWeight: FontWeight.w600);

  Widget _cell(Widget child, {Alignment align = Alignment.centerLeft}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Align(alignment: align, child: child),
      );

  @override
  Widget build(BuildContext context) {
    const border = BoxDecoration(border: Border(bottom: BorderSide(color: UiTokens.border)));
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(1.1),
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
                  JobCitiesLine(job: job, fontSize: 12),
                  if (jobCityOutcomeLine(job) case final line?) ...[
                    const SizedBox(height: 2),
                    Text(line, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 12)),
                  ],
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
              _cell(OutlinedButton(
                style: _secondaryStyle(),
                onPressed: () => onOpen(job),
                child: Text(jobActionLabel(job)),
              )),
            ],
          ),
      ],
    );
  }
}

/// Phone/narrow layout: one stacked row per search.
class _RecentRow extends StatelessWidget {
  final Map<String, dynamic> job;
  final void Function(Map<String, dynamic>) onOpen;

  const _RecentRow({required this.job, required this.onOpen});

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
                child: Text(
                  jobCategory(job),
                  style: const TextStyle(color: UiTokens.text, fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(child: SearchStatusBadge(job: job)),
            ],
          ),
          const SizedBox(height: 2),
          JobCitiesLine(job: job),
          if (jobCityOutcomeLine(job) case final line?) ...[
            const SizedBox(height: 2),
            Text(line, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
          ],
          const SizedBox(height: 4),
          Text(
            '$leadsText · ${formatServerDateTime(job['created_at'])}',
            style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Text('Credits used: ', style: TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
              Expanded(child: _CreditsCell(job: job, align: TextAlign.left)),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: _secondaryStyle(),
            onPressed: () => onOpen(job),
            child: Text(jobActionLabel(job)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ month line

class _MonthSummary {
  final int searches;
  final int leads;
  final int credits;

  const _MonthSummary(this.searches, this.leads, this.credits);

  factory _MonthSummary.from(List<Map<String, dynamic>> jobs, DateTime monthStart) {
    var searches = 0;
    var leads = 0;
    var credits = 0;
    for (final j in jobs) {
      final created = parseServerTimeLocal(j['created_at']);
      if (created == null || created.isBefore(monthStart)) continue;
      searches++;
      leads += jobInt(j, 'result_count');
      final used = jobInt(j, 'credit_charged') - jobInt(j, 'credit_refunded');
      credits += used < 0 ? 0 : used;
    }
    return _MonthSummary(searches, leads, credits);
  }

  String get label => 'This month: ${plural(searches, 'search', 'searches')} · '
      '${plural(leads, 'lead', 'leads')} · ${plural(credits, 'credit', 'credits')} used';
}
