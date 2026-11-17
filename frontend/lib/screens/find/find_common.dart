import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../providers/search_setup_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/app_shell_common.dart';
import '../../widgets/country_flag_badge.dart';

// ------------------------------------------------------------------ labels

/// Display-only country names. Requests always use the API key ("USA").
const Map<String, String> _countryNames = {
  'USA': 'United States',
  'UK': 'United Kingdom',
  'UAE': 'United Arab Emirates',
  'KSA': 'Saudi Arabia',
};

/// "USA" -> "United States"; other keys are shown as they are.
String countryDisplayName(String? key) {
  if (key == null) return '';
  return _countryNames[key] ?? key;
}

/// "province" -> "provinces".
String pluralTerm(String term) {
  if (term.endsWith('s')) return term;
  if (term.endsWith('y') && term.length > 1 && !'aeiou'.contains(term[term.length - 2])) {
    return '${term.substring(0, term.length - 1)}ies';
  }
  return '${term}s';
}

/// "province" -> "Provinces".
String capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// "13 provinces" / "1 region".
String termCount(int n, String term) => '${formatCount(n)} ${n == 1 ? term : pluralTerm(term)}';

/// "1 city" / "4 cities".
String citiesLabel(int n) => plural(n, 'city', 'cities');

/// "Montreal, Laval, Saint-Jérôme +1".
String cityNamesSummary(List<String> cities, {int max = 3}) {
  if (cities.isEmpty) return '';
  final names = cities.take(max).map(displayCityName).join(', ');
  final rest = cities.length - max;
  return rest > 0 ? '$names +$rest' : names;
}

/// City strings are "Name, Region"; the name is everything before the last
/// comma.
String displayCityName(String city) => SearchSetupProvider.cityNameOf(city);

String cityKey(String city) =>
    city.trim().toLowerCase().replaceAll(RegExp(r'\s*,\s*'), ', ');

/// "Laval, Quebec" style free text: a comma with text on both sides.
bool isValidCityRegion(String raw) {
  final i = raw.lastIndexOf(',');
  if (i <= 0) return false;
  return raw.substring(0, i).trim().isNotEmpty && raw.substring(i + 1).trim().isNotEmpty;
}

// ---------------------------------------------------------------- catalog

/// Location data for Find leads, loaded from the API (never invented):
/// countries (`/api/countries`), regions (`/api/states`), region terms and
/// counts (`/api/locations/summary`, optional) and cities per region.
///
/// Shared by both steps so "No longer listed" is decided the same way:
/// a selected city is no longer listed when its region (the part after the
/// last comma) is not offered any more or the city is absent from that
/// region's current list.
class LocationCatalog with ChangeNotifier {
  LocationCatalog({ApiService? api}) : api = api ?? ApiService();

  /// App-wide cache (the real API).
  static final LocationCatalog instance = LocationCatalog();
  static final Expando<LocationCatalog> _byApi = Expando<LocationCatalog>();

  /// The shared catalog, or one bound to [api] (tests).
  static LocationCatalog of(ApiService? api) =>
      api == null ? instance : (_byApi[api] ??= LocationCatalog(api: api));

  final ApiService api;

  List<String>? _countries;
  Map<String, List<String>>? _regions;
  Map<String, dynamic> _summary = const {};
  Object? _error;
  bool _loading = false;
  Future<void>? _inFlight;

  final Map<String, List<String>> _cities = {};
  final Map<String, Set<String>> _cityKeys = {};
  final Map<String, Object> _cityErrors = {};
  final Map<String, Future<List<String>>> _cityInFlight = {};

  bool get isLoaded => _countries != null && _regions != null;
  bool get isLoading => _loading;
  Object? get error => _error;
  List<String> get countries => _countries ?? const <String>[];

  List<String> regionsOf(String? country) =>
      country == null ? const <String>[] : (_regions?[country] ?? const <String>[]);

