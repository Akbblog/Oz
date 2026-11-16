import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../core/error_handler.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  Map<String, dynamic>? _currentUser;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _errorMessage;

  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get isAdmin => _currentUser?['is_admin'] == true;
  String? get errorMessage => _errorMessage;

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  AuthProvider() {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    _isLoading = true;
    notifyListeners();
    
    final token = await _apiService.getToken();
    if (token != null) {
      // Retry transient failures: a flaky network on page refresh must not
      // sign the user out. Only a definitive auth rejection clears the token.
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          _currentUser = await _apiService.getCurrentUser();
          _isAuthenticated = true;
          break;
        } catch (e) {
          if (ErrorHandler.isAuthError(e) || e is AuthorizationException) {
            _isAuthenticated = false;
            _currentUser = null;
            await _apiService.clearToken();
            break;
          }
          if (attempt == 2) {
            _isAuthenticated = false;
            _currentUser = null;
            _errorMessage =
                'Could not reach the server. Check your connection and reload.';
          } else {
            await Future<void>.delayed(Duration(seconds: 1 << attempt));
          }
        }
      }
    }
    
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String username, String password, {bool rememberMe = true}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiService.login(
        username: username,
        password: password,
        rememberMe: rememberMe,
      );
      _currentUser = response['user'];
      _isAuthenticated = true;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<String?> register(
    String username,
    String email,
    String password,
    String phone,
  ) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await _apiService.register(
        username: username,
        email: email,
        password: password,
        phone: phone,
      );
      _isLoading = false;
      notifyListeners();
      return response['message']?.toString();
    } catch (e) {
      _errorMessage = ErrorHandler.getUserFriendlyMessage(e);
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> logout() async {
    await _apiService.logout();
    _currentUser = null;
    _isAuthenticated = false;
    notifyListeners();
  }
}
