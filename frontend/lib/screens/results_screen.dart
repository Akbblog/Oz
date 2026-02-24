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
  String? _emptyMessage;
  List<Map<String, dynamic>> _loadedResults = [];
  String? _loadedJobId;

  // Search and filter state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortOption = 'Newest'; // Newest, Name A-Z, Category
  String _viewMode = 'Cards'; // Cards, Table
  String _cityFilter = 'All Cities';
  bool _contactMatchAll = false; // Any vs All selected contact filters
  bool _requireWebsite = false;
  Set<String> _contactFilters = {'Phone', 'Email', 'Website', 'Maps'};
  // Contact type filters

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
      _emptyMessage = null;
      _loadedResults = [];
      _loadedJobId = null;
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
    if (widget.overrideResults != null) return;

    if (widget.jobId != null) {
      await _loadJobResults(widget.jobId!);
      return;
    }

    await _loadMostRecentResults();
  }

  Future<void> _refreshResults() async {
    if (widget.overrideResults != null) {
      return;
    }

    try {
      final jobId = widget.jobId ?? _loadedJobId;
      if (jobId == null) return;
      await _loadJobResults(jobId, showLoading: false);
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

  Future<void> _loadJobResults(
    String jobId, {
    bool showLoading = true,
  }) async {
    if (jobId.trim().isEmpty) return;

    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
        _emptyMessage = null;
        _loadedResults = [];
        _loadedJobId = jobId;
      });
    } else {
      setState(() {
        _error = null;
        _emptyMessage = null;
        _loadedJobId = jobId;
      });
    }

    try {
      final data = await _apiService.getJobResults(jobId);
      final results = List<Map<String, dynamic>>.from(data['results'] ?? []);
      if (!mounted) return;
      setState(() {
        _loadedResults = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load results: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMostRecentResults() async {
    // If we have live results (current job), don't replace the UI with a loader.
    final scraperProvider =
        Provider.of<ScraperProvider>(context, listen: false);
    final liveResults = scraperProvider.currentJob?.results;
    if (liveResults != null && liveResults.isNotEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _emptyMessage = null;
      _loadedResults = [];
      _loadedJobId = null;
    });

    try {
      final jobs = await _apiService.getUserJobs();
      if (!mounted) return;

      if (jobs.isEmpty) {
        setState(() {
          _isLoading = false;
          _loadedResults = [];
          _loadedJobId = null;
          _emptyMessage = 'No jobs found. Start a new search to see results.';
        });
        return;
      }

      final latestJob = jobs.first;
      final latestJobId = (latestJob['job_id'] ?? '').toString();
      if (latestJobId.trim().isEmpty) {
        setState(() {
          _isLoading = false;
          _loadedResults = [];
          _loadedJobId = null;
          _emptyMessage = 'No recent job id found.';
        });
        return;
      }

      final data = await _apiService.getJobResults(latestJobId);
      final results = List<Map<String, dynamic>>.from(data['results'] ?? []);
      if (!mounted) return;
      setState(() {
        _loadedResults = results;
        _loadedJobId = latestJobId;
        _isLoading = false;
        if (results.isEmpty) {
          _emptyMessage = 'Your most recent job has no results yet.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load results: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _resolveResults(ScraperProvider scraperProvider) {
    if (widget.overrideResults != null) {
      return widget.overrideResults!;
    }
    if (widget.jobId != null) {
      return _loadedResults;
    }
    final live = scraperProvider.currentJob?.results;
    if (live != null && live.isNotEmpty) return live;
    return _loadedResults;
  }

  List<Map<String, dynamic>> _filterAndSortResults(
      List<Map<String, dynamic>> results) {
    var filtered = results.where((business) {
      // Apply search filter
      if (_searchQuery.isNotEmpty) {
        final name = (business['business_name'] ?? business['name'] ?? '')
            .toString()
            .toLowerCase();
        final category = (business['category'] ?? '').toString().toLowerCase();
        final city = (business['city'] ?? '').toString().toLowerCase();
        final address = (business['address'] ?? '').toString().toLowerCase();
        final email = (business['email'] ?? '').toString().toLowerCase();
        final query = _searchQuery.toLowerCase();

        if (!name.contains(query) &&
            !category.contains(query) &&
            !city.contains(query) &&
            !email.contains(query) &&
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
      final hasEmail = business['email'] != null &&
          (business['email'] ?? '').toString().isNotEmpty &&
          business['email'] != 'N/A';
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
        if (_contactFilters.contains('Email') && !hasEmail) return false;
        if (_contactFilters.contains('Website') && !hasWebsite) return false;
        if (_contactFilters.contains('Maps') && !hasAddress) return false;
        return true;
      }

      // Match ANY selected filter (OR logic)
      if (_contactFilters.contains('Phone') && hasPhone) return true;
      if (_contactFilters.contains('Email') && hasEmail) return true;
      if (_contactFilters.contains('Website') && hasWebsite) return true;
      if (_contactFilters.contains('Maps') && hasAddress) return true;
      return false;
    }).toList();

    // Apply sorting
    if (_sortOption == 'Name A-Z') {
      filtered.sort((a, b) {
        final nameA =
            (a['business_name'] ?? a['name'] ?? '').toString().toLowerCase();
        final nameB =
            (b['business_name'] ?? b['name'] ?? '').toString().toLowerCase();
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
        final nameA =
            (a['business_name'] ?? a['name'] ?? '').toString().toLowerCase();
        final nameB =
            (b['business_name'] ?? b['name'] ?? '').toString().toLowerCase();
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

  Future<void> _launchEmail(String email) async {
    if (email.isEmpty || email == 'N/A') return;
    final cleanEmail = email.trim();
    final uri = Uri.parse('mailto:$cleanEmail');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error launching email: $e');
    }
  }

  List<Widget> _buildContactFilterChips() {
    const filters = ['Phone', 'Email', 'Website', 'Maps'];
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
                      : filter == 'Email'
                          ? Icons.email_rounded
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
                  _contactFilters.length < 4)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                      _cityFilter = 'All Cities';
                      _contactFilters = {'Phone', 'Email', 'Website', 'Maps'};
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
        return 'email';
      case 5:
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
            onPressed: count > 0 ? () => _exportSelectedCsv(tableRows) : null,
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
            onPressed: count > 0 ? () => _exportSelectedJson(tableRows) : null,
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
      'whatsapp',
      'email',
      'website',
      'whatsapp_url',
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
                'whatsapp': r['whatsapp'] ?? 'N/A',
                'email': r['email'] ?? 'N/A',
                'website': r['website'] ?? 'N/A',
                'whatsapp_url': r['whatsapp_url'] ?? 'N/A',
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
            if (_selectedTableRows.isNotEmpty) _buildBulkActionsBar(rows),
            InfinityDataTable(
              layoutType: layoutType,
              columns: [
                const InfinityDataColumn(
                    label: 'Business Name', keyName: 'business_name'),
                const InfinityDataColumn(
                    label: 'Category', keyName: 'category'),
                const InfinityDataColumn(label: 'City', keyName: 'city'),
                const InfinityDataColumn(label: 'Phone', keyName: 'phone'),
                const InfinityDataColumn(label: 'Email', keyName: 'email'),
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
                        icon: Icons.email_rounded,
                        tooltip: 'Email',
                        onTap: () => _launchEmail(row['email'] ?? ''),
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
                    onEmailTap: () => _launchEmail(business['email'] ?? ''),
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
                childAspectRatio: 1.9,
              ),
              itemCount: results.length,
              itemBuilder: (context, index) {
                final business = results[index];
                return _LeadCard(
                  business: business,
                  onEmailTap: () => _launchEmail(business['email'] ?? ''),
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
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
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
                _emptyMessage ??
                    'Start your first lead search to discover\nbusiness opportunities in your area',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: Colors.white60,
                  height: 1.5,
                ),
              ),
              if (_searchQuery.isNotEmpty || _contactFilters.length < 4) ...[
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
                      _contactFilters = {'Phone', 'Email', 'Website', 'Maps'};
                    });
                  },
                  icon: const Icon(Icons.clear_all_rounded, size: 18),
                  label: const Text('Clear Filters'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryBlueLight,
                    side: BorderSide(
                        color: AppColors.primaryBlue.withValues(alpha: 0.35)),
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
    final scraperProvider = Provider.of<ScraperProvider>(ctx, listen: false);

    setState(() => _isDownloading = true);

    try {
      final downloadJobId = widget.jobId ?? _loadedJobId;
      final downloadData = downloadJobId != null
          ? await _apiService.downloadResults(downloadJobId)
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
  final VoidCallback? onEmailTap;
  final VoidCallback? onWebsiteTap;
  final VoidCallback? onAddressTap;

  const _LeadCard({
    required this.business,
    this.onEmailTap,
    this.onWebsiteTap,
    this.onAddressTap,
  });

  @override
  State<_LeadCard> createState() => _LeadCardState();
}

class _LeadCardState extends State<_LeadCard> {
  @override
  Widget build(BuildContext context) {
    final business = widget.business;

    final name = (business['business_name'] ?? business['name'] ?? 'Unknown')
        .toString()
        .trim();
    final category = (business['category'] ?? '').toString().trim();
    final address = (business['address'] ?? '').toString().trim();
    final phone = (business['phone'] ?? '').toString().trim();
    final email = (business['email'] ?? '').toString().trim();
    final website = (business['website'] ?? '').toString().trim();

    final hasPhone = phone.isNotEmpty && phone != 'N/A';
    final hasEmail = email.isNotEmpty && email != 'N/A';
    final hasWebsite = website.isNotEmpty && website != 'N/A';
    final hasAddress = address.isNotEmpty && address != 'N/A';
    final hasCategory = category.isNotEmpty && category != 'N/A';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.surfaceDark,
            AppColors.surfaceDark.withValues(alpha: 0.78),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.10),
            blurRadius: 16,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name.isEmpty ? 'Unknown' : name,
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasEmail)
                          _iconButton(
                            icon: Icons.email_rounded,
                            color: AppColors.primaryBlueLight,
                            tooltip: 'Send Email',
                            onTap: widget.onEmailTap,
                          ),
                        if (hasWebsite)
                          _iconButton(
                            icon: Icons.language_rounded,
                            color: AppColors.primaryBlueLight,
                            tooltip: 'Open Website',
                            onTap: widget.onWebsiteTap,
                          ),
                        if (hasAddress)
                          _iconButton(
                            icon: Icons.location_on_rounded,
                            color: AppColors.successGreen,
                            tooltip: 'View on Maps',
                            onTap: widget.onAddressTap,
                          ),
                      ],
                    ),
                    if (hasCategory) ...[
                      const SizedBox(height: 6),
                      _categoryBadge(category),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (hasAddress)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                address,
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.white60,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (hasPhone)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.phone_rounded,
                    size: 16,
                    color: AppColors.successGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      phone,
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white,
                        fontFamily: 'Roboto Mono',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.successGreen,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Verified Lead',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }

  Widget _categoryBadge(String category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.successGreen.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.successGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        category,
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.successGreen,
          fontWeight: FontWeight.w600,
          fontSize: 11,
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
