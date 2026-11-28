import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_breakpoints.dart';
import '../../providers/auth_provider.dart';
import '../../providers/search_setup_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/app_shell_common.dart';
import '../../widgets/country_flag_badge.dart';
import 'find_common.dart';
import 'selection_bar.dart';

/// Find leads — step 1 (Location), plan §6.2–6.3. Page body only.
///
/// Levels follow the URL so browser Back goes up a level:
/// * `/find` — countries (search, recents, compact rows);
/// * `/find?country=X` — desktop/tablet: split panel (regions + cities);
///   phone: region list;
/// * `/find?country=X&region=Y` — phone: city list (desktop: split panel
///   with Y highlighted).
///
/// Selections live in [SearchSetupProvider], which never drops cities by
/// itself: this page asks before switching region or country (and before
/// "Clear all" with more than 5 cities) and then calls `discardCities`.
class FindLocationStep extends StatefulWidget {
  /// Optional API (tests); defaults to the app's shared catalog.
  final ApiService? api;

  const FindLocationStep({super.key, this.api});

  @override
  State<FindLocationStep> createState() => _FindLocationStepState();
}

class _RecentPlace {
  final String? country;
  final String region;
  final bool available;

  const _RecentPlace(this.country, this.region, this.available);

  String get label {
    final c = country == null ? null : countryDisplayName(country);
    return c == null ? region : '$c · $region';
  }
}

class _FindLocationStepState extends State<FindLocationStep> {
  late final LocationCatalog _catalog;
  late final CostEstimator _estimator;
  late final SearchSetupProvider _setup;
  late final AuthProvider _auth;

  final _countryQuery = TextEditingController();
  final _regionQuery = TextEditingController();
  final _cityQuery = TextEditingController();
  final _citySearchFocus = FocusNode(debugLabel: 'city search');
  String _countryFilter = '';
  String _regionFilter = '';
  String _cityFilter = '';

  bool _parsedUrl = false;
  String? _urlCountry;
  String? _urlRegion;
  bool _synced = false;

  List<Map<String, dynamic>>? _recentJobs;
  bool _recentsRequested = false;

  @override
  void initState() {
    super.initState();
    _catalog = LocationCatalog.of(widget.api);
    _estimator = CostEstimator(widget.api ?? ApiService());
    _setup = context.read<SearchSetupProvider>();
    _auth = context.read<AuthProvider>();
    _setup.addListener(_onInputsChanged);
    _auth.addListener(_onAuthChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_parsedUrl) return;
    _parsedUrl = true;
    final name = ModalRoute.of(context)?.settings.name ?? '';
    final uri = Uri.tryParse(name);
    final q = uri?.queryParameters ?? const <String, String>{};
    _urlCountry = _clean(q['country']);
    _urlRegion = _urlCountry == null ? null : _clean(q['region']);
  }

  static String? _clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

  @override
  void dispose() {
    _setup.removeListener(_onInputsChanged);
    _auth.removeListener(_onAuthChanged);
    _estimator.dispose();
    _countryQuery.dispose();
    _regionQuery.dispose();
    _cityQuery.dispose();
    _citySearchFocus.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (!mounted) return;
    await Future.wait([_catalog.load(), _setup.load()]);
    if (!mounted) return;
    _onInputsChanged();
    _loadRecents();
    await _syncFromUrl();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (!_auth.isAuthenticated) {
      _estimator.reset();
      setState(() => _recentJobs = null);
      _recentsRequested = false;
    } else {
      _onInputsChanged();
      _loadRecents();
    }
  }

  void _onInputsChanged() {
    if (!mounted) return;
    if (!_auth.isAuthenticated) return;
    _estimator.request(numCities: _setup.cityCount, maxResults: _setup.maxResultsPerCity);
  }

  Future<void> _loadRecents() async {
    if (_recentsRequested || !_auth.isAuthenticated) return;
    _recentsRequested = true;
    try {
      final data = await _catalog.api.getJobs(limit: 20);
      final jobs = data['jobs'];
      if (!mounted) return;
      setState(() => _recentJobs = jobs is List ? jobs.whereType<Map<String, dynamic>>().toList() : const []);
    } catch (_) {
      // Recents are a shortcut; without them the page works the same.
    }
  }

