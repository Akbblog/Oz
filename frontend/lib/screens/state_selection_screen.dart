
import 'package:flutter/material.dart';
import 'package:country_flags/country_flags.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/responsive_utils.dart';
import '../widgets/widgets.dart';
import '../widgets/progress_stepper.dart';
import 'scraping_screen.dart';

class StateSelectionScreen extends StatefulWidget {
  final bool showHeader;
  final void Function(String citiesText, String maxResults)? onContinueToSearch;

  const StateSelectionScreen({
    super.key,
    this.showHeader = true,
    this.onContinueToSearch,
  });

  @override
  State<StateSelectionScreen> createState() => _StateSelectionScreenState();
}

class _StateSelectionScreenState extends State<StateSelectionScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {

  @override
  bool get wantKeepAlive => true;
  String? _selectedCountry = 'USA';
  String? _selectedState;
  List<String> _selectedCities = [];
  bool _selectAllCities = false;
  bool _isLoading = true;
  bool _isCitiesLoading = false;
  bool _includeSuburbs = true;
  bool _showDraftBanner = false;
  Map<String, List<String>> _statesAndCities = {};
  final Map<String, List<String>> _citiesCache = {};
  List<String> _filteredStates = [];
  List<String> _filteredCities = [];
  List<String> _availableCountries = [];
  final TextEditingController _stateSearchController = TextEditingController();
  final TextEditingController _citySearchController = TextEditingController();
  final ApiService _apiService = ApiService();

  late AnimationController _animationController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

