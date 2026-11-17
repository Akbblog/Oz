import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The search being set up in "Find leads" (step 1 Location, step 2 Details).
///
/// App-global so the selection survives navigation, the guest sign-in and a
/// page refresh. It persists to the two SharedPreferences keys the old wizard
/// used, so drafts saved by the previous version still load:
///
/// * [locationDraftKey] `{country, state, cities, include_suburbs, saved_at}`
///   (`include_suburbs` is ignored on read and always written `false`).
/// * [searchDraftKey] `{category, cities_text, max_results, saved_at}` where
///   `cities_text` is every city that will be searched, joined with "; ".
///
/// Selection rules (plan §7 #4):
/// * [addCities] is a union (keeps existing, appends new ones in order).
/// * [removeCities] removes only the cities it is given (the UI passes the
///   ones currently shown), never the whole selection.
/// * [setCountry] / [setRegion] never drop cities by themselves. The UI asks
///   [citiesOutside] / [hasSelection], confirms with the user, and only then
///   calls [discardCities].
class SearchSetupProvider with ChangeNotifier {
  SearchSetupProvider({bool autoLoad = true}) {
    if (autoLoad) unawaited(load());
  }

  static const String locationDraftKey = 'wizard_location_draft_v1';
  static const String searchDraftKey = 'wizard_search_draft_v1';

  /// Leads-per-city choices offered by the UI.
  static const List<int> maxResultsChoices = <int>[10, 20, 50, 100];
  static const int maxResultsCap = 100;
  static const int defaultMaxResults = 10;

  String? _country;
  String? _region;
  final List<String> _cities = <String>[];
  final List<String> _extraCities = <String>[];
  String _category = '';
  int _maxResultsPerCity = defaultMaxResults;
  bool _maxResultsWasCapped = false;
  bool _loaded = false;
  bool _restoredFromDraft = false;
  bool _disposed = false;
  Future<void>? _loading;

  // ---------------------------------------------------------------- getters

  String? get country => _country;
  String? get region => _region;

  /// Cities picked from the location lists, formatted "City, Region", in the
  /// order they were added.
  List<String> get cities => List<String>.unmodifiable(_cities);

  /// Free-text cities added by hand ("Add a city not listed").
  List<String> get extraCities => List<String>.unmodifiable(_extraCities);

  /// Every city that will be searched: [cities] then [extraCities], without
  /// duplicates (case-insensitive).
  List<String> get allCities {
    final seen = <String>{};
    final out = <String>[];
    for (final c in [..._cities, ..._extraCities]) {
      if (seen.add(_key(c))) out.add(c);
    }
    return out;
  }

  String get category => _category;
  int get maxResultsPerCity => _maxResultsPerCity;

  /// True when a saved draft or a previous search asked for more than
  /// [maxResultsCap] leads per city. The UI shows "Maximum is 100 leads per
  /// city" next to the (capped) choice; the larger value is never sent.
  bool get maxResultsWasCapped => _maxResultsWasCapped;

  bool get hasSelection => _cities.isNotEmpty || _extraCities.isNotEmpty;
  int get cityCount => allCities.length;
  bool get isLoaded => _loaded;

  /// True when [load] found a saved draft (for a "restored" notice).
  bool get restoredFromDraft => _restoredFromDraft;

  bool isSelected(String city) {
    final k = _key(city);
    return _cities.any((c) => _key(c) == k);
  }

  /// Selected cities (from the lists) that are not in [region].
  List<String> citiesOutside(String region) {
    final r = region.trim().toLowerCase();
    return _cities.where((c) => (regionOf(c) ?? '').toLowerCase() != r).toList();
  }

  // ------------------------------------------------------------- formatting

  /// "Montreal, Quebec" -> "Quebec". Null when the string has no region.
  static String? regionOf(String city) {
    final i = city.lastIndexOf(',');
    if (i < 0) return null;
    final r = city.substring(i + 1).trim();
    return r.isEmpty ? null : r;
  }

  /// "Montreal, Quebec" -> "Montreal".
  static String cityNameOf(String city) {
    final i = city.lastIndexOf(',');
    return (i < 0 ? city : city.substring(0, i)).trim();
  }

  /// "Montreal" + "Quebec" -> "Montreal, Quebec"; strings that already carry a
  /// region are kept as they are.
  static String formatCity(String city, String? region) {
    final trimmed = city.trim();
    if (trimmed.contains(',') || region == null || region.trim().isEmpty) {
      return trimmed;
    }
    return '$trimmed, ${region.trim()}';
  }

  static String _key(String city) =>
      city.trim().toLowerCase().replaceAll(RegExp(r'\s*,\s*'), ', ');

