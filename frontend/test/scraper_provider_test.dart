import 'dart:collection';

import 'package:business_scraper_app/core/error_handler.dart';
import 'package:business_scraper_app/providers/scraper_provider.dart';
import 'package:business_scraper_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Scripted API: each call pops the next response (a Map) or error (Exception).
class FakeApi extends ApiService {
  final Queue<Object> createScript = Queue<Object>();
  final Queue<Object> statusScript = Queue<Object>();
  List<Map<String, dynamic>> activeJobs = <Map<String, dynamic>>[];
  final List<String?> createKeys = <String?>[];
  final List<int?> logCursors = <int?>[];
  int statusCalls = 0;
  Map<String, dynamic>? _last;

  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<Map<String, dynamic>> createScrapingJob({
    required String category,
    required List<String> citiesData,
    int maxResultsPerCity = 10,
    String? idempotencyKey,
  }) async {
    createKeys.add(idempotencyKey);
    final next = createScript.removeFirst();
    if (next is Exception) throw next;
    return Map<String, dynamic>.from(next as Map);
  }

  @override
  Future<Map<String, dynamic>> getJobStatus(
    String jobId, {
    bool includeResults = true,
    int? logsAfter,
    Duration? requestTimeout,
  }) async {
    statusCalls++;
    logCursors.add(logsAfter);
    // When the script runs out, the server keeps answering with its last state.
    final next = statusScript.isEmpty ? (_last ?? _job('running')) : statusScript.removeFirst();
    if (next is Exception) throw next;
    _last = Map<String, dynamic>.from(next as Map)
      ..['logs'] = const <String>[];
    return Map<String, dynamic>.from(next);
  }

  @override
  Future<List<Map<String, dynamic>>> getActiveJobs() async => activeJobs;

  @override
  Future<void> cancelJob(String jobId) async {}
}

Map<String, dynamic> _job(
  String status, {
  int progress = 10,
  int results = 0,
  List<String> logs = const [],
  int cursor = 0,
  String createdAt = '2026-11-16T10:00:00.000Z',
  String serverTime = '2026-11-16T10:05:00.000Z',
}) =>
    {
      'job_id': 'job-1',
      'status': status,
      'category': 'ecommerce',
      'cities': ['Doha, Qatar', 'Lusail, Qatar'],
      'max_results_per_city': 10,
      'progress': progress,
      'total_cities': 2,
      'completed_cities': 0,
      'failed_cities': 0,
      'current_city': 'Doha, Qatar',
      'result_count': results,
      'results': const [],
      'results_included': false,
      'error': null,
      'created_at': createdAt,
      'completed_at': null,
      'server_time': serverTime,
      'credit_charged': 460,
      'credit_refunded': 0,
      'settled': false,
      'logs': logs,
      'next_log_cursor': cursor,
      'credit_balance': 690,
    };

Future<void> _settle([int ms = 120]) => Future<void>.delayed(Duration(milliseconds: ms));

