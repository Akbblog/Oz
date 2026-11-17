import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Custom exception types for better error handling
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic details;

  ApiException(this.message, {this.statusCode, this.details});

  @override
  String toString() => message;
}

class NetworkException extends ApiException {
  NetworkException(super.message) : super(statusCode: 0);
}

class AuthenticationException extends ApiException {
  AuthenticationException(super.message) : super(statusCode: 401);
}

class AuthorizationException extends ApiException {
  AuthorizationException(super.message) : super(statusCode: 403);
}

class ValidationException extends ApiException {
  ValidationException(super.message, {super.details})
      : super(statusCode: 400);
}

class ServerException extends ApiException {
  ServerException(super.message) : super(statusCode: 500);
}

class NotFoundException extends ApiException {
  NotFoundException(super.message) : super(statusCode: 404);
}

class RateLimitException extends ApiException {
  RateLimitException(super.message) : super(statusCode: 429);
}

class InsufficientCreditsException extends ApiException {
  InsufficientCreditsException(super.message) : super(statusCode: 402);
}

/// Error handler utility class
class ErrorHandler {
  /// Readable text from a FastAPI error body.
  ///
  /// `detail` can be a string, a 422 validation list
  /// (`[{loc: [body, field], msg: ...}]`) or an object with a message. Raw
  /// JSON or HTML is never returned; null means "no usable message".
  static String? extractDetail(dynamic body) {
    if (body is! Map) return null;
    final detail = body['detail'] ?? body['message'] ?? body['error'];
    return _readable(detail);
  }

  static String? _readable(dynamic detail) {
    if (detail == null) return null;
    if (detail is String) {
      final text = detail.trim();
      return text.isEmpty ? null : text;
    }
    if (detail is List) {
      final parts = <String>[];
      for (final item in detail) {
        if (item is Map) {
          final msg = '${item['msg'] ?? item['message'] ?? ''}'.trim();
          if (msg.isEmpty) continue;
          final field = _fieldName(item['loc']);
          final sentence = _sentence(msg);
          parts.add(field == null ? sentence : '$field: ${_lowerFirst(sentence)}');
        } else if (item is String && item.trim().isNotEmpty) {
          parts.add(_sentence(item.trim()));
        }
      }
      return parts.isEmpty ? null : parts.join(' ');
    }
    if (detail is Map) {
      return _readable(detail['message'] ?? detail['detail'] ?? detail['msg']);
    }
    return null;
  }

  static String? _fieldName(dynamic loc) {
    if (loc is! List) return null;
    for (final part in loc.reversed) {
      if (part is! String) continue;
      if (const {'body', 'query', 'path', 'header'}.contains(part)) continue;
      final words = part.replaceAll('_', ' ').trim();
      if (words.isEmpty) continue;
      return words[0].toUpperCase() + words.substring(1);
    }
    return null;
  }

  static String _sentence(String text) {
    var out = text.trim();
    if (out.isEmpty) return out;
    out = out[0].toUpperCase() + out.substring(1);
    if (!out.endsWith('.') && !out.endsWith('!') && !out.endsWith('?')) {
      out = '$out.';
    }
    return out;
  }

  static String _lowerFirst(String text) =>
      text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);

  /// Parse HTTP response and throw appropriate exception
  static void handleHttpError(http.Response response, {String? context}) {
    final statusCode = response.statusCode;

    // The backend's own explanation (FastAPI `detail`) is shown as-is. Raw
    // bodies (HTML error pages from a proxy, JSON dumps) are never shown.
    String errorMessage = '';
    dynamic errorDetails;

    try {
      final body = jsonDecode(response.body);
      errorDetails = body;
      errorMessage = extractDetail(body) ?? '';
    } catch (e) {
      errorMessage = '';
    }

    if (errorMessage.isEmpty) {
      switch (statusCode) {
        case 401:
          errorMessage = 'Your session has expired. Please sign in again.';
          break;
        case 402:
          errorMessage = 'Not enough credits.';
          break;
        case 403:
          errorMessage = "You don't have permission to do this.";
          break;
        case 404:
          errorMessage = 'Not found.';
          break;
        case 429:
          errorMessage = 'Too many requests. Please try again later.';
          break;
        default:
          final what = (context != null && context.isNotEmpty)
              ? '$context failed'
              : 'The request failed';
          errorMessage = '$what (error $statusCode). Please try again.';
      }
    }

    // Throw appropriate exception based on status code
    switch (statusCode) {
      case 400:
        throw ValidationException(errorMessage, details: errorDetails);
      case 401:
        throw AuthenticationException(errorMessage);
      case 402:
        throw InsufficientCreditsException(
            errorMessage.isEmpty ? 'Insufficient credits' : errorMessage);
      case 403:
        throw AuthorizationException(
            errorMessage.isEmpty
                ? 'You don\'t have permission to perform this action'
                : errorMessage);
      case 404:
        throw NotFoundException(
            errorMessage.isEmpty ? 'Resource not found' : errorMessage);
      case 429:
        throw RateLimitException(
            errorMessage.isEmpty
                ? 'Too many requests. Please try again later'
                : errorMessage);
      case 500:
      case 502:
      case 503:
      case 504:
        throw ServerException(
            'Server error. Please try again later or contact support.');
      default:
        throw ApiException(errorMessage, statusCode: statusCode);
    }
  }

  /// Handle network/connection errors
  static Exception handleNetworkError(dynamic error) {
    if (error is SocketException) {
      return NetworkException(
          'Network error. Please check your internet connection and try again.');
    }

    if (error is http.ClientException) {
      return NetworkException(
          'Unable to connect to server. Please check your internet connection.');
    }

    if (error.toString().contains('TimeoutException')) {
      return NetworkException(
          'Request timed out. Please check your connection and try again.');
    }

    return NetworkException('Network error: ${error.toString()}');
  }

  /// Get user-friendly error message
  static String getUserFriendlyMessage(dynamic error) {
    if (error is ApiException) {
      return error.message;
    }

    if (error is SocketException) {
      return 'No internet connection. Please check your network settings.';
    }

    if (error is FormatException) {
      return 'Invalid data format received from server.';
    }

    if (error.toString().contains('TimeoutException')) {
      return 'Request timed out. Please try again.';
    }

    return 'An unexpected error occurred. Please try again.';
  }

  /// Check if error is network-related
  static bool isNetworkError(dynamic error) {
    return error is NetworkException ||
        error is SocketException ||
        error is http.ClientException ||
        error.toString().contains('TimeoutException');
  }

  /// Check if error is authentication-related
  static bool isAuthError(dynamic error) {
    return error is AuthenticationException ||
        (error is ApiException && error.statusCode == 401);
  }

  /// Check if error requires user to login again
  static bool requiresReauth(dynamic error) {
    return isAuthError(error);
  }
}
