import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

enum ScrapingStatus {
  idle,
  running,
  completed,
  failed,
}

class ScrapingJob {
  final String jobId;
  final String category;
  final List<String> cities;
  final DateTime createdAt;
  ScrapingStatus status;
  int progress;
  String currentCity;
  List<Map<String, dynamic>> results;
  String? error;
  List<String> logs;

  ScrapingJob({
    required this.jobId,
    required this.category,
    required this.cities,
    required this.createdAt,
    this.status = ScrapingStatus.idle,
    this.progress = 0,
    this.currentCity = '',
    this.results = const [],
    this.error,
    this.logs = const [],
  });
}

class ScraperProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  ScrapingStatus _status = ScrapingStatus.idle;
  ScrapingJob? _currentJob;
  bool _isApiConnected = false;
  String _apiStatus = 'Checking...';

  ScrapingStatus get status => _status;
  ScrapingJob? get currentJob => _currentJob;
  bool get isApiConnected => _isApiConnected;
  String get apiStatus => _apiStatus;

  ScraperProvider() {
    checkApiConnection();
  }

  Future<void> checkApiConnection() async {
    try {
      _isApiConnected = await _apiService.healthCheck();
      _apiStatus = _isApiConnected ? 'Connected' : 'Disconnected';
      notifyListeners();
    } catch (e) {
      _isApiConnected = false;
      _apiStatus = 'Error: $e';
      notifyListeners();
    }
  }

  Future<void> startScraping({
    required String category,
    required List<String> citiesData,
    int maxResultsPerCity = 10,
  }) async {
    try {
      _status = ScrapingStatus.running;
      notifyListeners();

      final jobData = await _apiService.createScrapingJob(
        category: category,
        citiesData: citiesData,
        maxResultsPerCity: maxResultsPerCity,
      );

      _currentJob = ScrapingJob(
        jobId: jobData['job_id'],
        category: category,
        cities: citiesData,
        createdAt: DateTime.now(),
        status: ScrapingStatus.running,
      );

      notifyListeners();

      // Start polling for updates
      _pollJobStatus();
    } catch (e) {
      _status = ScrapingStatus.failed;
      _currentJob?.error = e.toString();
      notifyListeners();
    }
  }

  Future<void> _pollJobStatus() async {
    if (_currentJob == null) return;

    while (_status == ScrapingStatus.running) {
      await Future.delayed(Duration(seconds: 2));

      try {
        final jobData = await _apiService.getJobStatus(_currentJob!.jobId);

        _currentJob!.status = _parseStatus(jobData['status']);
        _currentJob!.progress = jobData['progress'] ?? 0;
        _currentJob!.currentCity = jobData['current_city'] ?? '';
        _currentJob!.results =
            List<Map<String, dynamic>>.from(jobData['results'] ?? []);
        _currentJob!.logs = List<String>.from(jobData['logs'] ?? []);

        if (jobData['error'] != null) {
          _currentJob!.error = jobData['error'];
        }

        notifyListeners();

        if (_currentJob!.status == ScrapingStatus.completed ||
            _currentJob!.status == ScrapingStatus.failed) {
          _status = _currentJob!.status;
          break;
        }
      } catch (e) {
        _currentJob!.error = 'Failed to get job status: $e';
        _currentJob!.status = ScrapingStatus.failed;
        _status = ScrapingStatus.failed;
        notifyListeners();
        break;
      }
    }
  }

  ScrapingStatus _parseStatus(String status) {
    switch (status) {
      case 'pending':
        return ScrapingStatus.running;
      case 'running':
        return ScrapingStatus.running;
      case 'completed':
        return ScrapingStatus.completed;
      case 'failed':
        return ScrapingStatus.failed;
      default:
        return ScrapingStatus.idle;
    }
  }

  Future<String> downloadResults() async {
    if (_currentJob == null) {
      throw Exception('No current job');
    }

    return await _apiService.downloadResults(_currentJob!.jobId);
  }

  List<String> getCurrentLogs() {
    return _currentJob?.logs ?? [];
  }

  void reset() {
    _status = ScrapingStatus.idle;
    _currentJob = null;
    notifyListeners();
  }
}