ScraperProvider _provider(FakeApi api) => ScraperProvider(
      api: api,
      pollInterval: const Duration(milliseconds: 5),
      retryBaseDelay: const Duration(milliseconds: 1),
      maxBackoff: const Duration(milliseconds: 10),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('transient polling errors never mark a running job as failed', () async {
    final api = FakeApi();
    api.createScript.add(_job('pending', progress: 0,
        logs: ['Job created for category: ecommerce', 'Credits charged: 460'], cursor: 2));
    api.statusScript.addAll([
      NetworkException('Unable to connect to server.'),
      ServerException('Server error'),
      NetworkException('Request timed out.'),
    ]);
    final p = _provider(api);

    expect(await p.startScraping(category: 'ecommerce', citiesData: ['Doha, Qatar', 'Lusail, Qatar']), isTrue);
    // Initial logs from the create response are shown immediately (not lost).
    expect(p.currentJob!.logs, contains('Credits charged: 460'));

    // Let the three failures happen.
    while (api.statusCalls < 3) {
      await _settle(5);
    }
    expect(p.currentJob!.status, ScrapingStatus.running);
    expect(p.status, ScrapingStatus.running);
    expect(p.syncState, JobSyncState.reconnecting);
    expect(p.hasActiveJob, isTrue, reason: 'cancel must stay available');

    // Then the server answers again -> live, still running, progress applied.
    api.statusScript.add(_job('running', progress: 16, results: 38, logs: ['Lead 1/10 in Doha'], cursor: 3));
    await _settle();
    expect(p.syncState, JobSyncState.live);
    expect(p.currentJob!.progress, greaterThanOrEqualTo(10));
    expect(p.currentJob!.status, ScrapingStatus.running);
    p.dispose();
  });

  test('only the server can fail a job', () async {
    final api = FakeApi();
    api.createScript.add(_job('pending'));
    api.statusScript.add({..._job('failed'), 'error': 'Every city timed out without results'});
    final p = _provider(api);
    await p.startScraping(category: 'ecommerce', citiesData: ['Doha, Qatar', 'Lusail, Qatar']);
    await _settle();
    expect(p.currentJob!.status, ScrapingStatus.failed);
    expect(p.currentJob!.error, 'Every city timed out without results');
    p.dispose();
  });

  test('job creation retries reuse one idempotency key', () async {
    final api = FakeApi();
    api.createScript.addAll([
      NetworkException('timed out'),
      NetworkException('timed out'),
      _job('pending'),
    ]);
    final p = _provider(api);
    expect(await p.startScraping(category: 'ecommerce', citiesData: ['Doha, Qatar']), isTrue);
    expect(api.createKeys.length, 3);
    expect(api.createKeys.toSet().length, 1, reason: 'same key => server charges once');
    expect(api.createKeys.first, startsWith('job-'));
    p.dispose();
  });

  test('uncertain creation reattaches to the job the server did create', () async {
    final api = FakeApi();
    api.createScript.addAll([
      NetworkException('reset'),
      NetworkException('reset'),
      NetworkException('reset'),
    ]);
    api.activeJobs = [_job('running')];
    final p = _provider(api);
    final ok = await p.startScraping(
      category: 'ecommerce',
      citiesData: ['Doha, Qatar', 'Lusail, Qatar'],
      maxResultsPerCity: 10,
    );
    expect(ok, isTrue);
    expect(p.currentJob!.jobId, 'job-1');
    expect(p.startError, isNull);
    p.dispose();
  });

  test('definitive server rejection is reported and not retried', () async {
    final api = FakeApi();
    api.createScript.add(InsufficientCreditsException('Insufficient credits. Required: 460, Available: 5'));
    final p = _provider(api);
    expect(await p.startScraping(category: 'ecommerce', citiesData: ['Doha, Qatar']), isFalse);
    expect(api.createKeys.length, 1);
    expect(p.startError, contains('Insufficient credits'));
    expect(p.currentJob, isNull);
    p.dispose();
  });

  test('a double press while a start is in flight sends one request', () async {
    final api = FakeApi();
    api.createScript.add(_job('running'));
    final p = _provider(api);
    final first = p.startScraping(category: 'ecommerce', citiesData: ['Doha, Qatar']);
    expect(await p.startScraping(category: 'ecommerce', citiesData: ['Doha, Qatar']), isFalse);
    expect(await first, isTrue);
    expect(api.createKeys.length, 1);
    p.dispose();
  });

  test('a new search can start while another runs (server enforces the limit)', () async {
    final api = FakeApi();
    api.createScript.add(_job('running'));
    api.createScript.add(_job('running'));
    final p = _provider(api);
    expect(await p.startScraping(category: 'ecommerce', citiesData: ['Doha, Qatar']), isTrue);
    expect(await p.startScraping(category: 'plumbers', citiesData: ['Lusail, Qatar']), isTrue);
    expect(api.createKeys.length, 2);
    expect(api.createKeys.toSet().length, 2, reason: 'a different search gets a new idempotency key');
    p.dispose();
  });

  test('refresh reattaches to the running job from the server', () async {
    final api = FakeApi();
    api.activeJobs = [_job('running', results: 12)];
    final p = _provider(api);
    expect(await p.resumeActiveJob(), isTrue);
    expect(p.currentJob!.resultCount, 12);
    expect(p.currentJob!.category, 'ecommerce', reason: 'category comes from the server, not the form');
    expect(p.hasActiveJob, isTrue);
    p.dispose();
  });

  test('polling asks only for new log lines after the first poll', () async {
    final api = FakeApi();
    api.createScript.add(_job('pending', logs: ['a', 'b'], cursor: 2));
    api.statusScript.addAll([
      _job('running', logs: ['a', 'b', 'c'], cursor: 3),
      _job('running', logs: ['d'], cursor: 4),
    ]);
    final p = _provider(api);
    await p.startScraping(category: 'ecommerce', citiesData: ['Doha, Qatar']);
    await _settle();
    expect(api.logCursors.first, isNull);
    expect(api.logCursors[1], 3);
    expect(p.currentJob!.logs, ['a', 'b', 'c', 'd']);
    p.dispose();
  });

  test('elapsed time uses UTC instants and the server clock (no +5h)', () {
    final job = ScrapingJob.fromJson(_job('running',
        createdAt: '2026-11-16T10:00:00.000Z', serverTime: '2026-11-16T10:05:00.000Z'));
    // The browser clock is "now"; offset aligns it with the server's 10:05Z.
    expect(job.elapsed.inMinutes, inInclusiveRange(4, 5));
  });

  test('naive server timestamps are treated as UTC, not browser-local', () {
    final naive = parseServerTime('2026-11-16T10:00:00');
    final utc = parseServerTime('2026-11-16T10:00:00Z');
    expect(naive, utc);
    expect(naive!.isUtc, isTrue);
    expect(parseServerTime(''), isNull);
    expect(parseServerTime('2026-11-16T15:00:00+05:00'), utc);
  });

  test('watchJob follows a job by id and is a no-op for the current job', () async {
    final api = FakeApi();
    api.statusScript.addAll([
      _job('running', results: 3),
      _job('running', results: 5),
    ]);
    final p = _provider(api);
    await p.watchJob('job-1');
    expect(p.currentJob!.jobId, 'job-1');
    expect(p.currentJob!.resultCount, 3);
    final calls = api.statusCalls;
    await p.watchJob('job-1');
    expect(api.statusCalls, calls, reason: 'already followed: nothing is refetched');
    p.dispose();
  });

  test('expired session is recoverable: polling resumes after sign-in', () async {
    final api = FakeApi();
    api.createScript.add(_job('running'));
    api.statusScript.add(AuthenticationException('Your session has expired.'));
    final p = _provider(api);
    await p.startScraping(category: 'ecommerce', citiesData: ['Doha, Qatar']);
    await _settle();
    expect(p.syncState, JobSyncState.authExpired);
    expect(p.currentJob!.status, ScrapingStatus.running, reason: 'the job keeps running');
    final callsWhileExpired = api.statusCalls;
    await _settle();
    expect(api.statusCalls, callsWhileExpired, reason: 'no polling while signed out');

    api.statusScript.add(_job('running', results: 9));
    await p.resumeAfterSignIn();
    await _settle();
    expect(p.syncState, JobSyncState.live);
    expect(p.currentJob!.resultCount, 9);
    p.dispose();
  });

  test('watchJob during an expired session is resumed after sign-in', () async {
    final api = FakeApi();
    api.statusScript.addAll([
      AuthenticationException('Your session has expired.'),
      _job('running', results: 4),
    ]);
    final p = _provider(api);
    await p.watchJob('job-1');
    expect(p.currentJob, isNull);
    expect(p.syncState, JobSyncState.authExpired);
    await p.resumeAfterSignIn();
    expect(p.currentJob!.jobId, 'job-1');
    expect(p.syncState, JobSyncState.live);
    p.dispose();
  });

  test('signOut stops following and forgets the remembered job', () async {
    final api = FakeApi();
    api.createScript.add(_job('running'));
    final p = _provider(api);
    await p.startScraping(category: 'ecommerce', citiesData: ['Doha, Qatar']);
    await _settle(20);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ScraperProvider.activeJobPrefKey), 'job-1');
    await p.signOut();
    expect(p.currentJob, isNull);
    expect(prefs.getString(ScraperProvider.activeJobPrefKey), isNull);
    p.dispose();
  });
}