  bool hasCountry(String? country) => country != null && (_regions?.containsKey(country) ?? false);

  bool regionExists(String? country, String region) {
    if (country == null) return countryOfRegion(region) != null;
    return regionsOf(country).contains(region);
  }

  /// The country offering [region] (first match), or null.
  String? countryOfRegion(String? region) {
    if (region == null) return null;
    final regions = _regions;
    if (regions == null) return null;
    for (final e in regions.entries) {
      if (e.value.contains(region)) return e.key;
    }
    return null;
  }

  /// "province", "state", "emirate", ... (default "region").
  String regionTerm(String? country) {
    final c = country == null ? null : _summary[country];
    final t = c is Map ? c['region_term'] : null;
    return (t is String && t.trim().isNotEmpty) ? t.trim().toLowerCase() : 'region';
  }

  /// City count for a region from the summary, else from a loaded list.
  int? cityCount(String? country, String region) {
    final c = country == null ? null : _summary[country];
    final regions = c is Map ? c['regions'] : null;
    final v = regions is Map ? regions[region] : null;
    if (v is num) return v.toInt();
    return _cities[region]?.length;
  }

  /// Loads countries and regions (and the optional summary) once.
  Future<void> load({bool force = false}) {
    if (isLoaded && !force) return Future<void>.value();
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<void> _load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final summaryFuture = api.getLocationsSummary().then<Map<String, dynamic>?>(
            (v) => v,
            onError: (Object _) => null,
          );
      final results = await Future.wait<Object>([api.getCountries(), api.getStates()]);
      final countries = results[0] as List<String>;
      final regions = results[1] as Map<String, List<String>>;
      if (countries.isEmpty) throw StateError('No countries');
      _summary = (await summaryFuture) ?? const {};
      _countries = countries;
      _regions = regions;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  List<String>? citiesIfLoaded(String region) => _cities[region];
  Object? cityError(String region) => _cityErrors[region];
  bool isLoadingCities(String region) => _cityInFlight.containsKey(region);

  /// Cities of [region] ("Name, Region" strings, server order).
  Future<List<String>> loadCities(String region, {bool force = false}) {
    final cached = _cities[region];
    if (cached != null && !force) return Future<List<String>>.value(cached);
    final existing = _cityInFlight[region];
    if (existing != null) return existing;
    _cityErrors.remove(region);
    final future = _fetchCities(region);
    _cityInFlight[region] = future;
    return future;
  }

  Future<List<String>> _fetchCities(String region) async {
    try {
      final raw = await api.getCities(region);
      final seen = <String>{};
      final list = <String>[];
      for (final c in raw) {
        final s = SearchSetupProvider.formatCity(c, region);
        if (s.isNotEmpty && seen.add(cityKey(s))) list.add(s);
      }
      _cities[region] = list;
      _cityKeys[region] = seen;
      return list;
    } catch (e) {
      _cityErrors[region] = e;
      rethrow;
    } finally {
      _cityInFlight.remove(region);
      notifyListeners();
    }
  }

  /// True when [city] belongs to [region]: its suffix is the region, or the
  /// region's loaded list contains it ("Al Hamra, Jeddah" in Makkah Region).
  bool cityInRegion(String city, String region) {
    if ((SearchSetupProvider.regionOf(city) ?? '').toLowerCase() == region.toLowerCase()) return true;
    return _cityKeys[region]?.contains(cityKey(city)) ?? false;
  }

  /// The region a selected city belongs to (a loaded list containing it,
  /// else its suffix).
  String? regionForCity(String city) {
    final key = cityKey(city);
    for (final e in _cityKeys.entries) {
      if (e.value.contains(key)) return e.key;
    }
    return SearchSetupProvider.regionOf(city);
  }

  /// The country a selected city belongs to, falling back to [fallback]
  /// when its region is unknown.
  String? countryForCity(String city, {String? fallback}) =>
      countryOfRegion(regionForCity(city)) ?? fallback;

  bool _inAnyLoadedList(String key) {
    for (final keys in _cityKeys.values) {
      if (keys.contains(key)) return true;
    }
    return false;
  }

  /// Regions whose lists decide whether [city] is listed: its suffix region
  /// when that is a region we offer; otherwise (a few cities carry a district
  /// or the country as suffix, e.g. "Al Hamra, Jeddah" in Makkah Region)
  /// every region of [country].
  Set<String> _candidateRegions(String city, String? country) {
    final suffix = SearchSetupProvider.regionOf(city);
    if (suffix == null) return const <String>{};
    if (countryOfRegion(suffix) != null) return {suffix};
    return regionsOf(country).toSet();
  }

  /// True when [city] is confirmed absent from the current lists, false when
  /// it is listed, null while undecided (lists loading or failed, or no way
  /// to tell which lists to check). Never guesses "no longer listed".
  bool? isNoLongerListed(String city, {String? country}) {
    if (!isLoaded) return null;
    if (_inAnyLoadedList(cityKey(city))) return false;
    // Every listed city is "Name, Region": text without a region is not in
    // our lists.
    if (SearchSetupProvider.regionOf(city) == null) return true;
    final candidates = _candidateRegions(city, country);
    if (candidates.isEmpty) return null;
    for (final r in candidates) {
      if (!_cityKeys.containsKey(r)) return null;
    }
    return true;
  }

  /// Starts loading every region needed to check [cities] (no-op for
  /// regions already loaded, loading or failed). Safe to call from build.
  void prefetchFor(Iterable<String> cities, {String? country}) {
    if (!isLoaded) return;
    final regions = <String>{};
    for (final c in cities) {
      if (_inAnyLoadedList(cityKey(c))) continue;
      for (final r in _candidateRegions(c, country)) {
        if (_cities.containsKey(r) || _cityInFlight.containsKey(r) || _cityErrors.containsKey(r)) {
          continue;
        }
        regions.add(r);
      }
    }
    for (final r in regions) {
      loadCities(r).then((_) {}, onError: (Object _) {});
    }
  }

  /// Selected cities that are confirmed to be no longer listed.
  List<String> noLongerListed(Iterable<String> cities, {String? country}) =>
      cities.where((c) => isNoLongerListed(c, country: country) == true).toList();
}

// --------------------------------------------------------------- estimate

/// Maximum charge from POST /api/credits/estimate, debounced (300 ms) with
/// stale responses ignored. Only for signed-in users (the endpoint needs a
/// session); [estimate] stays null otherwise.
class CostEstimator with ChangeNotifier {
  CostEstimator(this.api, {this.debounce = const Duration(milliseconds: 300)});

