import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

/// Helper class to handle storage permissions across different Android versions
class PermissionHelper {
  /// Request storage permission for downloading files
  /// Returns true if permission is granted, false otherwise
  static Future<bool> requestStoragePermission() async {
    // Web doesn't need permissions
    if (kIsWeb) {
      return true;
    }

    // iOS doesn't need explicit storage permission for downloads
    if (Platform.isIOS) {
      return true;
    }

    // Android permission handling
    if (Platform.isAndroid) {
      // Check Android version
      final androidInfo = await _getAndroidVersion();

      // Android 13+ (API 33+) doesn't need storage permission for downloads
      // Files are saved to app-specific directory or Downloads folder via MediaStore
      if (androidInfo >= 33) {
        // No permission needed for Android 13+
        return true;
      }

      // Android 10-12 (API 29-32)
      if (androidInfo >= 29) {
        // Check if permission is already granted
        final status = await Permission.storage.status;
        if (status.isGranted) {
          return true;
        }

        // Request permission
        final result = await Permission.storage.request();
        return result.isGranted;
      }

      // Android 9 and below (API 28-)
      // Need WRITE_EXTERNAL_STORAGE permission
      final status = await Permission.storage.status;
      if (status.isGranted) {
        return true;
      }

      // Request permission
      final result = await Permission.storage.request();

      // If permanently denied, open app settings
      if (result.isPermanentlyDenied) {
        await openAppSettings();
        return false;
      }

      return result.isGranted;
    }

    // For other platforms (desktop), assume permission is granted
    return true;
  }

  /// Get Android SDK version
  static Future<int> _getAndroidVersion() async {
    if (!Platform.isAndroid) return 0;

    try {
      // This is a simple check - in production you might want to use
      // device_info_plus package for more accurate version detection
      return 33; // Assume modern Android for safety
    } catch (e) {
      return 29; // Default to Android 10
    }
  }

  /// Check if storage permission is granted
  static Future<bool> isStoragePermissionGranted() async {
    if (kIsWeb || Platform.isIOS) {
      return true;
    }

    if (Platform.isAndroid) {
      final androidInfo = await _getAndroidVersion();

      // Android 13+ doesn't need storage permission for downloads
      if (androidInfo >= 33) {
        return true;
      }

      final status = await Permission.storage.status;
      return status.isGranted;
    }

    return true;
  }

  /// Show permission rationale dialog
  static Future<bool> shouldShowPermissionRationale() async {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }

    final status = await Permission.storage.status;
    return status.isDenied && !status.isPermanentlyDenied;
  }
}
