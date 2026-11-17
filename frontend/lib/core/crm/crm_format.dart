import 'package:flutter/material.dart';

import '../../widgets/app_shell_common.dart';
import '../utils/server_time.dart';

// Display helpers of the CRM screens. Values come from the API only; a
// missing value stays blank ("Not set"), nothing is estimated.

String crmStr(Object? v) {
  final s = '${v ?? ''}'.trim();
  return s == 'null' ? '' : s;
}

Map<String, dynamic> crmMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> crmList(Object? v) =>
    v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

int crmInt(Object? v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  return int.tryParse(crmStr(v)) ?? fallback;
}

int? crmIntOrNull(Object? v) {
  if (v is num) return v.toInt();
  return int.tryParse(crmStr(v));
}

num? crmNum(Object? v) {
  if (v is num) return v;
  final s = crmStr(v);
  return s.isEmpty ? null : num.tryParse(s);
}

/// 1250.5 → "1,250.50".
String crmAmount(num value, {int decimals = 2}) {
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final whole = formatCount(int.parse(parts[0]));
  final out = parts.length > 1 && decimals > 0 ? '$whole.${parts[1]}' : whole;
  return negative ? '-$out' : out;
}

/// "CAD 1,250.00" (ISO code first, never a converted or merged total).
String crmMoney(Object? value, Object? currency) {
  final v = crmNum(value);
  if (v == null) return '';
  final c = crmStr(currency).toUpperCase();
  return c.isEmpty ? crmAmount(v) : '$c ${crmAmount(v)}';
}

/// Per-currency totals of a pipeline column: "CAD 1,200.00 · USD 300.00".
String crmCurrencyTotals(Object? values) {
  final parts = <String>[];
  for (final v in crmList(values)) {
    final total = crmNum(v['total']);
    if (total == null || total == 0) continue;
    parts.add(crmMoney(total, v['currency']));
  }
  return parts.join(' · ');
}

/// Readable record type.
String crmTypeName(Object? type) => crmStr(type) == 'opportunity' ? 'Opportunity' : 'Lead';

/// Outcome badge: icon + word, never colour alone.
({String label, IconData icon, Color fg, Color bg}) crmOutcomeStyle(Object? outcome, {bool archived = false}) {
  if (archived) {
    return (label: 'Archived', icon: Icons.inventory_2_outlined, fg: UiTokens.cancelledFg, bg: UiTokens.cancelledBg);
  }
  switch (crmStr(outcome)) {
    case 'won':
      return (label: 'Won', icon: Icons.emoji_events_outlined, fg: UiTokens.completedFg, bg: UiTokens.completedBg);
    case 'lost':
      return (label: 'Lost', icon: Icons.do_not_disturb_on_outlined, fg: UiTokens.failedFg, bg: UiTokens.failedBg);
    default:
      return (label: 'Open', icon: Icons.radio_button_unchecked, fg: UiTokens.searchingFg, bg: UiTokens.searchingBg);
  }
}

// ------------------------------------------------------------- activities

const List<String> crmActivityTypes = ['call', 'email', 'meeting', 'message', 'task'];

String crmActivityTypeLabel(Object? type) {
  switch (crmStr(type)) {
    case 'call':
      return 'Call';
    case 'email':
      return 'Email to send';
    case 'meeting':
      return 'Meeting';
    case 'message':
      return 'Message';
    default:
      return 'Task';
  }
}

IconData crmActivityIcon(Object? type) {
  switch (crmStr(type)) {
    case 'call':
      return Icons.call_outlined;
    case 'email':
      return Icons.email_outlined;
    case 'meeting':
      return Icons.groups_outlined;
    case 'message':
      return Icons.chat_bubble_outline_rounded;
    default:
      return Icons.task_alt_rounded;
  }
}

enum CrmDueKind { overdue, today, upcoming, done, none }

bool crmActivityDone(Map<String, dynamic> a) =>
    crmStr(a['status']) == 'done' || crmStr(a['completed_at']).isNotEmpty;