  final ApiService api;
  final Duration debounce;

  Timer? _timer;
  int _seq = 0;
  int? _cities;
  int? _maxResults;
  int? _estimate;
  int? _currentBalance;
  bool _loading = false;
  Object? _error;
  bool _disposed = false;

  /// Estimated (maximum) charge for the last requested inputs.
  int? get estimate => _estimate;

  /// `current_balance` reported with the estimate, when present.
  int? get currentBalance => _currentBalance;
  bool get loading => _loading;
  Object? get error => _error;

  /// Asks for the cost of [numCities] × [maxResults]. Same inputs as the
  /// last request do nothing (unless [force]).
  void request({required int numCities, required int maxResults, bool force = false}) {
    if (!force && numCities == _cities && maxResults == _maxResults) return;
    _cities = numCities;
    _maxResults = maxResults;
    _timer?.cancel();
    _seq++;
    if (numCities <= 0) {
      _estimate = null;
      _error = null;
      _loading = false;
      _notify();
      return;
    }
    _estimate = null;
    _error = null;
    _loading = true;
    _notify();
    final seq = _seq;
    _timer = Timer(debounce, () => _fetch(seq, numCities, maxResults));
  }

  void retry() {
    final c = _cities;
    final m = _maxResults;
    if (c == null || m == null) return;
    request(numCities: c, maxResults: m, force: true);
  }

