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
          .where((e) => e is Map)
          .map((e) => Map<String, dynamic>.from(e as Map))
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

  // Authentication endpoints
  Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
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
  Future<Map<String, dynamic>> createScrapingJob({
    required String category,
    required List<String> citiesData,
    int maxResultsPerCity = 10,
  }) async {
    try {
      final headers = await _getHeaders();
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

  Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse('$baseUrl/api/jobs/$jobId'),
            headers: headers,
          )
          .timeout(timeout);

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
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/jobs'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['jobs']);
    } else {
      throw Exception('Failed to get jobs');
    }
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
    final response = await http.get(Uri.parse('$baseUrl/api/states'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        'USA': List<String>.from(data['USA'] ?? []),
        'UK': List<String>.from(data['UK'] ?? []),
        'UAE': List<String>.from(data['UAE'] ?? []),
        'KSA': List<String>.from(data['KSA'] ?? []),
        'Australia': List<String>.from(data['Australia'] ?? []),
      };
    } else {
      throw Exception('Failed to load states');
    }
  }

  Future<List<String>> getCities(String state) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/states/${Uri.encodeComponent(state)}/cities'),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<String>.from(data['cities'] ?? []);
    } else {
      throw Exception('Failed to load cities for $state');
    }
  }

  Future<List<String>> getCountries() async {
    final response = await http.get(Uri.parse('$baseUrl/api/countries'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<String>.from(data['countries'] ?? []);
    } else {
      throw Exception('Failed to load countries');
    }
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

  Future<void> deleteUser(int userId) async {
    final headers = await _getHeaders();
    final response = await http.delete(
      Uri.parse('$baseUrl/api/admin/users/$userId'),
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete user');
    }
  }

  // ==================== CREDIT ENDPOINTS ====================

  Future<Map<String, dynamic>> getCreditConfig() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/credits/config'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get credit config');
    }
  }

  Future<Map<String, dynamic>> getCreditBalance() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/credits/balance'),
      headers: headers,
    );

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

  Future<List<Map<String, dynamic>>> getCreditHistory() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/credits/history'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data['transactions']);
    } else if (response.statusCode == 404) {
      return [];
    } else {
      print(
          'getCreditHistory error: ${response.statusCode} - ${response.body}');
      throw Exception('Failed to get credit history: ${response.statusCode}');
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
      throw Exception('Failed to grant credits');
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
    int? displayPriceCents,
    bool? isActive,
  }) async {
    final headers = await _getHeaders();
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (credits != null) body['credits'] = credits;
    if (displayPriceCents != null)
      body['display_price_cents'] = displayPriceCents;
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
    if (minMonthlyCredits != null)
      body['min_monthly_credits'] = minMonthlyCredits;
    if (maxMonthlyCredits != null)
      body['max_monthly_credits'] = maxMonthlyCredits;
    if (pricePerCreditCents != null)
      body['price_per_credit_cents'] = pricePerCreditCents;
    if (discountPercentage != null)
      body['discount_percentage'] = discountPercentage;
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
    bool? isActive,
  }) async {
    final headers = await _getHeaders();
    final body = <String, dynamic>{};
    if (code != null) body['code'] = code;
    if (type != null) body['type'] = type;
    if (discountPercentage != null)
      body['discount_percentage'] = discountPercentage;
    if (discountAmountCents != null)
      body['discount_amount_cents'] = discountAmountCents;
    if (bonusCredits != null) body['bonus_credits'] = bonusCredits;
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

  Future<Map<String, dynamic>> validatePromoCode(String code) async {
    final headers = await _getHeaders();
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/promos/validate'),
          headers: headers,
          body: jsonEncode({'code': code}),
        )
        .timeout(timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
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
      throw Exception('Failed to deny user');
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
      throw Exception('Failed to restore user');
    }
  }
}
