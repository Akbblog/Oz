import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_breakpoints.dart';
import '../../providers/active_searches_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/credit_provider.dart';
import '../../providers/scraper_provider.dart';
import '../../providers/search_setup_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/app_shell.dart';
import 'find_common.dart';

/// Find leads — step 2 (Details & start), plan §6.4. Page body only.
///
/// Business type, leads per city (10/20/50/100), cities (chips + "Add a city
/// not listed"), the cost panel (from GET /api/credits/config and POST
/// /api/credits/estimate — the estimate is the maximum and is charged at
/// start) and the labelled Start button with visible reasons when disabled.
class FindDetailsStep extends StatefulWidget {
  /// Optional API (tests); defaults to the app's services.
  final ApiService? api;

  const FindDetailsStep({super.key, this.api});

  static const List<String> suggestions = [
    'Dentists',
    'Restaurants',
    'Plumbers',
    'Real estate agents',
    'Lawyers',
    'Gyms',
    'Coffee shops',
    'Auto repair',
  ];

  /// Backend limit for one search (POST /api/jobs `cities_data`).
  static const int maxCities = 500;

  @override
  State<FindDetailsStep> createState() => _FindDetailsStepState();
}

class _FindDetailsStepState extends State<FindDetailsStep> {
  late final LocationCatalog _catalog;
  late final CostEstimator _estimator;
  late final SearchSetupProvider _setup;
  late final AuthProvider _auth;

  final _category = TextEditingController();
  final _categoryFocus = FocusNode(debugLabel: 'business type');
  final _extraCity = TextEditingController();
  final _extraFocus = FocusNode(debugLabel: 'add city');
  final _costKey = GlobalKey();
  final _scroll = ScrollController();

  bool _categoryTouched = false;
  bool _showExtra = false;
  String? _extraError;
  bool _showAllCities = false;

  bool _submitting = false;
  bool _slow = false;
  bool _attempted = false;
  Timer? _slowTimer;

