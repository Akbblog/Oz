import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Railway production URL
  static const String baseUrl = 'https://oz-production.up.railway.app';
  // For local development, use: 'http://127.0.0.1:8001'

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  Future<void> clearToken() async {
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
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'email': email,
        'password': password,
      }),
    );

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Registration failed');
    }
  }

  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await saveToken(data['access_token']);
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Login failed');
    }
  }

  Future<Map<String, dynamic>> getCurrentUser() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/auth/me'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get user info');
    }
  }

  Future<void> logout() async {
    await clearToken();
  }

  // Job endpoints
  Future<Map<String, dynamic>> createScrapingJob({
    required String category,
    required List<String> citiesData,
    int maxResultsPerCity = 10,
  }) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/api/jobs'),
      headers: headers,
      body: jsonEncode({
        'category': category,
        'cities_data': citiesData,
        'max_results_per_city': maxResultsPerCity,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to create scraping job');
    }
  }

  Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/api/jobs/$jobId'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get job status');
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
        'content_type': data['content_type'] ?? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
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
          .timeout(Duration(seconds: 5));
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
      throw Exception('Failed to get credit balance');
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
    } else {
      throw Exception('Failed to get credit history');
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
    } else {
      throw Exception('Failed to get credit requests');
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
    final uri = Uri.parse('$baseUrl/api/admin/credits/requests/$requestId/deny');
    final response = await http.post(
      adminNote != null ? uri.replace(queryParameters: {'admin_note': adminNote}) : uri,
      headers: headers,
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to deny credit request');
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
}