  List<_RecentPlace> _recentPlaces() {
    final jobs = _recentJobs;
    if (jobs == null || !_catalog.isLoaded) return const [];
    final seen = <String>{};
    final out = <_RecentPlace>[];
    for (final job in jobs) {
      final region = jobRegion(job);
      if (region == null) continue;
      final country = jobCountry(job) ?? _catalog.countryOfRegion(region);
      if (!seen.add('${country ?? ''}|$region')) continue;
      final available = country != null && _catalog.regionExists(country, region);
      out.add(_RecentPlace(country, region, available));
      if (out.length >= 5) break;
    }
    return out;
  }

  // -------------------------------------------------------------- helpers

  bool get _isPhone => MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;

  /// Country of the current selection (for "No longer listed" checks).
  String? get _selectionCountry => _setup.country ?? _catalog.countryOfRegion(_setup.region);

  List<String> _citiesOutsideCountry(String country) => _setup.cities
      .where((c) => _catalog.countryForCity(c, fallback: _setup.country) != country)
      .toList();

  List<String> _citiesOutsideRegion(String region) =>
      _setup.cities.where((c) => !_catalog.cityInRegion(c, region)).toList();

  /// Asks before dropping cities outside [country]. False = keep everything.
  Future<bool> _confirmCountry(String country) async {
    final outside = _citiesOutsideCountry(country);
    if (outside.isEmpty) return true;
    final current = countryDisplayName(
      _setup.country ?? _catalog.countryForCity(outside.first) ?? '',
    );
    final k = outside.length;
    final hasName = current.isNotEmpty;
    final ok = await confirmFindAction(
      context,
      title: 'Change country?',
      message: hasName
          ? 'Your ${formatCount(k)} selected ${k == 1 ? 'city' : 'cities'} in $current will be removed.'
          : 'Your ${formatCount(k)} selected ${k == 1 ? 'city' : 'cities'} will be removed.',
      keepLabel: hasName ? 'Keep $current' : 'Keep',
      confirmLabel: 'Change country',
    );
    if (ok) _setup.discardCities(outside);
    return ok;
  }

  /// Asks before dropping cities outside [region]. False = keep everything.
  Future<bool> _confirmRegion(String region) async {
    final outside = _citiesOutsideRegion(region);
    if (outside.isEmpty) return true;
    final oldRegions = outside.map((c) => _catalog.regionForCity(c)).toSet();
    final old = oldRegions.length == 1 ? oldRegions.first : null;
    final k = outside.length;
    final what = old == null
        ? '${formatCount(k)} ${k == 1 ? 'city' : 'cities'} outside $region'
        : '${formatCount(k)} $old ${k == 1 ? 'city' : 'cities'}';
    final ok = await confirmFindAction(
      context,
      title: 'Switch to $region?',
      message: 'Your $what will be removed from this search.',
      keepLabel: old == null ? 'Stay' : 'Stay in $old',
      confirmLabel: 'Switch and remove',
    );
    if (ok) _setup.discardCities(outside);
    return ok;
  }

