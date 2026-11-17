import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/download_helper.dart';
import '../core/error_handler.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/refresh_bus.dart';
import '../providers/active_searches_provider.dart';
import '../providers/credit_provider.dart';
import '../providers/crm_provider.dart';
import '../providers/scraper_provider.dart';
import '../providers/search_setup_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/country_flag_badge.dart';
import '../widgets/crm/crm_results.dart';
import '../widgets/job_log_panel.dart';
import '../widgets/search_actions.dart';
import 'results_screen.dart';

/// Search page (`/searches/<jobId>`), plan §6.5–6.6.
///
/// Follows the search through [ScraperProvider.watchJob] (works for cold
/// deep links, after sign-in and for finished searches). While it runs: status,
/// cities progress (never a percentage), notices, credits and the technical
/// log. When it ends: a compact summary with downloads and actions, then the
/// leads ([ResultsScreen] embedded).
///
/// A light side request (GET /api/jobs/{id}) adds what the provider does not
/// keep: country/region, timestamped log lines, and the refund settlement
/// after the provider stopped polling.
class SearchDetailScreen extends StatefulWidget {
  final String jobId;
  final ApiService? api;

  const SearchDetailScreen({super.key, required this.jobId, this.api});

  @override
  State<SearchDetailScreen> createState() => _SearchDetailScreenState();
}

class _SearchDetailScreenState extends State<SearchDetailScreen> {
  late final ApiService _api = widget.api ?? ApiService();

  bool _watching = false;
  Object? _watchError;
  bool _notFound = false;

  /// Latest GET /api/jobs/{id} payload of the side request.
  Map<String, dynamic>? _meta;
  List<JobLogEntry> _logEntries = const [];
  int? _logCursor;
  bool _sideBusy = false;
  Timer? _sideTimer;

  /// Settlement checks so far (every 3 s, at most [_maxSettlementPolls]).
  int _settlementPolls = 0;
  static const int _maxSettlementPolls = 200; // 10 minutes

  bool _logOpen = false;
  bool _citiesOpen = false;
  bool _detailsOpen = false;
  bool _cancelRequested = false;
  bool _cancelling = false;
  bool _downloading = false;
  bool _deleting = false;

  String get _id => widget.jobId;

  @override
  void initState() {
    super.initState();
    unawaited(CreditProvider.instance.loadConfig());
    _watch();
    _fetchMeta();
    _sideTimer = Timer.periodic(const Duration(seconds: 3), (_) => _sideTick());
  }

  @override
  void dispose() {
    _sideTimer?.cancel();
    super.dispose();
  }

  ScrapingJob? _jobFrom(ScraperProvider p) {
    final j = p.currentJob;
    return j != null && j.jobId == _id ? j : null;
  }

  Future<void> _watch() async {
    if (_watching) return;
    _watching = true;
    if (mounted) {
      setState(() {
        _watchError = null;
      });
    }
    try {
      await context.read<ScraperProvider>().watchJob(_id);
    } on NotFoundException {
      if (mounted) setState(() => _notFound = true);
    } catch (e) {
      if (mounted) setState(() => _watchError = e);
    } finally {
      _watching = false;
    }
  }

  /// Side request: country/region, timestamped log lines and settlement.
  Future<void> _fetchMeta() async {
    if (_sideBusy) return;
    _sideBusy = true;
    try {
      final data = await _api.getJobStatus(
        _id,
        includeResults: false,
        logsAfter: _logCursor,
        requestTimeout: const Duration(seconds: 20),
      );
      if (!mounted) return;
      final entries = JobLogEntry.fromPayload(data['log_entries']);
      setState(() {
        _meta = Map<String, dynamic>.from(data);
        if (_logCursor == null) {
          _logEntries = entries;
        } else if (entries.isNotEmpty) {
          final merged = [..._logEntries, ...entries];
          _logEntries = merged.length > 3000 ? merged.sublist(merged.length - 3000) : merged;
        }
        final next = data['next_log_cursor'];
        if (next is num) _logCursor = next.toInt();
      });
    } on NotFoundException {
      if (mounted && _jobFrom(context.read<ScraperProvider>()) == null) {
        setState(() => _notFound = true);
      }
    } catch (_) {
      // The provider reports connection state; the side data is optional.
    } finally {
      _sideBusy = false;
    }
  }

