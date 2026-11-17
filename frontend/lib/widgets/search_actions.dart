import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/download_helper.dart';
import '../core/error_handler.dart';
import '../services/api_service.dart';
import 'app_shell_common.dart';

// Shared copy and actions of the search page and My searches (plan §6.5–6.7).
// Every number comes from API fields; nothing is estimated.

// ------------------------------------------------------------------ copy

/// Refund line of a finished search (brief "Refund line"):
/// * settled: "70 credits charged, 23 returned — 47 used." or, without a
///   refund, "70 credits used."
/// * not settled yet: "70 credits charged · calculating refund…"
String searchRefundLine({
  required int charged,
  required int refunded,
  required bool settled,
}) {
  if (!settled) return '${formatCount(charged)} credits charged · calculating refund…';
  if (refunded <= 0) return '${formatCount(charged)} credits used.';
  final used = charged - refunded;
  return '${formatCount(charged)} credits charged, ${formatCount(refunded)} returned — '
      '${formatCount(used < 0 ? 0 : used)} used.';
}

/// Credits line while a search runs: "70 credits charged at start." plus the
/// configured refund policy sentence (omitted when the policy is unknown).
String searchRunningCreditsLine(int charged, String? policySentence) {
  final first = '${formatCount(charged)} credits charged at start.';
  if (policySentence == null || policySentence.trim().isEmpty) return first;
  return '$first ${policySentence.trim()}';
}

/// Raw failure text -> plain words (without a final period).
String plainFailureReason(String? error) {
  final raw = (error ?? '').trim();
  if (raw.isEmpty) return 'something went wrong on our side';
  final l = raw.toLowerCase();
  if (l.contains('every city timed out')) {
    return "Google Maps didn't respond for any of the cities";
  }
  if (l.contains('interrupted too many times')) {
    return 'our search server was interrupted too many times';
  }
  if (l.contains('exceeded maximum allowed duration')) {
    return 'it ran longer than the maximum time allowed';
  }
  if (l.contains('no longer exists')) {
    return 'it no longer exists (it may have been deleted)';
  }
  if (l.contains('timed out') || l.contains('timeout')) {
    return "Google Maps didn't respond in time";
  }
  // Python exception text ("RuntimeError: ...") is not for users.
  if (RegExp(r'^[A-Za-z_]+(Error|Exception)\b').hasMatch(raw)) {
    return 'an unexpected error on our side';
  }
  var text = raw;
  while (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return text.isEmpty ? 'something went wrong on our side' : text;
}

/// True when [plainFailureReason] reworded the raw text (then the raw text
/// is offered under "Details").
bool failureReasonWasReworded(String? error) {
  final raw = (error ?? '').trim();
  if (raw.isEmpty) return false;
  var stripped = raw;
  while (stripped.endsWith('.')) {
    stripped = stripped.substring(0, stripped.length - 1);
  }
  return plainFailureReason(raw) != stripped;
}

/// The headline of a finished search (brief status copy), from API fields.
/// "Completed with no leads" reads differently from a useful search, and a
/// cancelled/failed search says how many leads it kept.
String finishedSearchHeadline(Map<String, dynamic> job) {
  final leads = jobInt(job, 'result_count');
  final total = jobInt(job, 'total_cities');
  final c = CitySummary.of(job);
  switch ('${job['status']}') {
    case 'completed':
      if (leads == 0) {
        return 'This search finished, but no leads were found in '
            '${total == 1 ? 'the city' : 'any of the ${formatCount(total)} cities'} searched.';
      }
      if (c != null && c.withLeads > 0 && c.withLeads < total) {
        return '${plural(leads, 'lead', 'leads')} found in '
            '${formatCount(c.withLeads)} of ${plural(total, 'city', 'cities')}.';
      }
      return '${plural(leads, 'lead', 'leads')} from ${plural(total, 'city', 'cities')}.';
    case 'cancelled':
      return leads > 0
          ? 'You cancelled this search. ${plural(leads, 'lead was', 'leads were')} saved.'
          : 'You cancelled this search before any leads were saved.';
    case 'failed':
      final reason = plainFailureReason(job['error'] as String?);
      if (leads > 0) {
        return 'This search stopped early: $reason. '
            '${plural(leads, 'lead was', 'leads were')} saved.';
      }
      return "This search couldn't finish: $reason.";
    default:
      return '';
  }
}

/// Status badge of the search page: [searchStatusOf] plus "Stopping…" while
/// a cancel request is being processed. ([zeroCities] is accepted for
/// compatibility; per-city facts now come from `city_summary`.)
SearchStatusInfo searchPageStatus(
  Map<String, dynamic> job, {
  int zeroCities = 0,
  bool stopping = false,
}) {
  final status = '${job['status']}';
  if (stopping && (status == 'running' || status == 'pending')) {
    return const SearchStatusInfo(SearchStatusKind.searching, 'Stopping…',
        UiTokens.searchingFg, UiTokens.searchingBg, Icons.hourglass_bottom_rounded);
  }
  return searchStatusOf(job);
}

/// "took 32 s", "took 4 min 05 s", "took 1 h 12 min".
String formatTookDuration(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  if (s < 60) return '$s s';
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (h > 0) return '$h h ${m.toString().padLeft(2, '0')} min';
  return '$m min ${sec.toString().padLeft(2, '0')} s';
}

/// Lead count per "City, Region" from loaded leads.
Map<String, int> leadCountsByCity(Iterable<Map<String, dynamic>> results) {
  final counts = <String, int>{};
  for (final r in results) {
    final city = '${r['city'] ?? ''}'.trim();
    if (city.isEmpty || city == 'N/A') continue;
    final state = '${r['state'] ?? ''}'.trim();
    final key = state.isEmpty ? city : '$city, $state';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

String _normCity(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s*,\s*'), ',').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Leads found for one requested city ("Montreal, Quebec") given
/// [leadCountsByCity]. Matches case/spacing-insensitively, then by city name
/// alone when that name is unique.
int leadsForCity(String requested, Map<String, int> counts) {
  final exact = counts[requested];
  if (exact != null) return exact;
  final want = _normCity(requested);
  for (final e in counts.entries) {
    if (_normCity(e.key) == want) return e.value;
  }
  final name = _normCity(requested.split(',').first);
  final byName = counts.entries.where((e) => _normCity(e.key.split(',').first) == name).toList();
  if (byName.length == 1) return byName.first.value;
  return 0;
}

/// Full URL of a search page (for "Copy link").
String searchPageUrl(String jobId) {
  final path = '/searches/${Uri.encodeComponent(jobId)}';
  final base = Uri.base;
  if (base.scheme == 'http' || base.scheme == 'https') {
    return '${base.origin}$path';
  }
  return path;
}

// ---------------------------------------------------------------- styles

ButtonStyle searchPrimaryButtonStyle() => FilledButton.styleFrom(
      backgroundColor: UiTokens.primary,
      foregroundColor: Colors.white,
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

ButtonStyle searchSecondaryButtonStyle() => OutlinedButton.styleFrom(
      foregroundColor: UiTokens.text,
      side: const BorderSide(color: UiTokens.border),
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

ButtonStyle searchDangerTextButtonStyle() => TextButton.styleFrom(
      foregroundColor: UiTokens.failedFg,
      minimumSize: const Size(44, 44),
      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    );

/// Card surface of the redesign (#242427 on #171717).
class SearchCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SearchCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: UiTokens.card,
        borderRadius: BorderRadius.circular(UiTokens.radius),
        border: Border.all(color: UiTokens.border),
      ),
      child: child,
    );
  }
}

/// Amber notice with an optional action (reconnecting, signed out, …).
class SearchNotice extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String? body;
  final Widget? action;

  const SearchNotice({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.color = UiTokens.partialFg,
    this.background = UiTokens.partialBg,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(UiTokens.radius),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (body != null) TextSpan(text: ' $body'),
                    ]),
                    style: const TextStyle(color: UiTokens.text, fontSize: 14, height: 1.35),
                  ),
                ),
              ],
            ),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- actions

void showSearchSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? const Color(0xFF8C2F2A) : const Color(0xFF2A2E33),
    ),
  );
}

/// Copies [text] and confirms with a "Copied" snackbar.
Future<void> copyWithSnack(BuildContext context, String text, {String message = 'Copied'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSearchSnack(context, message);
}

/// Readable message for a failed Excel download.
String downloadErrorMessage(Object error) {
  if (error is NotFoundException) {
    final m = error.message.trim();
    if (m.toLowerCase().contains('no leads')) return 'No leads were saved for this search, so there is nothing to download.';
    return 'This search no longer exists.';
  }
  if (error is ApiException && error.statusCode == 409) {
    return 'This search is still running. The download is available when it ends.';
  }
  if (ErrorHandler.isAuthError(error)) {
    return "You've been signed out. Sign in again to download.";
  }
  if (ErrorHandler.isNetworkError(error)) {
    return "We couldn't reach the server. Check your connection and try again.";
  }
  return "The download didn't work: ${ErrorHandler.getUserFriendlyMessage(error)}";
}

/// Downloads a search's saved leads as Excel (also for cancelled/failed
/// searches with saved leads). Shows a readable message on failure.
Future<bool> downloadSearchExcel(BuildContext context, ApiService api, String jobId) async {
  try {
    final data = await api.downloadJobExcel(jobId);
    if (!context.mounted) return false;
    final content = '${data['content'] ?? ''}';
    if (content.isEmpty) {
      showSearchSnack(context, 'The download was empty. Please try again.', error: true);
      return false;
    }
    return await saveExcel(content, '${data['filename']}', context: context);
  } catch (e) {
    if (context.mounted) showSearchSnack(context, downloadErrorMessage(e), error: true);
    return false;
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String keepLabel,
  required String confirmLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: UiTokens.card,
      title: Text(title, style: const TextStyle(color: UiTokens.text)),
      content: Text(body, style: const TextStyle(color: UiTokens.textSecondary, height: 1.4)),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(44, 44)),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(keepLabel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: UiTokens.failedFg,
            foregroundColor: Colors.black,
            minimumSize: const Size(44, 44),
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// "Cancel this search?" (plan §6.5).
Future<bool> confirmCancelSearch(BuildContext context) => _confirm(
      context,
      title: 'Cancel this search?',
      body: 'It stops after the current business. Leads found so far are kept.',
      keepLabel: 'Keep searching',
      confirmLabel: 'Cancel search',
    );

/// "Delete this search and its N leads?" (plan §6.7).
Future<bool> confirmDeleteSearch(BuildContext context, int leads) => _confirm(
      context,
      title: 'Delete search?',
      body: "Delete this search and its ${plural(leads, 'lead', 'leads')}? This can't be undone.",
      keepLabel: 'Keep',
      confirmLabel: 'Delete',
    );
