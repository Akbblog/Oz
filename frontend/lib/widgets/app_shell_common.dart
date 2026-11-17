import 'package:flutter/material.dart';

import '../core/utils/server_time.dart';

/// Visual tokens of the user-facing redesign (dark theme, plan §10).
class UiTokens {
  UiTokens._();

  static const Color background = Color(0xFF171717);
  static const Color card = Color(0xFF242427);
  static const Color border = Color(0xFF3A3A3E);
  static const Color text = Color(0xFFE3E5E8);
  static const Color textSecondary = Color(0xFFA9B4C2);
  static const Color textMuted = Color(0xFF8B95A3);
  static const Color accent = Color(0xFF6CC4D6);
  static const Color primary = Color(0xFF2C5F6D);
  static const Color primaryHover = Color(0xFF347381);
  static const Color selectedSurface = Color(0xFF1E3A42);

  static const Color searchingFg = Color(0xFF669DF1);
  static const Color searchingBg = Color(0xFF1A2638);
  static const Color completedFg = Color(0xFF4BCE97);
  static const Color completedBg = Color(0xFF14271F);
  static const Color partialFg = Color(0xFFEED12B);
  static const Color partialBg = Color(0xFF26230F);
  static const Color failedFg = Color(0xFFF87168);
  static const Color failedBg = Color(0xFF2A1817);
  static const Color cancelledFg = Color(0xFFA0A6AD);
  static const Color cancelledBg = Color(0xFF232427);

  static const double radius = 12;
}

// ---------------------------------------------------------------- numbers

/// 4102 -> "4,102".
String formatCount(num value) {
  final negative = value < 0;
  final digits = value.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return negative ? '-$buf' : buf.toString();
}

/// "1 search" / "4 searches".
String plural(num n, String one, String many) =>
    '${formatCount(n)} ${n == 1 ? one : many}';

int jobInt(Map<String, dynamic> job, String key) {
  final v = job[key];
  if (v is num) return v.toInt();
  return int.tryParse('${v ?? ''}') ?? 0;
}

// ------------------------------------------------------------------ times

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Local time as "Today 13:04", "Yesterday 09:10" or "Nov 17, 13:04"
/// (plus the year when it is not the current year).
String formatLocalDateTime(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final ref = (now ?? DateTime.now()).toLocal();
  final time = '${_two(local.hour)}:${_two(local.minute)}';
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(ref.year, ref.month, ref.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today $time';
  if (diff == 1) return 'Yesterday $time';
  final date = '${_months[local.month - 1]} ${local.day}';
  if (local.year != ref.year) return '$date, ${local.year}, $time';
  return '$date, $time';
}

/// Server timestamp -> local display string ("—" when missing).
String formatServerDateTime(Object? serverValue, {DateTime? now}) {
  final t = parseServerTimeLocal(serverValue);
  return t == null ? '—' : formatLocalDateTime(t, now: now);
}

/// Elapsed time as "just now", "1 min ago", "3 h ago", "2 days ago".
String formatAgo(Duration elapsed) {
  if (elapsed.isNegative || elapsed.inSeconds < 60) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours} h ago';
  final d = elapsed.inDays;
  return d == 1 ? '1 day ago' : '$d days ago';
}

// --------------------------------------------------------- search summary

/// "Montreal, Quebec" -> "Montreal".
String _cityName(String city) {
  final i = city.lastIndexOf(',');
  return (i < 0 ? city : city.substring(0, i)).trim();
}

String? _regionOf(String city) {
  final i = city.lastIndexOf(',');
  if (i < 0) return null;
  final r = city.substring(i + 1).trim();
  return r.isEmpty ? null : r;
}

List<String> jobCities(Map<String, dynamic> job) {
  final raw = job['cities'];
  if (raw is! List) return const <String>[];
  return raw.map((c) => '$c'.trim()).where((c) => c.isNotEmpty).toList();
}

/// The region of a search: `region` from the API, else the region shared by
/// every city ("Montreal, Quebec" ...), else null.
String? jobRegion(Map<String, dynamic> job) {
  final r = job['region'];
  if (r is String && r.trim().isNotEmpty) return r.trim();
  final cities = jobCities(job);
  if (cities.isEmpty) return null;
  final regions = cities.map(_regionOf).toSet();
  if (regions.length == 1) return regions.first;
  return null;
}

String? jobCountry(Map<String, dynamic> job) {
  final c = job['country'];
  if (c is String && c.trim().isNotEmpty) return c.trim();
  return null;
}

/// "Quebec, Canada", "Quebec", "Canada" or null.
String? jobPlaceLabel(Map<String, dynamic> job) {
  final parts = [jobRegion(job), jobCountry(job)].whereType<String>().toList();
  return parts.isEmpty ? null : parts.join(', ');
}

/// "Montreal +3 · Quebec, Canada", "Montreal, Laval · Quebec, Canada".
String jobCitiesSummary(Map<String, dynamic> job) {
  final cities = jobCities(job);
  String names;
  if (cities.isEmpty) {
    final total = jobInt(job, 'total_cities');
    names = total > 0 ? plural(total, 'city', 'cities') : '';
  } else if (cities.length == 1) {
    names = _cityName(cities.first);
  } else if (cities.length == 2) {
    names = '${_cityName(cities[0])}, ${_cityName(cities[1])}';
  } else {
    names = '${_cityName(cities.first)} +${cities.length - 1}';
  }
  final place = jobPlaceLabel(job);
  if (place == null) return names;
  if (names.isEmpty) return place;
  return '$names · $place';
}