  /// Largest allowed choice that is not above [value] (min 10), so a legacy
  /// value never increases the cost; values above 100 become 100 and are
  /// flagged.
  static ({int value, bool capped}) normalizeMaxResults(Object? raw) {
    final n = raw is num ? raw.toInt() : int.tryParse('${raw ?? ''}');
    if (n == null || n <= 0) return (value: defaultMaxResults, capped: false);
    if (n > maxResultsCap) return (value: maxResultsCap, capped: true);
    var best = maxResultsChoices.first;
    for (final c in maxResultsChoices) {
      if (c <= n) best = c;
    }
    return (value: best, capped: false);
  }

  // ------------------------------------------------------------- mutations

  /// Sets the country. Does not remove any selected city; when the country
  /// changes, the region is unset (regions belong to a country).
  void setCountry(String? country) {
    final next = (country == null || country.trim().isEmpty) ? null : country.trim();
    if (next == _country) return;
    _country = next;
    _region = null;
    _changed();
  }

  /// Sets the region being browsed. Does not remove any selected city.
  void setRegion(String? region) {
    final next = (region == null || region.trim().isEmpty) ? null : region.trim();
    if (next == _region) return;
    _region = next;
    _changed();
  }

  /// Union: keeps the current selection and appends cities not yet selected.
  void addCities(Iterable<String> cities) {
    var changed = false;
    for (final raw in cities) {
      final city = raw.trim();
      if (city.isEmpty || isSelected(city)) continue;
      _cities.add(city);
      changed = true;
    }
    if (changed) _changed();
  }

  /// Removes exactly the given cities (e.g. the ones currently shown).
  void removeCities(Iterable<String> cities) {
    final keys = cities.map(_key).toSet();
    final before = _cities.length;
    _cities.removeWhere((c) => keys.contains(_key(c)));
    if (_cities.length != before) _changed();
  }

  void toggleCity(String city) {
    if (isSelected(city)) {
      removeCities([city]);
    } else {
      addCities([city]);
    }
  }

  /// "Clear all": removes every selected city, including hand-added ones.
  void clearAll() {
    if (_cities.isEmpty && _extraCities.isEmpty) return;
    _cities.clear();
    _extraCities.clear();
    _changed();
  }

  /// Explicitly drops cities after the user confirmed (e.g. switching region
  /// or country). With no argument every selected city is dropped
  /// (hand-added cities are kept unless [includeExtra] is true).
  void discardCities([Iterable<String>? cities, bool includeExtra = false]) {
    if (cities == null) {
      final had = _cities.isNotEmpty || (includeExtra && _extraCities.isNotEmpty);
      _cities.clear();
      if (includeExtra) _extraCities.clear();
      if (had) _changed();
      return;
    }
    removeCities(cities);
  }

  void setCategory(String category) {
    if (category == _category) return;
    _category = category;
    _changed();
  }

  /// Sets leads per city (snapped to an allowed choice, never above 100).
  /// Clears the "was capped" note because the user chose a value.
  void setMaxResultsPerCity(int value) {
    final n = normalizeMaxResults(value);
    if (n.value == _maxResultsPerCity && !_maxResultsWasCapped) return;
    _maxResultsPerCity = n.value;
    _maxResultsWasCapped = n.capped;
    _changed();
  }

  void addExtraCity(String city) {
    final c = city.trim();
    if (c.isEmpty) return;
    final k = _key(c);
    if (_extraCities.any((e) => _key(e) == k) || isSelected(c)) return;
    _extraCities.add(c);
    _changed();
  }

  void removeExtraCity(String city) {
    final k = _key(city);
    final before = _extraCities.length;
    _extraCities.removeWhere((e) => _key(e) == k);
    if (_extraCities.length != before) _changed();
  }

  void setExtraCities(Iterable<String> cities) {
    _extraCities
      ..clear()
      ..addAll(_dedupe(cities.map((c) => c.trim()).where((c) => c.isNotEmpty))
          .where((c) => !isSelected(c)));
    _changed();
  }