  /// Signed out: forget everything.
  void reset() {
    _timer?.cancel();
    _seq++;
    _cities = null;
    _maxResults = null;
    _estimate = null;
    _currentBalance = null;
    _error = null;
    _loading = false;
    _notify();
  }

  Future<void> _fetch(int seq, int numCities, int maxResults) async {
    try {
      final data = await api.estimateJobCost(numCities: numCities, maxResultsPerCity: maxResults);
      if (seq != _seq || _disposed) return;
      final v = data['estimated_cost'];
      _estimate = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
      final b = data['current_balance'];
      _currentBalance = b is num ? b.toInt() : null;
      _error = _estimate == null ? StateError('No estimate') : null;
    } catch (e) {
      if (seq != _seq || _disposed) return;
      _estimate = null;
      _error = e;
    }
    _loading = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

// ------------------------------------------------------------- navigation

/// Route arguments marking a page pushed by Find leads itself, so "up"
/// can pop instead of pushing a duplicate.
const Map<String, Object> findChildArgs = {'findChild': true};

bool isFindChild(BuildContext context) {
  final args = ModalRoute.of(context)?.settings.arguments;
  return args is Map && args['findChild'] == true;
}

/// "/find", "/find?country=Canada", "/find?country=Canada&region=Quebec".
String findUrl({String? country, String? region}) {
  if (country == null) return '/find';
  final q = <String, String>{'country': country, if (region != null) 'region': region};
  return Uri(path: '/find', queryParameters: q).toString();
}

/// Goes to the parent level: pops when this page was pushed by Find leads,
/// otherwise (deep link, refresh) replaces it with [parentUrl].
void goUpTo(BuildContext context, String parentUrl) {
  final nav = Navigator.of(context);
  if (isFindChild(context) && nav.canPop()) {
    nav.pop();
  } else {
    nav.pushReplacementNamed(parentUrl);
  }
}

// ---------------------------------------------------------------- widgets

const TextStyle findTitleStyle = TextStyle(color: UiTokens.text, fontSize: 18, fontWeight: FontWeight.w700);
const TextStyle findBodyStyle = TextStyle(color: UiTokens.text, fontSize: 14);
const TextStyle findSecondaryStyle = TextStyle(color: UiTokens.textSecondary, fontSize: 13);
const TextStyle findMutedStyle = TextStyle(color: UiTokens.textMuted, fontSize: 12);

BoxDecoration findCardDecoration({Color? border}) => BoxDecoration(
      color: UiTokens.card,
      borderRadius: BorderRadius.circular(UiTokens.radius),
      border: Border.all(color: border ?? UiTokens.border),
    );

/// Setup steps "1 Location · 2 Details & start" (named steps, no %).
class FindSteps extends StatelessWidget {
  final int current;
  final VoidCallback? onLocation;

  const FindSteps({super.key, required this.current, this.onLocation});

  @override
  Widget build(BuildContext context) {
    Widget step(int n, String label, {VoidCallback? onTap}) {
      final done = n < current;
      final active = n == current;
      final circle = Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? UiTokens.primary : Colors.transparent,
          border: Border.all(
            color: done ? UiTokens.completedFg : (active ? UiTokens.primary : UiTokens.textMuted),
          ),
        ),
        child: done
            ? const Icon(Icons.check_rounded, size: 14, color: UiTokens.completedFg)
            : Text('$n',
                style: TextStyle(
                  color: active ? Colors.white : UiTokens.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                )),
      );
      final content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          circle,
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: active ? UiTokens.text : UiTokens.textSecondary,
              fontSize: 14,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      );
      final semantic = '$label, step $n of 2${done ? ', done' : ''}${active ? ', current step' : ''}';
      if (onTap == null) {
        return Semantics(label: semantic, excludeSemantics: true, child: content);
      }
      return Semantics(
        label: semantic,
        button: true,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4), child: content),
        ),
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        step(1, 'Location', onTap: current > 1 ? onLocation : null),
        Container(width: 28, height: 1, color: UiTokens.border),
        step(2, 'Details & start'),
      ],
    );
  }
}