/// "4 cities in Quebec, Canada" (or "4 cities").
String jobCitiesInPlace(Map<String, dynamic> job) {
  final total = jobInt(job, 'total_cities');
  final n = total > 0 ? total : jobCities(job).length;
  final place = jobPlaceLabel(job);
  final cities = plural(n, 'city', 'cities');
  return place == null ? cities : '$cities in $place';
}

String jobCategory(Map<String, dynamic> job) {
  final c = '${job['category'] ?? ''}'.trim();
  return c.isEmpty ? 'Search' : c;
}

// ----------------------------------------------------------------- status

enum SearchStatusKind { queued, searching, completed, partial, failed, cancelled, unknown }

class SearchStatusInfo {
  final SearchStatusKind kind;
  final String label;
  final Color foreground;
  final Color background;
  final IconData icon;

  const SearchStatusInfo(this.kind, this.label, this.foreground, this.background, this.icon);

  bool get isActive => kind == SearchStatusKind.queued || kind == SearchStatusKind.searching;
}

bool jobIsActive(Map<String, dynamic> job) {
  final s = '${job['status']}';
  return s == 'pending' || s == 'running';
}

bool jobIsTerminal(Map<String, dynamic> job) {
  final s = '${job['status']}';
  return s == 'completed' || s == 'failed' || s == 'cancelled';
}

/// Badge text/colours from the API status (plan §6.5 / brief status copy).
SearchStatusInfo searchStatusOf(Map<String, dynamic> job) {
  final leads = jobInt(job, 'result_count');
  switch ('${job['status']}') {
    case 'pending':
      return const SearchStatusInfo(SearchStatusKind.queued, 'Queued',
          UiTokens.searchingFg, UiTokens.searchingBg, Icons.schedule_rounded);
    case 'running':
      return const SearchStatusInfo(SearchStatusKind.searching, 'Searching',
          UiTokens.searchingFg, UiTokens.searchingBg, Icons.autorenew_rounded);
    case 'completed':
      final failedCities = jobInt(job, 'failed_cities');
      if (failedCities > 0) {
        return SearchStatusInfo(
          SearchStatusKind.partial,
          'Completed · ${plural(failedCities, 'city', 'cities')} found nothing',
          UiTokens.partialFg,
          UiTokens.partialBg,
          Icons.warning_amber_rounded,
        );
      }
      return const SearchStatusInfo(SearchStatusKind.completed, 'Completed',
          UiTokens.completedFg, UiTokens.completedBg, Icons.check_rounded);
    case 'failed':
      return SearchStatusInfo(
        SearchStatusKind.failed,
        leads > 0 ? 'Failed · partial results' : 'Failed',
        UiTokens.failedFg,
        UiTokens.failedBg,
        Icons.close_rounded,
      );
    case 'cancelled':
      return const SearchStatusInfo(SearchStatusKind.cancelled, 'Cancelled',
          UiTokens.cancelledFg, UiTokens.cancelledBg, Icons.block_rounded);
    default:
      return SearchStatusInfo(SearchStatusKind.unknown, '${job['status'] ?? 'Unknown'}',
          UiTokens.cancelledFg, UiTokens.cancelledBg, Icons.help_outline_rounded);
  }
}

/// Status badge: always icon + word (never colour alone).
class SearchStatusBadge extends StatelessWidget {
  final Map<String, dynamic> job;
  final SearchStatusInfo? info;

  const SearchStatusBadge({super.key, required this.job, this.info});

  @override
  Widget build(BuildContext context) {
    final s = info ?? searchStatusOf(job);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: s.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: s.foreground.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: 14, color: s.foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              s.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: s.foreground,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- credits

/// Treats a missing `settled` flag on a final search as settled (older
/// servers settled synchronously); explicit `false` means refund pending.
bool jobSettled(Map<String, dynamic> job) {
  final v = job['settled'];
  if (v is bool) return v;
  return jobIsTerminal(job);
}

/// Credits-used cell for lists (Home "Recent searches", My searches):
/// * settled: "27" (+ "(13 returned)" via [jobCreditsReturnedNote])
/// * active: "70 charged"
/// * final but not settled yet: "70 charged · refund pending"
String jobCreditsUsedLabel(Map<String, dynamic> job) {
  final charged = jobInt(job, 'credit_charged');
  final refunded = jobInt(job, 'credit_refunded');
  if (jobIsActive(job)) return '${formatCount(charged)} charged';
  if (!jobSettled(job)) return '${formatCount(charged)} charged · refund pending';
  final used = charged - refunded;
  return formatCount(used < 0 ? 0 : used);
}

/// "(13 returned)" for settled searches with a refund, else null.
String? jobCreditsReturnedNote(Map<String, dynamic> job) {
  if (jobIsActive(job) || !jobSettled(job)) return null;
  final refunded = jobInt(job, 'credit_refunded');
  return refunded > 0 ? '(${formatCount(refunded)} returned)' : null;
}

/// The next step for a search row.
String jobActionLabel(Map<String, dynamic> job) {
  final leads = jobInt(job, 'result_count');
  switch ('${job['status']}') {
    case 'pending':
    case 'running':
      return 'View progress';
    case 'completed':
      return 'Open results';
    case 'cancelled':
      return leads > 0 ? 'Open ${plural(leads, 'lead', 'leads')}' : 'See details';
    case 'failed':
      return 'See why';
    default:
      return 'Open';
  }
}

/// Leads cell: "9 so far" while active, else "7".
String jobLeadsLabel(Map<String, dynamic> job) {
  final leads = jobInt(job, 'result_count');
  return jobIsActive(job) ? '${formatCount(leads)} so far' : formatCount(leads);
}
