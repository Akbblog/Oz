/// Server timestamps -> correct local times.
///
/// The API returns explicit UTC (`2026-11-16T10:00:00.000Z`) for job data.
/// Older endpoints still return naive ISO strings; the backend container's
/// clock is UTC, so a naive value is interpreted as UTC as well. Parsing a
/// naive string with `DateTime.parse` treated it as *browser-local* time,
/// which shifted durations and "x ago" labels by the user's UTC offset
/// (about +5h in Pakistan).
library;

DateTime? parseServerTime(Object? value) {
  if (value == null) return null;
  final raw = '$value'.trim();
  if (raw.isEmpty) return null;
  final hasOffset =
      raw.endsWith('Z') || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(raw);
  return DateTime.tryParse(hasOffset ? raw : '${raw}Z');
}

/// Same as [parseServerTime] but converted to the viewer's local time for
/// display. Durations computed between two of these values are correct.
DateTime? parseServerTimeLocal(Object? value) =>
    parseServerTime(value)?.toLocal();