  /// Applies the URL level to the setup (deep link / refresh). Navigation
  /// inside the page sets the setup before pushing, so this is a no-op then.
  Future<void> _syncFromUrl() async {
    if (_synced) return;
    _synced = true;
    final country = _urlCountry;
    if (country == null || !_catalog.hasCountry(country)) return;
    if (_setup.country != country) {
      if (!await _confirmCountry(country)) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed(findUrl(country: _selectionCountry));
        }
        return;
      }
      _setup.setCountry(country);
    }
    final region = _urlRegion;
    if (region != null && _catalog.regionExists(country, region) && _setup.region != region) {
      if (!await _confirmRegion(region)) {
        if (mounted) {
          final keep = _setup.region;
          final keepOk = keep != null && _catalog.regionExists(country, keep);
          Navigator.of(context).pushReplacementNamed(
            findUrl(country: country, region: _isPhone && keepOk ? keep : null),
          );
        }
        return;
      }
      _setup.setRegion(region);
    }
    if (_setup.region != null) _catalog.loadCities(_setup.region!).ignore();
  }

  // ------------------------------------------------------------- actions

  Future<void> _pickCountry(String country) async {
    if (!await _confirmCountry(country)) return;
    if (!mounted) return;
    _setup.setCountry(country);
    _regionQuery.clear();
    _regionFilter = '';
    Navigator.of(context).pushNamed(findUrl(country: country), arguments: findChildArgs);
  }

  Future<void> _pickRegion(String country, String region, {bool push = false}) async {
    if (!await _confirmRegion(region)) return;
    if (!mounted) return;
    _setup.setRegion(region);
    _catalog.loadCities(region).ignore();
    setState(() {
      _cityQuery.clear();
      _cityFilter = '';
    });
    if (push) {
      Navigator.of(context).pushNamed(findUrl(country: country, region: region), arguments: findChildArgs);
      return;
    }
    // Keyboard flow: region list -> this region's city search.
    try {
      await _catalog.loadCities(region);
    } catch (_) {
      return;
    }
    if (!mounted || _setup.region != region) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _citySearchFocus.requestFocus();
    });
  }

  Future<void> _openRecent(_RecentPlace place) async {
    final country = place.country;
    if (!place.available || country == null) return;
    if (!await _confirmCountry(country)) return;
    if (!await _confirmRegion(place.region)) return;
    if (!mounted) return;
    _setup.setCountry(country);
    _setup.setRegion(place.region);
    _catalog.loadCities(place.region).ignore();
    Navigator.of(context).pushNamed(findUrl(country: country, region: place.region), arguments: findChildArgs);
  }

  void _continueDraft() {
    final country = _selectionCountry;
    if (country == null || !_catalog.hasCountry(country)) return;
    final region = _setup.region;
    final regionOk = region != null && _catalog.regionExists(country, region);
    if (_setup.country != country) _setup.setCountry(country);
    if (regionOk && _setup.region != region) _setup.setRegion(region);
    Navigator.of(context).pushNamed(
      findUrl(country: country, region: regionOk ? region : null),
      arguments: findChildArgs,
    );
  }

  Future<void> _startOver() async {
    final k = _setup.cityCount;
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
    _setup.clearAll();
    _setup.setCountry(null);
  }

  void _continue() {
    Navigator.of(context).pushNamed('/find/details', arguments: findChildArgs);
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final setup = context.watch<SearchSetupProvider>();
    final signedIn = context.watch<AuthProvider>().isAuthenticated;
    return ListenableBuilder(
      listenable: Listenable.merge([_catalog, _estimator]),
      builder: (context, _) {
        final country = _selectionCountry;
        _catalog.prefetchFor(setup.cities, country: country);
        final unlisted = _catalog.noLongerListed(setup.cities, country: country);
        return Column(
          children: [
            Expanded(child: _content(setup, unlisted, signedIn)),
            FindSelectionBar(
              catalog: _catalog,
              estimate: signedIn ? _estimator.estimate : null,
              country: country,
              onContinue: _continue,
            ),
          ],
        );
      },
    );
  }

  Widget _content(SearchSetupProvider setup, List<String> unlisted, bool signedIn) {
    if (!_catalog.isLoaded) {
      if (_catalog.error != null && !_catalog.isLoading) return _loadError();
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: UiTokens.accent),
            SizedBox(height: 12),
            Text('Loading locations…', style: findSecondaryStyle),
          ],
        ),
      );
    }
    final country = _urlCountry;
    if (country == null) return _countryLevel(setup, unlisted, signedIn);
    if (!_catalog.hasCountry(country)) return _unknownCountry(country);
    if (_isPhone) {
      final region = _urlRegion;
      if (region == null) return _phoneRegionLevel(setup, country, unlisted);
      if (!_catalog.regionExists(country, region)) return _unknownRegion(country, region);
      return _phoneCityLevel(setup, country, region, unlisted);
    }
    return _splitLevel(setup, country, unlisted);
  }

  Widget _loadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: UiTokens.textSecondary, size: 32),
            const SizedBox(height: 12),
            const Text("Locations didn't load.", style: findTitleStyle, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: UiTokens.primary, minimumSize: const Size(120, 44)),
              onPressed: () => _catalog.load(force: true),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _unknownCountry(String country) {
    return _messageWithAction(
      "We don't have locations for “$country”.",
      'See all countries',
      () => goUpTo(context, '/find'),
    );
  }

  Widget _unknownRegion(String country, String region) {
    final term = _catalog.regionTerm(country);
    return _messageWithAction(
      '“$region” is no longer available.',
      'See all ${pluralTerm(term)}',
      () => goUpTo(context, findUrl(country: country)),
    );
  }

  Widget _messageWithAction(String message, String action, VoidCallback onPressed) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, style: findTitleStyle, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(64, 44)),
              onPressed: onPressed,
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }

  EdgeInsets get _pagePadding => EdgeInsets.fromLTRB(_isPhone ? 16 : 24, 16, _isPhone ? 16 : 24, 16);

  // ------------------------------------------------------- country level

  /// Cities in a country, from the summary (0 when the summary is missing).
  int _cityTotal(String country) {
    var total = 0;
    for (final r in _catalog.regionsOf(country)) {
      total += _catalog.cityCount(country, r) ?? 0;
    }
    return total;
  }

  /// Regions (states, provinces...) of any country whose name matches [q].
  List<(String country, String region)> _regionMatches(String q) {
    if (q.length < 2) return const [];
    final out = <(String, String)>[];
    for (final c in _catalog.countries) {
      for (final r in _catalog.regionsOf(c)) {
        if (r.toLowerCase().contains(q)) out.add((c, r));
      }
    }
    out.sort((x, y) {
      final sx = x.$2.toLowerCase().startsWith(q) ? 0 : 1;
      final sy = y.$2.toLowerCase().startsWith(q) ? 0 : 1;
      return sx != sy ? sx - sy : x.$2.compareTo(y.$2);
    });
    return out.length > 12 ? out.sublist(0, 12) : out;
  }

  Widget _countryLevel(SearchSetupProvider setup, List<String> unlisted, bool signedIn) {
    final width = MediaQuery.sizeOf(context).width;
    final showAside = width >= 1320;
    final q = _countryFilter.trim().toLowerCase();
    final countries = _catalog.countries
        .where((c) => q.isEmpty || c.toLowerCase().contains(q) || countryDisplayName(c).toLowerCase().contains(q))
        .toList();
    final regionHits = _regionMatches(q);
    final recents = signedIn ? _recentPlaces() : const <_RecentPlace>[];
    final draftCountry = _selectionCountry;
    final showDraft = setup.cities.isNotEmpty && draftCountry != null && _catalog.hasCountry(draftCountry);
    var regionTotal = 0, cityTotal = 0;
    for (final c in _catalog.countries) {
      regionTotal += _catalog.regionsOf(c).length;
      cityTotal += _cityTotal(c);
    }

    final list = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: _pagePadding.copyWith(bottom: 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FindSteps(current: 1),
                const SizedBox(height: 18),
                Semantics(
                  header: true,
                  child: Text('Where do you want leads?',
                      style: findTitleStyle.copyWith(fontSize: _isPhone ? 22 : 28, letterSpacing: -0.5, height: 1.15)),
                ),
                const SizedBox(height: 6),
                Text(
                  cityTotal > 0
                      ? 'Start with a country, then pick its states and cities. '
                          '${formatCount(_catalog.countries.length)} countries, ${formatCount(regionTotal)} regions and '
                          '${formatCount(cityTotal)} cities to choose from.'
                      : 'Start with a country, then pick its states and cities.',
                  style: findSecondaryStyle.copyWith(fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 16),
                FindSearchField(
                  controller: _countryQuery,
                  hint: 'Search a country, state or region',
                  onChanged: (v) => setState(() => _countryFilter = v),
                ),
                if (showDraft) ...[
                  const SizedBox(height: 12),
                  _draftBanner(setup, draftCountry),
                ],
                if (unlisted.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _unlistedNotice(unlisted, draftCountry),
                ],
                if (recents.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Recent', style: findSecondaryStyle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final r in recents) _recentChip(r)],
                  ),
                ],
                if (regionHits.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text('States and regions matching “${_countryFilter.trim()}”', style: findSecondaryStyle),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [for (final hit in regionHits) _regionHit(hit.$1, hit.$2)],
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  q.isEmpty
                      ? 'All countries (${_catalog.countries.length})'
                      : '${countries.length} of ${_catalog.countries.length} countries match “${_countryFilter.trim()}”',
                  style: findSecondaryStyle,
                ),
                const SizedBox(height: 10),
                if (countries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      regionHits.isEmpty
                          ? 'No country matches your search.'
                          : 'No country has that name. Pick one of the regions above.',
                      style: findSecondaryStyle,
                    ),
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: _pagePadding.copyWith(top: 0, bottom: 28),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _isPhone ? 600 : 330,
              mainAxisExtent: 80,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _countryRow(countries[i], setup),
              childCount: countries.length,
            ),
          ),
        ),
      ],
    );

    if (!showAside) return list;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: list),
        SizedBox(
          width: 332,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 16, 24, 24),
            child: _guidePanel(signedIn),
          ),
        ),
      ],
    );
  }

  /// A region found by the search: opens that region directly.
  Widget _regionHit(String country, String region) {
    final cities = _catalog.cityCount(country, region);
    final label = '$region, ${countryDisplayName(country)}';
    return Semantics(
      button: true,
      label: cities == null ? label : '$label, ${citiesLabel(cities)}',
      excludeSemantics: true,
      child: ActionChip(
        avatar: CountryFlagBadge(countryName: country, size: 14),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        label: Text(cities == null ? label : '$label · ${formatCount(cities)}'),
        labelStyle: const TextStyle(color: UiTokens.text, fontSize: 13),
        backgroundColor: UiTokens.card,
        side: const BorderSide(color: UiTokens.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        onPressed: () async {
          await _pickCountry(country);
          if (mounted) await _pickRegion(country, region, push: _isPhone);
        },
      ),
    );
  }

  /// Wide screens: what happens next and what a lead contains.
  Widget _guidePanel(bool signedIn) {
    Widget card({required Widget child}) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: UiTokens.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: UiTokens.border),
          ),
          child: child,
        );
    Widget step(int n, String title, String text, {bool current = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: current ? UiTokens.accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: current ? UiTokens.accent : UiTokens.border),
                ),
                child: Text('$n',
                    style: TextStyle(
                        color: current ? const Color(0xFF06181D) : UiTokens.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: current ? UiTokens.text : UiTokens.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(text, style: const TextStyle(color: UiTokens.textMuted, fontSize: 12.5, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        );
    Widget included(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Row(
            children: [
              Icon(icon, size: 16, color: UiTokens.completedFg),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13))),
            ],
          ),
        );
    const heading = TextStyle(color: UiTokens.text, fontSize: 14.5, fontWeight: FontWeight.w700);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('How a search works', style: heading),
              const SizedBox(height: 14),
              step(1, 'Choose where', 'A country, then its states and cities.', current: true),
              step(2, 'Say who', 'The kind of business and how many results per city.'),
              step(3, 'Get the list', 'It runs on our servers; download it as Excel or CSV.'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Every lead includes', style: heading),
              const SizedBox(height: 12),
              included(Icons.storefront_outlined, 'Business name and category'),
              included(Icons.call_outlined, 'Phone number'),
              included(Icons.language_rounded, 'Website'),
              included(Icons.mail_outline_rounded, 'Email, when the business lists one'),
              included(Icons.place_outlined, 'Address, city and state'),
              included(Icons.map_outlined, 'Google Maps link'),
            ],
          ),
        ),
        if (!signedIn) ...[
          const SizedBox(height: 12),
          card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Just looking?', style: heading),
                const SizedBox(height: 6),
                const Text(
                  'You can set up a whole search without an account. You only need one to run it.',
                  style: TextStyle(color: UiTokens.textSecondary, fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: UiTokens.accent,
                      side: const BorderSide(color: UiTokens.border),
                      minimumSize: const Size(64, 42),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.of(context).pushNamed('/register'),
                    child: const Text('Create a free account'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _draftBanner(SearchSetupProvider setup, String country) {
    final region = setup.region;
    final place = (region != null && _catalog.regionExists(country, region)) ? region : countryDisplayName(country);
    return FindNotice(
      icon: Icons.history_rounded,
      color: UiTokens.accent,
      text: 'Continue where you left off: ${citiesLabel(setup.cities.length)} in $place',
      action: Wrap(
        spacing: 4,
        children: [
          TextButton(
            style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(64, 40)),
            onPressed: _continueDraft,
            child: const Text('Continue'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: UiTokens.textSecondary, minimumSize: const Size(64, 40)),
            onPressed: _startOver,
            child: const Text('Start over'),
          ),
        ],
      ),
    );
  }

  Widget _unlistedNotice(List<String> unlisted, String? country) {
    return FindNotice(
      icon: Icons.warning_amber_rounded,
      text: noLongerListedNotice(unlisted.length),
      action: TextButton(
        style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(64, 40)),
        onPressed: () => showReviewList(context, catalog: _catalog, country: country),
        child: const Text('Review list'),
      ),
    );
  }

  Widget _recentChip(_RecentPlace r) {
    final label = r.available ? r.label : '${r.label} — No longer available';
    return Semantics(
      button: true,
      enabled: r.available,
      label: r.available ? 'Recent: ${r.label}' : 'Recent: ${r.label}, no longer available',
      excludeSemantics: true,
      child: ActionChip(
        avatar: r.country == null ? null : CountryFlagBadge(countryName: r.country, size: 14),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        label: Text(label),
        labelStyle: TextStyle(color: r.available ? UiTokens.text : UiTokens.textMuted, fontSize: 13),
        backgroundColor: UiTokens.background,
        disabledColor: UiTokens.background,
        side: const BorderSide(color: UiTokens.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        onPressed: r.available ? () => _openRecent(r) : null,
      ),
    );
  }

  Widget _countryRow(String key, SearchSetupProvider setup) {
    final name = countryDisplayName(key);
    final n = _catalog.regionsOf(key).length;
    final countText = termCount(n, _catalog.regionTerm(key));
    final cities = _cityTotal(key);
    final current = key == _selectionCountry && setup.cities.isNotEmpty;
    return FindRow(
      semanticLabel: '$name, $countText${current ? ', has your selection' : ''}',
      selected: current,
      onActivate: () => _pickCountry(key),
      color: UiTokens.card,
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: current ? UiTokens.accent : UiTokens.border, width: current ? 1.5 : 1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: UiTokens.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: UiTokens.border),
              ),
              child: CountryFlagBadge(countryName: key, size: 22),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: UiTokens.text, fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: -0.1)),
                  const SizedBox(height: 3),
                  // One line: the city total gives way first on a narrow card.
                  Row(
                    children: [
                      Flexible(
                        flex: 3,
                        child: Text(countText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: UiTokens.textSecondary, fontSize: 12.5, height: 1.2)),
                      ),
                      if (cities > 0) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          flex: 2,
                          child: Text('· ${citiesLabel(cities)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: UiTokens.textMuted, fontSize: 12.5, height: 1.2)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(current ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                size: current ? 18 : 20, color: current ? UiTokens.accent : UiTokens.textMuted),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------- split level

  Widget _splitLevel(SearchSetupProvider setup, String country, List<String> unlisted) {
    final width = MediaQuery.sizeOf(context).width;
    final regionsWidth = width >= 1200 ? 300.0 : 240.0;
    final region = (setup.region != null && _catalog.regionExists(country, setup.region!)) ? setup.region : null;
    return Padding(
      padding: _pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FindSteps(current: 1),
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: UiTokens.card,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: UiTokens.border),
                ),
                child: Semantics(
                  header: true,
                  child: FindCountryLabel(countryKey: country, flagSize: 18),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: UiTokens.accent,
                  minimumSize: const Size(64, 48),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                onPressed: () => goUpTo(context, '/find'),
                child: const Text('Change country'),
              ),
            ],
          ),
          if (unlisted.isNotEmpty) ...[
            const SizedBox(height: 8),
            _unlistedNotice(unlisted, country),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: regionsWidth,
                  child: Container(
                    decoration: findCardDecoration(),
                    padding: const EdgeInsets.all(10),
                    // Groups keep Tab inside one panel (regions, then cities)
                    // instead of zig-zagging across columns by reading order.
                    child: FocusTraversalGroup(child: _regionList(setup, country, selected: region, push: false)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    decoration: findCardDecoration(),
                    padding: const EdgeInsets.all(12),
                    child: region == null
                        ? Center(
                            child: Text(
                              'Choose a ${_catalog.regionTerm(country)} to see its cities.',
                              style: findSecondaryStyle,
                              textAlign: TextAlign.center,
                            ),
                          )
                        : FocusTraversalGroup(child: _cityPane(setup, region)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _regionList(SearchSetupProvider setup, String country, {String? selected, required bool push}) {
    final term = _catalog.regionTerm(country);
    final q = _regionFilter.trim().toLowerCase();
    final regions = _catalog.regionsOf(country).where((r) => q.isEmpty || r.toLowerCase().contains(q)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FindSearchField(
          controller: _regionQuery,
          hint: 'Search ${pluralTerm(term)}',
          onChanged: (v) => setState(() => _regionFilter = v),
        ),
        const SizedBox(height: 8),
        if (regions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('No ${term == 'region' ? 'region' : term} matches your search.', style: findSecondaryStyle),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: regions.length,
            itemExtent: 48,
            itemBuilder: (context, i) => _regionRow(setup, country, regions[i], selected == regions[i], push),
          ),
        ),
      ],
    );
  }

  int _selectedIn(SearchSetupProvider setup, String region) {
    final list = _catalog.citiesIfLoaded(region);
    if (list != null) {
      final keys = list.map(cityKey).toSet();
      return setup.cities.where((c) => keys.contains(cityKey(c))).length;
    }
    return setup.cities.where((c) => _catalog.cityInRegion(c, region)).length;
  }

  Widget _regionRow(SearchSetupProvider setup, String country, String region, bool selected, bool push) {
    final n = _catalog.cityCount(country, region);
    final k = _selectedIn(setup, region);
    final countText = n == null ? '' : formatCount(n);
    final semantics = StringBuffer(region);
    if (k > 0) {
      semantics.write(', ${formatCount(k)} of ${n == null ? '' : '$countText '}cities selected');
    } else if (n != null) {
      semantics.write(', ${citiesLabel(n)}');
    }
    void onTap() => _pickRegion(country, region, push: push);
    // Muted text is 3.98:1 on the selected surface; use the secondary colour there.
    final countStyle = TextStyle(color: selected ? UiTokens.textSecondary : UiTokens.textMuted, fontSize: 12);
    return FindRow(
      semanticLabel: semantics.toString(),
      selected: selected,
      onActivate: onTap,
      color: selected ? UiTokens.selectedSurface : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                region,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: UiTokens.text,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (k > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(color: UiTokens.primary, borderRadius: BorderRadius.circular(999)),
                child: Text(formatCount(k),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              if (n != null) Text(' / $countText', style: countStyle),
            ] else
              Text(countText, style: countStyle),
            if (push) const Icon(Icons.chevron_right_rounded, color: UiTokens.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  /// Cities of [region]: search, "Select N shown" (union), "Clear shown"
  /// (only shown), match hint, virtualised checkbox rows.
  Widget _cityPane(SearchSetupProvider setup, String region) {
    final list = _catalog.citiesIfLoaded(region);
    if (list == null) {
      if (_catalog.cityError(region) != null && !_catalog.isLoadingCities(region)) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Cities didn't load.", style: findTitleStyle),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: UiTokens.primary, minimumSize: const Size(120, 44)),
                onPressed: () => _catalog.loadCities(region, force: true).ignore(),
                child: const Text('Try again'),
              ),
            ],
          ),
        );
      }
      if (!_catalog.isLoadingCities(region)) _catalog.loadCities(region).ignore();
      return const Center(child: CircularProgressIndicator(color: UiTokens.accent));
    }
    if (list.isEmpty) {
      return const Center(child: Text('No cities listed for this region yet.', style: findSecondaryStyle));
    }

    final q = _cityFilter.trim();
    final ql = q.toLowerCase();
    final shown = ql.isEmpty ? list : list.where((c) => displayCityName(c).toLowerCase().contains(ql)).toList();
    final shownSelected = shown.where(setup.isSelected).length;
    final allShownSelected = shown.isNotEmpty && shownSelected == shown.length;

    final search = FindSearchField(
      controller: _cityQuery,
      focusNode: _citySearchFocus,
      hint: 'Search cities in $region',
      onChanged: (v) => setState(() => _cityFilter = v),
    );
    final selectShown = (!allShownSelected && shown.isNotEmpty)
        ? OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: UiTokens.text,
              side: const BorderSide(color: findFieldBorder),
              minimumSize: const Size(48, 48),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: () => setup.addCities(shown),
            child: Text('Select ${formatCount(shown.length)} shown'),
          )
        : null;
    final clearShown = shownSelected > 0
        ? TextButton(
            style: TextButton.styleFrom(
              foregroundColor: UiTokens.accent,
              minimumSize: const Size(48, 48),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: () => setup.removeCities(shown),
            child: const Text('Clear shown'),
          )
        : null;

    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      final columns = w >= 720 ? 3 : (w >= 400 ? 2 : 1);
      final header = w >= 560
          ? Row(children: [
              Expanded(child: search),
              if (selectShown != null) ...[const SizedBox(width: 8), selectShown],
              if (clearShown != null) ...[const SizedBox(width: 4), clearShown],
            ])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                if (selectShown != null || clearShown != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 8, runSpacing: 4, children: [
                      if (selectShown != null) selectShown,
                      if (clearShown != null) clearShown,
                    ]),
                  ),
              ],
            );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (q.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${formatCount(shown.length)} of ${citiesLabel(list.length)} match “$q”. Your other selections are kept.',
              style: findSecondaryStyle,
            ),
          ],
          const SizedBox(height: 8),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No city matches your search.', style: findSecondaryStyle),
            ),
          Expanded(
            child: columns == 1
                ? ListView.builder(
                    itemCount: shown.length,
                    itemExtent: 48,
                    itemBuilder: (context, i) => _CityRow(
                      city: shown[i],
                      selected: setup.isSelected(shown[i]),
                      onToggle: () => setup.toggleCity(shown[i]),
                    ),
                  )
                : GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: 48,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: shown.length,
                    itemBuilder: (context, i) => _CityRow(
                      city: shown[i],
                      selected: setup.isSelected(shown[i]),
                      onToggle: () => setup.toggleCity(shown[i]),
                    ),
                  ),
          ),
        ],
      );
    });
  }

  // --------------------------------------------------------- phone levels

  /// Phone header, stacked so nothing meaningful is truncated at 360 px:
  ///
  ///     ‹ Provinces                 Step 1 of 2
  ///     [flag] Canada
  ///     Quebec                      (city level only)
  Widget _phoneHeader({required String back, required VoidCallback onBack, String? title, required String country}) {
    final countryLine = FindCountryLabel(
      countryKey: country,
      flagSize: 16,
      style: title == null
          ? const TextStyle(color: UiTokens.text, fontSize: 18, fontWeight: FontWeight.w700)
          : const TextStyle(color: UiTokens.textSecondary, fontSize: 14, fontWeight: FontWeight.w600),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: UiTokens.accent,
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.only(left: 0, right: 12),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              onPressed: onBack,
              icon: const Icon(Icons.chevron_left_rounded, size: 22),
              label: Text(back, semanticsLabel: 'Back to ${back.toLowerCase()}'),
            ),
            const Spacer(),
            const Text('Step 1 of 2', style: TextStyle(color: UiTokens.textSecondary, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 2),
        if (title == null)
          Semantics(header: true, child: countryLine)
        else ...[
          countryLine,
          const SizedBox(height: 2),
          Semantics(
            header: true,
            child: Text(title, style: const TextStyle(color: UiTokens.text, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }

  Widget _phoneRegionLevel(SearchSetupProvider setup, String country, List<String> unlisted) {
    return Padding(
      padding: _pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _phoneHeader(back: 'Countries', onBack: () => goUpTo(context, '/find'), country: country),
          if (unlisted.isNotEmpty) ...[const SizedBox(height: 8), _unlistedNotice(unlisted, country)],
          const SizedBox(height: 8),
          Expanded(child: _regionList(setup, country, selected: setup.region, push: true)),
        ],
      ),
    );
  }

  Widget _phoneCityLevel(SearchSetupProvider setup, String country, String region, List<String> unlisted) {
    final term = _catalog.regionTerm(country);
    return Padding(
      padding: _pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _phoneHeader(
            back: capitalize(pluralTerm(term)),
            onBack: () => goUpTo(context, findUrl(country: country)),
            title: region,
            country: country,
          ),
          if (unlisted.isNotEmpty) ...[const SizedBox(height: 8), _unlistedNotice(unlisted, country)],
          const SizedBox(height: 8),
          Expanded(child: _cityPane(setup, region)),
        ],
      ),
    );
  }
}

/// Dense checkbox row (48 px): real checkbox semantics ("Montreal,
/// checkbox, checked"), one focus stop, Space/Enter toggles. Activating it
/// moves focus to the row (see [FindRow]).
class _CityRow extends StatelessWidget {
  final String city;
  final bool selected;
  final VoidCallback onToggle;

  const _CityRow({required this.city, required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final name = displayCityName(city);
    return FindRow(
      semanticLabel: name,
      checked: selected,
      onActivate: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF2E2E32)))),
        padding: const EdgeInsets.only(right: 6),
        child: Row(
          children: [
            // Visual only: the row handles taps, keys and semantics.
            IgnorePointer(
              child: ExcludeFocus(
                child: Checkbox(
                  value: selected,
                  onChanged: (_) {},
                  activeColor: UiTokens.accent,
                  checkColor: Colors.black,
                  side: const BorderSide(color: UiTokens.textSecondary, width: 1.5),
                ),
              ),
            ),
            Expanded(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: UiTokens.text,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
