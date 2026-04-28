import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

/// Environment configuration for API endpoints
/// Automatically detects localhost for development or uses production URL
class Environment {
  static const String _productionApiFallback =
      'https://server.dev.progresslms.io';

  /// Get the appropriate API URL based on the environment
  static String get apiUrl {
    // Allow override via const environment variable (for build-time config)
    const envApiUrl = String.fromEnvironment('API_URL', defaultValue: '');
    if (envApiUrl.isNotEmpty) {
      return envApiUrl;
    }

    // Development fallback: point to local backend.
    // Override with --dart-define=API_URL=... when needed.
    if (!kReleaseMode) {
      return 'http://localhost:8001';
    }

    // Production web fallback: call Railway directly when no build-time API_URL
    // was provided, avoiding 404s from missing host rewrites.
    if (kIsWeb) {
      return _productionApiFallback;
    }

    // Production mobile/desktop fallback: use deployed Railway backend.
    return _productionApiFallback;
  }

  /// Check if we're in production mode
  static bool get isProduction => kReleaseMode;

  /// Check if we're in development mode
  static bool get isDevelopment => !kReleaseMode;

  /// Get environment name for debugging
  static String get environmentName =>
      isProduction ? 'Production' : 'Development';
}