  void _sideTick() {
    if (!mounted) return;
    final job = _jobFrom(context.read<ScraperProvider>());
    if (job == null) return;
    final needSettlement =
        job.isTerminal && !_settled(job) && _settlementPolls < _maxSettlementPolls;
    final needLog = _logOpen && job.isActive;
    // Per-city facts (city_summary/city_outcomes) are final only once the
    // search has ended: refresh the side data when its status is behind.
    final metaBehind = job.isTerminal && _meta != null && '${_meta!['status']}' != _statusString(job);
    if (needSettlement) _settlementPolls++;
    if (needSettlement || needLog || metaBehind) _fetchMeta();
  }

  // --------------------------------------------------------------- values

  bool _metaSettled() => _meta?['settled'] == true;

  bool _settled(ScrapingJob job) => job.settled || _metaSettled();

  int _refunded(ScrapingJob job) {
    if (!job.settled && _metaSettled()) return jobInt(_meta!, 'credit_refunded');
    return job.creditRefunded;
  }

  int _charged(ScrapingJob job) {
    final m = _meta;
    if (job.creditCharged == 0 && m != null) return jobInt(m, 'credit_charged');
    return job.creditCharged;
  }

  static String _statusString(ScrapingJob job) {
    switch (job.status) {
      case ScrapingStatus.running:
        return job.isQueued ? 'pending' : 'running';
      case ScrapingStatus.completed:
        return 'completed';
      case ScrapingStatus.failed:
        return 'failed';
      case ScrapingStatus.cancelled:
        return 'cancelled';
      case ScrapingStatus.idle:
        return 'unknown';
    }
  }

  /// The job as an API-shaped map for the shared helpers.
  Map<String, dynamic> _jobMap(ScrapingJob job) {
    final m = _meta ?? const <String, dynamic>{};
    return {
      'job_id': job.jobId,
      'status': _statusString(job),
      'category': job.category,
      'cities': job.cities,
      'country': m['country'],
      'region': m['region'],
      'total_cities': job.totalCities,
      'completed_cities': job.completedCities,
      'failed_cities': job.failedCities,
      'current_city': job.currentCity,
      'result_count': job.resultCount,
      'credit_charged': _charged(job),
      'credit_refunded': _refunded(job),
      'settled': _settled(job),
      'max_results_per_city': job.maxResultsPerCity > 0 ? job.maxResultsPerCity : m['max_results_per_city'],
      'error': job.error,
      'created_at': job.createdAt.toIso8601String(),
      'completed_at': job.completedAt?.toIso8601String(),
      if ('${m['status']}' == _statusString(job)) ...{
        'city_summary': m['city_summary'],
        'city_outcomes': m['city_outcomes'],
      },
    };
  }

  /// Marks where the leads start, for "View partial results".
  final GlobalKey _leadsAnchor = GlobalKey();