/// Due state of an activity in the viewer's local time.
CrmDueKind crmDueKind(Map<String, dynamic> a, {DateTime? now}) {
  if (crmActivityDone(a)) return CrmDueKind.done;
  final due = parseServerTimeLocal(a['due_at']);
  if (due == null) return CrmDueKind.none;
  final n = (now ?? DateTime.now()).toLocal();
  if (a['overdue'] == true || due.isBefore(n)) return CrmDueKind.overdue;
  if (due.year == n.year && due.month == n.month && due.day == n.day) return CrmDueKind.today;
  return CrmDueKind.upcoming;
}

({String label, IconData icon, Color fg, Color bg}) crmDueStyle(CrmDueKind kind) {
  switch (kind) {
    case CrmDueKind.overdue:
      return (label: 'Overdue', icon: Icons.warning_amber_rounded, fg: UiTokens.failedFg, bg: UiTokens.failedBg);
    case CrmDueKind.today:
      return (label: 'Due today', icon: Icons.today_rounded, fg: UiTokens.partialFg, bg: UiTokens.partialBg);
    case CrmDueKind.upcoming:
      return (label: 'Upcoming', icon: Icons.event_rounded, fg: UiTokens.searchingFg, bg: UiTokens.searchingBg);
    case CrmDueKind.done:
      return (label: 'Done', icon: Icons.check_circle_outline_rounded, fg: UiTokens.completedFg, bg: UiTokens.completedBg);
    case CrmDueKind.none:
      return (label: 'No date', icon: Icons.event_busy_outlined, fg: UiTokens.cancelledFg, bg: UiTokens.cancelledBg);
  }
}

/// A local date + time picked by the user → UTC ISO-8601 with `Z`.
String crmDueAtUtc(DateTime localDate, TimeOfDay time) =>
    DateTime(localDate.year, localDate.month, localDate.day, time.hour, time.minute).toUtc().toIso8601String();

/// Default due time of a new activity: tomorrow 09:00 local.
DateTime crmDefaultDue([DateTime? now]) {
  final n = (now ?? DateTime.now()).toLocal();
  return DateTime(n.year, n.month, n.day + 1, 9);
}

// ------------------------------------------------------------------ times

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

/// Unambiguous local timestamp: "Tue, Nov 18, 2026, 13:04 (UTC+05:00)".
String crmFullLocal(DateTime value) {
  final l = value.toLocal();
  final off = l.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final abs = off.abs();
  return '${_weekdays[l.weekday - 1]}, ${_monthNames[l.month - 1]} ${l.day}, ${l.year}, '
      '${_two(l.hour)}:${_two(l.minute)} (UTC$sign${_two(abs.inHours)}:${_two(abs.inMinutes % 60)})';
}

/// "Nov 18, 2026" of a `YYYY-MM-DD` date (no time zone shift).
String crmDateLabel(Object? ymd) {
  final s = crmStr(ymd);
  final d = DateTime.tryParse(s.length >= 10 ? s.substring(0, 10) : s);
  if (d == null) return s;
  return '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';
}

/// Local short time of a server timestamp ("Today 13:04").
String crmWhen(Object? serverValue) => formatServerDateTime(serverValue);

// ----------------------------------------------------------------- record

String crmRecordTitle(Map<String, dynamic> r) {
  final t = crmStr(r['title']);
  if (t.isNotEmpty) return t;
  final n = crmStr(crmMap(r['company'])['name']);
  return n.isEmpty ? 'Untitled record' : n;
}

/// "Montreal, Quebec" from a company.
String crmPlace(Map<String, dynamic> company) {
  final parts = <String>[];
  for (final k in ['city', 'region', 'country']) {
    final v = crmStr(company[k]);
    if (v.isNotEmpty && !parts.any((p) => p.toLowerCase() == v.toLowerCase())) parts.add(v);
  }
  return parts.take(2).join(', ');
}

/// One meaningful contact hint for a card (phone, else email, else site).
({IconData icon, String text})? crmContactHint(Map<String, dynamic> company) {
  final phone = crmStr(company['phone']);
  if (phone.isNotEmpty) return (icon: Icons.call_outlined, text: phone);
  final email = crmStr(company['email']);
  if (email.isNotEmpty) return (icon: Icons.email_outlined, text: email);
  final site = crmStr(company['website']);
  if (site.isNotEmpty) {
    final host = Uri.tryParse(site)?.host ?? '';
    return (icon: Icons.language_rounded, text: host.isNotEmpty ? host.replaceFirst('www.', '') : site);
  }
  return null;
}