  @override
  void initState() {
    super.initState();
    _catalog = LocationCatalog.of(widget.api);
    _estimator = CostEstimator(widget.api ?? ApiService());
    _setup = context.read<SearchSetupProvider>();
    _auth = context.read<AuthProvider>();
    _category.text = _setup.category;
    _setup.addListener(_onSetupChanged);
    _auth.addListener(_onAuthChanged);
    _categoryFocus.addListener(() {
      if (!_categoryFocus.hasFocus && mounted) setState(() => _categoryTouched = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _setup.removeListener(_onSetupChanged);
    _auth.removeListener(_onAuthChanged);
    _slowTimer?.cancel();
    _estimator.dispose();
    _category.dispose();
    _categoryFocus.dispose();
    _extraCity.dispose();
    _extraFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    if (!mounted) return;
    unawaited(_catalog.load());
    _loadCredits();
    await _setup.load();
    if (!mounted) return;
    _onSetupChanged();
  }

  void _loadCredits() {
    if (!_auth.isAuthenticated) return;
    final credit = context.read<CreditProvider>();
    unawaited(credit.loadConfig());
    if (!credit.hasValue) unawaited(credit.refresh());
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (_auth.isAuthenticated) {
      _loadCredits();
      _onSetupChanged();
    } else {
      _estimator.reset();
    }
  }

  void _onSetupChanged() {
    if (!mounted) return;
    // A draft restored after this page opened fills the empty field.
    if (!_categoryFocus.hasFocus && _category.text != _setup.category) {
      _category.text = _setup.category;
    }
    if (_auth.isAuthenticated) {
      final k = _setup.cityCount;
      _estimator.request(
        numCities: k > FindDetailsStep.maxCities ? 0 : k,
        maxResults: _setup.maxResultsPerCity,
      );
    }
  }

  // ------------------------------------------------------------- actions

  void _editCities() {
    if (isFindChild(context) && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    final country = _setup.country ?? _catalog.countryOfRegion(_setup.region);
    final region = _setup.region;
    final regionOk = country != null && region != null && _catalog.regionExists(country, region);
    Navigator.of(context).pushNamed(findUrl(country: country, region: regionOk ? region : null));
  }

  void _addExtra() {
    final raw = _extraCity.text.trim();
    if (!isValidCityRegion(raw)) {
      setState(() => _extraError = "Use the format City, Region — for example 'Laval, Quebec'.");
      _extraFocus.requestFocus();
      return;
    }
    final i = raw.lastIndexOf(',');
    final normalized = '${raw.substring(0, i).trim()}, ${raw.substring(i + 1).trim()}';
    _setup.addExtraCity(normalized);
    setState(() => _extraError = null);
    _extraCity.clear();
    _extraFocus.requestFocus();
  }

  void _scrollToCost() {
    final ctx = _costKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250));
    }
  }

  Future<void> _start() async {
    if (_submitting) return;
    if (!_auth.isAuthenticated) {
      await _showSignInSheet();
      return;
    }
    final scraper = context.read<ScraperProvider>();
    final active = context.read<ActiveSearchesProvider>();
    final navigator = Navigator.of(context);
    setState(() {
      _submitting = true;
      _slow = false;
      _attempted = true;
    });
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _submitting) setState(() => _slow = true);
    });
    bool ok;
    try {
      ok = await scraper.startScraping(
        category: _setup.category.trim(),
        citiesData: _setup.allCities,
        maxResultsPerCity: _setup.maxResultsPerCity,
      );
    } catch (_) {
      ok = false;
    }
    _slowTimer?.cancel();
    if (!mounted) return;
    final jobId = scraper.currentJob?.jobId;
    if (ok && jobId != null && jobId.isNotEmpty) {
      unawaited(active.refresh());
      // Replace this form so Back returns to Find leads, not a stale form.
      navigator.pushReplacementNamed('/searches/${Uri.encodeComponent(jobId)}');
      return;
    }
    setState(() {
      _submitting = false;
      _slow = false;
    });
  }

  Future<void> _showSignInSheet() async {
    await _setup.persist();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: UiTokens.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, color: UiTokens.accent),
                    SizedBox(width: 10),
                    Expanded(child: Text('Sign in required', style: findTitleStyle)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Account needed to continue', style: findMutedStyle),
                const SizedBox(height: 12),
                const Text(
                  'You can explore cities and search setup freely. To start a search and use credits, '
                  'please sign in or create an account. Your setup is saved.',
                  style: TextStyle(color: UiTokens.textSecondary, fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: UiTokens.primary, minimumSize: const Size(0, 48)),
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    AppNav.signIn(context, returnRoute: '/find/details');
                  },
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Sign in to continue'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: UiTokens.textSecondary,
                          side: const BorderSide(color: UiTokens.border),
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: const Text('Not now'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: UiTokens.text,
                          side: const BorderSide(color: UiTokens.border),
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                          Navigator.of(context).pushNamed('/register');
                        },
                        icon: const Icon(Icons.person_add_rounded, size: 16),
                        label: const Text('Create account'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- model

  /// Why Start is disabled (null = enabled). [action] is the fix button.
  ({String text, String? action, VoidCallback? onAction})? _blockReason({
    required bool signedIn,
    required CreditProvider credit,
  }) {
    if (_setup.category.trim().isEmpty) return (text: 'Enter a business type', action: null, onAction: null);
    final k = _setup.cityCount;
    if (k == 0) return (text: 'Select at least one city', action: 'Edit cities', onAction: _editCities);
    if (k > FindDetailsStep.maxCities) {
      return (
        text: 'A search can include up to ${FindDetailsStep.maxCities} cities — you have ${formatCount(k)}.',
        action: 'Edit cities',
        onAction: _editCities,
      );
    }
    if (!signedIn) return null;
    final estimate = _estimator.estimate;
    if (estimate == null) {
      if (_estimator.error != null && !_estimator.loading) {
        return (text: "We couldn't calculate the cost.", action: 'Try again', onAction: _estimator.retry);
      }
      return (text: 'Calculating the cost…', action: null, onAction: null);
    }
    final balance = _balance(credit);
    if (balance != null && balance < estimate) {
      return (
        text: 'Not enough credits — you need ${formatCount(estimate)}, you have ${formatCount(balance)}',
        action: 'Get credits',
        onAction: () => AppNav.go(context, '/credits'),
      );
    }
    return null;
  }

  /// Balance from [CreditProvider], else the one reported with the estimate.
  int? _balance(CreditProvider credit) => credit.hasValue ? credit.balance : _estimator.currentBalance;

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final setup = context.watch<SearchSetupProvider>();
    final signedIn = context.watch<AuthProvider>().isAuthenticated;
    final credit = context.watch<CreditProvider>();
    final scraper = context.watch<ScraperProvider>();
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < AppBreakpoints.mobile;
    final wide = width >= AppBreakpoints.tablet;

    return ListenableBuilder(
      listenable: Listenable.merge([_catalog, _estimator]),
      builder: (context, _) {
        final country = setup.country ?? _catalog.countryOfRegion(setup.region);
        _catalog.prefetchFor(setup.cities, country: country);
        final unlisted = _catalog.noLongerListed(setup.cities, country: country);
        final block = _blockReason(signedIn: signedIn, credit: credit);
        final starting = _submitting || scraper.isStarting;
        final error = (_attempted && !starting) ? scraper.startError : null;

        final form = _formCard(setup, unlisted);
        final cost = _costCard(setup, credit, signedIn, block, starting, error, showButton: !phone);
        final padding = EdgeInsets.fromLTRB(phone ? 16 : 24, 16, phone ? 16 : 24, 24);

        final body = SingleChildScrollView(
          controller: _scroll,
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FindSteps(current: 2, onLocation: _editCities),
              const SizedBox(height: 16),
              if (unlisted.isNotEmpty) ...[
                FindNotice(icon: Icons.warning_amber_rounded, text: noLongerListedNotice(unlisted.length)),
                const SizedBox(height: 12),
              ],
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: form),
                    const SizedBox(width: 16),
                    SizedBox(width: width >= 1200 ? 360 : 320, child: cost),
                  ],
                )
              else ...[
                form,
                const SizedBox(height: 16),
                cost,
              ],
            ],
          ),
        );

        if (!phone) return body;
        return Column(
          children: [
            Expanded(child: body),
            _phoneBar(signedIn, block, starting, error),
          ],
        );
      },
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: const TextStyle(color: UiTokens.text, fontSize: 14, fontWeight: FontWeight.w600)),
      );

  Widget _formCard(SearchSetupProvider setup, List<String> unlisted) {
    final showCategoryError = _categoryTouched && setup.category.trim().isEmpty;
    final policy = context.read<CreditProvider>().refundPolicy;
    return Container(
      decoration: findCardDecoration(),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: const Text('Search details', style: findTitleStyle)),
          const SizedBox(height: 14),
          _label('Business type'),
          TextField(
            controller: _category,
            focusNode: _categoryFocus,
            inputFormatters: maxLength(120),
            textInputAction: TextInputAction.done,
            onChanged: (v) => _setup.setCategory(v),
            onSubmitted: (_) => setState(() => _categoryTouched = true),
            style: findBodyStyle,
            cursorColor: UiTokens.accent,
            decoration: InputDecoration(
              hintText: 'for example dentists',
              hintStyle: const TextStyle(color: UiTokens.textMuted),
              filled: true,
              fillColor: UiTokens.background,
              errorText: showCategoryError ? "Enter a business type, for example 'dentists'." : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: findFieldBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: findFocusRing, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: UiTokens.failedFg),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: UiTokens.failedFg, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in FindDetailsStep.suggestions)
                ActionChip(
                  label: Text(s),
                  labelStyle: const TextStyle(color: UiTokens.text, fontSize: 13),
                  backgroundColor: UiTokens.background,
                  side: const BorderSide(color: UiTokens.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                  onPressed: () {
                    _category.text = s;
                    _category.selection = TextSelection.collapsed(offset: s.length);
                    _setup.setCategory(s);
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          _label('Leads per city (maximum)'),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: ButtonStyle(
                minimumSize: const WidgetStatePropertyAll(Size(56, 44)),
                foregroundColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? Colors.white : UiTokens.text),
                backgroundColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected) ? UiTokens.primary : UiTokens.background),
                side: const WidgetStatePropertyAll(BorderSide(color: UiTokens.border)),
              ),
              segments: [
                for (final n in SearchSetupProvider.maxResultsChoices)
                  ButtonSegment<int>(value: n, label: Text('$n'), tooltip: '$n leads per city at most'),
              ],
              selected: {setup.maxResultsPerCity},
              onSelectionChanged: (s) => _setup.setMaxResultsPerCity(s.first),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Google Maps often has fewer businesses than this in small towns.'
            '${policy == 'delivered' ? ' You only pay for leads delivered.' : ''}',
            style: findSecondaryStyle,
          ),
          if (setup.maxResultsWasCapped) ...[
            const SizedBox(height: 4),
            const Text('Maximum is 100 leads per city.', style: TextStyle(color: UiTokens.partialFg, fontSize: 13)),
          ],
          const SizedBox(height: 20),
          _label(setup.cityCount == 0 ? 'Cities' : 'Cities (${formatCount(setup.cityCount)})'),
          if (_placeLine(setup) case final place?) ...[place, const SizedBox(height: 8)],
          _cityChips(setup, unlisted),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: UiTokens.accent,
                  minimumSize: const Size(64, 44),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: _editCities,
                child: const Text('Edit cities'),
              ),
              if (!_showExtra)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(64, 44)),
                  onPressed: () {
                    setState(() => _showExtra = true);
                    WidgetsBinding.instance.addPostFrameCallback((_) => _extraFocus.requestFocus());
                  },
                  child: const Text('Add a city not listed'),
                ),
            ],
          ),
          if (_showExtra) _extraField(),
        ],
      ),
    );
  }

  /// "[flag] Canada · Quebec" above the city chips (null without a country).
  Widget? _placeLine(SearchSetupProvider setup) {
    final country = setup.country ?? _catalog.countryOfRegion(setup.region);
    if (country == null || country.isEmpty || setup.cityCount == 0) return null;
    final region = setup.region;
    const style = TextStyle(color: UiTokens.textSecondary, fontSize: 13, fontWeight: FontWeight.w600);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        FindCountryLabel(countryKey: country, flagSize: 14, style: style),
        if (region != null && region.isNotEmpty) Text('· $region', style: style),
      ],
    );
  }

  Widget _cityChips(SearchSetupProvider setup, List<String> unlisted) {
    final unlistedKeys = unlisted.map(cityKey).toSet();
    final entries = <Widget>[];
    for (final c in setup.cities) {
      final gone = unlistedKeys.contains(cityKey(c));
      entries.add(CityChip(
        city: c,
        label: gone ? c : displayCityName(c),
        noLongerListed: gone,
        onRemove: () => _setup.removeCities([c]),
      ));
    }
    for (final c in setup.extraCities) {
      entries.add(CityChip(city: c, label: c, note: 'added by you', onRemove: () => _setup.removeExtraCity(c)));
    }
    if (entries.isEmpty) {
      return const Text('No cities selected yet.', style: findSecondaryStyle);
    }
    const limit = 30;
    final collapsed = !_showAllCities && entries.length > limit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: collapsed ? entries.take(limit).toList() : entries),
        if (entries.length > limit)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(64, 44)),
            onPressed: () => setState(() => _showAllCities = !_showAllCities),
            child: Text(collapsed ? 'Show all ${formatCount(entries.length)} cities' : 'Show fewer'),
          ),
      ],
    );
  }

  Widget _extraField() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _extraCity,
              focusNode: _extraFocus,
              inputFormatters: maxLength(200),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _addExtra(),
              onEditingComplete: () {},
              onChanged: (_) {
                if (_extraError != null) setState(() => _extraError = null);
              },
              style: findBodyStyle,
              cursorColor: UiTokens.accent,
              decoration: InputDecoration(
                labelText: 'Add a city not listed',
                labelStyle: const TextStyle(color: UiTokens.textSecondary),
                hintText: 'City, Region',
                hintStyle: const TextStyle(color: UiTokens.textMuted),
                helperText: _extraError == null ? 'Use the format City, Region.' : null,
                helperStyle: findMutedStyle,
                errorText: _extraError,
                errorMaxLines: 2,
                filled: true,
                fillColor: UiTokens.background,
                isDense: true,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: findFieldBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: findFocusRing, width: 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: UiTokens.failedFg),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: UiTokens.failedFg, width: 1.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: UiTokens.text,
              side: const BorderSide(color: UiTokens.border),
              minimumSize: const Size(64, 48),
            ),
            onPressed: _addExtra,
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _costRow(String label, String value, {bool bold = false, Color? valueColor}) {
    final style = TextStyle(
      color: bold ? UiTokens.text : UiTokens.textSecondary,
      fontSize: bold ? 17 : 14,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style.copyWith(color: valueColor ?? UiTokens.text)),
        ],
      ),
    );
  }

  static int? _configInt(Map<String, dynamic>? config, String key) {
    final v = config?[key];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}');
  }

  Widget _costCard(
    SearchSetupProvider setup,
    CreditProvider credit,
    bool signedIn,
    ({String text, String? action, VoidCallback? onAction})? block,
    bool starting,
    String? error, {
    required bool showButton,
  }) {
    final children = <Widget>[
      Semantics(header: true, child: const Text('Cost', style: findTitleStyle)),
      const SizedBox(height: 10),
    ];
    final k = setup.cityCount;
    final m = setup.maxResultsPerCity;
    final estimate = signedIn ? _estimator.estimate : null;

    if (!signedIn) {
      children.add(const Text(
        'Sign in to see the cost and your balance. Nothing is charged before you press Start.',
        style: findSecondaryStyle,
      ));
    } else {
      final config = credit.config;
      final base = _configInt(config, 'base');
      final perCity = _configInt(config, 'per_city');
      final perResult = _configInt(config, 'per_result');
      if (base != null && perCity != null && perResult != null && k > 0) {
        children
          ..add(_costRow('Job fee', formatCount(base)))
          ..add(_costRow('${citiesLabel(k)} × ${formatCount(perCity)}', formatCount(k * perCity)))
          ..add(_costRow('Up to ${formatCount(k * m)} leads × ${formatCount(perResult)}',
              formatCount(k * m * perResult)));
        final sum = base + k * perCity + k * m * perResult;
        final minJob = _configInt(config, 'min_job');
        if (estimate != null && estimate > sum && minJob != null) {
          children.add(_costRow('Minimum charge per search', formatCount(minJob)));
        }
      }
      String charged;
      if (k == 0) {
        charged = '—';
      } else if (estimate != null) {
        charged = formatCount(estimate);
      } else if (_estimator.loading) {
        charged = '…';
      } else {
        charged = '—';
      }
      children.add(Semantics(
        label: estimate == null ? 'Charged now: not available yet' : 'Charged now: ${formatCount(estimate)} credits, the maximum',
        excludeSemantics: true,
        child: _costRow('Charged now', charged, bold: true),
      ));
      final balance = _balance(credit);
      if (estimate != null && balance != null) {
        final after = balance - estimate;
        children.add(_costRow('Balance after', formatCount(after),
            valueColor: after < 0 ? UiTokens.failedFg : null));
      }
      final sentence = credit.refundPolicySentence;
      if (sentence != null) {
        children
          ..add(const SizedBox(height: 8))
          ..add(Text(sentence, style: findSecondaryStyle));
      }
    }

    if (showButton) {
      children
        ..add(const SizedBox(height: 16))
        ..addAll(_startControls(signedIn, block, starting, error, estimate: estimate))
        ..add(Center(
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: UiTokens.accent,
              minimumSize: const Size(64, 44),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            onPressed: _editCities,
            child: const Text('Back'),
          ),
        ));
    }

    return Container(
      key: _costKey,
      decoration: findCardDecoration(),
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  String _startLabel(bool signedIn, int? estimate) {
    if (!signedIn) return 'Sign in to start';
    if (estimate != null && _setup.cityCount > 0) return 'Start search · ${formatCount(estimate)} credits';
    return 'Start search';
  }

  List<Widget> _startControls(
    bool signedIn,
    ({String text, String? action, VoidCallback? onAction})? block,
    bool starting,
    String? error, {
    int? estimate,
    bool compactLabel = false,
  }) {
    final enabled = block == null && !starting;
    return [
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: UiTokens.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: UiTokens.border,
          disabledForegroundColor: UiTokens.textSecondary,
          minimumSize: const Size(0, 52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        onPressed: enabled ? _start : null,
        child: Text(compactLabel
            ? (signedIn ? 'Start search' : 'Sign in to start')
            : _startLabel(signedIn, estimate)),
      ),
      if (starting) ...[
        const SizedBox(height: 10),
        Semantics(
          liveRegion: true,
          child: Row(
            children: [
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: UiTokens.accent)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _slow
                      ? "Still starting — it's safe to wait. Pressing Start again won't charge twice."
                      : 'Starting your search…',
                  style: findSecondaryStyle,
                ),
              ),
            ],
          ),
        ),
      ] else if (block != null) ...[
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Text(block.text, style: findSecondaryStyle),
              if (block.action != null)
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: UiTokens.accent,
                    minimumSize: const Size(48, 48),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  onPressed: block.onAction,
                  child: Text(block.action!),
                ),
            ],
          ),
        ),
      ],
      if (error != null && !starting) ...[
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error_outline_rounded, size: 18, color: UiTokens.failedFg),
              const SizedBox(width: 8),
              Expanded(child: Text(error, style: const TextStyle(color: UiTokens.failedFg, fontSize: 13))),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _phoneBar(
    bool signedIn,
    ({String text, String? action, VoidCallback? onAction})? block,
    bool starting,
    String? error,
  ) {
    final estimate = signedIn ? _estimator.estimate : null;
    final headline = !signedIn
        ? 'Sign in to see the cost'
        : (estimate != null && _setup.cityCount > 0)
            ? '${formatCount(estimate)} credits charged now'
            : null;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E21),
        border: Border(top: BorderSide(color: UiTokens.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headline != null)
            Row(
              children: [
                Expanded(
                  child: Text(headline,
                      style: const TextStyle(color: UiTokens.text, fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                  onPressed: _scrollToCost,
                  child: const Text('Cost details'),
                ),
              ],
            ),
          const SizedBox(height: 4),
          ..._startControls(signedIn, block, starting, error, estimate: estimate, compactLabel: true),
        ],
      ),
    );
  }
}
