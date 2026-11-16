import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/error_handler.dart';
import '../services/api_service.dart';
import '../core/utils/server_time.dart';
import '../core/utils/refresh_bus.dart';
import 'credit_provider.dart';

export '../core/utils/server_time.dart' show parseServerTime;

enum ScrapingStatus {
  idle,
  running,
  completed,
  failed,
  cancelled,
}

/// How fresh the job state on screen is. A connection problem is never a job
/// failure: only the server decides that a job failed.
enum JobSyncState { live, reconnecting, authExpired }

ScrapingStatus parseScrapingStatus(Object? status) {
  switch ('$status') {
    case 'pending':
    case 'running':
      return ScrapingStatus.running;
    case 'completed':
      return ScrapingStatus.completed;
    case 'failed':
      return ScrapingStatus.failed;
    case 'cancelled':
      return ScrapingStatus.cancelled;
    default:
      return ScrapingStatus.idle;
  }
}

class ScrapingJob {
  final String jobId;
  String category;
  List<String> cities;
  DateTime createdAt;
  int totalCities;
  int maxResultsPerCity;
  ScrapingStatus status;
  bool isQueued;
  int progress;
  int completedCities;
  int failedCities;
  int resultCount;
  String currentCity;
  List<Map<String, dynamic>> results;
  bool resultsLoaded;
  String? error;
  List<String> logs;
  DateTime? completedAt;
  int creditCharged;
  int creditRefunded;
  bool settled;

  /// serverTime - clientTime, so elapsed time is correct even if the
  /// browser clock or timezone is off.
  Duration clockOffset;

  ScrapingJob({
    required this.jobId,
    required this.category,
    required this.cities,
    required this.createdAt,
    required this.totalCities,
    this.maxResultsPerCity = 0,
    this.status = ScrapingStatus.idle,
    this.isQueued = false,
    this.progress = 0,
    this.completedCities = 0,
    this.failedCities = 0,
    this.resultCount = 0,
    this.currentCity = '',
    List<Map<String, dynamic>>? results,
    this.resultsLoaded = false,
    this.error,
    List<String>? logs,
    this.completedAt,
    this.creditCharged = 0,
    this.creditRefunded = 0,
    this.settled = false,
    this.clockOffset = Duration.zero,
  })  : results = results ?? <Map<String, dynamic>>[],
        logs = logs ?? <String>[];

  bool get isActive => status == ScrapingStatus.running;
  bool get isTerminal =>
      status == ScrapingStatus.completed ||
      status == ScrapingStatus.failed ||
      status == ScrapingStatus.cancelled;

  /// Server-clock "now".
  DateTime get serverNow => DateTime.now().add(clockOffset);

  Duration get elapsed {
    final end = completedAt ?? serverNow;
    final d = end.difference(createdAt);
    return d.isNegative ? Duration.zero : d;
  }

  factory ScrapingJob.fromJson(Map<String, dynamic> json) {
    final job = ScrapingJob(
      jobId: '${json['job_id']}',
      category: '${json['category'] ?? ''}',
      cities: List<String>.from(json['cities'] ?? const <String>[]),
      createdAt: parseServerTime(json['created_at']) ?? DateTime.now().toUtc(),
      totalCities: (json['total_cities'] as num?)?.toInt() ?? 0,
    );
    job.applyStatus(json);
    return job;
  }

