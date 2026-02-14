import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

/// Environment configuration for API endpoints
/// Automatically detects localhost for development or uses production URL
class Environment {
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

    // Production web: use same-origin so hosting rewrites/proxy can route /api.
    if (kIsWeb) {
      return '';
    }

    // Production mobile/desktop fallback: use deployed Railway backend.
    return 'https://oz-production.up.railway.app';
  }

  /// Check if we're in production mode
  static bool get isProduction => kReleaseMode;

  /// Check if we're in development mode
  static bool get isDevelopment => !kReleaseMode;

  /// Get environment name for debugging
  static String get environmentName =>
      isProduction ? 'Production' : 'Development';
}
