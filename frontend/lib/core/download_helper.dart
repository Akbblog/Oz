import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:universal_html/html.dart' as html;

import 'permission_helper.dart';

// ------------------------------------------------------------------ CSV

/// Leading characters a spreadsheet reads as the start of a formula.
const List<String> _formulaPrefixes = ['=', '+', '-', '@', '\t', '\r'];

/// One CSV cell (RFC 4180) with formula-injection protection.
///
/// * A value starting with `= + - @`, TAB or CR is prefixed with `'` so a
///   spreadsheet shows it as text instead of evaluating it (scraped business
///   names such as `=HYPERLINK(...)` are untrusted).
/// * A value containing a double quote, comma, CR or LF is wrapped in double
///   quotes and its quotes are doubled.
String csvCell(Object? value) {
  var s = value == null ? '' : '$value';
  if (s.isNotEmpty && _formulaPrefixes.any(s.startsWith)) {
    s = "'$s";
  }
  final needsQuotes =
      s.contains('"') || s.contains(',') || s.contains('\n') || s.contains('\r');
  if (!needsQuotes) return s;
  return '"${s.replaceAll('"', '""')}"';
}

/// Columns of a lead export (same order as before).
const List<String> leadCsvColumns = [
  'business_name',
  'category',
  'city',
  'state',
  'phone',
  'email',
  'website',
  'address',
  'google_maps_url',
];

/// Leads as CSV text: a header plus one line per lead, CRLF line ends
/// (RFC 4180). [saveCsv] adds the UTF-8 BOM.
String leadsToCsv(
  Iterable<Map<String, dynamic>> rows, {
  List<String> columns = leadCsvColumns,
}) {
  final buffer = StringBuffer();
  buffer.write(columns.map(csvCell).join(','));
  buffer.write('\r\n');
  for (final row in rows) {
    buffer.write(columns.map((c) {
      final v = row[c] ?? (c == 'business_name' ? row['name'] : null);
      return csvCell(v);
    }).join(','));
    buffer.write('\r\n');
  }
  return buffer.toString();
}

// ------------------------------------------------------------ web saving

/// How long the browser keeps a download's object URL alive. Revoking it
/// right after `click()` (the old behaviour) can cut the download short on
/// some browsers (notably Chrome on Android), leaving a truncated,
/// "corrupted" file.
const Duration downloadRevokeDelay = Duration(seconds: 30);

/// Revokes [url] after [delay]. Separate so it can be tested without a
/// browser.
@visibleForTesting
Timer scheduleObjectUrlRevoke(
  String url, {
  void Function(String url)? revoke,
  Duration delay = downloadRevokeDelay,
}) {
  return Timer(delay, () {
    try {
      (revoke ?? html.Url.revokeObjectUrl)(url);
    } catch (_) {}
  });
}

/// Web download: the anchor is attached to the document, clicked, removed,
/// and the object URL is revoked later ([downloadRevokeDelay]).
void _webDownload(List<int> bytes, String mimeType, String filename) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  scheduleObjectUrlRevoke(url);
}

Future<bool> _saveBytes({
  required Uint8List bytes,
  required String webMimeType,
  required MimeType nativeMimeType,
  required String filename,
  BuildContext? context,
}) async {
  if (kIsWeb) {
    try {
      _webDownload(bytes, webMimeType, filename);
      if (context != null && context.mounted) {
        _showSuccessMessage(context, filename, null);
      }
      return true;
    } catch (e) {
      debugPrint('Error downloading file on web: $e');
      if (context != null && context.mounted) {
        _showErrorMessage(context, 'the download could not be started.');
      }
      return false;
    }
  }

  final hasPermission = await PermissionHelper.requestStoragePermission();
  if (!hasPermission) {
    if (context != null && context.mounted) {
      _showPermissionDeniedDialog(context);
    }
    return false;
  }

  try {
    final savedPath = await FileSaver.instance.saveFile(
      name: filename,
      bytes: bytes,
      mimeType: nativeMimeType,
    );
    if (_isBadPath(savedPath)) {
      throw Exception('Save path invalid');
    }
    if (context != null && context.mounted) {
      _showSuccessMessage(context, filename, savedPath);
    }
    return true;
  } catch (e) {
    debugPrint('Error saving file: $e');
    if (context != null && context.mounted) {
      _showErrorMessage(context, e.toString());
    }
    return false;
  }
}

/// Cross-platform Excel (.xlsx) download of base64 content from the API.
/// Browser download on web, file_saver on native platforms.
Future<bool> saveExcel(
  String base64Content,
  String filename, {
  BuildContext? context,
}) async {
  final bytes = base64Decode(base64Content);
  return _saveBytes(
    bytes: Uint8List.fromList(bytes),
    webMimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    nativeMimeType: MimeType.microsoftExcel,
    filename: filename,
    context: context,
  );
}

/// CSV download. A UTF-8 BOM is added so spreadsheet apps (Excel, Google
/// Sheets on Android) read accents correctly. Build the text with
/// [leadsToCsv] / [csvCell].
Future<bool> saveCsv(
  String content,
  String fileNameBase, {
  BuildContext? context,
}) async {
  final encoded = utf8.encode(content);
  final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...encoded]);
  return _saveBytes(
    bytes: bytes,
    webMimeType: 'text/csv;charset=utf-8',
    nativeMimeType: MimeType.csv,
    filename: '$fileNameBase.csv',
    context: context,
  );
}

/// JSON download.
Future<bool> saveJson(
  String content,
  String fileNameBase, {
  BuildContext? context,
}) async {
  return _saveBytes(
    bytes: Uint8List.fromList(utf8.encode(content)),
    webMimeType: 'application/json;charset=utf-8',
    nativeMimeType: MimeType.json,
    filename: '$fileNameBase.json',
    context: context,
  );
}

/// Plain-text download (e.g. a search's technical log).
Future<bool> saveTextFile(
  String content,
  String fileNameBase, {
  BuildContext? context,
}) async {
  return _saveBytes(
    bytes: Uint8List.fromList(utf8.encode(content)),
    webMimeType: 'text/plain;charset=utf-8',
    nativeMimeType: MimeType.text,
    filename: '$fileNameBase.txt',
    context: context,
  );
}

/// A safe file-name part ("plumbers / heating" -> "plumbers_heating").
String safeFileNamePart(String value, {int maxLength = 40}) {
  final cleaned = value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (cleaned.isEmpty) return 'search';
  return cleaned.length > maxLength ? cleaned.substring(0, maxLength) : cleaned;
}

/// A file-name timestamp in local time ("2026-11-17_1304").
String fileTimestamp([DateTime? at]) {
  final t = (at ?? DateTime.now()).toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)}_${two(t.hour)}${two(t.minute)}';
}

bool _isBadPath(String path) {
  return path.isEmpty || path.contains('Something went wrong');
}

/// Permission denied dialog with an option to ask again.
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

void _showSuccessMessage(
  BuildContext context,
  String fileName,
  String? path,
) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
      backgroundColor: Colors.green.shade800,
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

void _showErrorMessage(BuildContext context, String error) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
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
      backgroundColor: Colors.red.shade800,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
    ),
  );
}
