import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

/// Environment configuration for API endpoints
/// Automatically detects localhost for development or uses production URL
class Environment {
  static const String _legacyRailwayApiUrl =
      'https://oz-production-2309.up.railway.app';
  static const String _productionApiFallback = 'https://server.progresslms.io';

  /// Get the appropriate API URL based on the environment
  static String get apiUrl {
    // Allow override via const environment variable (for build-time config)
    const envApiUrl = String.fromEnvironment('API_URL', defaultValue: '');
    final normalizedEnvApiUrl =
        envApiUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalizedEnvApiUrl.isNotEmpty &&
        normalizedEnvApiUrl != _legacyRailwayApiUrl) {
      return normalizedEnvApiUrl;
    }

    // Development fallback: point to local backend.
    // Override with --dart-define=API_URL=... when needed.
    if (!kReleaseMode) {
      return 'http://localhost:8001';
    }

    // Production web fallback: use the current frontend origin and let the host
    // rewrite /api to the active backend. This avoids stale compiled backend URLs
    // and browser CORS preflights for normal Vercel deployments.
    if (kIsWeb) {
      return '';
    }

    // Production mobile/desktop fallback: use deployed backend directly.
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
