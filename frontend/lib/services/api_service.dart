import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/environment.dart';
import '../core/error_handler.dart';

class ApiService {
  // Dynamic base URL based on environment
  static String get baseUrl => Environment.apiUrl;

  // Default timeout duration
  static const Duration timeout = Duration(seconds: 30);

  // Optional in-memory token for "session-only" auth (Remember Me unchecked).
  static String? _inMemoryToken;

  List<Map<String, dynamic>> _decodeListOfMaps(String body, {String? key}) {
    final decoded = jsonDecode(body);
    dynamic listValue = decoded;

    if (decoded is Map<String, dynamic> &&
        key != null &&
        decoded.containsKey(key)) {
      listValue = decoded[key];
    }

    if (listValue is List) {
      return listValue
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return const <Map<String, dynamic>>[];
  }

  Future<String?> getToken() async {
    if (_inMemoryToken != null && _inMemoryToken!.isNotEmpty) {
      return _inMemoryToken;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<void> saveToken(String token, {bool persist = true}) async {
    final prefs = await SharedPreferences.getInstance();
    if (persist) {
      _inMemoryToken = null;
      await prefs.setString('auth_token', token);
    } else {
      _inMemoryToken = token;
      await prefs.remove('auth_token');
    }
  }

  Future<void> clearToken() async {
    _inMemoryToken = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await getToken();
    final headers = {'Content-Type': 'application/json'};
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  /// GET [path] and decode the JSON body. Errors become [ApiException]s with
  /// the backend's own `detail` text (never raw JSON); timeouts and connection
  /// failures become [NetworkException]s.
  Future<dynamic> _getJson(
    String path, {
    Map<String, String>? query,
    String? context,
    Duration? requestTimeout,
  }) async {
    try {
      final headers = await _getHeaders();
      var uri = Uri.parse('$baseUrl$path');
      if (query != null && query.isNotEmpty) {
        uri = uri.replace(queryParameters: query);
      }
      final response = await http
          .get(uri, headers: headers)
          .timeout(requestTimeout ?? timeout);
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      ErrorHandler.handleHttpError(response, context: context);
      throw ApiException('${context ?? 'Request'} failed');
    } on TimeoutException {
      throw NetworkException('Request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  // Authentication endpoints
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String phone,
    String? fullName,
    String? company,
    String? phoneCountry,
    String? visitorId,
    String? sessionId,
    String? geoCountry,
    String? geoCity,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'email': email,
              'password': password,
              'phone': phone,
              if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
              if (company != null && company.isNotEmpty) 'company': company,
              if (phoneCountry != null && phoneCountry.isNotEmpty)
                'phone_country': phoneCountry,
              if (visitorId != null) 'visitor_id': visitorId,
              if (sessionId != null) 'session_id': sessionId,
              if (geoCountry != null) 'geo_country': geoCountry,
              if (geoCity != null) 'geo_city': geoCity,
            }),
          )
          .timeout(timeout);

      if (response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        ErrorHandler.handleHttpError(response, context: 'Registration');
        throw ApiException('Registration failed');
      }
    } on TimeoutException {
      throw NetworkException(
          'Registration request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
    bool rememberMe = true,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await saveToken(data['access_token'], persist: rememberMe);
        return data;
      } else {
        ErrorHandler.handleHttpError(response, context: 'Login');
        throw ApiException('Login failed');
      }
    } on TimeoutException {
      throw NetworkException('Login request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  Future<Map<String, dynamic>> getCurrentUser() async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/auth/me'),
            headers: headers,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        ErrorHandler.handleHttpError(response, context: 'Get user info');
        throw ApiException('Failed to get user info');
      }
    } on TimeoutException {
      throw NetworkException(
          'Request timed out. Please check your connection.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  Future<void> logout() async {
    await clearToken();
  }

  // Password reset endpoints
  Future<void> forgotPassword({required String email}) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/forgot-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'email': email}),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        ErrorHandler.handleHttpError(response,
            context: 'Password reset request');
        throw ApiException('Failed to request password reset');
      }
    } on TimeoutException {
      throw NetworkException('Request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  Future<Map<String, dynamic>> verifyResetToken(String token) async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/auth/verify-reset-token/$token'),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        ErrorHandler.handleHttpError(response, context: 'Token verification');
        throw ApiException('Invalid or expired reset token');
      }
    } on TimeoutException {
      throw NetworkException('Request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/reset-password'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'token': token,
              'new_password': newPassword,
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        ErrorHandler.handleHttpError(response, context: 'Password reset');
        throw ApiException('Failed to reset password');
      }
    } on TimeoutException {
      throw NetworkException('Request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  // Job endpoints

  /// Creates a job. [idempotencyKey] must be reused for retries of the same
  /// submission: the server then returns the original job instead of charging
  /// again, so a timeout or dropped connection can be retried safely.
  Future<Map<String, dynamic>> createScrapingJob({
    required String category,
    required List<String> citiesData,
    int maxResultsPerCity = 10,
    String? idempotencyKey,
  }) async {
    try {
      final headers = await _getHeaders();
      if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/jobs'),
            headers: headers,
            body: jsonEncode({
              'category': category,
              'cities_data': citiesData,
              'max_results_per_city': maxResultsPerCity,
            }),
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        ErrorHandler.handleHttpError(response, context: 'Create job');
        throw ApiException('Failed to create scraping job');
      }
    } on TimeoutException {
      throw NetworkException('Job creation timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  /// Job status. Pollers should pass `includeResults: false` and the last
  /// `next_log_cursor` as [logsAfter] so each poll only moves new data.
  Future<Map<String, dynamic>> getJobStatus(
    String jobId, {
    bool includeResults = true,
    int? logsAfter,
    Duration? requestTimeout,
  }) async {
    try {
      final headers = await _getHeaders();
      final query = <String, String>{
        'include_results': includeResults ? 'true' : 'false',
        if (logsAfter != null) 'logs_after': '$logsAfter',
      };
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/jobs/$jobId').replace(queryParameters: query),
            headers: headers,
          )
          .timeout(requestTimeout ?? timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        ErrorHandler.handleHttpError(response, context: 'Get job status');
        throw ApiException('Failed to get job status');
      }
    } on TimeoutException {
      throw NetworkException('Request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  /// Pending/running jobs of the current user (used to reattach after a
  /// refresh, navigation or an uncertain job-creation response).
  Future<List<Map<String, dynamic>>> getActiveJobs() async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/api/jobs/active'), headers: headers)
          .timeout(timeout);
      if (response.statusCode == 200) {
        return _decodeListOfMaps(response.body, key: 'jobs');
      }
      ErrorHandler.handleHttpError(response, context: 'Get active jobs');
      throw ApiException('Failed to get active jobs');
    } on TimeoutException {
      throw NetworkException('Request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  Future<Map<String, dynamic>> getJobResults(String jobId) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/jobs/$jobId/results'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get job results');
    }
  }

  Future<List<Map<String, dynamic>>> getUserJobs() async {
    final data = await _getJson('/api/jobs', context: 'Loading searches');
    final raw = data is Map ? data['jobs'] : data;
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// One page of the user's searches. Text query ([q]), date range
  /// ([from] inclusive / [to] exclusive, sent as UTC instants), status and
  /// [sort] (`newest` | `oldest` | `most_leads`) are all applied by the
  /// server across every search, then [limit]/[offset] page the result.
  ///
  /// Returns a map with `jobs` (list of job maps), `total` (int, matches all
  /// filters), `counts` (status -> int for the q/date filters),
  /// `overall_total` (int?, all searches) and `paginated` (bool). An older
  /// server that ignores `limit` returns every job; then `total` is the
  /// length of that full list, the window is applied locally and `counts` is
  /// empty.
  Future<Map<String, dynamic>> getJobs({
    int? limit,
    int? offset,
    String? status,
    String? q,
    DateTime? from,
    DateTime? to,
    String? sort,
  }) async {
    final query = <String, String>{
      if (limit != null) 'limit': '$limit',
      if (offset != null) 'offset': '$offset',
      if (status != null && status.isNotEmpty) 'status': status,
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (from != null) 'from': from.toUtc().toIso8601String(),
      if (to != null) 'to': to.toUtc().toIso8601String(),
      if (sort != null && sort.isNotEmpty) 'sort': sort,
    };
    final data =
        await _getJson('/api/jobs', query: query, context: 'Loading searches');
    final rawJobs = data is Map ? data['jobs'] : data;
    var jobs = rawJobs is List
        ? rawJobs
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final rawTotal = data is Map ? data['total'] : null;
    final paginated = rawTotal is num;
    final total = paginated ? rawTotal.toInt() : jobs.length;
    if (!paginated) {
      final start = (offset ?? 0).clamp(0, jobs.length);
      final end =
          limit == null ? jobs.length : (start + limit).clamp(0, jobs.length);
      jobs = jobs.sublist(start, end);
    }
    final counts = <String, int>{};
    final rawCounts = data is Map ? data['counts'] : null;
    if (rawCounts is Map) {
      rawCounts.forEach((key, value) {
        if (value is num) counts['$key'] = value.toInt();
      });
    }
    final overall = data is Map ? data['overall_total'] : null;
    return {
      'jobs': jobs,
      'total': total,
      'counts': counts,
      'overall_total': overall is num ? overall.toInt() : null,
      'paginated': paginated,
    };
  }

  Future<void> deleteJob(String jobId) async {
    final headers = await _getHeaders();
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/jobs/$jobId'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      ErrorHandler.handleHttpError(response, context: 'Delete job');
      throw ApiException('Failed to delete job');
    }
  }

  Future<Map<String, dynamic>> downloadResults(String jobId) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/jobs/$jobId/download'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'filename': data['filename'] ?? 'results.xlsx',
        'content': data['content'],
        'content_type': data['content_type'] ??
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        'encoding': data['encoding'] ?? 'base64',
      };
    } else {
      throw Exception('Failed to download results');
    }
  }

  // States and Cities endpoints
  Future<Map<String, List<String>>> getStates() async {
    final response =
        await http.get(Uri.parse('$baseUrl/api/states')).timeout(timeout);
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid states response');
      }

      final out = <String, List<String>>{};
      decoded.forEach((key, value) {
        if (value is List) {
          out[key] = value.map((e) => e.toString()).toList();
        }
      });
      return out;
    } else {
      throw Exception('Failed to load states');
    }
  }

  Future<List<String>> getCities(String state) async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/states/${Uri.encodeComponent(state)}/cities'),
        )
        .timeout(timeout);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<String>.from(data['cities'] ?? []);
    } else {
      throw Exception('Failed to load cities for $state');
    }
  }

  Future<List<String>> getCountries() async {
    final response =
        await http.get(Uri.parse('$baseUrl/api/countries')).timeout(timeout);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<String>.from(data['countries'] ?? []);
    } else {
      throw Exception('Failed to load countries');
    }
  }

  /// GET /api/locations/summary → `{countries: {Canada: {region_term:
  /// "province", regions: {Quebec: 30, ...}}}}` (public, read-only).
  /// Returns the inner `countries` map.
  Future<Map<String, dynamic>> getLocationsSummary() async {
    final data = await _getJson('/api/locations/summary',
        context: 'Loading locations');
    final countries = data is Map ? data['countries'] : null;
    return countries is Map
        ? Map<String, dynamic>.from(countries)
        : <String, dynamic>{};
  }

  Future<bool> healthCheck() async {
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/health'),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Admin endpoints
  Future<Map<String, dynamic>> getAdminStats() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/stats'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get admin stats');
    }
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/users'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['users']);
    } else {
      throw Exception('Failed to get users');
    }
  }

  Future<void> approveUser(int userId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/users/$userId/approve'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to approve user');
    }
  }

  /// Profile fields only (username, email, phone). Roles are never sent from
  /// here; use [updateUserRole] for an explicit, owner-only role change. Pass
  /// only the fields that changed.
  Future<void> updateUserProfileAdmin(
    int userId, {
    String? username,
    String? email,
    String? phone,
    String? phoneCountry,
    String? fullName,
    String? company,
  }) async {
    final headers = await _getHeaders();
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (email != null) body['email'] = email;
    if (phone != null) body['phone'] = phone;
    if (phone != null && phoneCountry != null) {
      body['phone_country'] = phoneCountry;
    }
    if (fullName != null) body['full_name'] = fullName;
    if (company != null) body['company'] = company;

    final response = await http
        .put(
          Uri.parse('$baseUrl/api/admin/users/$userId'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      ErrorHandler.handleHttpError(response, context: 'Update profile');
      throw ApiException('Failed to update user profile');
    }
  }

  Future<Map<String, dynamic>> bulkApproveUsers(List<int> userIds) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/users/bulk-approve'),
      headers: headers,
      body: jsonEncode({'user_ids': userIds}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to bulk-approve users');
    }
  }

  Future<Map<String, dynamic>> suspendUser(
    int userId, {
    String? reason,
  }) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/users/$userId/suspend'),
      headers: headers,
      body: jsonEncode({
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      ErrorHandler.handleHttpError(response, context: 'Suspend');
      throw ApiException('Failed to suspend user');
    }
  }

  Future<Map<String, dynamic>> unsuspendUser(int userId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/users/$userId/unsuspend'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      ErrorHandler.handleHttpError(response, context: 'Unsuspend');
      throw ApiException('Failed to restore suspended user');
    }
  }

  Future<void> deleteUser(int userId) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/api/admin/users/$userId'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      ErrorHandler.handleHttpError(response, context: 'Delete user');
      throw ApiException('Failed to delete user');
    }
  }

  // ==================== CREDIT ENDPOINTS ====================

  /// Credit configuration (costs, limits and, when the server provides
  /// them, `min_job_cost` and `refund_policy`). Treat every field as optional.
  Future<Map<String, dynamic>> getCreditConfig() async {
    final data = await _getJson('/api/credits/config',
        context: 'Loading credit settings');
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> getCreditBalance() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/credits/balance'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print(
          'getCreditBalance error: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to get credit balance: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> estimateJobCost({
    required int numCities,
    int maxResultsPerCity = 10,
  }) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/credits/estimate'),
      headers: headers,
      body: jsonEncode({
        'num_cities': numCities,
        'max_results_per_city': maxResultsPerCity,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to estimate job cost');
    }
  }

  /// Credit ledger (GET /api/credits/history), newest first. Each entry has
  /// `amount` (+/-), `balance_after`, `transaction_type`, `reason`, `job_id`
  /// and `created_at`.
  Future<List<Map<String, dynamic>>> getCreditHistory() async {
    try {
      final data = await _getJson('/api/credits/history',
          context: 'Loading credit history');
      final list = data is Map ? data['transactions'] : data;
      if (list is! List) return <Map<String, dynamic>>[];
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } on NotFoundException {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> requestCredits({
    required int amount,
    String? reason,
  }) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/credits/request'),
      headers: headers,
      body: jsonEncode({
        'amount_requested': amount,
        'reason': reason,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to request credits');
    }
  }

  Future<List<Map<String, dynamic>>> getMyCreditRequests() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/credits/requests'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['requests']);
    } else if (response.statusCode == 404) {
      return [];
    } else {
      print(
          'getMyCreditRequests error: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to get credit requests: ${response.statusCode}');
    }
  }

  // ==================== ADMIN CREDIT MANAGEMENT ====================

  Future<List<Map<String, dynamic>>> getAdminCreditRequests() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/credits/requests'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['requests']);
    } else {
      throw Exception('Failed to get credit requests');
    }
  }

  Future<Map<String, dynamic>> approveCreditRequest(int requestId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/credits/requests/$requestId/approve'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to approve credit request');
    }
  }

  Future<void> denyCreditRequest(int requestId, {String? adminNote}) async {
    final headers = await _getHeaders();
    final uri =
        Uri.parse('$baseUrl/api/admin/credits/requests/$requestId/deny');
    final response = await http.post(
      adminNote != null
          ? uri.replace(queryParameters: {'admin_note': adminNote})
          : uri,
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to deny credit request');
    }
  }

  Future<Map<String, dynamic>> bulkApproveCreditRequests(
      List<int> requestIds) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/credits/requests/bulk-approve'),
      headers: headers,
      body: jsonEncode({'request_ids': requestIds}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to bulk-approve credit requests');
    }
  }

  Future<Map<String, dynamic>> bulkDenyCreditRequests(
    List<int> requestIds, {
    String? adminNote,
  }) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/credits/requests/bulk-deny'),
      headers: headers,
      body: jsonEncode({'request_ids': requestIds, 'admin_note': adminNote}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to bulk-deny credit requests');
    }
  }

  Future<Map<String, dynamic>> grantCredits({
    required int userId,
    required int amount,
    String? reason,
  }) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/admin/users/$userId/credits'),
      headers: headers,
      body: jsonEncode({
        'amount': amount,
        'reason': reason,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      ErrorHandler.handleHttpError(response, context: 'Grant credits');
      throw ApiException('Failed to grant credits');
    }
  }

  Future<Map<String, dynamic>> getUserCreditsAdmin(int userId) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/users/$userId/credits'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get user credits');
    }
  }

  // ==================== ADMIN ANALYTICS ====================

  Future<Map<String, dynamic>> getAdminRevenueDashboard() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/admin/analytics/revenue'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load revenue analytics');
    }
  }

  Future<Map<String, dynamic>> getAdminMrr() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/admin/analytics/mrr'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load MRR analytics');
    }
  }

  // ==================== ADMIN PACKAGES & PLANS ====================

  Future<Map<String, dynamic>> getAdminCreditPackages() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/admin/payments/packages'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load packages');
    }
  }

  Future<Map<String, dynamic>> createCreditPackage({
    required String name,
    required int credits,
    required int basePriceCents,
    required int displayPriceCents,
    bool isActive = true,
  }) async {
    final headers = await _getHeaders();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/admin/payments/packages'),
          headers: headers,
          body: jsonEncode({
            'name': name,
            'credits': credits,
            'base_price_cents': basePriceCents,
            'display_price_cents': displayPriceCents,
            'is_active': isActive,
          }),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create package');
    }
  }

  Future<void> updateCreditPackage(
    int packageId, {
    String? name,
    int? credits,
    int? basePriceCents,
    int? displayPriceCents,
    bool? isActive,
  }) async {
    final headers = await _getHeaders();
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (credits != null) body['credits'] = credits;
    if (basePriceCents != null) body['base_price_cents'] = basePriceCents;
    if (displayPriceCents != null) {
      body['display_price_cents'] = displayPriceCents;
    }
    if (isActive != null) body['is_active'] = isActive;

    final response = await http
        .put(
          Uri.parse('$baseUrl/api/admin/payments/packages/$packageId'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to update package');
    }
  }

  Future<void> deleteCreditPackage(int packageId) async {
    final headers = await _getHeaders();
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/admin/payments/packages/$packageId'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to delete package');
    }
  }

  Future<Map<String, dynamic>> getAdminSubscriptionPlans() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/admin/subscriptions/plans'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load plans');
    }
  }

  Future<Map<String, dynamic>> createSubscriptionPlan({
    required String name,
    required String billingInterval,
    required int creditsPerPeriod,
    required int basePriceCents,
    String? stripePriceId,
    bool isActive = true,
  }) async {
    final headers = await _getHeaders();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/admin/subscriptions/plans'),
          headers: headers,
          body: jsonEncode({
            'name': name,
            'billing_interval': billingInterval,
            'credits_per_period': creditsPerPeriod,
            'base_price_cents': basePriceCents,
            'stripe_price_id': stripePriceId,
            'is_active': isActive,
          }),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create plan');
    }
  }

  Future<void> updateSubscriptionPlan(
    int planId, {
    String? name,
    String? billingInterval,
    int? creditsPerPeriod,
    int? basePriceCents,
    String? stripePriceId,
    bool? isActive,
  }) async {
    final headers = await _getHeaders();
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (billingInterval != null) body['billing_interval'] = billingInterval;
    if (creditsPerPeriod != null) body['credits_per_period'] = creditsPerPeriod;
    if (basePriceCents != null) body['base_price_cents'] = basePriceCents;
    if (stripePriceId != null) body['stripe_price_id'] = stripePriceId;
    if (isActive != null) body['is_active'] = isActive;

    final response = await http
        .put(
          Uri.parse('$baseUrl/api/admin/subscriptions/plans/$planId'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to update plan');
    }
  }

  Future<void> deleteSubscriptionPlan(int planId) async {
    final headers = await _getHeaders();
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/admin/subscriptions/plans/$planId'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to delete plan');
    }
  }

  // ==================== PRICING TIERS ====================

  Future<List<Map<String, dynamic>>> getPricingTiers() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/pricing/tiers'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load pricing tiers');
    }
  }

  Future<Map<String, dynamic>> createPricingTier({
    required String name,
    int minMonthlyCredits = 0,
    int? maxMonthlyCredits,
    required double pricePerCreditCents,
    double discountPercentage = 0,
    bool requiresApproval = false,
    bool isActive = true,
  }) async {
    final headers = await _getHeaders();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/admin/pricing/tiers'),
          headers: headers,
          body: jsonEncode({
            'name': name,
            'min_monthly_credits': minMonthlyCredits,
            'max_monthly_credits': maxMonthlyCredits,
            'price_per_credit_cents': pricePerCreditCents,
            'discount_percentage': discountPercentage,
            'requires_approval': requiresApproval,
            'is_active': isActive,
          }),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create pricing tier');
    }
  }

  Future<void> updatePricingTier(
    int tierId, {
    String? name,
    int? minMonthlyCredits,
    int? maxMonthlyCredits,
    double? pricePerCreditCents,
    double? discountPercentage,
    bool? requiresApproval,
    bool? isActive,
  }) async {
    final headers = await _getHeaders();
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (minMonthlyCredits != null) {
      body['min_monthly_credits'] = minMonthlyCredits;
    }
    if (maxMonthlyCredits != null) {
      body['max_monthly_credits'] = maxMonthlyCredits;
    }
    if (pricePerCreditCents != null) {
      body['price_per_credit_cents'] = pricePerCreditCents;
    }
    if (discountPercentage != null) {
      body['discount_percentage'] = discountPercentage;
    }
    if (requiresApproval != null) body['requires_approval'] = requiresApproval;
    if (isActive != null) body['is_active'] = isActive;

    final response = await http
        .put(
          Uri.parse('$baseUrl/api/admin/pricing/tiers/$tierId'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to update pricing tier');
    }
  }

  // ==================== ADMIN PROMOS ====================

  Future<Map<String, dynamic>> getAdminPromos() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/admin/promos'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load promos');
    }
  }

  Future<Map<String, dynamic>> createPromo({
    required String code,
    required String type,
    double discountPercentage = 0,
    int discountAmountCents = 0,
    int bonusCredits = 0,
    int? maxUses,
    int maxUsesPerUser = 1,
    int minPurchaseCents = 0,
    String? validFrom,
    String? validUntil,
    String appliesTo = 'all',
    bool isActive = true,
  }) async {
    final headers = await _getHeaders();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/admin/promos'),
          headers: headers,
          body: jsonEncode({
            'code': code,
            'type': type,
            'discount_percentage': discountPercentage,
            'discount_amount_cents': discountAmountCents,
            'bonus_credits': bonusCredits,
            'max_uses': maxUses,
            'max_uses_per_user': maxUsesPerUser,
            'min_purchase_cents': minPurchaseCents,
            'valid_from': validFrom,
            'valid_until': validUntil,
            'applies_to': appliesTo,
            'is_active': isActive,
          }),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create promo');
    }
  }

  Future<void> updatePromo(
    int promoId, {
    String? code,
    String? type,
    double? discountPercentage,
    int? discountAmountCents,
    int? bonusCredits,
    int? maxUses,
    int? maxUsesPerUser,
    int? minPurchaseCents,
    String? validFrom,
    String? validUntil,
    String? appliesTo,
    bool? isActive,
  }) async {
    final headers = await _getHeaders();
    final body = <String, dynamic>{};
    if (code != null) body['code'] = code;
    if (type != null) body['type'] = type;
    if (discountPercentage != null) {
      body['discount_percentage'] = discountPercentage;
    }
    if (discountAmountCents != null) {
      body['discount_amount_cents'] = discountAmountCents;
    }
    if (bonusCredits != null) body['bonus_credits'] = bonusCredits;
    if (maxUses != null) body['max_uses'] = maxUses;
    if (maxUsesPerUser != null) body['max_uses_per_user'] = maxUsesPerUser;
    if (minPurchaseCents != null) body['min_purchase_cents'] = minPurchaseCents;
    if (validFrom != null) body['valid_from'] = validFrom;
    if (validUntil != null) body['valid_until'] = validUntil;
    if (appliesTo != null) body['applies_to'] = appliesTo;
    if (isActive != null) body['is_active'] = isActive;

    final response = await http
        .put(
          Uri.parse('$baseUrl/api/admin/promos/$promoId'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to update promo');
    }
  }

  Future<void> deactivatePromo(int promoId) async {
    final headers = await _getHeaders();
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/admin/promos/$promoId'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to deactivate promo');
    }
  }

  Future<Map<String, dynamic>> getAdminPromoUsage(int promoId) async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/admin/promos/$promoId/usage'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load promo usage');
    }
  }

  // ==================== PAYMENT ENDPOINTS (USER-FACING) ====================

  Future<List<Map<String, dynamic>>> getCreditPackages() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/payments/packages'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return _decodeListOfMaps(response.body, key: 'packages');
    } else {
      throw Exception('Failed to load credit packages');
    }
  }

  Future<void> cancelJob(String jobId) async {
    final headers = await _getHeaders();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/jobs/$jobId/cancel'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      ErrorHandler.handleHttpError(response, context: 'Cancel job');
      throw ApiException('Failed to cancel job');
    }
  }

  Future<Map<String, dynamic>> calculatePrice({
    required int packageId,
    String? promoCode,
  }) async {
    final headers = await _getHeaders();
    final body = <String, dynamic>{'package_id': packageId};
    if (promoCode != null && promoCode.isNotEmpty) {
      body['promo_code'] = promoCode;
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/payments/calculate-price'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      ErrorHandler.handleHttpError(response, context: 'Price calculation');
      throw ApiException('Failed to calculate price');
    }
  }

  Future<Map<String, dynamic>> purchaseCredits({
    required int packageId,
    required String paymentProvider,
    String? paymentMethodId,
    String? promoCode,
    required String idempotencyKey,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/payments/purchase'),
            headers: headers,
            body: jsonEncode({
              'package_id': packageId,
              'payment_provider': paymentProvider,
              'payment_method_id': paymentMethodId,
              'promo_code': promoCode,
              'idempotency_key': idempotencyKey,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        ErrorHandler.handleHttpError(response, context: 'Purchase');
        throw ApiException('Failed to process purchase');
      }
    } on TimeoutException {
      throw NetworkException(
          'Purchase request timed out. Please check your payment status.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  /// Public price list (no account needed): {currency, packs: [{id, name, credits, price_cents}]}.
  Future<Map<String, dynamic>> getPublicCreditPacks() async {
    final response = await http
        .get(Uri.parse('$baseUrl/api/public/credit-packs'))
        .timeout(timeout);
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException('Could not load prices', statusCode: response.statusCode);
  }

  /// What the checkout may offer this user (provider, environment, currency, availability).
  Future<Map<String, dynamic>> getCheckoutConfig() async {
    final headers = await _getHeaders();
    final response = await http
        .get(Uri.parse('$baseUrl/api/payments/checkout-config'), headers: headers)
        .timeout(timeout);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    ErrorHandler.handleHttpError(response, context: 'Checkout');
    throw ApiException('Could not load checkout options');
  }

  /// Server-confirmed status of a Safepay payment. The server may check with
  /// Safepay itself; the browser return never grants credits.
  Future<Map<String, dynamic>> getSafepayPaymentStatus(String transactionId) async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/payments/safepay/${Uri.encodeComponent(transactionId)}/status'),
          headers: headers,
        )
        .timeout(timeout);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    ErrorHandler.handleHttpError(response, context: 'Payment status');
    throw ApiException('Could not check the payment status');
  }

  /// The shopper came back through Safepay's cancel link.
  Future<Map<String, dynamic>> cancelSafepayPayment(String transactionId) async {
    final headers = await _getHeaders();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/payments/safepay/${Uri.encodeComponent(transactionId)}/cancel'),
          headers: headers,
        )
        .timeout(timeout);
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    ErrorHandler.handleHttpError(response, context: 'Payment status');
    throw ApiException('Could not update the payment');
  }

  Future<Map<String, dynamic>> simplePurchaseCredits({
    required int credits,
    String? promoCode,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/payments/simple-purchase'),
            headers: headers,
            body: jsonEncode({
              'credits': credits,
              'promo_code': promoCode,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        ErrorHandler.handleHttpError(response, context: 'Simple Purchase');
        throw ApiException('Failed to initiate checkout');
      }
    } on TimeoutException {
      throw NetworkException('Checkout request timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  Future<List<Map<String, dynamic>>> getPaymentTransactions() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/payments/transactions'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return _decodeListOfMaps(response.body, key: 'transactions');
    } else if (response.statusCode == 404) {
      return [];
    } else {
      print(
          'getPaymentTransactions error: ${response.statusCode} - ${response.body}');
      throw Exception(
          'Failed to load payment transactions: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getPaymentTransaction(
      String transactionId) async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/payments/transactions/$transactionId'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load transaction details');
    }
  }

  Future<Map<String, dynamic>> capturePayPalPayment({
    required String transactionId,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/payments/paypal/capture'),
            headers: headers,
            body: jsonEncode({'transaction_id': transactionId}),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        ErrorHandler.handleHttpError(response, context: 'PayPal capture');
        throw ApiException('Failed to complete PayPal payment');
      }
    } on TimeoutException {
      throw NetworkException('PayPal capture timed out. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  // ==================== PAYMENT METHODS ====================

  Future<List<Map<String, dynamic>>> getPaymentMethods() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/payments/methods'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return _decodeListOfMaps(response.body, key: 'methods');
    } else {
      throw Exception('Failed to load payment methods');
    }
  }

  Future<Map<String, dynamic>> addPaymentMethod(String paymentMethodId) async {
    final headers = await _getHeaders();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/payments/methods'),
          headers: headers,
          body: jsonEncode({'payment_method_id': paymentMethodId}),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      ErrorHandler.handleHttpError(response, context: 'Add payment method');
      throw ApiException('Failed to add payment method');
    }
  }

  Future<void> removePaymentMethod(int methodId) async {
    final headers = await _getHeaders();
    final response = await http
        .delete(
          Uri.parse('$baseUrl/api/payments/methods/$methodId'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to remove payment method');
    }
  }

  Future<void> setDefaultPaymentMethod(int methodId) async {
    final headers = await _getHeaders();
    final response = await http
        .put(
          Uri.parse('$baseUrl/api/payments/methods/$methodId/default'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to set default payment method');
    }
  }

  // ==================== SUBSCRIPTIONS (USER-FACING) ====================

  Future<List<Map<String, dynamic>>> getSubscriptionPlans() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/subscriptions/plans'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return _decodeListOfMaps(response.body, key: 'plans');
    } else {
      throw Exception('Failed to load subscription plans');
    }
  }

  Future<Map<String, dynamic>> createSubscription({
    required int planId,
    String? paymentMethodId,
    String? promoCode,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/subscriptions/subscribe'),
            headers: headers,
            body: jsonEncode({
              'plan_id': planId,
              'payment_method_id': paymentMethodId,
              'promo_code': promoCode,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        ErrorHandler.handleHttpError(response, context: 'Create subscription');
        throw ApiException('Failed to create subscription');
      }
    } on TimeoutException {
      throw NetworkException('Subscription request timed out.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  Future<Map<String, dynamic>> getMySubscription() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/subscriptions/my-subscription'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 404) {
      return {};
    } else {
      print(
          'getMySubscription error: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to load subscription: ${response.statusCode}');
    }
  }

  Future<void> cancelSubscription(int subscriptionId,
      {bool immediate = false}) async {
    final headers = await _getHeaders();
    final response = await http
        .put(
          Uri.parse('$baseUrl/api/subscriptions/$subscriptionId/cancel'),
          headers: headers,
          body: jsonEncode({'immediate': immediate}),
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      ErrorHandler.handleHttpError(response, context: 'Cancel subscription');
      throw ApiException('Failed to cancel subscription');
    }
  }

  Future<void> pauseSubscription(int subscriptionId) async {
    final headers = await _getHeaders();
    final response = await http
        .put(
          Uri.parse('$baseUrl/api/subscriptions/$subscriptionId/pause'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to pause subscription');
    }
  }

  Future<void> resumeSubscription(int subscriptionId) async {
    final headers = await _getHeaders();
    final response = await http
        .put(
          Uri.parse('$baseUrl/api/subscriptions/$subscriptionId/resume'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Failed to resume subscription');
    }
  }

  // ==================== INVOICES ====================

  Future<List<Map<String, dynamic>>> getInvoices() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/invoices'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return _decodeListOfMaps(response.body, key: 'invoices');
    } else if (response.statusCode == 404) {
      return [];
    } else {
      print('getInvoices error: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to load invoices: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getInvoiceDetails(int invoiceId) async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/invoices/$invoiceId'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load invoice details');
    }
  }

  Future<Map<String, dynamic>> downloadInvoice(int invoiceId) async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/invoices/$invoiceId/download'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'filename': data['filename'] ?? 'invoice.pdf',
        'content': data['content'],
        'content_type': data['content_type'] ?? 'application/pdf',
        'encoding': data['encoding'] ?? 'base64',
      };
    } else {
      throw Exception('Failed to download invoice');
    }
  }

  // ==================== PROMO VALIDATION (USER-FACING) ====================

  Future<Map<String, dynamic>> validatePromoCode(
    String code, {
    String appliesTo = 'packages',
    int? packageId,
    int quantity = 1,
    int? subtotalCents,
  }) async {
    final headers = await _getHeaders();
    final body = <String, dynamic>{
      'code': code,
      'applies_to': appliesTo,
      'quantity': quantity,
    };
    if (packageId != null) body['package_id'] = packageId;
    if (subtotalCents != null) body['subtotal_cents'] = subtotalCents;

    final response = await http
        .post(
          Uri.parse('$baseUrl/api/promos/validate'),
          headers: headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['valid'] == false) {
        throw ApiException('Invalid promo code');
      }
      return Map<String, dynamic>.from(decoded as Map);
    } else {
      ErrorHandler.handleHttpError(response, context: 'Promo validation');
      throw ApiException('Invalid promo code');
    }
  }

  // ==================== USER ANALYTICS ====================

  Future<Map<String, dynamic>> getSpendingAnalytics() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/analytics/spending'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load spending analytics');
    }
  }

  Future<Map<String, dynamic>> getUsageAnalytics() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/analytics/usage'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load usage analytics');
    }
  }

  // ==================== USER PROMOS/REFERRALS ====================

  Future<Map<String, dynamic>> getMyReferralCode() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/promos/my-referral-code'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get referral code');
    }
  }

  Future<Map<String, dynamic>> getReferralStats() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/promos/referral-stats'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get referral stats');
    }
  }

  // ==================== ADMIN SETTINGS ====================

  Future<Map<String, dynamic>> getFeatureFlags() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/features'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get feature flags');
    }
  }

  Future<Map<String, dynamic>> getAdminSettings() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/admin/settings'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get admin settings');
    }
  }

  Future<String> getAdminSetting(String key) async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/admin/settings/$key'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['value'] ?? '';
    } else {
      throw Exception('Failed to get setting: $key');
    }
  }

  Future<Map<String, dynamic>> updateAdminSetting(
      String key, String value) async {
    final headers = await _getHeaders();
    final response = await http
        .put(
          Uri.parse('$baseUrl/api/admin/settings/$key'),
          headers: headers,
          body: jsonEncode({'value': value}),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update setting: $key');
    }
  }

  // ==================== ADMIN ACTIVITY / AUDIT ====================

  Future<Map<String, dynamic>> getActivityFeed({
    int? userId,
    String? action,
    String? status,
    String? dateFrom,
    String? dateTo,
    int limit = 50,
    int offset = 0,
  }) async {
    final headers = await _getHeaders();
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (userId != null) params['user_id'] = userId.toString();
    if (action != null && action.isNotEmpty) params['action'] = action;
    if (status != null && status.isNotEmpty) params['status'] = status;
    if (dateFrom != null && dateFrom.isNotEmpty) params['date_from'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) params['date_to'] = dateTo;

    final uri = Uri.parse('$baseUrl/api/admin/activity')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: headers).timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load activity feed');
    }
  }

  Future<List<String>> getActivityActions() async {
    final headers = await _getHeaders();
    final response = await http
        .get(Uri.parse('$baseUrl/api/admin/activity/actions'), headers: headers)
        .timeout(timeout);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<String>.from(data['actions'] ?? []);
    } else {
      throw Exception('Failed to load activity actions');
    }
  }

  Future<String> exportActivityCSV({
    int? userId,
    String? action,
    String? dateFrom,
    String? dateTo,
  }) async {
    final headers = await _getHeaders();
    headers.remove('Content-Type');
    final params = <String, String>{};
    if (userId != null) params['user_id'] = userId.toString();
    if (action != null && action.isNotEmpty) params['action'] = action;
    if (dateFrom != null && dateFrom.isNotEmpty) params['date_from'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) params['date_to'] = dateTo;

    final uri = Uri.parse('$baseUrl/api/admin/activity/export')
        .replace(queryParameters: params.isNotEmpty ? params : null);
    final response = await http.get(uri, headers: headers).timeout(timeout);

    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to export activity CSV');
    }
  }

  Future<Map<String, dynamic>> getUserTimeline(int userId,
      {int limit = 100, int offset = 0}) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/api/admin/users/$userId/timeline')
        .replace(queryParameters: {
      'limit': limit.toString(),
      'offset': offset.toString(),
    });
    final response = await http.get(uri, headers: headers).timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load user timeline');
    }
  }

  Future<Map<String, dynamic>> getUserKpis(int userId) async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/admin/users/$userId/kpis'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load user KPIs');
    }
  }

  /// Classified credit totals, reconciliation and one page of ledger history.
  Future<Map<String, dynamic>> getUserCreditReport(int userId,
      {int page = 1, int pageSize = 25}) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/api/admin/users/$userId/credit-report')
        .replace(queryParameters: {
      'page': '$page',
      'page_size': '$pageSize',
    });
    final response = await http.get(uri, headers: headers).timeout(timeout);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to load credit history (${response.statusCode})');
  }

  /// Time-windowed overview metrics. [range] is 24h, 7d, 30d or all.
  Future<Map<String, dynamic>> getAdminOverview(String range) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/api/admin/overview')
        .replace(queryParameters: {'range': range});
    final response = await http.get(uri, headers: headers).timeout(timeout);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to load overview (${response.statusCode})');
  }

  /// Internal dependency health reported by the backend process.
  Future<Map<String, dynamic>> getAdminHealth() async {
    final headers = await _getHeaders();
    final response = await http
        .get(Uri.parse('$baseUrl/api/admin/health'), headers: headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    }
    throw Exception('Health check failed (${response.statusCode})');
  }

  /// Measures the public path from this browser to the API (on the web build:
  /// this site's /api rewrite -> Cloudflare tunnel -> backend). Returns the
  /// round-trip time in milliseconds. Throws unless the answer is the API's
  /// own health document: a proxy, captive portal or error page that answers
  /// HTTP 200 with HTML is NOT "reachable".
  Future<int> probePublicApi({http.Client? client}) async {
    final uri = Uri.parse('$baseUrl/api/health');
    final sw = Stopwatch()..start();
    final response = await (client != null ? client.get(uri) : http.get(uri))
        .timeout(const Duration(seconds: 8));
    sw.stop();
    if (response.statusCode != 200) {
      throw Exception('Public API returned HTTP ${response.statusCode}');
    }
    if (!isApiHealthBody(response.body)) {
      throw Exception(
          'Public URL answered HTTP 200, but not with the API health response');
    }
    return sw.elapsedMilliseconds;
  }

  /// True only for the backend's `/api/health` JSON:
  /// `{"status": "healthy", "timestamp": "<iso time>"}`.
  static bool isApiHealthBody(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map &&
          decoded['status'] == 'healthy' &&
          decoded['timestamp'] is String &&
          DateTime.tryParse(decoded['timestamp'] as String) != null;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getUserJobsAdmin(int userId) async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/admin/users/$userId/jobs'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return _decodeListOfMaps(response.body, key: 'jobs');
    } else {
      throw Exception('Failed to load user jobs');
    }
  }

  Future<Map<String, dynamic>> getAdminAllJobs({
    String? status,
    int page = 1,
    int limit = 50,
  }) async {
    final headers = await _getHeaders();
    final query = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };
    if (status != null && status.trim().isNotEmpty) {
      query['status'] = status.trim().toLowerCase();
    }

    final uri =
        Uri.parse('$baseUrl/api/admin/jobs').replace(queryParameters: query);
    final response = await http.get(uri, headers: headers).timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load admin jobs');
    }
  }

  Future<Map<String, dynamic>> getAdminJobActivity({
    int? userId,
    String? eventType,
    String? jobStatus,
    String? jobType,
    String? dateFrom,
    String? dateTo,
    int limit = 50,
    int offset = 0,
  }) async {
    final headers = await _getHeaders();
    final params = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (userId != null) params['user_id'] = userId.toString();
    if (eventType != null && eventType.isNotEmpty) {
      params['event_type'] = eventType;
    }
    if (jobStatus != null && jobStatus.isNotEmpty) {
      params['job_status'] = jobStatus;
    }
    if (jobType != null && jobType.isNotEmpty) params['job_type'] = jobType;
    if (dateFrom != null && dateFrom.isNotEmpty) params['date_from'] = dateFrom;
    if (dateTo != null && dateTo.isNotEmpty) params['date_to'] = dateTo;

    final uri = Uri.parse('$baseUrl/api/admin/job-activity')
        .replace(queryParameters: params);
    final response = await http.get(uri, headers: headers).timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load job activity feed');
    }
  }

  Future<Map<String, dynamic>> getAdminJobActivityFilters() async {
    final headers = await _getHeaders();
    final response = await http
        .get(
          Uri.parse('$baseUrl/api/admin/job-activity/filters'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load job activity filters');
    }
  }

  // ── Analytics Admin Endpoints ─────────────────────────────────────────────

  Future<Map<String, dynamic>> getAnalyticsDau({int days = 30}) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/api/admin/analytics/dau')
        .replace(queryParameters: {'days': days.toString()});
    final response = await http.get(uri, headers: headers).timeout(timeout);
    if (response.statusCode == 200)
      return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('Failed to load DAU analytics');
  }

  Future<Map<String, dynamic>> getAnalyticsFeatureAdoption(
      {int days = 30}) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/api/admin/analytics/feature-adoption')
        .replace(queryParameters: {'days': days.toString()});
    final response = await http.get(uri, headers: headers).timeout(timeout);
    if (response.statusCode == 200)
      return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('Failed to load feature adoption analytics');
  }

  Future<Map<String, dynamic>> getAnalyticsFunnel({int days = 90}) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/api/admin/analytics/funnel')
        .replace(queryParameters: {'days': days.toString()});
    final response = await http.get(uri, headers: headers).timeout(timeout);
    if (response.statusCode == 200)
      return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('Failed to load funnel analytics');
  }

  Future<Map<String, dynamic>> getAnalyticsSessionStats({int days = 30}) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/api/admin/analytics/session-stats')
        .replace(queryParameters: {'days': days.toString()});
    final response = await http.get(uri, headers: headers).timeout(timeout);
    if (response.statusCode == 200)
      return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('Failed to load session stats');
  }

  Future<Map<String, dynamic>> getAnalyticsCreditPatterns(
      {int days = 30}) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/api/admin/analytics/credit-patterns')
        .replace(queryParameters: {'days': days.toString()});
    final response = await http.get(uri, headers: headers).timeout(timeout);
    if (response.statusCode == 200)
      return jsonDecode(response.body) as Map<String, dynamic>;
    throw Exception('Failed to load credit pattern analytics');
  }

  // ─────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getJobResultsAdmin(
    String jobId, {
    int limit = 100,
    int offset = 0,
    String? search,
  }) async {
    final headers = await _getHeaders();
    final query = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (search != null && search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }
    final uri = Uri.parse('$baseUrl/api/admin/jobs/$jobId/results')
        .replace(queryParameters: query);
    final response = await http
        .get(
          uri,
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load job results');
    }
  }

  /// Explicit role change (owner only): PUT /api/admin/users/{id}/role.
  Future<Map<String, dynamic>> updateUserRole(int userId, String role,
      {String? reason}) async {
    final headers = await _getHeaders();
    final response = await http
        .put(
          Uri.parse('$baseUrl/api/admin/users/$userId/role'),
          headers: headers,
          body: jsonEncode({
            'role': role,
            if (reason != null && reason.trim().isNotEmpty)
              'reason': reason.trim(),
          }),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    ErrorHandler.handleHttpError(response, context: 'Change role');
    throw ApiException('Failed to update user role');
  }

  Future<Map<String, dynamic>> denyUser(int userId, {String? adminNote}) async {
    final headers = await _getHeaders();
    final uri = Uri.parse('$baseUrl/api/admin/users/$userId/deny');
    final response = await http
        .post(
          adminNote != null
              ? uri.replace(queryParameters: {'admin_note': adminNote})
              : uri,
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      ErrorHandler.handleHttpError(response, context: 'Deny');
      throw ApiException('Failed to deny user');
    }
  }

  Future<Map<String, dynamic>> restoreUser(int userId) async {
    final headers = await _getHeaders();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/admin/users/$userId/restore'),
          headers: headers,
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      ErrorHandler.handleHttpError(response, context: 'Restore');
      throw ApiException('Failed to restore user');
    }
  }

  // ------------------------------------------------ search page (FE-SEARCH)

  /// Excel file of a search's saved leads (GET /api/jobs/{id}/download):
  /// `{filename, content (base64), content_type}`. Works for completed,
  /// cancelled and failed searches with at least one saved lead. Errors keep
  /// the server's own wording: [NotFoundException] ("No leads were saved for
  /// this search" / "Job not found") and an [ApiException] with status 409
  /// while the search is still running.
  Future<Map<String, dynamic>> downloadJobExcel(String jobId) async {
    final data = await _getJson(
      '/api/jobs/${Uri.encodeComponent(jobId)}/download',
      context: 'Download',
      requestTimeout: const Duration(seconds: 90),
    );
    if (data is! Map || data['content'] is! String) {
      throw ApiException('The download was empty. Please try again.');
    }
    return {
      'filename': '${data['filename'] ?? 'leads.xlsx'}',
      'content': data['content'],
      'content_type': data['content_type'] ??
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    };
  }

  /// Saved leads of one search (GET /api/jobs/{id}/results) with readable
  /// errors.
  Future<List<Map<String, dynamic>>> getJobLeads(String jobId) async {
    final data = await _getJson(
      '/api/jobs/${Uri.encodeComponent(jobId)}/results',
      context: 'Loading leads',
      requestTimeout: const Duration(seconds: 60),
    );
    final raw = data is Map ? data['results'] : data;
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ------------------------------------------------------------------
  // Admin console: visitors, analytics and revenue extras
  // ------------------------------------------------------------------

  Map<String, dynamic> _asMap(dynamic data) =>
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

  List<Map<String, dynamic>> _asRows(dynamic data, [String key = 'data']) {
    final raw = data is Map ? data[key] : data;
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Site visits (one row per browser session), newest first.
  Future<Map<String, dynamic>> getAdminVisitors({
    int days = 7,
    int limit = 50,
    int offset = 0,
    String? q,
    String? country,
    String? kind,
    String? source,
    bool live = false,
    int? userId,
  }) async {
    final query = <String, String>{
      if (live) 'live': 'true',
      if (userId != null) 'user_id': '$userId',
      'days': '$days',
      'limit': '$limit',
      'offset': '$offset',
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (country != null && country.isNotEmpty) 'country': country,
      if (kind != null && kind.isNotEmpty && kind != 'all') 'kind': kind,
      if (source != null && source.isNotEmpty) 'source': source,
    };
    return _asMap(await _getJson('/api/admin/visitors',
        query: query, context: 'Loading visitors'));
  }

  /// Country of this browser's network ("PK"), or null. Never throws: it
  /// only preselects the dial code on the sign-up form.
  Future<String?> getGeoHint() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/geo/hint'))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final c = data is Map ? data['country'] : null;
      return c is String && c.length == 2 ? c.toUpperCase() : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getAdminVisitorsSummary({int days = 7}) async =>
      _asMap(await _getJson('/api/admin/visitors/summary',
          query: {'days': '$days'}, context: 'Loading visitor summary'));

  Future<Map<String, dynamic>> getAdminVisit(String sessionId) async =>
      _asMap(await _getJson(
          '/api/admin/visitors/${Uri.encodeComponent(sessionId)}',
          context: 'Loading visit'));

  Future<List<Map<String, dynamic>>> getAnalyticsTopPages(
          {int days = 30, int limit = 12}) async =>
      _asRows(await _getJson('/api/admin/analytics/top-pages',
          query: {'days': '$days', 'limit': '$limit'},
          context: 'Loading top pages'));

  Future<List<Map<String, dynamic>>> getAnalyticsRetention(
          {int days = 60}) async =>
      _asRows(await _getJson('/api/admin/analytics/retention',
          query: {'days': '$days'}, context: 'Loading retention'));

  Future<List<Map<String, dynamic>>> getAnalyticsMau({int months = 12}) async =>
      _asRows(await _getJson('/api/admin/analytics/mau',
          query: {'months': '$months'}, context: 'Loading monthly users'));

  Future<List<Map<String, dynamic>>> getAnalyticsUserJourney(int userId,
          {int limit = 100}) async =>
      _asRows(
          await _getJson('/api/admin/analytics/user-journey/$userId',
              query: {'limit': '$limit'}, context: 'Loading user journey'),
          'events');

  /// Contact form (works signed in or out). Throws with the server's own
  /// reason when the message is refused.
  Future<void> sendContactMessage({
    required String name,
    required String email,
    required String message,
    String? phone,
    String? phoneCountry,
    String? topic,
    String? website,
    String? visitorId,
    String? geoCountry,
    String? geoCity,
    String? page,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/contact'),
            headers: await _getHeaders(),
            body: jsonEncode({
              'name': name,
              'email': email,
              'message': message,
              if (phone != null && phone.isNotEmpty) 'phone': phone,
              if (phone != null && phone.isNotEmpty && phoneCountry != null)
                'phone_country': phoneCountry,
              if (topic != null) 'topic': topic,
              if (website != null && website.isNotEmpty) 'website': website,
              if (visitorId != null) 'visitor_id': visitorId,
              if (geoCountry != null) 'geo_country': geoCountry,
              if (geoCity != null) 'geo_city': geoCity,
              if (page != null) 'page': page,
            }),
          )
          .timeout(timeout);
      if (response.statusCode == 200) return;
      ErrorHandler.handleHttpError(response, context: 'Sending your message');
      throw ApiException('Your message could not be sent. Please try again.');
    } on TimeoutException {
      throw NetworkException('Sending took too long. Please try again.');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  Future<Map<String, dynamic>> getAdminContactMessages({
    String? status,
    String? q,
    int limit = 50,
    int offset = 0,
  }) async =>
      _asMap(await _getJson('/api/admin/contact',
          query: {
            'limit': '$limit',
            'offset': '$offset',
            if (status != null && status.isNotEmpty) 'status': status,
            if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
          },
          context: 'Loading messages'));

  Future<Map<String, dynamic>> getAdminContactSummary() async => _asMap(
      await _getJson('/api/admin/contact/summary', context: 'Loading messages'));

  Future<Map<String, dynamic>> updateAdminContactMessage(int id,
      {String? status, String? adminNote}) async {
    final response = await http
        .put(
          Uri.parse('$baseUrl/api/admin/contact/$id'),
          headers: await _getHeaders(),
          body: jsonEncode({
            if (status != null) 'status': status,
            if (adminNote != null) 'admin_note': adminNote,
          }),
        )
        .timeout(timeout);
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    }
    ErrorHandler.handleHttpError(response, context: 'Updating the message');
    throw ApiException('The message could not be updated');
  }

  Future<Map<String, dynamic>> getAdminChurn() async => _asMap(
      await _getJson('/api/admin/analytics/churn', context: 'Loading churn'));
}