  /// Merge one status payload. Logs are appended when the payload came from a
  /// cursor query (`append: true`), replaced otherwise.
  void applyStatus(Map<String, dynamic> json, {bool appendLogs = false}) {
    final serverNow = parseServerTime(json['server_time']);
    if (serverNow != null) clockOffset = serverNow.difference(DateTime.now());
    final rawStatus = json['status'];
    status = parseScrapingStatus(rawStatus);
    isQueued = rawStatus == 'pending';
    progress = (json['progress'] as num?)?.toInt() ?? progress;
    totalCities = (json['total_cities'] as num?)?.toInt() ?? totalCities;
    completedCities = (json['completed_cities'] as num?)?.toInt() ?? completedCities;
    failedCities = (json['failed_cities'] as num?)?.toInt() ?? failedCities;
    currentCity = '${json['current_city'] ?? currentCity}';
    maxResultsPerCity = (json['max_results_per_city'] as num?)?.toInt() ?? maxResultsPerCity;
    creditCharged = (json['credit_charged'] as num?)?.toInt() ?? creditCharged;
    creditRefunded = (json['credit_refunded'] as num?)?.toInt() ?? creditRefunded;
    settled = json['settled'] == true;
    final category = json['category'];
    if (category is String && category.isNotEmpty) this.category = category;
    final cityList = json['cities'];
    if (cityList is List && cityList.isNotEmpty) cities = List<String>.from(cityList);
    final created = parseServerTime(json['created_at']);
    if (created != null) createdAt = created;
    completedAt = parseServerTime(json['completed_at']);
    error = json['error'] as String?;

    final included = json['results_included'] != false && json['results'] is List;
    if (included) {
      results = List<Map<String, dynamic>>.from(
        (json['results'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
      resultsLoaded = true;
    }
    resultCount = (json['result_count'] as num?)?.toInt() ?? (included ? results.length : resultCount);

    final newLogs = List<String>.from(json['logs'] ?? const <String>[]);
    if (appendLogs) {
      if (newLogs.isNotEmpty) {
        logs = [...logs, ...newLogs];
        if (logs.length > 3000) logs = logs.sublist(logs.length - 3000);
      }
    } else if (json.containsKey('logs')) {
      logs = newLogs;
    }
  }
}

class ScraperProvider with ChangeNotifier {
  ScraperProvider({
    ApiService? api,
    Duration? pollInterval,
    Duration? retryBaseDelay,
    Duration? maxBackoff,
  })  : _apiService = api ?? ApiService(),
        _pollInterval = pollInterval ?? const Duration(seconds: 2),
        _retryBaseDelay = retryBaseDelay ?? const Duration(seconds: 1),
        _maxBackoff = maxBackoff ?? const Duration(seconds: 10) {
    checkApiConnection();
  }

  static const String activeJobPrefKey = 'active_job_id_v1';

  final ApiService _apiService;
  final Duration _pollInterval;
  final Duration _retryBaseDelay;
  final Duration _maxBackoff;

  ScrapingStatus _status = ScrapingStatus.idle;
  ScrapingJob? _currentJob;
  bool _isApiConnected = false;
  String _apiStatus = 'Checking...';
  bool _starting = false;
  String? _startError;
  JobSyncState _syncState = JobSyncState.live;
  String? _syncMessage;
  DateTime? _lastSyncedAt;
  int _consecutiveFailures = 0;
  int _logCursor = 0;
  int _pollGeneration = 0;
  bool _disposed = false;

  // Reused for retries of the same submission so the server never charges twice.
  String? _pendingKey;
  String? _pendingSignature;

  ScrapingStatus get status => _status;
  ScrapingJob? get currentJob => _currentJob;
  bool get isApiConnected => _isApiConnected;
  String get apiStatus => _apiStatus;
  bool get isStarting => _starting;
  String? get startError => _startError;
  JobSyncState get syncState => _syncState;
  String? get syncMessage => _syncMessage;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// True while a job is queued or running on the server (or being created).
  bool get hasActiveJob => _starting || (_currentJob?.isActive ?? false);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> checkApiConnection() async {
    try {
      _isApiConnected = await _apiService.healthCheck();
      _apiStatus = _isApiConnected ? 'Connected' : 'Disconnected';
    } catch (e) {
      _isApiConnected = false;
      _apiStatus = 'Error: $e';
    }
    _notify();
  }

  static String newIdempotencyKey() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return 'job-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  /// Creates a job. Returns true when a job is (or already was) running.
  ///
  /// Network failures are retried with the same idempotency key. If the
  /// outcome is still unknown we look for the job on the server before
  /// reporting an error, so a slow response never leads to a second charge.
  Future<bool> startScraping({
    required String category,
    required List<String> citiesData,
    int maxResultsPerCity = 10,
  }) async {
    if (hasActiveJob) {
      _startError = 'A job is already running. Wait for it to finish or cancel it first.';
      _notify();
      return false;
    }

    final signature = '$category|${citiesData.join(';')}|$maxResultsPerCity';
    if (_pendingKey == null || _pendingSignature != signature) {
      _pendingKey = newIdempotencyKey();
      _pendingSignature = signature;
    }
    final key = _pendingKey!;

    _starting = true;
    _startError = null;
    _notify();

    Object? lastError;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final jobData = await _apiService.createScrapingJob(
            category: category,
            citiesData: citiesData,
            maxResultsPerCity: maxResultsPerCity,
            idempotencyKey: key,
          );
          _pendingKey = null;
          _pendingSignature = null;
          final balance = jobData['credit_balance'];
          if (balance is num) CreditProvider.instance.setBalance(balance.toInt());
          _attach(ScrapingJob.fromJson(Map<String, dynamic>.from(jobData)));
          RefreshBus.notifyJobsChanged();
          return true;
        } catch (e) {
          lastError = e;
          if (!ErrorHandler.isNetworkError(e) && e is! ServerException) {
            // Definitive answer from the server (402, 429, 422, 401...).
            _pendingKey = null;
            _pendingSignature = null;
            _startError = ErrorHandler.getUserFriendlyMessage(e);
            unawaited(CreditProvider.instance.refresh());
            return false;
          }
          await Future<void>.delayed(_retryBaseDelay * (1 << attempt));
        }
      }

      // Outcome unknown: the job may exist. Try to find it before giving up.
      final reattached = await resumeActiveJob(preferSignature: signature);
      if (reattached) return true;
      _startError =
          'We could not confirm that the job started (${ErrorHandler.getUserFriendlyMessage(lastError)}). '
          'Pressing start again is safe - it will not charge twice.';
      return false;
    } finally {
      _starting = false;
      _notify();
    }
  }