  /// "Run again": replaces the setup with a previous search. Uses the job's
  /// own `max_results_per_city` (capped at 100 and flagged when larger),
  /// `country`/`region` when the server provides them, otherwise the region
  /// shared by all of its cities.
  void loadFromJob(Map<String, dynamic> job) {
    final cities = <String>[];
    final raw = job['cities'];
    if (raw is List) {
      for (final c in raw) {
        final s = '$c'.trim();
        if (s.isNotEmpty) cities.add(s);
      }
    }
    final country = job['country'];
    final region = job['region'];
    _country = (country is String && country.trim().isNotEmpty) ? country.trim() : null;
    String? inferredRegion;
    if (region is String && region.trim().isNotEmpty) {
      inferredRegion = region.trim();
    } else if (cities.isNotEmpty) {
      final regions = cities.map(regionOf).toSet();
      if (regions.length == 1 && regions.first != null) inferredRegion = regions.first;
    }
    _region = inferredRegion;
    _cities
      ..clear()
      ..addAll(_dedupe(cities));
    _extraCities.clear();
    _category = '${job['category'] ?? ''}'.trim();
    final n = normalizeMaxResults(job['max_results_per_city']);
    _maxResultsPerCity = n.value;
    _maxResultsWasCapped = n.capped;
    _restoredFromDraft = false;
    _changed();
  }

  /// Sign-out: forget everything and delete both drafts.
  Future<void> clear() async {
    if (!_loaded) _dirtyBeforeLoad = true;
    _country = null;
    _region = null;
    _cities.clear();
    _extraCities.clear();
    _category = '';
    _maxResultsPerCity = defaultMaxResults;
    _maxResultsWasCapped = false;
    _restoredFromDraft = false;
    _persistTimer?.cancel();
    _notify();
    await removeDrafts();
  }

  static Future<void> removeDrafts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(locationDraftKey);
      await prefs.remove(searchDraftKey);
    } catch (_) {}
  }

  // ------------------------------------------------------------ persistence

  /// Reads the saved drafts once (concurrent callers share the same read).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final location = _decode(prefs.getString(locationDraftKey));
      final search = _decode(prefs.getString(searchDraftKey));
      // Something changed while we were reading (e.g. "Run again"): keep it.
      if (_dirtyBeforeLoad) return;
      if (location != null) {
        final country = location['country'];
        final state = location['state'];
        _country = (country is String && country.trim().isNotEmpty) ? country.trim() : null;
        _region = (state is String && state.trim().isNotEmpty) ? state.trim() : null;
        final raw = location['cities'];
        if (raw is List) {
          _cities
            ..clear()
            ..addAll(_dedupe(raw
                .map((c) => formatCity('$c', _region))
                .where((c) => c.isNotEmpty)));
        }
      }
      if (search != null) {
        _category = '${search['category'] ?? ''}'.trim();
        final text = '${search['cities_text'] ?? ''}';
        final fromText = text
            .split(RegExp(r'[;\n]'))
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty);
        if (location == null) {
          // Old drafts without a location step: the text is the selection.
          _cities
            ..clear()
            ..addAll(_dedupe(fromText));
          _extraCities.clear();
        } else {
          _extraCities
            ..clear()
            ..addAll(_dedupe(fromText).where((c) => !isSelected(c)));
        }
        if (search.containsKey('max_results')) {
          final n = normalizeMaxResults(search['max_results']);
          _maxResultsPerCity = n.value;
          _maxResultsWasCapped = n.capped;
        }
      }
      _restoredFromDraft = location != null || search != null;
    } catch (_) {
      // A broken draft must never block the page.
    } finally {
      _loaded = true;
      _notify();
    }
  }

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  static List<String> _dedupe(Iterable<String> items) {
    final seen = <String>{};
    final out = <String>[];
    for (final c in items) {
      if (seen.add(_key(c))) out.add(c);
    }
    return out;
  }

  bool _dirtyBeforeLoad = false;
  Timer? _persistTimer;

  void _changed() {
    if (!_loaded) _dirtyBeforeLoad = true;
    _notify();
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 250), () => unawaited(persist()));
  }

  /// Writes both drafts now. Called automatically (debounced) after changes;
  /// call it directly before navigating away from the app (e.g. sign-in).
  Future<void> persist() async {
    _persistTimer?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();
      if (_country == null && _region == null && _cities.isEmpty) {
        await prefs.remove(locationDraftKey);
      } else {
        await prefs.setString(
          locationDraftKey,
          jsonEncode({
            'country': _country ?? '',
            'state': _region ?? '',
            'cities': _cities,
            'include_suburbs': false,
            'saved_at': now,
          }),
        );
      }
      if (_category.isEmpty && !hasSelection && _maxResultsPerCity == defaultMaxResults) {
        await prefs.remove(searchDraftKey);
      } else {
        await prefs.setString(
          searchDraftKey,
          jsonEncode({
            'category': _category,
            'cities_text': allCities.join('; '),
            'max_results': _maxResultsPerCity,
            'saved_at': now,
          }),
        );
      }
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _persistTimer?.cancel();
    super.dispose();
  }
}