/// Outline of text fields in Find leads: 3.6:1 against the card and 4.1:1
/// against the field fill (WCAG 1.4.11), unlike [UiTokens.border] (≈1.4:1).
const Color findFieldBorder = Color(0xFF737A85);

/// Keyboard focus ring for rows and chips (7.7:1 on the card).
const Color findFocusRing = UiTokens.accent;

/// Text field borders shared by the Find leads steps.
InputDecoration findFieldDecoration({String? hintText, Widget? prefixIcon, Widget? suffixIcon}) => InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: UiTokens.textMuted, fontSize: 14),
      filled: true,
      fillColor: UiTokens.background,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: findFieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: findFocusRing, width: 2),
      ),
    );

/// Search box. Enter never submits the step (it keeps focus).
class FindSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;

  const FindSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) {},
        onEditingComplete: () {},
        style: findBodyStyle,
        cursorColor: UiTokens.accent,
        decoration: findFieldDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: UiTokens.textSecondary),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.close_rounded, size: 20, color: UiTokens.textSecondary),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                    focusNode?.requestFocus();
                  },
                ),
        ),
      ),
    );
  }
}

/// A selectable row (country, region or city) that keeps keyboard,
/// pointer and screen-reader focus in step:
///
/// * one focus stop with a visible 2 px ring in keyboard mode; Enter and
///   Space activate it (via [InkWell]);
/// * activating it — click, tap, key or the screen reader's tap action —
///   moves focus to the row. Without that, a screen-reader tap left Flutter's
///   focus on the previously focused text field while the browser had
///   already moved DOM focus to the row, so the field's editing session was
///   closed by the engine but never reopened: typing into it was lost.
/// * its semantics node is focusable, so the browser's focus and Flutter's
///   agree when the row is reached with a screen reader.
class FindRow extends StatefulWidget {
  final String semanticLabel;
  final VoidCallback onActivate;
  final Widget child;

  /// Non-null for checkbox rows (city rows).
  final bool? checked;

  /// Current item (region shown, country of the selection).
  final bool selected;

  final Color color;
  final BorderSide side;
  final BorderRadius borderRadius;

