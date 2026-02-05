import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/scraper_provider.dart';
import '../services/api_service.dart';
import '../core/download_helper.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/responsive_utils.dart';
import '../widgets/progress_stepper.dart';
import '../widgets/infinity_data_table.dart';

class ResultsScreen extends StatefulWidget {
  final String? jobId;
  final List<Map<String, dynamic>>? overrideResults;
  final String? title;
  final bool showHeader;

  const ResultsScreen({
    super.key,
    this.jobId,
    this.overrideResults,
    this.title,
    this.showHeader = true,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  bool _isDownloading = false;
  String? _error;
  List<Map<String, dynamic>> _loadedResults = [];

  // Search and filter state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortOption = 'Newest'; // Newest, Name A-Z, Category
  String _viewMode = 'Cards'; // Cards, Table
  String _cityFilter = 'All Cities';
  bool _contactMatchAll = false; // Any vs All selected contact filters
  bool _requireWebsite = false;
  Set<String> _contactFilters = {
    'Phone',
    'Website',
    'Maps'
  }; // Contact type filters

  // Table view state (bulk actions)
  Set<int> _selectedTableRows = {};
  int? _tableSortColumnIndex;
  bool _tableSortAscending = true;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: AppSpacing.durationMedium,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();
    _loadIfNeeded();
  }

  @override
  void didUpdateWidget(covariant ResultsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final jobIdChanged = widget.jobId != oldWidget.jobId;
    final overrideResultsChanged =
        widget.overrideResults != oldWidget.overrideResults;

    if (jobIdChanged || overrideResultsChanged) {
      _error = null;
      _loadedResults = [];
      _selectedTableRows = {};
      _tableSortColumnIndex = null;
      _tableSortAscending = true;

      if (jobIdChanged) {
        _searchController.text = '';
        _searchQuery = '';
        _cityFilter = 'All Cities';
      }

      _loadIfNeeded();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadIfNeeded() async {
    if (widget.jobId == null || widget.overrideResults != null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _loadedResults = [];
    });

    try {
      final data = await _apiService.getJobResults(widget.jobId!);
      final results = List<Map<String, dynamic>>.from(data['results'] ?? []);
      if (mounted) {
        setState(() {
          _loadedResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load results: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshResults() async {
    if (widget.jobId == null || widget.overrideResults != null) {
      return;
    }

    try {
      final data = await _apiService.getJobResults(widget.jobId!);
      final results = List<Map<String, dynamic>>.from(data['results'] ?? []);
      if (mounted) {
        setState(() {
          _loadedResults = results;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh results: $e'),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _resolveResults(ScraperProvider scraperProvider) {
    if (widget.overrideResults != null) {
      return widget.overrideResults!;
    }
    if (widget.jobId != null) {
      return _loadedResults;
    }
    return scraperProvider.currentJob?.results ?? [];
  }

  List<Map<String, dynamic>> _filterAndSortResults(
      List<Map<String, dynamic>> results) {
    var filtered = results.where((business) {
      // Apply search filter
      if (_searchQuery.isNotEmpty) {
        final name =
            (business['business_name'] ?? business['name'] ?? '')
                .toString()
                .toLowerCase();
        final category = (business['category'] ?? '').toString().toLowerCase();
        final city = (business['city'] ?? '').toString().toLowerCase();
        final address = (business['address'] ?? '').toString().toLowerCase();
        final query = _searchQuery.toLowerCase();

        if (!name.contains(query) &&
            !category.contains(query) &&
            !city.contains(query) &&
            !address.contains(query)) {
          return false;
        }
      }

      // City filter
      if (_cityFilter != 'All Cities') {
        final city = (business['city'] ?? '').toString().trim();
        final state = (business['state'] ?? '').toString().trim();
        final cityState = state.isEmpty ? city : '$city, $state';
        if (cityState != _cityFilter) {
          return false;
        }
      }

      // Apply contact type filters
      final hasPhone = business['phone'] != null &&
          (business['phone'] ?? '').toString().isNotEmpty &&
          business['phone'] != 'N/A';
      final hasWebsite = business['website'] != null &&
          (business['website'] ?? '').toString().isNotEmpty &&
          business['website'] != 'N/A';
      final hasAddress = business['address'] != null &&
          (business['address'] ?? '').toString().isNotEmpty &&
          business['address'] != 'N/A';

      if (_requireWebsite && !hasWebsite) return false;

      // If no filters selected, show all
      if (_contactFilters.isEmpty) return true;

      if (_contactMatchAll) {
        if (_contactFilters.contains('Phone') && !hasPhone) return false;
        if (_contactFilters.contains('Website') && !hasWebsite) return false;
        if (_contactFilters.contains('Maps') && !hasAddress) return false;
        return true;
      }

      // Match ANY selected filter (OR logic)
      if (_contactFilters.contains('Phone') && hasPhone) return true;
      if (_contactFilters.contains('Website') && hasWebsite) return true;
      if (_contactFilters.contains('Maps') && hasAddress) return true;
      return false;
    }).toList();

    // Apply sorting
    if (_sortOption == 'Name A-Z') {
      filtered.sort((a, b) {
        final nameA = (a['business_name'] ?? a['name'] ?? '')
            .toString()
            .toLowerCase();
        final nameB = (b['business_name'] ?? b['name'] ?? '')
            .toString()
            .toLowerCase();
        return nameA.compareTo(nameB);
      });
    } else if (_sortOption == 'Category') {
      filtered.sort((a, b) {
        final catA = (a['category'] ?? '').toString().toLowerCase();
        final catB = (b['category'] ?? '').toString().toLowerCase();
        return catA.compareTo(catB);
      });
    } else if (_sortOption == 'City') {
      filtered.sort((a, b) {
        final cityA = (a['city'] ?? '').toString().toLowerCase();
        final cityB = (b['city'] ?? '').toString().toLowerCase();
        if (cityA != cityB) return cityA.compareTo(cityB);
        final nameA = (a['business_name'] ?? a['name'] ?? '')
            .toString()
            .toLowerCase();
        final nameB = (b['business_name'] ?? b['name'] ?? '')
            .toString()
            .toLowerCase();
        return nameA.compareTo(nameB);
      });
    }
    // 'Newest' keeps the original order

    return filtered;
  }

  Future<void> _launchUrl(String url) async {
    if (url.isEmpty || url == 'N/A') return;

    String finalUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      finalUrl = 'https://$url';
    }

    try {
      final uri = Uri.parse(finalUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open: $url'),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening URL: $e'),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    }
  }

  Future<void> _launchPhone(String phone) async {
    if (phone.isEmpty || phone == 'N/A') return;
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error launching phone: $e');
    }
  }

  Future<void> _launchMaps(String address) async {
    if (address.isEmpty || address == 'N/A') return;

    final encodedAddress = Uri.encodeComponent(address);
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$encodedAddress',
    );

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching maps: $e');
    }
  }

  List<Widget> _buildContactFilterChips() {
    const filters = ['Phone', 'Website', 'Maps'];
    return filters.map((filter) {
      final isActive = _contactFilters.contains(filter);
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.xs),
        child: GestureDetector(
          onTap: () {
            setState(() {
              if (isActive) {
                _contactFilters.remove(filter);
              } else {
                _contactFilters.add(filter);
              }
              _selectedTableRows = {};
            });
          },
          child: AnimatedContainer(
            duration: AppSpacing.durationFast,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.primaryBlue.withValues(alpha: 0.18)
                  : AppColors.elevatedCardDark,
              borderRadius: AppSpacing.borderRadiusSm,
              border: Border.all(
                color: isActive
                    ? AppColors.primaryBlueLight.withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.08),
                width: isActive ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  filter == 'Phone'
                      ? Icons.phone_rounded
                      : filter == 'Website'
                          ? Icons.language_rounded
                          : Icons.location_on_rounded,
                  size: 14,
                  color: isActive ? Colors.white : Colors.white70,
                ),
                const SizedBox(width: 4),
                Text(
                  filter,
                  style: AppTypography.labelSmall.copyWith(
                    color: isActive ? Colors.white : Colors.white70,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildContactMatchModeChips() {
    return [
      _matchModeChip(
        label: 'ANY',
        isActive: !_contactMatchAll,
        onTap: () {
          setState(() {
            _contactMatchAll = false;
            _selectedTableRows = {};
          });
        },
      ),
      const SizedBox(width: AppSpacing.xs),
      _matchModeChip(
        label: 'ALL',
        isActive: _contactMatchAll,
        onTap: () {
          setState(() {
            _contactMatchAll = true;
            _selectedTableRows = {};
          });
        },
      ),
    ];
  }

  Widget _matchModeChip({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppSpacing.durationFast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryBlue.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: AppSpacing.borderRadiusSm,
          border: Border.all(
            color: isActive
                ? AppColors.primaryBlueLight.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: isActive ? Colors.white : Colors.white60,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final scraperProvider = Provider.of<ScraperProvider>(context);
    final allResults = _resolveResults(scraperProvider);
    final filteredResults = _filterAndSortResults(allResults);
    final layoutType =
        AppBreakpoints.getLayoutType(MediaQuery.of(context).size.width);

      return Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: SafeArea(
        top: widget.showHeader,
        bottom: false,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Stack(
            children: [
              _buildBackgroundEffects(),
              Column(
                children: [
                  if (widget.showHeader) _buildHeader(allResults.length),
                  if (widget.showHeader) const WorkflowStepper(currentStep: 3),
                  _buildSearchAndFilter(layoutType, allResults),
                  _buildStats(filteredResults),
                  Expanded(child: _buildContent(filteredResults, layoutType)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundEffects() {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _GridPainter(),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                AppColors.primaryBlue.withValues(alpha: 0.18),
                Colors.transparent,
              ],
              radius: 1.2,
              center: const Alignment(0, -0.8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark.withValues(alpha: 0.9),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Infinity Leads',
                  style: AppTypography.titleLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.title ?? 'Live Results',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primaryBlueLight,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _downloadButton(count),
        ],
      ),
    );
  }

  Widget _downloadButton(int count) {
    return GestureDetector(
      onTap:
          count > 0 && !_isDownloading ? () => _downloadResults(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.elevatedCardDark,
          borderRadius: AppSpacing.borderRadiusSm,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            if (_isDownloading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.successGreen,
                  ),
                ),
              )
            else
              const Icon(Icons.download_rounded,
                  color: AppColors.successGreen, size: 18),
            const SizedBox(width: 6),
            Text(
              'Excel',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.successGreen,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter(
    LayoutType layoutType,
    List<Map<String, dynamic>> allResults,
  ) {
    final canTable = ResponsiveUtils.shouldUseTableView(layoutType);
    final cityOptions = _resolveCityOptions(allResults);
    final hasCityValue = cityOptions.contains(_cityFilter);
    final safeCityFilter = hasCityValue ? _cityFilter : 'All Cities';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Column(
        children: [
          // Search bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.elevatedCardDark,
              borderRadius: AppSpacing.borderRadiusSm,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: TextField(
              controller: _searchController,
              style: AppTypography.bodyMedium.copyWith(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by name, category, or city...',
                hintStyle: AppTypography.bodyMedium.copyWith(
                  color: Colors.white38,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Colors.white54,
                  size: 20,
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear_rounded,
                          color: Colors.white54,
                          size: 20,
                        ),
                         onPressed: () {
                           setState(() {
                             _searchController.clear();
                             _searchQuery = '';
                             _selectedTableRows = {};
                           });
                         },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
              ),
               onChanged: (value) {
                 setState(() {
                   _searchQuery = value;
                   _selectedTableRows = {};
                 });
               },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Contact Type Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  'Show Results With:',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white60,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ..._buildContactFilterChips(),
                const SizedBox(width: AppSpacing.sm),
                ..._buildContactMatchModeChips(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // City + quick clear
          Row(
            children: [
              PopupMenuButton<String>(
                initialValue: hasCityValue ? _cityFilter : null,
                color: AppColors.surfaceDark,
                onSelected: (value) {
                  setState(() {
                    _cityFilter = value;
                    _selectedTableRows = {};
                  });
                },
                itemBuilder: (context) => cityOptions
                    .map((c) => PopupMenuItem<String>(
                          value: c,
                          child: Text(
                            c,
                            style: AppTypography.bodySmall.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ))
                    .toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.elevatedCardDark,
                    borderRadius: AppSpacing.borderRadiusSm,
                    border: Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_city_rounded,
                        color: AppColors.primaryBlueLight,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          safeCityFilter,
                          style: AppTypography.labelSmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.expand_more_rounded,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _requireWebsite,
                      onChanged: (value) {
                    setState(() {
                      _requireWebsite = value ?? false;
                      _selectedTableRows = {};
                    });
                  },
                      activeColor: AppColors.primaryBlue,
                      checkColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _requireWebsite = !_requireWebsite;
                        _selectedTableRows = {};
                      });
                    },
                    child: Text(
                      'Has website',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (_searchQuery.isNotEmpty ||
                  _cityFilter != 'All Cities' ||
                  _requireWebsite ||
                  _contactFilters.length < 3)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                      _cityFilter = 'All Cities';
                      _contactFilters = {'Phone', 'Website', 'Maps'};
                      _contactMatchAll = false;
                      _requireWebsite = false;
                      _sortOption = 'Newest';
                      _selectedTableRows = {};
                    });
                  },
                  child: Text(
                    'Clear',
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Sort and View toggles
          Row(
            children: [
              Expanded(child: SizedBox.shrink()),
              if (canTable) ...[
                const SizedBox(width: AppSpacing.sm),
                _viewToggle(),
              ],
              const SizedBox(width: AppSpacing.sm),
              PopupMenuButton<String>(
                initialValue: _sortOption,
                color: AppColors.surfaceDark,
                icon: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.elevatedCardDark,
                    borderRadius: AppSpacing.borderRadiusSm,
                    border: Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        color: AppColors.primaryBlueLight,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _sortOption,
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                 onSelected: (value) {
                   setState(() {
                     _sortOption = value;
                     _selectedTableRows = {};
                   });
                 },
                itemBuilder: (context) => [
                  _buildSortMenuItem('Newest', Icons.access_time_rounded),
                  _buildSortMenuItem('Name A-Z', Icons.sort_by_alpha_rounded),
                  _buildSortMenuItem('Category', Icons.category_rounded),
                  _buildSortMenuItem('City', Icons.location_city_rounded),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _resolveCityOptions(List<Map<String, dynamic>> results) {
    final set = <String>{'All Cities'};
    for (final r in results) {
      final city = (r['city'] ?? '').toString().trim();
      if (city.isEmpty || city == 'N/A') continue;
      final state = (r['state'] ?? '').toString().trim();
      final key = state.isEmpty ? city : '$city, $state';
      set.add(key);
    }
    final list = set.toList();
    if (list.length <= 1) return const ['All Cities'];
    final rest = list.where((e) => e != 'All Cities').toList()..sort();
    return ['All Cities', ...rest];
  }

  Widget _viewToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.elevatedCardDark,
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          _toggleChip('Cards', Icons.view_module_rounded),
          _toggleChip('Table', Icons.table_chart_rounded),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, IconData icon) {
    final isActive = _viewMode == label;
    return GestureDetector(
      onTap: () => setState(() {
        _viewMode = label;
        _selectedTableRows = {};
        _tableSortColumnIndex = null;
        _tableSortAscending = true;
      }),
      child: AnimatedContainer(
        duration: AppSpacing.durationFast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryBlue.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: AppSpacing.borderRadiusSm,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? Colors.white : Colors.white54,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: isActive ? Colors.white : Colors.white54,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildSortMenuItem(String value, IconData icon) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white70),
          const SizedBox(width: AppSpacing.xs),
          Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(List<Map<String, dynamic>> results) {
    final cities = results
        .map((r) => (r['city'] ?? '').toString().trim())
        .where((c) => c.isNotEmpty && c != 'N/A')
        .toSet();
    final categories = results
        .map((r) => (r['category'] ?? '').toString().trim())
        .where((c) => c.isNotEmpty && c != 'N/A')
        .toSet();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _statTile('Leads', results.length.toString()),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _statTile('Cities', cities.length.toString()),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _statTile('Cats', categories.length.toString()),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Container(
      padding: AppSpacing.paddingSm,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.18),
            blurRadius: 14,
            spreadRadius: -10,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white60,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String? _tableSortKeyForColumn(int columnIndex) {
    switch (columnIndex) {
      case 0:
        return 'business_name';
      case 1:
        return 'category';
      case 2:
        return 'city';
      case 3:
        return 'phone';
      case 4:
        return 'website';
      default:
        return null;
    }
  }

  Widget _buildBulkActionsBar(List<Map<String, dynamic>> tableRows) {
    final count = _selectedTableRows.length;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.elevatedCardDark,
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.18),
              borderRadius: AppSpacing.borderRadiusRound,
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              '$count selected',
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed:
                count > 0 ? () => _exportSelectedCsv(tableRows) : null,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: AppColors.successGreen.withValues(alpha: 0.5),
              ),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(
              'Export CSV',
              style: AppTypography.labelSmall.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed:
                count > 0 ? () => _exportSelectedJson(tableRows) : null,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: AppColors.infoBlue.withValues(alpha: 0.5),
              ),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
            ),
            icon: const Icon(Icons.data_object_rounded, size: 18),
            label: Text(
              'JSON',
              style: AppTypography.labelSmall.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(
            onPressed: () => setState(() => _selectedTableRows = {}),
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
    );
  }

  Future<void> _exportSelectedCsv(List<Map<String, dynamic>> tableRows) async {
    if (_selectedTableRows.isEmpty) return;

    final selected = _selectedTableRows
        .where((i) => i >= 0 && i < tableRows.length)
        .map((i) => tableRows[i])
        .toList();

    final csv = _toCsv(selected);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    await saveCsv(csv, 'infinity_leads_selected_$stamp', context: context);
  }

  Future<void> _exportSelectedJson(List<Map<String, dynamic>> tableRows) async {
    if (_selectedTableRows.isEmpty) return;

    final selected = _selectedTableRows
        .where((i) => i >= 0 && i < tableRows.length)
        .map((i) => tableRows[i])
        .toList();

    final payload = jsonEncode(selected);
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    await saveJson(payload, 'infinity_leads_selected_$stamp', context: context);
  }

  String _toCsv(List<Map<String, dynamic>> rows) {
    const headers = [
      'business_name',
      'category',
      'city',
      'state',
      'phone',
      'website',
      'address',
      'google_maps_url',
    ];

    final buffer = StringBuffer();
    buffer.writeln(headers.join(','));
    for (final row in rows) {
      final values = headers.map((h) => _csvEscape(row[h])).toList();
      buffer.writeln(values.join(','));
    }
    return buffer.toString();
  }

  String _csvEscape(dynamic value) {
    final s = (value ?? '').toString();
    final escaped = s.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('\n') ||
        escaped.contains('\r')) {
      return '"$escaped"';
    }
    return escaped;
  }

  Widget _buildContent(
      List<Map<String, dynamic>> results, LayoutType layoutType) {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (results.isEmpty) {
      return _buildEmptyState();
    }

    final canTable = ResponsiveUtils.shouldUseTableView(layoutType);
    if (canTable && _viewMode == 'Table') {
      final baseRows = results
          .map((r) => {
                'business_name': r['business_name'] ?? r['name'] ?? 'Unknown',
                'category': r['category'] ?? 'N/A',
                'city': r['city'] ?? 'N/A',
                'state': r['state'] ?? '',
                'phone': r['phone'] ?? 'N/A',
                'website': r['website'] ?? 'N/A',
                'address': r['address'] ?? 'N/A',
                'google_maps_url': r['google_maps_url'] ?? '',
              })
          .toList();

      final rows = List<Map<String, dynamic>>.from(baseRows);
      if (_tableSortColumnIndex != null) {
        final key = _tableSortKeyForColumn(_tableSortColumnIndex!);
        if (key != null) {
          rows.sort((a, b) {
            final av = (a[key] ?? '').toString().toLowerCase();
            final bv = (b[key] ?? '').toString().toLowerCase();
            return av.compareTo(bv);
          });
          if (!_tableSortAscending) {
            final reversed = rows.reversed.toList();
            rows
              ..clear()
              ..addAll(reversed);
          }
        }
      }
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selectedTableRows.isNotEmpty)
              _buildBulkActionsBar(rows),
            InfinityDataTable(
              layoutType: layoutType,
              columns: [
                const InfinityDataColumn(
                    label: 'Business Name', keyName: 'business_name'),
                const InfinityDataColumn(label: 'Category', keyName: 'category'),
                const InfinityDataColumn(label: 'City', keyName: 'city'),
                const InfinityDataColumn(label: 'Phone', keyName: 'phone'),
                const InfinityDataColumn(label: 'Website', keyName: 'website'),
                InfinityDataColumn(
                  label: 'Actions',
                  keyName: 'actions',
                  cellBuilder: (row) => Row(
                    children: [
                      _tableActionButton(
                        icon: Icons.call,
                        tooltip: 'Call',
                        onTap: () => _launchPhone(row['phone'] ?? ''),
                      ),
                      _tableActionButton(
                        icon: Icons.language,
                        tooltip: 'Website',
                        onTap: () => _launchUrl(row['website'] ?? ''),
                      ),
                      _tableActionButton(
                        icon: Icons.location_on,
                        tooltip: 'Map',
                        onTap: () => _launchMaps(row['address'] ?? ''),
                      ),
                    ],
                  ),
                ),
              ],
              rows: rows,
              sortable: true,
              showCheckboxes: true,
              selectedRows: _selectedTableRows,
              onSelectionChanged: (selection) {
                setState(() => _selectedTableRows = selection);
              },
              sortColumnIndex: _tableSortColumnIndex,
              sortAscending: _tableSortAscending,
              onSort: (columnIndex, ascending) {
                setState(() {
                  _tableSortColumnIndex = columnIndex;
                  _tableSortAscending = ascending;
                  _selectedTableRows = {};
                });
              },
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshResults,
      color: AppColors.primaryBlue,
      backgroundColor: AppColors.surfaceDark,
      child: layoutType == LayoutType.mobile
          ? ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final business = results[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: _LeadCard(
                    business: business,
                    onPhoneTap: () => _launchPhone(business['phone'] ?? ''),
                    onWebsiteTap: () => _launchUrl(business['website'] ?? ''),
                    onAddressTap: () => _launchMaps(business['address'] ?? ''),
                  ),
                );
              },
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: layoutType == LayoutType.desktopLarge
                    ? 4
                    : layoutType == LayoutType.desktopMedium
                        ? 3
                        : 2,
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                childAspectRatio: 1.8,
              ),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final business = results[index];
                return _LeadCard(
                  business: business,
                  onPhoneTap: () => _launchPhone(business['phone'] ?? ''),
                  onWebsiteTap: () => _launchUrl(business['website'] ?? ''),
                  onAddressTap: () => _launchMaps(business['address'] ?? ''),
                );
              },
            ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Loading results...',
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppSpacing.borderRadiusSm,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryBlue, AppColors.primaryBlueDark],
              ),
              borderRadius: AppSpacing.borderRadiusSm,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.25),
                  blurRadius: 8,
                  spreadRadius: -6,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Container(
          padding: AppSpacing.paddingMd,
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: AppColors.dangerRed, size: 40),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Failed to Load',
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.white60,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton.icon(
                onPressed: _loadIfNeeded,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Container(
          padding: AppSpacing.paddingLg,
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.22),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_off_rounded,
                  color: AppColors.primaryBlueLight,
                  size: 48,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'No Results Yet',
                style: AppTypography.titleLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Start your first lead search to discover\nbusiness opportunities in your area',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: Colors.white60,
                  height: 1.5,
                ),
              ),
              if (_searchQuery.isNotEmpty || _contactFilters.length < 3) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'No results match your current filters.\nTry adjusting your search criteria.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white38,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                      _contactFilters = {'Phone', 'Website', 'Maps'};
                    });
                  },
                  icon: const Icon(Icons.clear_all_rounded, size: 18),
                  label: const Text('Clear Filters'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryBlueLight,
                    side: BorderSide(color: AppColors.primaryBlue.withValues(alpha: 0.35)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadResults(BuildContext ctx) async {
    final scaffoldMessenger = ScaffoldMessenger.of(ctx);
    final scraperProvider =
        Provider.of<ScraperProvider>(ctx, listen: false);

    setState(() => _isDownloading = true);

    try {
      final downloadData = widget.jobId != null
          ? await _apiService.downloadResults(widget.jobId!)
          : await scraperProvider.downloadResults();

      final filename = downloadData['filename'] as String;
      final content = downloadData['content'] as String;

      if (!mounted) return;
      await saveExcel(content, filename, context: context);
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to download: $e'),
          backgroundColor: AppColors.dangerRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }
}

class _LeadCard extends StatefulWidget {
  final Map<String, dynamic> business;
  final VoidCallback? onPhoneTap;
  final VoidCallback? onWebsiteTap;
  final VoidCallback? onAddressTap;

  const _LeadCard({
    required this.business,
    this.onPhoneTap,
    this.onWebsiteTap,
    this.onAddressTap,
  });

  @override
  State<_LeadCard> createState() => _LeadCardState();
}

class _LeadCardState extends State<_LeadCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _expandController;
  final Set<String> _expandedContacts = {};

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _toggleContactExpanded(String contactType) {
    setState(() {
      if (_expandedContacts.contains(contactType)) {
        _expandedContacts.remove(contactType);
      } else {
        _expandedContacts.add(contactType);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = widget.business['phone'] != null &&
        widget.business['phone'] != 'N/A' &&
        widget.business['phone'].toString().isNotEmpty;
    final hasWebsite = widget.business['website'] != null &&
        widget.business['website'] != 'N/A' &&
        widget.business['website'].toString().isNotEmpty;
    final hasAddress = widget.business['address'] != null &&
        widget.business['address'] != 'N/A' &&
        widget.business['address'].toString().isNotEmpty;

    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.elevatedCardDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border:
            Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.14),
            blurRadius: 18,
            spreadRadius: -10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Business Info Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.business['business_name'] ?? 'Unknown Business',
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (hasAddress)
                      Text(
                        widget.business['address'],
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white60,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.successGreen.withValues(alpha: 0.12),
                  borderRadius: AppSpacing.borderRadiusRound,
                  border: Border.all(
                    color: AppColors.successGreen.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  widget.business['category'] ?? 'Category',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.successGreen,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Verified Badge
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.successGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Verified Lead',
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white60,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Animated Contact Buttons
          Column(
            children: [
              if (hasPhone) ...[
                _buildExpandableContactButton(
                  'Phone',
                  Icons.phone_rounded,
                  widget.business['phone'] ?? '',
                  widget.onPhoneTap,
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              if (hasWebsite) ...[
                _buildExpandableContactButton(
                  'Website',
                  Icons.language_rounded,
                  widget.business['website'] ?? '',
                  widget.onWebsiteTap,
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              if (hasAddress)
                _buildExpandableContactButton(
                  'Maps',
                  Icons.location_on_rounded,
                  widget.business['address'] ?? '',
                  widget.onAddressTap,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableContactButton(
    String label,
    IconData icon,
    String value,
    VoidCallback? onTap,
  ) {
    final isExpanded = _expandedContacts.contains(label);

    return GestureDetector(
      onTap: () {
        if (isExpanded) {
          // Second click: perform action
          onTap?.call();
          _toggleContactExpanded(label);
        } else {
          // First click: expand to show value
          _toggleContactExpanded(label);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: isExpanded ? AppSpacing.xs : AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          gradient: isExpanded
              ? LinearGradient(
                  colors: [AppColors.primaryBlue, AppColors.primaryBlueDark],
                )
              : LinearGradient(
                  colors: [
                    AppColors.primaryBlue.withValues(alpha: 0.7),
                    AppColors.primaryBlueDark.withValues(alpha: 0.7),
                  ],
                ),
          borderRadius: AppSpacing.borderRadiusSm,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlueDark.withValues(
                alpha: isExpanded ? 0.5 : 0.3,
              ),
              blurRadius: isExpanded ? 12 : 8,
              spreadRadius: isExpanded ? -4 : -6,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isExpanded) ...[
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (isExpanded) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 14,
              ),
            ] else
              Icon(
                Icons.expand_more_rounded,
                color: Colors.white70,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}

// Colors now consolidated in AppColors

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    const spacing = 40.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