  void _attach(ScrapingJob job) {
    _currentJob = job;
    _status = job.status;
    _consecutiveFailures = 0;
    _syncState = JobSyncState.live;
    _syncMessage = null;
    _lastSyncedAt = DateTime.now();
    _notify();
    _persistActiveJob(job.isActive ? job.jobId : null);
    // First poll replaces logs (full list), later polls append via cursor.
    _logCursor = -1;
    _startPolling();
  }

  Future<void> _persistActiveJob(String? jobId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (jobId == null) {
        await prefs.remove(activeJobPrefKey);
      } else {
        await prefs.setString(activeJobPrefKey, jobId);
      }
    } catch (_) {}
  }

  /// Reattach to a running job after refresh/login/navigation.
  /// Returns true if a job was attached.
  Future<bool> resumeActiveJob({String? preferSignature}) async {
    if (_currentJob?.isActive ?? false) return true;
    try {
      final jobs = await _apiService.getActiveJobs();
      if (jobs.isNotEmpty) {
        Map<String, dynamic> pick = jobs.first;
        if (preferSignature != null) {
          for (final j in jobs) {
            final sig = '${j['category']}|${List<String>.from(j['cities'] ?? []).join(';')}|${j['max_results_per_city']}';
            if (sig == preferSignature) {
              pick = j;
              break;
            }
          }
        }
        _attach(ScrapingJob.fromJson(pick));
        return true;
      }
      // Nothing running: show the last job we were watching, if it still exists.
      final prefs = await SharedPreferences.getInstance();
      final lastId = prefs.getString(activeJobPrefKey);
      if (lastId != null && _currentJob == null) {
        final data = await _apiService.getJobStatus(lastId, includeResults: true);
        _attach(ScrapingJob.fromJson(data));
        await _persistActiveJob(null);
        return true;
      }
    } catch (e) {
      if (e is NotFoundException) await _persistActiveJob(null);
      // Offline: leave state as is; the screen offers a retry.
    }
    return false;
  }

  Duration _backoff() {
    final ms = _pollInterval.inMilliseconds * (1 << min(_consecutiveFailures, 4));
    return Duration(milliseconds: min(_maxBackoff.inMilliseconds, max(1, ms)));
  }

  void _startPolling() {
    final generation = ++_pollGeneration;
    unawaited(_pollLoop(generation));
  }

  Future<void> _pollLoop(int generation) async {
    while (!_disposed && generation == _pollGeneration) {
      final job = _currentJob;
      if (job == null) return;
      if (job.isTerminal && job.resultsLoaded) return;

      await Future<void>.delayed(_consecutiveFailures == 0 ? _pollInterval : _backoff());
      if (_disposed || generation != _pollGeneration || _currentJob != job) return;

      final wantResults = job.isTerminal; // fetch the full result set once, at the end
      try {
        final data = await _apiService.getJobStatus(
          job.jobId,
          includeResults: wantResults,
          logsAfter: _logCursor >= 0 ? _logCursor : null,
          requestTimeout: const Duration(seconds: 20),
        );
        if (generation != _pollGeneration || _currentJob != job) return;
        final wasActive = job.isActive;
        job.applyStatus(data, appendLogs: _logCursor >= 0);
        _logCursor = (data['next_log_cursor'] as num?)?.toInt() ?? _logCursor;
        _status = job.status;
        _consecutiveFailures = 0;
        _syncState = JobSyncState.live;
        _syncMessage = null;
        _lastSyncedAt = DateTime.now();

        if (wasActive && job.isTerminal) {
          _persistActiveJob(null);
          RefreshBus.notifyJobsChanged();
          unawaited(CreditProvider.instance.refresh()); // refunds land at settlement
        }
        if (job.isTerminal && !job.settled) {
          // Settlement can lag the status by a moment; refresh balance again later.
          Future<void>.delayed(const Duration(seconds: 5), () => CreditProvider.instance.refresh());
        }
        _notify();
      } catch (e) {
        if (generation != _pollGeneration || _currentJob != job) return;
        if (e is NotFoundException) {
          job.error = 'This job no longer exists (it may have been deleted).';
          job.status = ScrapingStatus.failed;
          _status = ScrapingStatus.failed;
          _persistActiveJob(null);
          _notify();
          return;
        }
        if (ErrorHandler.isAuthError(e)) {
          _syncState = JobSyncState.authExpired;
          _syncMessage = 'Your session expired. Sign in again to keep following this job - it is still running on the server.';
          _notify();
          return;
        }
        // Network/proxy/5xx: the job keeps running server-side. Keep status, back off, retry.
        _consecutiveFailures++;
        _syncState = JobSyncState.reconnecting;
        _syncMessage = 'Connection problem - retrying in ${max(1, _backoff().inSeconds)}s. '
            'The job keeps running on the server.';
        _notify();
      }
    }
  }

  /// Manual "retry now" from the UI.
  void retrySyncNow() {
    if (_currentJob == null) return;
    _consecutiveFailures = 0;
    _syncMessage = 'Reconnecting...';
    _notify();
    _startPolling();
  }

  Future<void> cancelCurrentJob() async {
    final job = _currentJob;
    if (job == null) return;
    await _apiService.cancelJob(job.jobId);
    job.logs = [...job.logs, 'Cancellation requested - stopping after the current business...'];
    _notify();
    // Keep polling: the server reports the real final state and any refund.
    _consecutiveFailures = 0;
    _startPolling();
  }

  Future<Map<String, dynamic>> downloadResults() async {
    if (_currentJob == null) {
      throw Exception('No current job');
    }
    return await _apiService.downloadResults(_currentJob!.jobId);
  }

  List<String> getCurrentLogs() => _currentJob?.logs ?? const <String>[];

  /// Clear the panel (e.g. "New search"). Does not cancel a running job.
  void reset() {
    if (_currentJob?.isActive ?? false) return;
    _pollGeneration++;
    _status = ScrapingStatus.idle;
    _currentJob = null;
    _startError = null;
    _syncState = JobSyncState.live;
    _syncMessage = null;
    _persistActiveJob(null);
    _notify();
  }

  /// Sign-out: stop following jobs without touching them on the server.
  void detach() {
    _pollGeneration++;
    if (_currentJob == null && _startError == null && _pendingKey == null) return;
    _status = ScrapingStatus.idle;
    _currentJob = null;
    _startError = null;
    _pendingKey = null;
    _pendingSignature = null;
    _syncState = JobSyncState.live;
    _syncMessage = null;
    _notify();
  }

  void clearStartError() {
    if (_startError == null) return;
    _startError = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollGeneration++;
    super.dispose();
  }
}
