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
  /// Parse HTTP response and throw appropriate exception
  static void handleHttpError(http.Response response, {String? context}) {
    final statusCode = response.statusCode;

    // Try to parse error message from response body
    String errorMessage = 'An error occurred';
    dynamic errorDetails;

    try {
      final body = jsonDecode(response.body);
      errorMessage = body['detail'] ?? body['message'] ?? errorMessage;
      errorDetails = body;
    } catch (e) {
      // If parsing fails, use response body as message
      errorMessage = response.body.isNotEmpty ? response.body : errorMessage;
    }

    // Add context if provided
    if (context != null && context.isNotEmpty) {
      errorMessage = '$context: $errorMessage';
    }

    // Throw appropriate exception based on status code
    switch (statusCode) {
      case 400:
        throw ValidationException(errorMessage, details: errorDetails);
      case 401:
        throw AuthenticationException(
            errorMessage.isEmpty ? 'Authentication failed. Please log in again.' : errorMessage);
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
