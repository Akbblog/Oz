import 'dart:convert';
import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:universal_html/html.dart' as html;
import 'permission_helper.dart';

/// Cross-platform Excel (.xlsx) file download helper.
/// Uses browser download API on web, file_saver on native platforms.
/// Handles permissions automatically on Android.
Future<bool> saveExcel(
  String base64Content,
  String filename, {
  BuildContext? context,
}) async {
  // Decode base64 content to bytes
  final bytes = base64Decode(base64Content);

  if (kIsWeb) {
    // Web: trigger browser download
    try {
      final blob = html.Blob(
        [bytes],
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..click();
      html.Url.revokeObjectUrl(url);
      if (context != null && context.mounted) {
        _showSuccessMessage(context, filename, null);
      }
      return true;
    } catch (e) {
      debugPrint('Error downloading file on web: $e');
      return false;
    }
  } else {
    // Native platforms: request permission first
    final hasPermission = await PermissionHelper.requestStoragePermission();

    if (!hasPermission) {
      // Show error message if context is provided
      if (context != null && context.mounted) {
        _showPermissionDeniedDialog(context);
      }
      return false;
    }

    try {
      // Save file using file_saver
      final savedPath = await FileSaver.instance.saveFile(
        name: filename,
        bytes: Uint8List.fromList(bytes),
        mimeType: MimeType.microsoftExcel,
      );

      if (_isBadPath(savedPath)) {
        throw Exception('Save path invalid');
      }

      // Show success message if context is provided
      if (context != null && context.mounted) {
        _showSuccessMessage(context, filename, savedPath);
      }

      return true;
    } catch (e) {
      debugPrint('Error saving file: $e');

      // Show error message if context is provided
      if (context != null && context.mounted) {
        _showErrorMessage(context, e.toString());
      }

      return false;
    }
  }
}

/// Legacy CSV download support (for backward compatibility)
Future<bool> saveCsv(
  String content,
  String fileNameBase, {
  BuildContext? context,
}) async {
  // Add UTF-8 BOM to improve compatibility with mobile spreadsheet apps.
  final encoded = utf8.encode(content);
  final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...encoded]);

  if (kIsWeb) {
    // Web: trigger browser download
    try {
      final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', '$fileNameBase.csv')
        ..click();
      html.Url.revokeObjectUrl(url);
      if (context != null && context.mounted) {
        _showSuccessMessage(context, fileNameBase, null);
      }
      return true;
    } catch (e) {
      debugPrint('Error downloading file on web: $e');
      return false;
    }
  } else {
    // Native platforms: request permission first
    final hasPermission = await PermissionHelper.requestStoragePermission();

    if (!hasPermission) {
      // Show error message if context is provided
      if (context != null && context.mounted) {
        _showPermissionDeniedDialog(context);
      }
      return false;
    }

    try {
      // Save file using file_saver
      final savedPath = await FileSaver.instance.saveFile(
        name: '$fileNameBase.csv',
        bytes: bytes,
        mimeType: MimeType.csv,
      );

      if (_isBadPath(savedPath)) {
        throw Exception('Save path invalid');
      }

      // Show success message if context is provided
      if (context != null && context.mounted) {
        _showSuccessMessage(context, fileNameBase, savedPath);
      }

      return true;
    } catch (e) {
      debugPrint('Error saving file: $e');

      // Show error message if context is provided
      if (context != null && context.mounted) {
        _showErrorMessage(context, e.toString());
      }

      return false;
    }
  }
}

/// JSON download support.
Future<bool> saveJson(
  String content,
  String fileNameBase, {
  BuildContext? context,
}) async {
  final bytes = Uint8List.fromList(utf8.encode(content));

  if (kIsWeb) {
    try {
      final blob = html.Blob([bytes], 'application/json;charset=utf-8;');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download', '$fileNameBase.json')
        ..click();
      html.Url.revokeObjectUrl(url);
      if (context != null && context.mounted) {
        _showSuccessMessage(context, fileNameBase, null);
      }
      return true;
    } catch (e) {
      debugPrint('Error downloading JSON on web: $e');
      return false;
    }
  } else {
    final hasPermission = await PermissionHelper.requestStoragePermission();
    if (!hasPermission) {
      if (context != null && context.mounted) {
        _showPermissionDeniedDialog(context);
      }
      return false;
    }

    try {
      final savedPath = await FileSaver.instance.saveFile(
        name: '$fileNameBase.json',
        bytes: bytes,
        mimeType: MimeType.json,
      );

      if (_isBadPath(savedPath)) {
        throw Exception('Save path invalid');
      }

      if (context != null && context.mounted) {
        _showSuccessMessage(context, fileNameBase, savedPath);
      }

      return true;
    } catch (e) {
      debugPrint('Error saving JSON file: $e');
      if (context != null && context.mounted) {
        _showErrorMessage(context, e.toString());
      }
      return false;
    }
  }
}

bool _isBadPath(String path) {
  return path.isEmpty || path.contains('Something went wrong');
}

/// Show permission denied dialog with option to open settings
void _showPermissionDeniedDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange.shade700,
          ),
          const SizedBox(width: 12),
          const Text('Permission Required'),
        ],
      ),
      content: const Text(
        'Storage permission is required to download files. '
        'Please grant the permission in app settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(context);
            await PermissionHelper.requestStoragePermission();
          },
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
}

/// Show success message
void _showSuccessMessage(
  BuildContext context,
  String fileName,
  String? path,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              path == null
                  ? 'Download started: $fileName'
                  : 'Saved: $fileName\n$path',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      backgroundColor: Colors.green.shade600,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      action: path == null
          ? null
          : SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () async {
                await OpenFilex.open(path);
              },
            ),
    ),
  );
}

/// Show error message
void _showErrorMessage(BuildContext context, String error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Error saving file: $error'),
          ),
        ],
      ),
      backgroundColor: Colors.red.shade600,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ),
  );
}