String crmStageName(Map<String, dynamic> r) => crmStr(crmMap(r['stage'])['name']);

// ----------------------------------------------------------------- events

String _name(Object? v) {
  if (v is Map) return crmStr(v['name'] ?? v['title'] ?? v['subject']);
  return crmStr(v);
}

/// One history line.
String crmEventText(Map<String, dynamic> e) {
  final type = crmStr(e['type']);
  final before = crmMap(e['before']);
  final after = crmMap(e['after']);
  String? field(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = _name(m[k]);
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  switch (type) {
    case 'imported':
      final cat = field(after, ['category', 'source', 'job_category']);
      return cat == null ? 'Added from a search' : 'Added from a search ($cat)';
    case 'source_linked':
      return 'Linked to another search result';
    case 'created':
      return 'Created manually';
    case 'updated':
      final keys = after.keys.where((k) => k != 'version').toList();
      return keys.isEmpty ? 'Details updated' : 'Updated ${keys.map((k) => k.replaceAll('_', ' ')).join(', ')}';
    case 'stage_changed':
      final from = field(before, ['stage', 'stage_name']);
      final to = field(after, ['stage', 'stage_name']);
      if (from != null && to != null) return 'Moved from $from to $to';
      return to == null ? 'Stage changed' : 'Moved to $to';
    case 'converted':
      return 'Converted to opportunity';
    case 'won':
      return 'Marked won';
    case 'lost':
      final reason = field(after, ['reason', 'lost_reason']);
      return reason == null ? 'Marked lost' : 'Marked lost: $reason';
    case 'reopened':
      return 'Reopened';
    case 'archived':
      return 'Archived';
    case 'restored':
      return 'Restored from archive';
    case 'note_added':
      return 'Note added';
    case 'note_edited':
      return 'Note edited';
    case 'person_added':
      final n = field(after, ['name']);
      return n == null ? 'Contact person added' : 'Contact person added: $n';
    case 'person_updated':
      return 'Contact person updated';
    case 'person_removed':
      final n = field(before, ['name']);
      return n == null ? 'Contact person removed' : 'Contact person removed: $n';
    case 'tags_changed':
      return 'Tags changed';
    case 'activity_scheduled':
      final s = field(after, ['subject']);
      return s == null ? 'Activity scheduled' : 'Activity scheduled: $s';
    case 'activity_rescheduled':
      return 'Activity rescheduled';
    case 'activity_done':
      final s = field(after, ['subject']);
      return s == null ? 'Activity done' : 'Activity done: $s';
    case 'activity_reopened':
      return 'Activity reopened';
    default:
      return type.isEmpty ? 'Change' : type.replaceAll('_', ' ');
  }
}

// ------------------------------------------------------------- validation

/// Null when [v] is empty or a valid http(s) address with a host.
String? crmValidateWebsite(String v) {
  final s = v.trim();
  if (s.isEmpty) return null;
  final u = Uri.tryParse(s);
  if (u == null || (u.scheme != 'http' && u.scheme != 'https') || u.host.isEmpty) {
    return 'Use a full address starting with http:// or https://';
  }
  return null;
}

String? crmValidateEmail(String v) {
  final s = v.trim();
  if (s.isEmpty) return null;
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s) ? null : 'Enter a valid email address';
}

String? crmValidateCurrency(String v, {required bool valueSet}) {
  final s = v.trim();
  if (s.isEmpty) return valueSet ? 'Enter the 3-letter currency code (e.g. CAD)' : null;
  return RegExp(r'^[A-Za-z]{3}$').hasMatch(s) ? null : 'Use a 3-letter ISO code such as CAD, USD or EUR';
}

String? crmValidateValue(String v) {
  final s = v.trim().replaceAll(',', '');
  if (s.isEmpty) return null;
  final n = num.tryParse(s);
  if (n == null) return 'Enter a number, e.g. 1500 or 1500.50';
  if (n < 0) return 'The value cannot be negative';
  if (n >= 1e12) return 'That value is too large';
  return null;
}

String? crmValidateProbability(String v) {
  final s = v.trim().replaceAll('%', '');
  if (s.isEmpty) return null;
  final n = int.tryParse(s);
  if (n == null || n < 0 || n > 100) return 'Enter a whole number from 0 to 100';
  return null;
}
