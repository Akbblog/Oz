
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
  String _activeFilter = 'All'; // All, Has Phone, Has Website
  String _sortOption = 'Newest'; // Newest, Name A-Z, Category
  String _viewMode = 'Cards'; // Cards, Table

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
            backgroundColor: AppColors.rose,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _resolveResults(ScraperProvider scraperProvider) {
    if (widget.overrideResults != null) {
      return widget.overrideResults!;
    }
    if (_loadedResults.isNotEmpty) {
      return _loadedResults;
    }
    return scraperProvider.currentJob?.results ?? [];
  }

  List<Map<String, dynamic>> _filterAndSortResults(List<Map<String, dynamic>> results) {
    var filtered = results.where((business) {
      // Apply search filter
      if (_searchQuery.isNotEmpty) {
        final name = (business['name'] ?? '').toString().toLowerCase();
        final category = (business['category'] ?? '').toString().toLowerCase();
        final city = (business['city'] ?? '').toString().toLowerCase();
        final query = _searchQuery.toLowerCase();

        if (!name.contains(query) &&
            !category.contains(query) &&
            !city.contains(query)) {
          return false;
        }
      }

      // Apply data quality filters
      if (_activeFilter == 'Has Phone') {
        final phone = business['phone'] ?? '';
        if (phone.isEmpty || phone == 'N/A') return false;
      } else if (_activeFilter == 'Has Website') {
        final website = business['website'] ?? '';
        if (website.isEmpty || website == 'N/A') return false;
      }

      return true;
    }).toList();

    // Apply sorting
    if (_sortOption == 'Name A-Z') {
      filtered.sort((a, b) {
        final nameA = (a['name'] ?? '').toString().toLowerCase();
        final nameB = (b['name'] ?? '').toString().toLowerCase();
        return nameA.compareTo(nameB);
      });
    } else if (_sortOption == 'Category') {
      filtered.sort((a, b) {
        final catA = (a['category'] ?? '').toString().toLowerCase();
        final catB = (b['category'] ?? '').toString().toLowerCase();
        return catA.compareTo(catB);
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
            backgroundColor: AppColors.rose,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening URL: $e'),
            backgroundColor: AppColors.rose,
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

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final scraperProvider = Provider.of<ScraperProvider>(context);
    final allResults = _resolveResults(scraperProvider);
    final filteredResults = _filterAndSortResults(allResults);
    final layoutType =
        AppBreakpoints.getLayoutType(MediaQuery.of(context).size.width);

    return Scaffold(
      backgroundColor: AppColors.backgroundDeep,
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
                  _buildSearchAndFilter(layoutType),
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
                AppColors.primaryViolet.withValues(alpha: 0.25),
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
        color: AppColors.backgroundDeep.withValues(alpha: 0.9),
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
                    color: AppColors.primaryViolet,
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
      onTap: count > 0 && !_isDownloading
          ? () => _downloadResults(context)
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.backgroundCard,
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
                    AppColors.emerald,
                  ),
                ),
              )
            else
              const Icon(Icons.download_rounded,
                  color: AppColors.emerald, size: 18),
            const SizedBox(width: 6),
            Text(
              'Excel',
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.emerald,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilter(LayoutType layoutType) {
    final canTable = ResponsiveUtils.shouldUseTableView(layoutType);
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
              color: AppColors.backgroundCard,
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
                });
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Filter and Sort chips
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('All', Icons.list_rounded),
                      const SizedBox(width: AppSpacing.xs),
                      _filterChip('Has Phone', Icons.phone_rounded),
                      const SizedBox(width: AppSpacing.xs),
                      _filterChip('Has Website', Icons.language_rounded),
                    ],
                  ),
                ),
              ),
              if (canTable) ...[
                const SizedBox(width: AppSpacing.sm),
                _viewToggle(),
              ],
              const SizedBox(width: AppSpacing.sm),
              PopupMenuButton<String>(
                initialValue: _sortOption,
                color: AppColors.backgroundCard,
                icon: Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundCard,
                    borderRadius: AppSpacing.borderRadiusSm,
                    border: Border.all(
                      color: AppColors.primaryViolet.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        color: AppColors.primaryViolet,
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
                  });
                },
                itemBuilder: (context) => [
                  _buildSortMenuItem('Newest', Icons.access_time_rounded),
                  _buildSortMenuItem('Name A-Z', Icons.sort_by_alpha_rounded),
                  _buildSortMenuItem('Category', Icons.category_rounded),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _viewToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(
          color: AppColors.primaryViolet.withValues(alpha: 0.3),
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
      onTap: () => setState(() => _viewMode = label),
      child: AnimatedContainer(
        duration: AppSpacing.durationFast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryViolet.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: AppSpacing.borderRadiusSm,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? AppColors.primaryViolet : Colors.white54,
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

  Widget _filterChip(String label, IconData icon) {
    final isActive = _activeFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeFilter = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryViolet.withValues(alpha: 0.2)
              : AppColors.backgroundCard,
          borderRadius: AppSpacing.borderRadiusSm,
          border: Border.all(
            color: isActive
                ? AppColors.primaryViolet
                : Colors.white.withValues(alpha: 0.1),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? AppColors.primaryViolet : Colors.white70,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: isActive ? Colors.white : Colors.white70,
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
    final cities = results.map((r) => r['city']).toSet();
    final categories = results.map((r) => r['category']).toSet();

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
        color: AppColors.backgroundStatCard,
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(
          color: AppColors.primaryViolet.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryViolet.withValues(alpha: 0.2),
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

  Widget _buildContent(List<Map<String, dynamic>> results, LayoutType layoutType) {
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
      final tableRows = results
          .map((r) => {
                'business_name': r['business_name'] ?? r['name'] ?? 'Unknown',
                'category': r['category'] ?? 'N/A',
                'city': r['city'] ?? 'N/A',
                'phone': r['phone'] ?? 'N/A',
                'website': r['website'] ?? 'N/A',
                'address': r['address'] ?? 'N/A',
              })
          .toList();
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        child: InfinityDataTable(
          layoutType: layoutType,
          columns: [
            const InfinityDataColumn(label: 'Business Name', keyName: 'business_name'),
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
          rows: tableRows,
          sortable: true,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshResults,
      color: AppColors.primaryViolet,
      backgroundColor: AppColors.backgroundCard,
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
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryViolet),
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
                colors: [AppColors.primaryViolet, AppColors.indigo],
              ),
              borderRadius: AppSpacing.borderRadiusSm,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryViolet.withValues(alpha: 0.3),
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
            color: AppColors.backgroundCard,
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: AppColors.rose, size: 40),
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
            color: AppColors.backgroundCard,
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(
              color: AppColors.primaryViolet.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.primaryViolet.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_off_rounded,
                  color: AppColors.primaryViolet,
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
              if (_searchQuery.isNotEmpty || _activeFilter != 'All') ...[
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
                      _activeFilter = 'All';
                    });
                  },
                  icon: const Icon(Icons.clear_all_rounded, size: 18),
                  label: const Text('Clear Filters'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryViolet,
                    side: BorderSide(color: AppColors.primaryViolet),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadResults(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final scraperProvider = Provider.of<ScraperProvider>(context, listen: false);

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
          backgroundColor: AppColors.rose,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }
}

class _LeadCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final hasPhone = business['phone'] != null &&
        business['phone'] != 'N/A' &&
        business['phone'].toString().isNotEmpty;
    final hasWebsite = business['website'] != null &&
        business['website'] != 'N/A' &&
        business['website'].toString().isNotEmpty;
    final hasAddress = business['address'] != null &&
        business['address'] != 'N/A' &&
        business['address'].toString().isNotEmpty;

    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.primaryViolet.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryViolet.withValues(alpha: 0.2),
            blurRadius: 18,
            spreadRadius: -10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      business['business_name'] ?? 'Unknown Business',
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (hasAddress)
                      Text(
                        business['address'],
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white60,
                        ),
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
                  color: AppColors.emerald.withValues(alpha: 0.12),
                  borderRadius: AppSpacing.borderRadiusRound,
                  border: Border.all(
                    color: AppColors.emerald.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  business['category'] ?? 'Category',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.emerald,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.emerald,
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
              Row(
                children: [
                  if (hasPhone) _actionButton(Icons.call, onPhoneTap, 'Call'),
                  if (hasWebsite) _actionButton(Icons.language, onWebsiteTap, 'Visit Website'),
                  if (hasAddress) _actionButton(Icons.location_on, onAddressTap, 'View on Map'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, VoidCallback? onTap, String tooltip) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Tooltip(
        message: tooltip,
        decoration: BoxDecoration(
          color: AppColors.backgroundCard,
          borderRadius: AppSpacing.borderRadiusSm,
          border: Border.all(
            color: AppColors.primaryViolet.withValues(alpha: 0.5),
          ),
        ),
        textStyle: AppTypography.labelSmall.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryViolet, AppColors.indigo],
              ),
              borderRadius: AppSpacing.borderRadiusSm,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryViolet.withValues(alpha: 0.4),
                  blurRadius: 10,
                  spreadRadius: -6,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
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
