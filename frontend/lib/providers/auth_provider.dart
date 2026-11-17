import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../core/error_handler.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  Map<String, dynamic>? _currentUser;
  bool _isAuthenticated = false;
  bool _isLoading = false;
  bool _isRestoring = true;
  String? _errorMessage;

  /// Draft keys removed on every sign-out (also cleared by
  /// SearchSetupProvider through its sign-out hook).
  static const List<String> signOutPrefKeys = <String>[
    'wizard_location_draft_v1',
    'wizard_search_draft_v1',
    'active_job_id_v1',
  ];

  final List<Future<void> Function()> _signOutHooks = <Future<void> Function()>[];
  int _sessionGeneration = 0;

  /// Incremented on every successful sign-in (including the initial session
  /// restore), so listeners can resume work after a re-login even when
  /// [isAuthenticated] did not change (expired token, same tab).
  int get sessionGeneration => _sessionGeneration;

  /// Registers work to run on every sign-out (clear drafts, stop polling...).
  /// Returns a function that unregisters it.
  VoidCallback addSignOutHook(Future<void> Function() hook) {
    _signOutHooks.add(hook);
    return () => _signOutHooks.remove(hook);
  }

  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;

  /// True until the saved session has been checked on app start (deep links
  /// wait for this before deciding between the page and sign-in).
  bool get isRestoring => _isRestoring;
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
          _sessionGeneration++;
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
    _isRestoring = false;
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
      _sessionGeneration++;
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

  /// Signs out on every path (avatar menu, Account page, admin screens):
  /// clears the token, the search drafts and the remembered job, then runs
  /// the registered sign-out hooks (providers reset their state).
  Future<void> logout() async {
    await _apiService.logout();
    _currentUser = null;
    _isAuthenticated = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in signOutPrefKeys) {
        await prefs.remove(key);
      }
    } catch (_) {}
    for (final hook in List<Future<void> Function()>.of(_signOutHooks)) {
      try {
        await hook();
      } catch (e) {
        debugPrint('Sign-out hook failed: $e');
      }
    }
    notifyListeners();
  }
}
