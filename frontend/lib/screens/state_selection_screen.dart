import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../core/theme/app_theme.dart';
import '../widgets/widgets.dart';
import 'scraping_screen.dart';

class StateSelectionScreen extends StatefulWidget {
  const StateSelectionScreen({super.key});

  @override
  State<StateSelectionScreen> createState() => _StateSelectionScreenState();
}

class _StateSelectionScreenState extends State<StateSelectionScreen>
    with TickerProviderStateMixin {
  String? _selectedCountry = 'USA';
  String? _selectedState;
  List<String> _selectedCities = [];
  bool _selectAllCities = false;
  bool _isLoading = true;
  bool _isCitiesLoading = false;
  Map<String, List<String>> _statesAndCities = {};
  final Map<String, List<String>> _citiesCache = {};
  List<String> _filteredStates = [];
  List<String> _filteredCities = [];
  final TextEditingController _stateSearchController = TextEditingController();
  final TextEditingController _citySearchController = TextEditingController();
  final ApiService _apiService = ApiService();

  late AnimationController _animationController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

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

    // Pulse animation for loading indicator
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

      if (mounted) {
        setState(() {
          _statesAndCities = {
            for (final state in states)
              state: _citiesCache[state] ?? <String>[],
          };
          _filteredStates = states;
          _isLoading = false;
        });
        _animationController.forward();

        // Preload cities for first few states in background
        _preloadCities(states.take(5).toList());
      }
    } catch (e) {
      debugPrint('Error loading initial data: $e');
      if (mounted) {
        setState(() {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      body: _isLoading ? _buildLoadingState() : _buildContent(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated loading indicator
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryStart.withValues(alpha: 0.4),
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
          // Loading text with dots animation
          _LoadingTextAnimation(text: 'Loading locations'),
          const SizedBox(height: AppSpacing.lg),
          // Progress indicator
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              backgroundColor: AppColors.primaryStart.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryStart),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        padding: AppSpacing.paddingMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(),
            const SizedBox(height: AppSpacing.lg),

            // Country Selector
            _buildCountrySelector(),
            const SizedBox(height: AppSpacing.md),

            // State Selector
            _buildStateSelector(),
            const SizedBox(height: AppSpacing.md),

            // Cities Selector
            if (_selectedState != null) ...[
              _buildCitiesSelector(),
              const SizedBox(height: AppSpacing.md),
            ],

            // Selected Summary
            if (_selectedState != null && _selectedCities.isNotEmpty) ...[
              _buildSummaryCard(),
              const SizedBox(height: AppSpacing.md),
            ],

            // Continue Button
            _buildContinueButton(),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: AppSpacing.borderRadiusLg,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryStart.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: AppSpacing.borderRadiusMd,
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Locations',
                  style: AppTypography.titleLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Choose regions and cities to search',
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountrySelector() {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppSpacing.borderRadiusLg,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryStart.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.primaryStart.withValues(alpha: 0.1),
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: const Icon(
                  Icons.public_rounded,
                  color: AppColors.primaryStart,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Country',
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _buildCountryChip('USA', Icons.flag_rounded),
              const SizedBox(width: AppSpacing.sm),
              _buildCountryChip('UK', Icons.flag_rounded),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCountryChip(String country, IconData icon) {
    final isSelected = _selectedCountry == country;
    return Expanded(
      child: GestureDetector(
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
        child: AnimatedContainer(
          duration: AppSpacing.durationFast,
          padding: AppSpacing.paddingSm,
          decoration: BoxDecoration(
            gradient: isSelected ? AppColors.primaryGradient : null,
            color: isSelected ? null : AppColors.surfaceLight,
            borderRadius: AppSpacing.borderRadiusMd,
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : AppColors.textMuted.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : AppColors.textSecondary,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                country,
                style: AppTypography.labelLarge.copyWith(
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStateSelector() {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppSpacing.borderRadiusLg,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryStart.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.secondaryStart.withValues(alpha: 0.1),
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: const Icon(
                  Icons.map_rounded,
                  color: AppColors.secondaryStart,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'State / Region',
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_selectedState != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: AppSpacing.borderRadiusSm,
                  ),
                  child: Text(
                    _selectedState!,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Search Field
          TextField(
            controller: _stateSearchController,
            style: AppTypography.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Search states...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _stateSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _stateSearchController.clear();
                        _filterStates();
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // States Grid
          SizedBox(
            height: 180,
            child: _filteredStates.isEmpty
                ? Center(
                    child: Text(
                      'No states found',
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: AppSpacing.sm,
                      mainAxisSpacing: AppSpacing.sm,
                      childAspectRatio: 3,
                    ),
                    itemCount: _filteredStates.length,
                    itemBuilder: (context, index) {
                      final state = _filteredStates[index];
                      final isSelected = _selectedState == state;
                      final hasCachedCities = _citiesCache.containsKey(state);
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
                        child: AnimatedContainer(
                          duration: AppSpacing.durationFast,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            gradient: isSelected ? AppColors.secondaryGradient : null,
                            color: isSelected ? null : AppColors.surfaceLight,
                            borderRadius: AppSpacing.borderRadiusMd,
                            border: Border.all(
                              color: isSelected
                                  ? Colors.transparent
                                  : AppColors.textMuted.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textMuted,
                                size: 18,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  state,
                                  style: AppTypography.labelMedium.copyWith(
                                    color: isSelected
                                        ? Colors.white
                                        : AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // Show indicator if cities are cached
                              if (hasCachedCities && !isSelected)
                                Icon(
                                  Icons.bolt_rounded,
                                  size: 14,
                                  color: AppColors.success.withValues(alpha: 0.7),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCitiesSelector() {
    return AnimatedContainer(
      duration: AppSpacing.durationMedium,
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppSpacing.borderRadiusLg,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryStart.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.accentStart.withValues(alpha: 0.1),
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: const Icon(
                  Icons.location_city_rounded,
                  color: AppColors.accentStart,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Cities',
                style: AppTypography.titleSmall.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  gradient: _selectedCities.isNotEmpty
                      ? AppColors.successGradient
                      : null,
                  color: _selectedCities.isEmpty
                      ? AppColors.textMuted.withValues(alpha: 0.1)
                      : null,
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: Text(
                  '${_selectedCities.length} selected',
                  style: AppTypography.labelSmall.copyWith(
                    color: _selectedCities.isNotEmpty
                        ? Colors.white
                        : AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Search Field
          TextField(
            controller: _citySearchController,
            style: AppTypography.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Search cities...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _citySearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _citySearchController.clear();
                        _filterCities();
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Loading or Select All Row
          if (_isCitiesLoading)
            _buildCitiesLoadingState()
          else
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
                      ? AppColors.primaryStart.withValues(alpha: 0.1)
                      : AppColors.surfaceLight,
                  borderRadius: AppSpacing.borderRadiusMd,
                ),
                child: Row(
                  children: [
                    Icon(
                      _selectAllCities
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      color: _selectAllCities
                          ? AppColors.primaryStart
                          : AppColors.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Select All',
                      style: AppTypography.labelLarge.copyWith(
                        color: _selectAllCities
                            ? AppColors.primaryStart
                            : AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_filteredCities.length} cities',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          if (!_isCitiesLoading)
            // Cities List
            SizedBox(
              height: 200,
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
                            ? AppColors.primaryStart.withValues(alpha: 0.08)
                            : Colors.transparent,
                        borderRadius: AppSpacing.borderRadiusSm,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            color: isSelected
                                ? AppColors.primaryStart
                                : AppColors.textMuted,
                            size: 20,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            city,
                            style: AppTypography.bodyMedium.copyWith(
                              color: isSelected
                                  ? AppColors.primaryStart
                                  : AppColors.textPrimary,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
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
      ),
    );
  }

  Widget _buildCitiesLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          // Animated loading spinner
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.accentStart,
                  ),
                ),
              ),
              Icon(
                Icons.location_city_rounded,
                color: AppColors.accentStart,
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _LoadingTextAnimation(
            text: 'Loading cities',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Shimmer placeholder for cities
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

  Widget _buildSummaryCard() {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        gradient: AppColors.infoGradient,
        borderRadius: AppSpacing.borderRadiusLg,
        boxShadow: [
          BoxShadow(
            color: AppColors.info.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: AppSpacing.borderRadiusMd,
            ),
            child: const Icon(
              Icons.summarize_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ready to search',
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                  ),
                ),
                Text(
                  '${_selectedCities.length} cities in $_selectedState',
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_rounded,
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton() {
    final canContinue = _selectedState != null && _selectedCities.isNotEmpty;
    return GradientButton(
      text: 'Continue to Search',
      icon: Icons.rocket_launch_rounded,
      onPressed: canContinue
          ? () {
              final citiesText = _selectedCities
                  .map((city) => '$city, $_selectedState')
                  .join('; ');

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
  }
}

/// Animated loading text with dots
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
            color: AppColors.textSecondary,
          ),
    );
  }
}

/// Shimmer effect placeholder
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
                AppColors.surfaceLight,
                AppColors.textMuted.withValues(alpha: 0.1),
                AppColors.surfaceLight,
              ],
            ),
          ),
        );
      },
    );
  }
}