  void _scrollToLeads() {
    final ctx = _leadsAnchor.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  bool _stopping(ScrapingJob job) {
    if (!job.isActive) return false;
    return _cancelRequested || job.logs.any((l) => l.startsWith('Cancellation requested'));
  }

  int _totalCities(ScrapingJob job) => job.totalCities > 0 ? job.totalCities : job.cities.length;

  String _title(ScrapingJob job) {
    final category = job.category.trim().isEmpty ? 'Search' : job.category.trim();
    return '$category in ${plural(_totalCities(job), 'city', 'cities')}';
  }

  String _subtitle(Map<String, dynamic> map, ScrapingJob job) {
    final parts = <String>[];
    final place = jobPlaceLabel(map);
    if (place != null) parts.add(place);
    parts.add('started ${formatLocalDateTime(job.createdAt)}');
    final m = jobInt(map, 'max_results_per_city');
    if (m > 0) parts.add('up to ${plural(m, 'lead', 'leads')} per city');
    return parts.join(' · ');
  }

  /// Requested cities that produced no lead. Uses the server's per-city
  /// outcomes when present, else the loaded leads (completed searches only).
  List<String> _zeroCities(ScrapingJob job, Map<String, dynamic> map) {
    final outcomes = map['city_outcomes'];
    if (outcomes is List) {
      return [
        for (final o in outcomes)
          if (o is Map && o['outcome'] == 'empty') '${o['city']}',
      ];
    }
    if (!job.resultsLoaded || job.status != ScrapingStatus.completed) return const [];
    final counts = leadCountsByCity(job.results);
    return [for (final c in job.cities) if (leadsForCity(c, counts) == 0) c];
  }

  // -------------------------------------------------------------- actions

  Future<void> _cancel(ScrapingJob job) async {
    if (_cancelling) return;
    final ok = await confirmCancelSearch(context);
    if (!ok || !mounted) return;
    setState(() => _cancelling = true);
    final scraper = context.read<ScraperProvider>();
    final active = context.read<ActiveSearchesProvider>();
    try {
      if (scraper.currentJob?.jobId == _id) {
        await scraper.cancelCurrentJob();
      } else {
        await _api.cancelJob(_id);
      }
      if (!mounted) return;
      setState(() => _cancelRequested = true);
      unawaited(active.refresh());
    } catch (e) {
      if (mounted) {
        showSearchSnack(context, "We couldn't cancel the search: ${ErrorHandler.getUserFriendlyMessage(e)}",
            error: true);
      }
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    await downloadSearchExcel(context, _api, _id);
    if (mounted) setState(() => _downloading = false);
  }

  Future<void> _exportCsv(ScrapingJob job) async {
    if (!job.resultsLoaded || job.results.isEmpty) return;
    final shortId = _id.length > 8 ? _id.substring(0, 8) : _id;
    await saveCsv(
      leadsToCsv(job.results),
      'leads_${safeFileNamePart(job.category, maxLength: 30)}_$shortId',
      context: context,
    );
  }

  void _runAgain(Map<String, dynamic> map) {
    context.read<SearchSetupProvider>().loadFromJob(map);
    Navigator.of(context).pushNamed('/find/details');
  }

  Future<void> _delete(ScrapingJob job) async {
    if (_deleting) return;
    final ok = await confirmDeleteSearch(context, job.resultCount);
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    final navigator = Navigator.of(context);
    final scraper = context.read<ScraperProvider>();
    try {
      await _api.deleteJob(_id);
      if (!mounted) return;
      showSearchSnack(context, 'Search deleted');
      if (scraper.currentJob?.jobId == _id) scraper.reset();
      RefreshBus.notifyJobsChanged();
      navigator.pushReplacementNamed('/searches');
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException && e.statusCode == 409
          ? "This search is still running. Cancel it first, then delete it."
          : "We couldn't delete the search: ${ErrorHandler.getUserFriendlyMessage(e)}";
      showSearchSnack(context, msg, error: true);
      setState(() => _deleting = false);
    }
  }

  void _signIn() => AppNav.signIn(context, returnRoute: '/searches/${Uri.encodeComponent(_id)}');

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final scraper = context.watch<ScraperProvider>();
    final job = _jobFrom(scraper);

    if (job == null && !_notFound && _watchError == null && !_watching) {
      // Another search became the followed one (e.g. a new search was
      // started) and the user came back here: follow this one again. Only
      // the visible page does this, so two search pages never fight.
      final route = ModalRoute.of(context);
      if (route == null || route.isCurrent) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _jobFrom(context.read<ScraperProvider>()) == null) _watch();
        });
      }
    }

    if (_notFound) return _message(context, "This search doesn't exist", 'It may have been deleted.');
    if (job == null) {
      if (scraper.syncState == JobSyncState.authExpired) {
        return _pad(context, [
          SearchNotice(
            icon: Icons.lock_clock_rounded,
            title: "You've been signed out.",
            body: 'Sign in to see this search.',
            action: _noticeButton('Sign in', _signIn),
          ),
        ]);
      }
      if (_watchError != null) {
        final e = _watchError;
        final text = ErrorHandler.isNetworkError(e)
            ? "We couldn't reach the server. Your search is safe."
            : "We couldn't load this search: ${ErrorHandler.getUserFriendlyMessage(e)}";
        return _pad(context, [
          SearchCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: const TextStyle(color: UiTokens.text, fontSize: 15)),
                const SizedBox(height: 12),
                OutlinedButton(style: searchSecondaryButtonStyle(), onPressed: _watch, child: const Text('Try again')),
              ],
            ),
          ),
        ]);
      }
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading this search…', style: TextStyle(color: UiTokens.textSecondary)),
          ],
        ),
      );
    }

    final map = _jobMap(job);
    if (job.isTerminal) return _buildFinished(context, scraper, job, map);
    return _buildRunning(context, scraper, job, map);
  }

  Widget _pad(BuildContext context, List<Widget> children) {
    final width = MediaQuery.sizeOf(context).width;
    return ListView(
      padding: EdgeInsets.all(width < 600 ? 16 : 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }

  Widget _message(BuildContext context, String title, String body) {
    return _pad(context, [
      SearchCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: UiTokens.text, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 14)),
            const SizedBox(height: 14),
            FilledButton(
              style: searchPrimaryButtonStyle(),
              onPressed: () => AppNav.go(context, '/searches'),
              child: const Text('Go to My searches'),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _noticeButton(String label, VoidCallback onPressed) => TextButton(
        style: TextButton.styleFrom(
          foregroundColor: UiTokens.accent,
          minimumSize: const Size(44, 44),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
        ),
        onPressed: onPressed,
        child: Text(label),
      );

  Widget? _backLink(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= AppBreakpoints.mobile) return null;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(44, 44)),
        onPressed: () => AppNav.go(context, '/searches'),
        icon: const Icon(Icons.chevron_left_rounded),
        label: const Text('My searches', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  List<Widget> _notices(ScraperProvider scraper, ScrapingJob job) {
    final out = <Widget>[];
    if (scraper.syncState == JobSyncState.reconnecting) {
      final match = RegExp(r'(\d+)\s*s').firstMatch(scraper.syncMessage ?? '');
      final title = match == null
          ? 'Connection lost — retrying now.'
          : 'Connection lost — retrying in ${match.group(1)} s.';
      out.add(SearchNotice(
        icon: Icons.wifi_off_rounded,
        title: title,
        body: job.isActive
            ? 'Your search keeps running on our servers; nothing is lost.'
            : 'Your leads are saved on our servers; nothing is lost.',
        action: _noticeButton('Retry now', scraper.retrySyncNow),
      ));
    } else if (scraper.syncState == JobSyncState.authExpired) {
      out.add(SearchNotice(
        icon: Icons.lock_clock_rounded,
        title: "You've been signed out.",
        body: job.isActive
            ? 'Your search is still running. Sign in to keep following it.'
            : 'Sign in to see this search.',
        action: _noticeButton('Sign in', _signIn),
      ));
    }
    return out;
  }

  // ------------------------------------------------------------- running

  Widget _buildRunning(BuildContext context, ScraperProvider scraper, ScrapingJob job, Map<String, dynamic> map) {
    final crm = context.watch<CrmProvider?>();
    final stopping = _stopping(job);
    final status = searchPageStatus(map, stopping: stopping);
    final total = _totalCities(job);
    final done = job.completedCities.clamp(0, total);
    final width = MediaQuery.sizeOf(context).width;

    String headline;
    if (stopping) {
      headline = 'Stopping after the current business. Leads found so far are kept.';
    } else if (job.isQueued) {
      headline = 'Waiting for a free search slot.';
    } else {
      headline = '$done of $total cities done · ${plural(job.resultCount, 'lead', 'leads')} so far';
    }

    final header = SearchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              SearchStatusBadge(job: map, info: status),
              _UpdatedAgo(lastSyncedAt: scraper.lastSyncedAt),
              if (!stopping)
                TextButton.icon(
                  style: searchDangerTextButtonStyle(),
                  onPressed: _cancelling ? null : () => _cancel(job),
                  icon: _cancelling
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('Cancel search'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(_title(job),
                style: const TextStyle(color: UiTokens.text, fontSize: 22, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (jobCountry(map) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 6),
                  child: CountryFlagBadge(countryName: jobCountry(map), size: 14),
                ),
              Flexible(
                child: Text(_subtitle(map, job), style: const TextStyle(color: UiTokens.textSecondary, fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!job.isQueued) ...[
            Row(
              children: [
                Expanded(
                  child: Text('$done of $total cities done',
                      style: const TextStyle(color: UiTokens.text, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                Text('${plural(job.resultCount, 'lead', 'leads')} so far',
                    style: const TextStyle(color: UiTokens.text, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              label: '$done of $total cities done',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total > 0 ? done / total : 0,
                  minHeight: 8,
                  backgroundColor: UiTokens.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(UiTokens.searchingFg),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Semantics(
            liveRegion: true,
            child: Text(
              stopping || job.isQueued
                  ? headline
                  : (job.currentCity.trim().isNotEmpty ? 'Now searching ${job.currentCity.trim()}' : headline),
              style: TextStyle(
                color: stopping || job.isQueued ? UiTokens.text : UiTokens.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          if (job.failedCities > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${plural(job.failedCities, 'city', 'cities')} timed out; leads found before the timeout were kept.',
              style: const TextStyle(color: UiTokens.partialFg, fontSize: 13),
            ),
          ],
        ],
      ),
    );

    final cities = SearchCard(child: _CitiesList(job: job, title: 'Cities'));
    final credits = SearchCard(
      child: ListenableBuilder(
        listenable: CreditProvider.instance,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Credits', style: TextStyle(color: UiTokens.text, fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              searchRunningCreditsLine(_charged(job), CreditProvider.instance.refundPolicySentence),
              style: const TextStyle(color: UiTokens.textSecondary, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );

    final back = _backLink(context);
    return _pad(context, [
      if (back != null) back,
      header,
      for (final n in _notices(scraper, job)) ...[const SizedBox(height: 16), n],
      const SizedBox(height: 16),
      if (width >= 900)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: cities),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: credits),
          ],
        )
      else ...[
        cities,
        const SizedBox(height: 16),
        credits,
      ],
      if (crm != null && crm.isEnabled && !job.isQueued) ...[
        const SizedBox(height: 16),
        CrmRunningSearchCard(jobId: _id, api: crm.api, savedLeads: job.resultCount),
      ],
      const SizedBox(height: 16),
      SearchCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: _logDisclosure(job),
      ),
      const SizedBox(height: 24),
    ]);
  }

  List<JobLogEntry> _entries(ScrapingJob job) =>
      _logEntries.isNotEmpty ? _logEntries : JobLogEntry.fromLines(job.logs);

  Widget _logDisclosure(ScrapingJob job) {
    final entries = _entries(job);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Disclosure(
          label: 'Technical log (${plural(entries.length, 'line', 'lines')})',
          open: _logOpen,
          onTap: () {
            setState(() => _logOpen = !_logOpen);
            if (_logOpen) _fetchMeta();
          },
        ),
        if (_logOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: JobLogPanel(
              entries: entries,
              jobId: _id,
              category: job.category,
              isRunning: job.isActive,
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ finished

  Widget _buildFinished(BuildContext context, ScraperProvider scraper, ScrapingJob job, Map<String, dynamic> map) {
    final back = _backLink(context);
    final crm = context.watch<CrmProvider?>();
    return ResultsScreen(
      key: ValueKey('results-$_id'),
      jobId: _id,
      embedded: true,
      api: _api,
      category: job.category,
      overrideResults: job.resultsLoaded ? job.results : null,
      resultsPending: !job.resultsLoaded,
      crmEnabled: crm?.isEnabled ?? false,
      crmApi: crm?.api,
      leading: [
        if (back != null) back,
        for (final n in _notices(scraper, job)) n,
        _summaryCard(context, job, map),
        SizedBox(key: _leadsAnchor, height: 0),
      ],
    );
  }

  Widget _summaryCard(BuildContext context, ScrapingJob job, Map<String, dynamic> map) {
    final zero = _zeroCities(job, map);
    final status = searchPageStatus(map);
    final partial = jobHasPartialResults(map);
    final noLeads = job.status == ScrapingStatus.completed && job.resultCount == 0;
    final leads = job.resultCount;
    final settled = _settled(job);
    final charged = _charged(job);
    final refunded = _refunded(job);
    final phone = MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;

    // Stats from data only; parts that are unknown are left out.
    final stats = <String>[];
    final completed = job.completedAt;
    final took = completed == null ? null : 'took ${formatTookDuration(completed.difference(job.createdAt))}';
    if (job.resultsLoaded && job.results.isNotEmpty) {
      final counts = leadCountsByCity(job.results);
      if (counts.isNotEmpty) {
        final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
        stats.add('Top city: ${top.key} (${formatCount(top.value)})');
      }
    }
    final total = _totalCities(job);
    // Phones skip the average: the facts line above already gives leads and cities.
    if (!phone && total > 0 && leads > 0) {
      final avg = leads / total;
      final avgText = avg == avg.roundToDouble() ? avg.toStringAsFixed(0) : avg.toStringAsFixed(1);
      stats.add('Avg $avgText per city');
    }

    final reworded = job.status == ScrapingStatus.failed && failureReasonWasReworded(job.error);
    final logCount = _entries(job).length;

    final buttons = <Widget>[
      if (partial)
        FilledButton.icon(
          style: searchPrimaryButtonStyle(),
          onPressed: _scrollToLeads,
          icon: const Icon(Icons.list_alt_rounded, size: 18),
          label: Text('View partial results (${formatCount(leads)})'),
        ),
      if (leads > 0)
        (partial ? OutlinedButton.icon : FilledButton.icon)(
          style: partial ? searchSecondaryButtonStyle() : searchPrimaryButtonStyle(),
          onPressed: _downloading ? null : _download,
          icon: _downloading
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.download_rounded, size: 18),
          label: Text(partial ? 'Download partial Excel' : 'Download Excel'),
        ),
      if (leads > 0)
        OutlinedButton.icon(
          style: searchSecondaryButtonStyle(),
          onPressed: job.resultsLoaded && job.results.isNotEmpty ? () => _exportCsv(job) : null,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('CSV'),
        ),
      leads > 0
          ? OutlinedButton(style: searchSecondaryButtonStyle(), onPressed: () => _runAgain(map), child: const Text('Run again'))
          : FilledButton(style: searchPrimaryButtonStyle(), onPressed: () => _runAgain(map), child: const Text('Run again')),
      // On phones "Copy link" moves into the menu to keep the leads close.
      if (!phone)
        OutlinedButton(
          style: searchSecondaryButtonStyle(),
          onPressed: () => copyWithSnack(context, searchPageUrl(_id), message: 'Link copied'),
          child: const Text('Copy link'),
        ),
      PopupMenuButton<String>(
        tooltip: 'More actions',
        color: UiTokens.card,
        icon: const Icon(Icons.more_horiz_rounded, color: UiTokens.textSecondary),
        onSelected: (v) {
          if (v == 'copy-link') copyWithSnack(context, searchPageUrl(_id), message: 'Link copied');
          if (v == 'copy-id') copyWithSnack(context, _id, message: 'Search ID copied');
          if (v == 'delete') _delete(job);
        },
        itemBuilder: (_) => [
          if (phone) const PopupMenuItem(value: 'copy-link', child: Text('Copy link')),
          const PopupMenuItem(value: 'copy-id', child: Text('Copy ID')),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Delete…', style: TextStyle(color: UiTokens.failedFg)),
          ),
        ],
      ),
    ];

    return SearchCard(
      padding: EdgeInsets.all(phone ? 16 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 4,
            children: [
              SearchStatusBadge(job: map, info: status),
              if (completed != null)
                Text('Finished ${formatLocalDateTime(completed)} · $took',
                    style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text(_title(job),
                style: TextStyle(color: UiTokens.text, fontSize: phone ? 19 : 22, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (jobCountry(map) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 6),
                  child: CountryFlagBadge(countryName: jobCountry(map), size: 14),
                ),
              Flexible(
                child: Text(_subtitle(map, job), style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              finishedSearchHeadline(map),
              style: const TextStyle(color: UiTokens.text, fontSize: 15, fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
          SizedBox(height: phone ? 6 : 10),
          _OutcomeStats(job: map),
          if (zero.isNotEmpty && !noLeads && !phone)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                zero.length <= 3
                    ? 'No leads in ${zero.map((c) => c.split(',').first.trim()).join(', ')}.'
                    : 'No leads in ${plural(zero.length, 'city', 'cities')} (see Cities below).',
                style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13.5),
              ),
            ),
          if (noLeads)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Nothing was saved, so there is nothing to download. You can run it again with a broader '
                'business type or different cities.',
                style: TextStyle(color: UiTokens.textSecondary, fontSize: 13.5, height: 1.35),
              ),
            ),
          if (reworded) ...[
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: UiTokens.accent,
                minimumSize: const Size(44, 36),
                padding: EdgeInsets.zero,
              ),
              onPressed: () => setState(() => _detailsOpen = !_detailsOpen),
              child: Text(_detailsOpen ? 'Hide details' : 'Details'),
            ),
            if (_detailsOpen)
              SelectableText(
                job.error ?? '',
                style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13, fontFamily: 'monospace'),
              ),
          ],
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              searchRefundLine(charged: charged, refunded: refunded, settled: settled),
              style: const TextStyle(color: UiTokens.textSecondary, fontSize: 14),
            ),
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(stats.join(' · '), style: const TextStyle(color: UiTokens.textMuted, fontSize: 13)),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: buttons),
          const SizedBox(height: 8),
          const Divider(color: UiTokens.border, height: 1),
          Wrap(
            spacing: 4,
            children: [
              _Disclosure(
                label: 'Cities (${formatCount(_totalCities(job))})',
                open: _citiesOpen,
                compact: true,
                onTap: () => setState(() => _citiesOpen = !_citiesOpen),
              ),
              _Disclosure(
                label: 'Technical log (${plural(logCount, 'line', 'lines')})',
                open: _logOpen,
                compact: true,
                onTap: () {
                  setState(() => _logOpen = !_logOpen);
                  if (_logOpen && _logEntries.isEmpty) _fetchMeta();
                },
              ),
            ],
          ),
          if (_citiesOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CitiesList(job: job, outcomes: map['city_outcomes']),
            ),
          if (_logOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: JobLogPanel(entries: _entries(job), jobId: _id, category: job.category),
            ),
        ],
      ),
    );
  }
}

/// Leads found, cities searched, cities with leads and cities with no leads,
/// side by side (plus timed out / not searched when they apply). Only facts
/// the server reported; nothing is shown for older servers without
/// `city_summary` except the lead count.
class _OutcomeStats extends StatelessWidget {
  final Map<String, dynamic> job;

  const _OutcomeStats({required this.job});

  @override
  Widget build(BuildContext context) {
    final c = CitySummary.of(job);
    final leads = jobInt(job, 'result_count');
    final items = <(String, String, Color?)>[
      (formatCount(leads), leads == 1 ? 'Lead found' : 'Leads found', null),
      if (c != null) ...[
        ('${formatCount(c.searched)} of ${formatCount(c.total)}', 'Cities searched', null),
        (formatCount(c.withLeads), 'With leads', null),
        (formatCount(c.empty), 'With no leads', c.empty > 0 ? UiTokens.partialFg : null),
        if (c.timedOut > 0) (formatCount(c.timedOut), 'Timed out', UiTokens.partialFg),
        if (c.interrupted + c.notSearched > 0)
          (formatCount(c.interrupted + c.notSearched), 'Not finished', UiTokens.textSecondary),
      ],
    ];
    final label = [for (final i in items) '${i.$2}: ${i.$1}'].join(', ');
    // Phones: one compact line keeps the first lead on the first screen.
    if (MediaQuery.sizeOf(context).width < AppBreakpoints.mobile) {
      return Semantics(
        container: true,
        label: label,
        excludeSemantics: true,
        child: Text.rich(
          TextSpan(children: [
            for (var k = 0; k < items.length; k++) ...[
              if (k > 0) const TextSpan(text: '  ·  ', style: TextStyle(color: UiTokens.textMuted)),
              TextSpan(
                  text: items[k].$1,
                  style: TextStyle(color: items[k].$3 ?? UiTokens.text, fontWeight: FontWeight.w700)),
              TextSpan(text: ' ${items[k].$2.toLowerCase()}'),
            ],
          ]),
          style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13.5, height: 1.4),
        ),
      );
    }
    return Semantics(
      container: true,
      label: label,
      excludeSemantics: true,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final i in items)
            Container(
              constraints: const BoxConstraints(minWidth: 96),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: UiTokens.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: UiTokens.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(i.$1,
                      style: TextStyle(color: i.$3 ?? UiTokens.text, fontSize: 17, fontWeight: FontWeight.w700)),
                  Text(i.$2, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 12.5)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Updated 3 s ago" from the provider's last successful poll.
class _UpdatedAgo extends StatefulWidget {
  final DateTime? lastSyncedAt;

  const _UpdatedAgo({required this.lastSyncedAt});

  @override
  State<_UpdatedAgo> createState() => _UpdatedAgoState();
}

class _UpdatedAgoState extends State<_UpdatedAgo> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final at = widget.lastSyncedAt;
    if (at == null) return const SizedBox.shrink();
    final s = DateTime.now().difference(at).inSeconds;
    final text = s < 60 ? 'Updated ${s < 0 ? 0 : s} s ago' : 'Updated ${s ~/ 60} min ago';
    return ExcludeSemantics(
      child: Text(text, style: const TextStyle(color: UiTokens.textMuted, fontSize: 13)),
    );
  }
}

/// A labelled open/close row (keyboard and screen-reader friendly).
class _Disclosure extends StatelessWidget {
  final String label;
  final bool open;
  final VoidCallback onTap;

  /// Sized to its label (several in one row) instead of full width.
  final bool compact;

  const _Disclosure({required this.label, required this.open, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: open,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: EdgeInsets.only(right: compact ? 8 : 0),
            child: Row(
              mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, color: UiTokens.textSecondary),
                const SizedBox(width: 6),
                Flexible(
                  fit: compact ? FlexFit.loose : FlexFit.tight,
                  child: Text(label,
                      style: const TextStyle(color: UiTokens.text, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _CityState { done, empty, timedOut, skipped, searching, waiting, failed, stopped, notSearched }

/// Per-city progress. A green check only means "searched and found leads"
/// (or "searched" while the leads are not loaded yet); cities of a
/// cancelled/failed search that were not searched are never shown as done.
class _CitiesList extends StatelessWidget {
  final ScrapingJob job;
  final String? title;

  /// `city_outcomes` from the API (finished searches); null = derive locally.
  final Object? outcomes;

  const _CitiesList({required this.job, this.title, this.outcomes});

  @override
  Widget build(BuildContext context) {
    final cities = job.cities;
    final counts = job.resultsLoaded ? leadCountsByCity(job.results) : const <String, int>{};
    final done = job.completedCities;

    final server = <String, Map>{
      if (outcomes is List)
        for (final o in outcomes as List)
          if (o is Map) '${o['city']}': o,
    };

    _CityState stateOf(int i) {
      final o = server[cities[i].trim()];
      if (o != null) {
        switch ('${o['outcome']}') {
          case 'with_leads':
            return _CityState.done;
          case 'empty':
            return _CityState.empty;
          case 'timed_out':
            return _CityState.timedOut;
          case 'interrupted':
            return job.status == ScrapingStatus.failed ? _CityState.failed : _CityState.stopped;
          case 'searching':
            return _CityState.searching;
          case 'not_searched':
            return job.isActive ? _CityState.waiting : _CityState.notSearched;
          case 'skipped':
            return _CityState.skipped;
        }
      }
      switch (job.status) {
        case ScrapingStatus.completed:
          if (!job.resultsLoaded) return _CityState.done;
          return leadsForCity(cities[i], counts) > 0 ? _CityState.done : _CityState.empty;
        case ScrapingStatus.running:
          if (i < done) return _CityState.done;
          if (i == done && !job.isQueued) return _CityState.searching;
          return _CityState.waiting;
        case ScrapingStatus.cancelled:
        case ScrapingStatus.failed:
          if (i < done) {
            if (!job.resultsLoaded) return _CityState.done;
            return leadsForCity(cities[i], counts) > 0 ? _CityState.done : _CityState.empty;
          }
          if (i == done) {
            return job.status == ScrapingStatus.failed ? _CityState.failed : _CityState.stopped;
          }
          return _CityState.notSearched;
        case ScrapingStatus.idle:
          return _CityState.waiting;
      }
    }

    Widget row(int i) {
      final city = cities[i];
      final st = stateOf(i);
      final o = server[city.trim()];
      final n = o != null && o['leads'] is num ? (o['leads'] as num).toInt() : leadsForCity(city, counts);
      final known = job.resultsLoaded || o != null;
      late IconData icon;
      late Color color;
      late String label;
      switch (st) {
        case _CityState.done:
          icon = Icons.check_rounded;
          color = UiTokens.completedFg;
          label = known ? plural(n, 'lead', 'leads') : 'done';
          break;
        case _CityState.empty:
          icon = Icons.remove_circle_outline_rounded;
          color = UiTokens.partialFg;
          label = 'no leads';
          break;
        case _CityState.timedOut:
          icon = Icons.timer_off_outlined;
          color = UiTokens.partialFg;
          label = n > 0 ? 'timed out · ${plural(n, 'lead', 'leads')} kept' : 'timed out · no leads';
          break;
        case _CityState.skipped:
          icon = Icons.do_not_disturb_alt_rounded;
          color = UiTokens.textMuted;
          label = 'skipped (not a valid city)';
          break;
        case _CityState.searching:
          icon = Icons.autorenew_rounded;
          color = UiTokens.searchingFg;
          label = 'searching…';
          break;
        case _CityState.waiting:
          icon = Icons.radio_button_unchecked_rounded;
          color = UiTokens.textMuted;
          label = 'waiting';
          break;
        case _CityState.failed:
          icon = Icons.close_rounded;
          color = UiTokens.failedFg;
          label = n > 0 ? 'stopped here (failed) · ${plural(n, 'lead', 'leads')} kept' : 'stopped here (failed)';
          break;
        case _CityState.stopped:
          icon = Icons.block_rounded;
          color = UiTokens.cancelledFg;
          label = n > 0 ? 'stopped here (cancelled) · ${plural(n, 'lead', 'leads')} kept' : 'stopped here (cancelled)';
          break;
        case _CityState.notSearched:
          icon = Icons.radio_button_unchecked_rounded;
          color = UiTokens.textMuted;
          label = 'not searched';
          break;
      }
      return Semantics(
        label: '$city: $label',
        excludeSemantics: true,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: UiTokens.border))),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(city, style: const TextStyle(color: UiTokens.text, fontSize: 14)),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: Text(label,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: st == _CityState.done ? UiTokens.text : color,
                      fontSize: 13.5,
                    )),
              ),
            ],
          ),
        ),
      );
    }

    final list = Column(children: [for (var i = 0; i < cities.length; i++) row(i)]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title!, style: const TextStyle(color: UiTokens.text, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
        ],
        if (cities.isEmpty)
          Text(
            job.totalCities > 0 ? plural(job.totalCities, 'city', 'cities') : 'No cities listed.',
            style: const TextStyle(color: UiTokens.textSecondary),
          )
        else if (cities.length > 12)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: SingleChildScrollView(child: list),
          )
        else
          list,
      ],
    );
  }
}