  static const String _locationDraftKey = 'wizard_location_draft_v1';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: AppSpacing.durationMedium,
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadInitialData();
    _stateSearchController.addListener(_filterStates);
    _citySearchController.addListener(_filterCities);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pulseController.dispose();
    _stateSearchController.dispose();
    _citySearchController.dispose();
    super.dispose();
  }

  void _filterStates() {
    final query = _stateSearchController.text.toLowerCase();
    setState(() {
      _filteredStates = _statesAndCities.keys
          .where((state) => state.toLowerCase().contains(query))
          .toList();
    });
  }

  void _filterCities() {
    final query = _citySearchController.text.toLowerCase();
    setState(() {
      if (_selectedState != null) {
        _filteredCities = _statesAndCities[_selectedState]!
            .where((city) => city.toLowerCase().contains(query))
            .toList();
      }
    });
  }
  Future<void> _loadInitialData() async {
    try {
      final draft = await _readLocationDraft();
      if (draft != null) {
        _selectedCountry = (draft['country'] as String?) ?? _selectedCountry;
        _selectedState = (draft['state'] as String?);
        _selectedCities = List<String>.from(draft['cities'] ?? const <String>[]);
        _includeSuburbs = (draft['include_suburbs'] as bool?) ?? _includeSuburbs;
      }

      final results = await Future.wait([
        _apiService.getCountries(),
        _apiService.getStates(),
      ]);
      final countries = results[0] as List<String>;
      final statesByCountry = results[1] as Map<String, List<String>>;

      if (_selectedCountry == null) {
        if (countries.contains('USA')) {
          _selectedCountry = 'USA';
        } else if (countries.isNotEmpty) {
          _selectedCountry = countries.first;
        }
      }

      List<String> states = [];
      if (_selectedCountry != null &&
          statesByCountry[_selectedCountry] != null) {
        states = List<String>.from(statesByCountry[_selectedCountry]!);
      }

      if (_selectedState != null && !states.contains(_selectedState)) {
        _selectedState = null;
        _selectedCities = [];
      }

      if (mounted) {
        setState(() {
          _availableCountries = countries;
          _statesAndCities = {
            for (final state in states)
              state: _citiesCache[state] ?? <String>[],
          };
          _filteredStates = states;
          _isLoading = false;
          _showDraftBanner = draft != null;
        });
        _animationController.forward();

        _preloadCities(states.take(5).toList());

        if (_selectedState != null) {
          await _loadCitiesForState(_selectedState!);
          if (!mounted) return;
          setState(() {
            final available = _statesAndCities[_selectedState] ?? const <String>[];
            _selectedCities = _selectedCities.where(available.contains).toList();
            _selectAllCities = _selectedCities.isNotEmpty &&
                _selectedCities.length == available.length;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading initial data: $e');
      if (mounted) {
        setState(() {
          _availableCountries = ['USA', 'UK', 'UAE', 'KSA', 'Australia'];
          _statesAndCities = {
            'California': ['Los Angeles', 'San Diego', 'San Jose', 'San Francisco'],
            'New York': ['New York', 'Buffalo', 'Rochester'],
            'Texas': ['Houston', 'Dallas', 'Austin'],
          };
          _filteredStates = _statesAndCities.keys.toList();
          _isLoading = false;
        });
        _animationController.forward();
      }
    }
  }

  Future<Map<String, dynamic>?> _readLocationDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_locationDraftKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Ignore draft read errors.
    }
    return null;
  }

  Future<void> _saveLocationDraft() async {
    final country = _selectedCountry;
    final state = _selectedState;
    if (country == null || country.isEmpty || state == null || state.isEmpty) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'country': country,
        'state': state,
        'cities': _selectedCities,
        'include_suburbs': _includeSuburbs,
        'saved_at': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_locationDraftKey, jsonEncode(payload));

      if (!mounted) return;
      setState(() => _showDraftBanner = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draft saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      // Ignore save errors.
    }
  }

  Future<void> _clearLocationDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_locationDraftKey);
    } catch (_) {
      // Ignore clear errors.
    }
    if (!mounted) return;
    setState(() => _showDraftBanner = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Draft cleared'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _preloadCities(List<String> states) async {
    for (final state in states) {
      if (_citiesCache.containsKey(state)) continue;
      try {
        final cities = await _apiService.getCities(state);
        if (mounted) {
          _citiesCache[state] = List<String>.from(cities);
          _statesAndCities[state] = _citiesCache[state]!;
        }
      } catch (e) {
        debugPrint('Error preloading cities for $state: $e');
      }
    }
  }

  Future<void> _loadCitiesForState(String state) async {
    if (_citiesCache.containsKey(state)) {
      setState(() {
        _statesAndCities[state] = _citiesCache[state] ?? <String>[];
        _filteredCities = _statesAndCities[state]!;
        _isCitiesLoading = false;
      });
      return;
    }

    setState(() {
      _isCitiesLoading = true;
      _filteredCities = [];
    });

    try {
      final cities = await _apiService.getCities(state);
      if (!mounted) return;
      setState(() {
        _citiesCache[state] = List<String>.from(cities);
        _statesAndCities[state] = _citiesCache[state]!;
        _filteredCities = _statesAndCities[state]!;
        _isCitiesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCitiesLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load cities for $state: $e')),
      );
    }
  }

  void _resetSelections() {
    setState(() {
      _selectedState = null;
      _selectedCities = [];
      _selectAllCities = false;
      _citySearchController.clear();
      _filteredCities = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    return Scaffold(
      backgroundColor: _LocationColors.background,
      body: _isLoading
          ? _buildLoadingState()
          : LayoutBuilder(
              builder: (context, constraints) {
                final layoutType =
                    AppBreakpoints.getLayoutType(constraints.maxWidth);
                if (layoutType == LayoutType.mobile) {
                  return _buildMobileContent(layoutType);
                }
                if (layoutType == LayoutType.tablet) {
                  return _buildTabletContent(layoutType);
                }
                return _buildDesktopContent(layoutType);
              },
            ),
    );
  }
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: _LocationColors.primaryGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _LocationColors.primary.withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.location_on_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          _LoadingTextAnimation(
            text: 'Loading locations',
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              backgroundColor: _LocationColors.primary.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(_LocationColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileContent(LayoutType layoutType) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        children: [
          if (widget.showHeader) _buildHeader(),
          const WorkflowStepper(currentStep: 0),
          _buildWizardProgress(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCountrySelector(),
                  const SizedBox(height: AppSpacing.lg),
                  _buildStateSection(layoutType: layoutType),
                  const SizedBox(height: AppSpacing.lg),
                  if (_selectedState != null)
                    _buildCitiesSection(layoutType: layoutType),
                  if (_selectedState != null)
                    const SizedBox(height: AppSpacing.lg),
                  _buildIncludeSuburbsCard(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildFooterActions(layoutType),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletContent(LayoutType layoutType) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        children: [
          if (widget.showHeader) _buildHeader(),
          const WorkflowStepper(currentStep: 0),
          _buildWizardProgress(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                ResponsiveUtils.getScreenPadding(layoutType),
                ResponsiveUtils.getScreenPadding(layoutType),
                ResponsiveUtils.getScreenPadding(layoutType),
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCountrySelector(),
                  const SizedBox(height: AppSpacing.lg),
                  _buildStateSection(layoutType: layoutType),
                  const SizedBox(height: AppSpacing.lg),
                  if (_selectedState != null)
                    _buildCitiesSection(layoutType: layoutType),
                  if (_selectedState != null)
                    const SizedBox(height: AppSpacing.lg),
                  _buildIncludeSuburbsCard(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildFooterActions(layoutType),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopContent(LayoutType layoutType) {
    final leftFlex = layoutType == LayoutType.desktopMedium ? 35 : 40;
    final rightFlex = 100 - leftFlex;
    final showCities = _selectedState != null;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        children: [
          if (widget.showHeader) _buildHeader(),
          const WorkflowStepper(currentStep: 0),
          _buildWizardProgress(),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                ResponsiveUtils.getScreenPadding(layoutType),
                ResponsiveUtils.getScreenPadding(layoutType),
                ResponsiveUtils.getScreenPadding(layoutType),
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCountrySelector(),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: leftFlex,
                        child: _buildStateSection(
                          layoutType: layoutType,
                          inSplitPanel: true,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        flex: rightFlex,
                        child: showCities
                            ? _buildCitiesSection(layoutType: layoutType)
                            : _buildEmptyCitiesPanel(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _buildIncludeSuburbsCard(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildFooterActions(layoutType),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        color: _LocationColors.background.withValues(alpha: 0.9),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.05),
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _LocationColors.surface,
                  borderRadius: AppSpacing.borderRadiusRound,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: const Icon(
                  Icons.location_city_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Select Locations',
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Choose cities for lead search',
                      style: AppTypography.labelSmall.copyWith(
                        color: _LocationColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _resetSelections,
                style: TextButton.styleFrom(
                  foregroundColor: _LocationColors.textSecondary,
                ),
                child: const Text('Reset'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountrySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.public_rounded,
              color: _LocationColors.primary,
              size: 16,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Target Market',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _availableCountries.length,
            separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, index) {
              final country = _availableCountries[index];
              final isSelected = _selectedCountry == country;
              return _buildCountryCard(country, isSelected);
            },
          ),
        ),
      ],
    );
  }
  Widget _buildCountryCard(String country, bool isSelected) {
    return GestureDetector(
      onTap: () async {
        if (country != _selectedCountry) {
          setState(() {
            _selectedCountry = country;
            _selectedState = null;
            _statesAndCities = {};
            _filteredCities = [];
            _isLoading = true;
          });
          await _loadInitialData();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? _LocationColors.primary.withValues(alpha: 0.15)
              : _LocationColors.surface,
          borderRadius: AppSpacing.borderRadiusMd,
          border: Border.all(
            color: isSelected
                ? _LocationColors.primary
                : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCountryLeading(country, isSelected: isSelected),
            const SizedBox(width: AppSpacing.xs),
            Text(
              country,
              style: AppTypography.labelMedium.copyWith(
                color: isSelected ? Colors.white : _LocationColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountryLeading(String country, {required bool isSelected}) {
    final code = _countryCode(country);
    if (code != null) {
      return Semantics(
        label: country,
        child: CountryFlag.fromCountryCode(
          code,
          theme: const ImageTheme(
            width: 22,
            height: 16,
            shape: RoundedRectangle(3),
          ),
        ),
      );
    }

    return Icon(
      Icons.public_rounded,
      color: isSelected ? _LocationColors.primary : _LocationColors.textSecondary,
      size: 18,
    );
  }

  String? _countryCode(String country) {
    switch (country) {
      case 'USA':
        return 'US';
      case 'UK':
        return 'GB';
      case 'UAE':
        return 'AE';
      case 'KSA':
        return 'SA';
      case 'Australia':
        return 'AU';
      default:
        return null;
    }
  }

  Widget _buildStateSection({
    required LayoutType layoutType,
    bool inSplitPanel = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.map_rounded,
              color: _LocationColors.primary,
              size: 16,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Select Region',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_filteredStates.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: _LocationColors.primary.withValues(alpha: 0.15),
                  borderRadius: AppSpacing.borderRadiusRound,
                ),
                child: Text(
                  '${_filteredStates.length}',
                  style: AppTypography.labelSmall.copyWith(
                    color: _LocationColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildStateSearch(),
        const SizedBox(height: AppSpacing.sm),
        _buildSelectedStateChips(),
        if (_selectedState != null) const SizedBox(height: AppSpacing.sm),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _stateGridColumns(layoutType, inSplitPanel),
            crossAxisSpacing: AppSpacing.xs,
            mainAxisSpacing: AppSpacing.xs,
            childAspectRatio: 2.8,
          ),
          itemCount: _filteredStates.length,
          itemBuilder: (context, index) {
            final state = _filteredStates[index];
            final isSelected = _selectedState == state;
            return _buildStateCard(state, isSelected);
          },
        ),
      ],
    );
  }

  Widget _buildStateSearch() {
    return TextField(
      controller: _stateSearchController,
      style: AppTypography.bodyMedium.copyWith(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search regions...',
        hintStyle: AppTypography.bodySmall.copyWith(
          color: _LocationColors.textSecondary,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: _LocationColors.textSecondary,
          size: 20,
        ),
        suffixIcon: _stateSearchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, color: Colors.white70, size: 20),
                onPressed: () {
                  _stateSearchController.clear();
                  _filterStates();
                },
              )
            : null,
        filled: true,
        fillColor: _LocationColors.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          borderSide: BorderSide(
            color: _LocationColors.primary,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        isDense: true,
      ),
    );
  }

  Widget _buildSelectedStateChips() {
    if (_selectedState == null) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        _buildChip(
          label: _selectedState!,
          onRemove: () => _resetSelections(),
        ),
        TextButton(
          onPressed: _resetSelections,
          style: TextButton.styleFrom(
            foregroundColor: _LocationColors.textSecondary,
          ),
          child: const Text('Clear all'),
        ),
      ],
    );
  }

  Widget _buildChip({required String label, required VoidCallback onRemove}) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: _LocationColors.primary.withValues(alpha: 0.12),
        borderRadius: AppSpacing.borderRadiusRound,
        border: Border.all(
          color: _LocationColors.primary.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: _LocationColors.primary.withValues(alpha: 0.2),
            blurRadius: 8,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: _LocationColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: _LocationColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStateCard(String state, bool isSelected) {
    final cityCount = (_statesAndCities[state] ?? []).length;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedState = isSelected ? null : state;
          _selectedCities = [];
          _selectAllCities = false;
          _citySearchController.clear();
          if (_selectedState != null) {
            _filteredCities = _statesAndCities[_selectedState] ?? [];
          }
        });
        if (!isSelected) {
          _loadCitiesForState(state);
        } else {
          setState(() {
            _filteredCities = [];
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? _LocationColors.primary.withValues(alpha: 0.12)
              : _LocationColors.surface,
          borderRadius: AppSpacing.borderRadiusMd,
          border: Border.all(
            color: isSelected
                ? _LocationColors.primary
                : Colors.white.withValues(alpha: 0.06),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isSelected
                    ? _LocationColors.primary.withValues(alpha: 0.2)
                    : _LocationColors.surfaceHighlight,
                borderRadius: AppSpacing.borderRadiusSm,
              ),
              child: Center(
                child: Text(
                  state.length >= 2 ? state.substring(0, 2).toUpperCase() : state,
                  style: AppTypography.labelSmall.copyWith(
                    color: isSelected ? _LocationColors.primary : Colors.white60,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                state,
                style: AppTypography.labelMedium.copyWith(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (cityCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _LocationColors.primary.withValues(alpha: 0.2)
                      : _LocationColors.surfaceHighlight,
                  borderRadius: AppSpacing.borderRadiusRound,
                ),
                child: Text(
                  '$cityCount',
                  style: AppTypography.labelSmall.copyWith(
                    color: isSelected
                        ? _LocationColors.primary
                        : _LocationColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  Widget _buildCitiesSection({required LayoutType layoutType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.location_city_rounded,
              color: _LocationColors.primary,
              size: 16,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Select Cities',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (_selectedCities.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: _LocationColors.primary.withValues(alpha: 0.15),
                  borderRadius: AppSpacing.borderRadiusRound,
                ),
                child: Text(
                  '${_selectedCities.length} selected',
                  style: AppTypography.labelSmall.copyWith(
                    color: _LocationColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildCitiesSearch(),
        const SizedBox(height: AppSpacing.sm),
        if (_isCitiesLoading)
          _buildCitiesLoadingState()
        else
          _buildCitiesList(layoutType),
      ],
    );
  }

  Widget _buildCitiesSearch() {
    return TextField(
      controller: _citySearchController,
      style: AppTypography.bodyMedium.copyWith(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search cities...',
        hintStyle: AppTypography.bodySmall.copyWith(
          color: _LocationColors.textSecondary,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: _LocationColors.textSecondary,
          size: 20,
        ),
        suffixIcon: _citySearchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, color: Colors.white70, size: 20),
                onPressed: () {
                  _citySearchController.clear();
                  _filterCities();
                },
              )
            : null,
        filled: true,
        fillColor: _LocationColors.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          borderSide: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          borderSide: BorderSide(
            color: _LocationColors.primary,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        isDense: true,
      ),
    );
  }

  Widget _buildCitiesList(LayoutType layoutType) {
    if (layoutType != LayoutType.mobile && layoutType != LayoutType.tablet) {
      return Column(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _selectAllCities = !_selectAllCities;
                if (_selectAllCities) {
                  _selectedCities = List.from(_filteredCities);
                } else {
                  _selectedCities = [];
                }
              });
            },
            child: Container(
              padding: AppSpacing.paddingSm,
              decoration: BoxDecoration(
                color: _selectAllCities
                    ? _LocationColors.primary.withValues(alpha: 0.1)
                    : _LocationColors.surface,
                borderRadius: AppSpacing.borderRadiusMd,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _selectAllCities
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: _selectAllCities
                        ? _LocationColors.primary
                        : _LocationColors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Select All',
                    style: AppTypography.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_filteredCities.length} cities',
                    style: AppTypography.labelSmall.copyWith(
                      color: _LocationColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _cityGridColumns(layoutType),
              crossAxisSpacing: AppSpacing.xs,
              mainAxisSpacing: AppSpacing.xs,
              childAspectRatio: 3.6,
            ),
            itemCount: _filteredCities.length,
            itemBuilder: (context, index) {
              final city = _filteredCities[index];
              final isSelected = _selectedCities.contains(city);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedCities.remove(city);
                    } else {
                      _selectedCities.add(city);
                    }
                    _selectAllCities =
                        _selectedCities.length == _filteredCities.length;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _LocationColors.primary.withValues(alpha: 0.1)
                        : _LocationColors.surface,
                    borderRadius: AppSpacing.borderRadiusSm,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: isSelected
                            ? _LocationColors.primary
                            : _LocationColors.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          city,
                          style: AppTypography.labelMedium.copyWith(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

    return Column(
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _selectAllCities = !_selectAllCities;
              if (_selectAllCities) {
                _selectedCities = List.from(_filteredCities);
              } else {
                _selectedCities = [];
              }
            });
          },
          child: Container(
            padding: AppSpacing.paddingSm,
            decoration: BoxDecoration(
              color: _selectAllCities
                  ? _LocationColors.primary.withValues(alpha: 0.1)
                  : _LocationColors.surface,
              borderRadius: AppSpacing.borderRadiusMd,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _selectAllCities
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: _selectAllCities
                      ? _LocationColors.primary
                      : _LocationColors.textSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Select All',
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_filteredCities.length} cities',
                  style: AppTypography.labelSmall.copyWith(
                    color: _LocationColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 220,
          child: ListView.builder(
            itemCount: _filteredCities.length,
            itemBuilder: (context, index) {
              final city = _filteredCities[index];
              final isSelected = _selectedCities.contains(city);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedCities.remove(city);
                    } else {
                      _selectedCities.add(city);
                    }
                    _selectAllCities =
                        _selectedCities.length == _filteredCities.length;
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  padding: AppSpacing.paddingSm,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _LocationColors.primary.withValues(alpha: 0.1)
                        : _LocationColors.surface,
                    borderRadius: AppSpacing.borderRadiusSm,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: isSelected
                            ? _LocationColors.primary
                            : _LocationColors.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        city,
                        style: AppTypography.bodyMedium.copyWith(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCitiesLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _LocationColors.primary,
                  ),
                ),
              ),
              Icon(
                Icons.location_city_rounded,
                color: _LocationColors.primary,
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _LoadingTextAnimation(
            text: 'Loading cities',
            style: AppTypography.bodySmall.copyWith(
              color: _LocationColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...List.generate(
            3,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _ShimmerPlaceholder(
                width: double.infinity,
                height: 40,
                delay: Duration(milliseconds: index * 100),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncludeSuburbsCard() {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: _LocationColors.surface,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: _LocationColors.primary.withValues(alpha: 0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 18,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _LocationColors.primary.withValues(alpha: 0.1),
              borderRadius: AppSpacing.borderRadiusMd,
              border: Border.all(
                color: _LocationColors.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(
              Icons.radar_rounded,
              color: _LocationColors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Include Suburbs',
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Expand search radius by 25 miles',
                  style: AppTypography.bodySmall.copyWith(
                    color: _LocationColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _includeSuburbs,
            onChanged: (value) {
              setState(() {
                _includeSuburbs = value;
              });
            },
            activeColor: _LocationColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildWizardProgress() {
    final completed = [
      _selectedCountry != null && _selectedCountry!.isNotEmpty,
      _selectedState != null && _selectedState!.isNotEmpty,
      _selectedCities.isNotEmpty,
    ].where((v) => v).length;
    final progress = (completed / 3).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        children: [
          if (_showDraftBanner)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              decoration: BoxDecoration(
                color: _LocationColors.primary.withValues(alpha: 0.12),
                borderRadius: AppSpacing.borderRadiusLg,
                border: Border.all(
                  color: _LocationColors.primary.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.save_rounded,
                    color: _LocationColors.primaryLight,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Draft loaded',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _clearLocationDraft,
                    child: Text(
                      'Clear',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: AppSpacing.borderRadiusRound,
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor:
                        _LocationColors.primary.withValues(alpha: 0.18),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _LocationColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${(progress * 100).round()}%',
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooterActions(LayoutType layoutType) {
    final canContinue = _selectedState != null && _selectedCities.isNotEmpty;
    final isCompact = layoutType == LayoutType.mobile;

    final continueButton = GradientButton(
      text: _selectedCities.isEmpty
          ? 'Select locations'
          : 'Continue (${_selectedCities.length} cities)',
      icon: Icons.arrow_forward_rounded,
      onPressed: canContinue
          ? () {
              final citiesText = _selectedCities
                  .map((city) => '$city, $_selectedState')
                  .join('; ');

              if (widget.onContinueToSearch != null) {
                widget.onContinueToSearch!(citiesText, '10');
                return;
              }

              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      ScrapingScreen(
                    initialCategory: '',
                    initialCities: citiesText,
                    initialMaxResults: '10',
                  ),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(1, 0),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        )),
                        child: child,
                      ),
                    );
                  },
                  transitionDuration: AppSpacing.durationMedium,
                ),
              );
            }
          : null,
    );

    final draftButton = OutlinedButton.icon(
      onPressed: (_selectedState == null) ? null : _saveLocationDraft,
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: _LocationColors.primary.withValues(alpha: 0.35),
        ),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
      icon: const Icon(Icons.save_rounded, size: 18),
      label: Text(
        'Save draft',
        style: AppTypography.labelLarge.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (isCompact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          draftButton,
          const SizedBox(height: AppSpacing.sm),
          continueButton,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: draftButton),
        const SizedBox(width: AppSpacing.sm),
        Expanded(flex: 2, child: continueButton),
      ],
    );
  }

  Widget _buildEmptyCitiesPanel() {
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: _LocationColors.surface,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Center(
        child: Text(
          'Select a state to view cities',
          style: AppTypography.bodyMedium.copyWith(
            color: _LocationColors.textSecondary,
          ),
        ),
      ),
    );
  }

  int _stateGridColumns(LayoutType layoutType, bool inSplitPanel) {
    switch (layoutType) {
      case LayoutType.mobile:
        return 2;
      case LayoutType.tablet:
        return 3;
      case LayoutType.desktopSmall:
        return inSplitPanel ? 2 : 3;
      case LayoutType.desktopMedium:
        return 3;
      case LayoutType.desktopLarge:
        return 4;
    }
  }

  int _cityGridColumns(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.mobile:
        return 1;
      case LayoutType.tablet:
        return 1;
      case LayoutType.desktopSmall:
        return 1;
      case LayoutType.desktopMedium:
        return 2;
      case LayoutType.desktopLarge:
        return 3;
    }
  }
}

class _LocationColors {
  static const Color background = AppColors.backgroundDark;
  static const Color surface = AppColors.surfaceDark;
  static const Color surfaceHighlight = AppColors.elevatedCardDark;
  static const Color primary = AppColors.primaryBlue;
  static const Color primaryLight = AppColors.primaryBlueLight;
  static const Color textSecondary = AppColors.textSecondaryDark;

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [AppColors.primaryBlue, AppColors.primaryBlueDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class _LoadingTextAnimation extends StatefulWidget {
  final String text;
  final TextStyle? style;

  const _LoadingTextAnimation({
    required this.text,
    this.style,
  });

  @override
  State<_LoadingTextAnimation> createState() => _LoadingTextAnimationState();
}

class _LoadingTextAnimationState extends State<_LoadingTextAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _dotCount = (_dotCount + 1) % 4;
          });
          _controller.reset();
          _controller.forward();
        }
      });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = '.' * _dotCount;
    final spaces = ' ' * (3 - _dotCount);
    return Text(
      '${widget.text}$dots$spaces',
      style: widget.style ??
          AppTypography.bodyMedium.copyWith(
            color: Colors.white70,
          ),
    );
  }
}

class _ShimmerPlaceholder extends StatefulWidget {
  final double width;
  final double height;
  final Duration delay;

  const _ShimmerPlaceholder({
    required this.width,
    required this.height,
    this.delay = Duration.zero,
  });

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.repeat();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: AppSpacing.borderRadiusSm,
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value, 0),
              colors: [
                _LocationColors.surface,
                _LocationColors.surfaceHighlight,
                _LocationColors.surface,
              ],
            ),
          ),
        );
      },
    );
  }
}