  const FindRow({
    super.key,
    required this.semanticLabel,
    required this.onActivate,
    required this.child,
    this.checked,
    this.selected = false,
    this.color = Colors.transparent,
    this.side = BorderSide.none,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  State<FindRow> createState() => _FindRowState();
}

class _FindRowState extends State<FindRow> {
  final FocusNode _focus = FocusNode(debugLabel: 'find row');
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _activate() {
    if (!_focus.hasFocus) _focus.requestFocus();
    widget.onActivate();
  }

  @override
  Widget build(BuildContext context) {
    final ring = _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Semantics(
      container: true,
      button: widget.checked == null,
      checked: widget.checked,
      selected: widget.checked == null ? widget.selected : null,
      focusable: true,
      focused: _focused,
      label: widget.semanticLabel,
      excludeSemantics: true,
      onTap: _activate,
      onFocus: () => _focus.requestFocus(),
      child: Material(
        color: widget.color,
        shape: RoundedRectangleBorder(
          borderRadius: widget.borderRadius,
          side: ring ? const BorderSide(color: findFocusRing, width: 2) : widget.side,
        ),
        child: InkWell(
          focusNode: _focus,
          borderRadius: widget.borderRadius,
          focusColor: Colors.transparent,
          onFocusChange: (v) => setState(() => _focused = v),
          onTap: _activate,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Flag + full country name ("[CA] Canada"); the flag is decorative and the
/// name wraps instead of truncating.
class FindCountryLabel extends StatelessWidget {
  final String countryKey;
  final TextStyle style;
  final double flagSize;
  final int? maxLines;

  const FindCountryLabel({
    super.key,
    required this.countryKey,
    this.style = const TextStyle(color: UiTokens.text, fontSize: 14, fontWeight: FontWeight.w600),
    this.flagSize = 16,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CountryFlagBadge(countryName: countryKey, size: flagSize),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            countryDisplayName(countryKey),
            style: style,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// One-line notice (info / warning) with an optional action.
class FindNotice extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;
  final Widget? action;

  const FindNotice({
    super.key,
    required this.text,
    this.icon = Icons.info_outline_rounded,
    this.color = UiTokens.partialFg,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color == UiTokens.partialFg ? UiTokens.partialBg : UiTokens.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: UiTokens.text, fontSize: 13))),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ],
      ),
    );
  }
}

/// "No longer listed" tag (word + icon, never colour alone).
class NoLongerListedTag extends StatelessWidget {
  const NoLongerListedTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: UiTokens.partialBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: UiTokens.partialFg.withValues(alpha: 0.5)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 12, color: UiTokens.partialFg),
          SizedBox(width: 3),
          Text('No longer listed', style: TextStyle(color: UiTokens.partialFg, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// "{n} of your cities are no longer in our list. They may return no results."
String noLongerListedNotice(int n) => n == 1
    ? '1 of your cities is no longer in our list. It may return no results.'
    : '${formatCount(n)} of your cities are no longer in our list. They may return no results.';

/// A removable city chip (remove target ≥ 32 px).
class CityChip extends StatelessWidget {
  final String city;
  final String label;
  final bool noLongerListed;
  final String? note;
  final VoidCallback onRemove;

  const CityChip({
    super.key,
    required this.city,
    required this.label,
    required this.onRemove,
    this.noLongerListed = false,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: UiTokens.background,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: noLongerListed ? UiTokens.partialFg.withValues(alpha: 0.6) : UiTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: UiTokens.text, fontSize: 13)),
          ),
          if (note != null) ...[
            const SizedBox(width: 6),
            Text(note!, style: findMutedStyle),
          ],
          if (noLongerListed) ...[const SizedBox(width: 6), const NoLongerListedTag()],
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'Remove $label',
              iconSize: 16,
              icon: const Icon(Icons.close_rounded, color: UiTokens.textSecondary),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- dialogs

/// Confirmation dialog: neutral "keep" action and a destructive action
/// (filled red only inside confirm dialogs). Returns true on confirm.
Future<bool> confirmFindAction(
  BuildContext context, {
  required String title,
  required String message,
  required String keepLabel,
  required String confirmLabel,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: UiTokens.card,
      title: Text(title, style: const TextStyle(color: UiTokens.text)),
      content: Text(message, style: const TextStyle(color: UiTokens.textSecondary)),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(keepLabel, style: const TextStyle(color: UiTokens.accent)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: UiTokens.failedFg, foregroundColor: Colors.black),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// "Clear all": asks first when more than 5 cities are selected.
Future<void> confirmClearAll(BuildContext context, SearchSetupProvider setup) async {
  final k = setup.cityCount;
  if (k == 0) return;
  if (k > 5) {
    final ok = await confirmFindAction(
      context,
      title: 'Clear all ${formatCount(k)} selected cities?',
      message: 'This removes every city from this search.',
      keepLabel: 'Keep',
      confirmLabel: 'Clear all',
    );
    if (!ok) return;
  }
  setup.clearAll();
}

// ------------------------------------------------------------ text input

/// Input formatter limiting text to [max] characters.
List<TextInputFormatter> maxLength(int max) => [LengthLimitingTextInputFormatter(max)];
