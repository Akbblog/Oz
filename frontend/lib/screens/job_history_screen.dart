import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/responsive_utils.dart';
import '../services/api_service.dart';
import '../core/download_helper.dart';
import '../widgets/infinity_data_table.dart';
import 'results_screen.dart';

class JobHistoryScreen extends StatefulWidget {
  final bool showHeader;

  const JobHistoryScreen({super.key, this.showHeader = true});

  @override
  State<JobHistoryScreen> createState() => _JobHistoryScreenState();
}

class _JobHistoryScreenState extends State<JobHistoryScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _filteredJobs = [];
  final Set<String> _downloadingJobs = {};

  // Filter state
  String _statusFilter = 'All'; // All, Completed, Failed, Running
  String _dateFilter = 'All'; // All, Today, This Week, This Month
  String _sortOption = 'Newest'; // Newest, Oldest, Most Results
  String _viewMode = 'Cards';
  Set<int> _selectedRows = {};
  int _page = 1;
  final int _pageSize = 10;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: AppSpacing.durationMedium,
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _searchController.addListener(_applyFilter);
    _loadJobs();
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadJobs() async {
    try {
      final jobs = await _apiService.getUserJobs();
      if (mounted) {
        setState(() {
          _jobs = jobs;
          _isLoading = false;
          _error = null;
        });
        _applyFilter();
        _animationController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load job history: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase().trim();

    setState(() {
      _selectedRows = {};
      _filteredJobs = _jobs.where((job) {
        // Search filter
        if (query.isNotEmpty) {
          final jobId = job['job_id']?.toString().toLowerCase() ?? '';
          final category = job['category']?.toString().toLowerCase() ?? '';
          final cities = _citiesList(job['cities']).join(' ').toLowerCase();

          if (!jobId.contains(query) &&
              !category.contains(query) &&
              !cities.contains(query)) {
            return false;
          }
        }

        // Status filter
        if (_statusFilter != 'All') {
          final status = job['status']?.toString().toLowerCase() ?? '';
          if (status != _statusFilter.toLowerCase()) {
            return false;
          }
        }

        // Date filter
        if (_dateFilter != 'All') {
          final createdAt = DateTime.tryParse(job['created_at'] ?? '');
          if (createdAt == null) return false;

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          switch (_dateFilter) {
            case 'Today':
              if (createdAt.isBefore(today)) return false;
              break;
            case 'This Week':
              final weekAgo = today.subtract(const Duration(days: 7));
              if (createdAt.isBefore(weekAgo)) return false;
              break;
            case 'This Month':
              final monthStart = DateTime(now.year, now.month, 1);
              if (createdAt.isBefore(monthStart)) return false;
              break;
          }
        }

        return true;
      }).toList();

      // Apply sorting
      if (_sortOption == 'Oldest') {
        _filteredJobs.sort((a, b) {
          final dateA =
              DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(1970);
          final dateB =
              DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(1970);
          return dateA.compareTo(dateB);
        });
      } else if (_sortOption == 'Most Results') {
        _filteredJobs.sort((a, b) {
          final countA = _resultsCount(a['results']);
          final countB = _resultsCount(b['results']);
          return countB.compareTo(countA); // Descending
        });
      }
      // 'Newest' keeps reverse chronological order (default from API)

      // Reset/normalize pagination after filters
      _page = 1;
    });
  }

  Future<void> _openResults(String jobId, String category) async {
    try {
      final data = await _apiService.getJobResults(jobId);
      final results = List<Map<String, dynamic>>.from(data['results'] ?? []);

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ResultsScreen(
              jobId: jobId,
              overrideResults: results,
              title: '$category Results (${results.length})',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed to load results: $e')),
              ],
            ),
            backgroundColor: AppColors.dangerRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _downloadJob(String jobId) async {
    if (_downloadingJobs.contains(jobId)) return;

    setState(() {
      _downloadingJobs.add(jobId);
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final downloadData = await _apiService.downloadResults(jobId);
      final filename = downloadData['filename'] as String;
      final content = downloadData['content'] as String;

      if (!mounted) return;
      await saveExcel(content, filename, context: context);
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Failed to download: $e')),
            ],
          ),
          backgroundColor: AppColors.dangerRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloadingJobs.remove(jobId);
        });
      }
    }
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '—';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${_monthName(parsed.month)} ${_pad(parsed.day)}, ${_pad(parsed.hour)}:${_pad(parsed.minute)}';
  }

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  String _pad(int v) => v.toString().padLeft(2, '0');

  List<String> _citiesList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty && e != 'N/A')
          .toList();
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty || trimmed == 'N/A') return const [];
      if (trimmed.contains(',')) {
        return trimmed
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty && e != 'N/A')
            .toList();
      }
      return [trimmed];
    }
    if (value == null) return const [];
    final s = value.toString().trim();
    if (s.isEmpty || s == 'N/A') return const [];
    return [s];
  }

  int _resultsCount(dynamic value) {
    if (value is List) return value.length;
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  _StatusStyle _statusStyle(String status) {
    switch (status) {
      case 'completed':
        return _StatusStyle(
          label: 'Completed',
          color: _JobHistoryColors.emerald,
          background: _JobHistoryColors.emerald.withValues(alpha: 0.12),
          icon: Icons.check_circle_rounded,
        );
      case 'failed':
        return _StatusStyle(
          label: 'Failed',
          color: _JobHistoryColors.rose,
          background: _JobHistoryColors.rose.withValues(alpha: 0.12),
          icon: Icons.error_rounded,
        );
      case 'cancelled':
        return _StatusStyle(
          label: 'Cancelled',
          color: _JobHistoryColors.rose,
          background: _JobHistoryColors.rose.withValues(alpha: 0.12),
          icon: Icons.cancel_rounded,
        );
      case 'running':
        return _StatusStyle(
          label: 'Running',
          color: _JobHistoryColors.indigo,
          background: _JobHistoryColors.indigo.withValues(alpha: 0.12),
          icon: Icons.sync_rounded,
        );
      case 'pending':
        return _StatusStyle(
          label: 'Pending',
          color: _JobHistoryColors.amber,
          background: _JobHistoryColors.amber.withValues(alpha: 0.12),
          icon: Icons.schedule_rounded,
        );
      default:
        return _StatusStyle(
          label: status.isEmpty ? 'Unknown' : status,
          color: Colors.white54,
          background: Colors.white10,
          icon: Icons.help_outline_rounded,
        );
    }
  }

  IconData _categoryIcon(String category) {
    final value = category.toLowerCase();
    if (value.contains('restaurant') || value.contains('food')) {
      return Icons.restaurant_rounded;
    }
    if (value.contains('dentist') || value.contains('clinic')) {
      return Icons.medical_services_rounded;
    }
    if (value.contains('shop') || value.contains('e-commerce')) {
      return Icons.shopping_cart_rounded;
    }
    if (value.contains('startup') || value.contains('tech')) {
      return Icons.lan_rounded;
    }
    if (value.contains('map')) {
      return Icons.travel_explore_rounded;
    }
    return Icons.work_history_rounded;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final layoutType =
        AppBreakpoints.getLayoutType(MediaQuery.of(context).size.width);
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    return Scaffold(
      backgroundColor: _JobHistoryColors.slate950,
      body: SafeArea(
        top: widget.showHeader,
        bottom: false,
        child: Column(
          children: [
            if (widget.showHeader) _buildHeader(),
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: RefreshIndicator(
                  color: AppColors.primaryBlue,
                  backgroundColor: AppColors.surfaceDark,
                  onRefresh: _loadJobs,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.xl,
                    ),
                    children: [
                      _buildSearchField(),
                      const SizedBox(height: AppSpacing.md),
                      _buildFilterChips(layoutType),
                      const SizedBox(height: AppSpacing.md),
                      if (_filteredJobs.isEmpty)
                        _buildEmptyState()
                      else
                        _buildJobsContent(layoutType),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _JobHistoryColors.slate950.withValues(alpha: 0.9),
        border: Border(
          bottom: BorderSide(
            color: _JobHistoryColors.indigo.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Job History',
            style: AppTypography.titleLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadJobs,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      style: AppTypography.bodyMedium.copyWith(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Search by Job ID or Category...',
        hintStyle: AppTypography.bodySmall.copyWith(color: Colors.white54),
        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
        filled: true,
        fillColor: _JobHistoryColors.slate900,
        border: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          borderSide: BorderSide(
            color: _JobHistoryColors.indigo.withValues(alpha: 0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          borderSide: BorderSide(
            color: _JobHistoryColors.indigo.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          borderSide: BorderSide(
            color: _JobHistoryColors.indigo.withValues(alpha: 0.6),
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
    );
  }

  Widget _buildFilterChips(LayoutType layoutType) {
    final canTable = ResponsiveUtils.shouldUseTableView(layoutType);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status filters
        Row(
          children: [
            Text(
              'Status:',
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white54,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('All', _statusFilter, (value) {
                      setState(() {
                        _statusFilter = value;
                        _applyFilter();
                      });
                    }),
                    const SizedBox(width: AppSpacing.xs),
                    _filterChip('Completed', _statusFilter, (value) {
                      setState(() {
                        _statusFilter = value;
                        _applyFilter();
                      });
                    }),
                    const SizedBox(width: AppSpacing.xs),
                    _filterChip('Failed', _statusFilter, (value) {
                      setState(() {
                        _statusFilter = value;
                        _applyFilter();
                      });
                    }),
                    const SizedBox(width: AppSpacing.xs),
                    _filterChip('Running', _statusFilter, (value) {
                      setState(() {
                        _statusFilter = value;
                        _applyFilter();
                      });
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // Date and Sort filters
        Row(
          children: [
            Expanded(
              child: PopupMenuButton<String>(
                initialValue: _dateFilter,
                color: _JobHistoryColors.slate900,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: _JobHistoryColors.slate900,
                    borderRadius: AppSpacing.borderRadiusSm,
                    border: Border.all(
                      color: _JobHistoryColors.indigo.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        color: _JobHistoryColors.indigo,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _dateFilter,
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_drop_down_rounded,
                        color: Colors.white54,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                onSelected: (value) {
                  setState(() {
                    _dateFilter = value;
                    _applyFilter();
                  });
                },
                itemBuilder: (context) => [
                  _buildMenuItem('All', Icons.layers_rounded),
                  _buildMenuItem('Today', Icons.today_rounded),
                  _buildMenuItem('This Week', Icons.date_range_rounded),
                  _buildMenuItem('This Month', Icons.calendar_month_rounded),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: PopupMenuButton<String>(
                initialValue: _sortOption,
                color: _JobHistoryColors.slate900,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: _JobHistoryColors.slate900,
                    borderRadius: AppSpacing.borderRadiusSm,
                    border: Border.all(
                      color: _JobHistoryColors.indigo.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sort_rounded,
                        color: _JobHistoryColors.indigo,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _sortOption,
                          style: AppTypography.labelSmall.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_drop_down_rounded,
                        color: Colors.white54,
                        size: 20,
                      ),
                    ],
                  ),
                ),
                onSelected: (value) {
                  setState(() {
                    _sortOption = value;
                    _applyFilter();
                  });
                },
                itemBuilder: (context) => [
                  _buildMenuItem('Newest', Icons.access_time_rounded),
                  _buildMenuItem('Oldest', Icons.history_rounded),
                  _buildMenuItem('Most Results', Icons.trending_up_rounded),
                ],
              ),
            ),
            if (canTable) ...[
              const SizedBox(width: AppSpacing.sm),
              _viewToggle(),
            ],
          ],
        ),
      ],
    );
  }

  Widget _viewToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _JobHistoryColors.slate900,
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(
          color: _JobHistoryColors.indigo.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          _toggleChip('Cards', Icons.view_agenda_rounded),
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
              ? _JobHistoryColors.indigo.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: AppSpacing.borderRadiusSm,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: isActive ? _JobHistoryColors.indigo : Colors.white54,
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

  Widget _buildJobsContent(LayoutType layoutType) {
    final canTable = ResponsiveUtils.shouldUseTableView(layoutType);
    final pageJobs = _pagedJobs();
    if (canTable && _viewMode == 'Table') {
      final rows = pageJobs.map((job) {
        final results = _resultsCount(job['results']);
        return {
          'job_id': job['job_id'] ?? '',
          'category': job['category'] ?? '',
          'status': job['status'] ?? '',
          'date': _formatDate(job['created_at']?.toString()),
          'results': results,
        };
      }).toList();

      final showCheckboxes = layoutType != LayoutType.desktopSmall;
      final table = InfinityDataTable(
        layoutType: layoutType,
        columns: const [
          InfinityDataColumn(label: 'Job ID', keyName: 'job_id'),
          InfinityDataColumn(label: 'Category', keyName: 'category'),
          InfinityDataColumn(label: 'Status', keyName: 'status'),
          InfinityDataColumn(label: 'Date', keyName: 'date'),
          InfinityDataColumn(
              label: 'Results', keyName: 'results', numeric: true),
        ],
        rows: rows,
        showCheckboxes: showCheckboxes,
        selectedRows: _selectedRows,
        onSelectionChanged: (updated) {
          setState(() => _selectedRows = updated);
        },
      );

      if (layoutType == LayoutType.desktopLarge) {
        final selectedIndex =
            _selectedRows.isNotEmpty ? _selectedRows.first : null;
        final selectedJob =
            selectedIndex != null && selectedIndex < pageJobs.length
                ? pageJobs[selectedIndex]
                : null;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 60,
              child: Column(
                children: [
                  table,
                  const SizedBox(height: AppSpacing.md),
                  _buildPagination(),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              flex: 40,
              child: selectedJob == null
                  ? _buildEmptyState()
                  : _buildJobDetailsPanel(selectedJob),
            ),
          ],
        );
      }

      return Column(
        children: [
          table,
          const SizedBox(height: AppSpacing.md),
          _buildPagination(),
        ],
      );
    }

    return Column(
      children: [
        ...pageJobs.map(_buildJobCard),
        const SizedBox(height: AppSpacing.lg),
        _buildPagination(),
      ],
    );
  }

  int get _totalPages {
    if (_filteredJobs.isEmpty) return 1;
    final pages = (_filteredJobs.length / _pageSize).ceil();
    return pages.clamp(1, 999999);
  }

  List<Map<String, dynamic>> _pagedJobs() {
    final total = _filteredJobs.length;
    if (total == 0) return const [];
    final start = (_page - 1) * _pageSize;
    if (start >= total) {
      _page = _totalPages;
    }
    final safeStart = ((_page - 1) * _pageSize).clamp(0, total);
    return _filteredJobs.skip(safeStart).take(_pageSize).toList();
  }

  Widget _buildPagination() {
    if (_filteredJobs.length <= _pageSize) {
      return const SizedBox.shrink();
    }

    final totalPages = _totalPages;
    final canPrev = _page > 1;
    final canNext = _page < totalPages;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _JobHistoryColors.slate900,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: canPrev
                ? () => setState(() {
                      _page -= 1;
                      _selectedRows = {};
                    })
                : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: const Text('Previous'),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Page $_page of $totalPages',
              textAlign: TextAlign.center,
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton(
            onPressed: canNext
                ? () => setState(() {
                      _page += 1;
                      _selectedRows = {};
                    })
                : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }

  Widget _buildJobDetailsPanel(Map<String, dynamic> job) {
    final jobId = job['job_id']?.toString() ?? '';
    final category = job['category']?.toString() ?? 'Unknown';
    final status = job['status']?.toString() ?? 'unknown';
    final createdAt = _formatDate(job['created_at']?.toString());
    final resultCount = _resultsCount(job['results']);
    final cities = _citiesList(job['cities']);
    final citiesText = cities.isNotEmpty ? cities.join(', ') : 'N/A';

    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: _JobHistoryColors.slate900,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: _JobHistoryColors.indigo.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Job Details',
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '#$jobId',
            style: AppTypography.bodySmall.copyWith(
              color: Colors.white54,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            category,
            style: AppTypography.titleSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Status: ${status.toUpperCase()}',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Created: $createdAt',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Results: $resultCount',
            style: AppTypography.labelLarge.copyWith(
              color: _JobHistoryColors.neon,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Cities:',
            style: AppTypography.labelSmall.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            citiesText,
            style: AppTypography.bodySmall.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: jobId.isEmpty
                      ? null
                      : () => _openResults(jobId, category),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _JobHistoryColors.neon,
                    side: BorderSide(color: _JobHistoryColors.indigo),
                  ),
                  child: const Text('View Results'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton(
                  onPressed: jobId.isEmpty ? null : () => _downloadJob(jobId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _JobHistoryColors.indigo,
                  ),
                  child: const Text('Download'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
      String label, String currentFilter, Function(String) onTap) {
    final isActive = currentFilter == label;
    return GestureDetector(
      onTap: () => onTap(label),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? _JobHistoryColors.indigo.withValues(alpha: 0.2)
              : _JobHistoryColors.slate900,
          borderRadius: AppSpacing.borderRadiusSm,
          border: Border.all(
            color: isActive
                ? _JobHistoryColors.indigo
                : Colors.white.withValues(alpha: 0.1),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: isActive ? Colors.white : Colors.white70,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildMenuItem(String value, IconData icon) {
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

  Widget _buildLoadingState() {
    return Scaffold(
      backgroundColor: _JobHistoryColors.slate950,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: _JobHistoryColors.slate900,
                borderRadius: AppSpacing.borderRadiusLg,
                border: Border.all(
                  color: _JobHistoryColors.indigo.withValues(alpha: 0.25),
                ),
              ),
              child: const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primaryBlue,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Loading history...',
              style: AppTypography.bodyMedium.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Scaffold(
      backgroundColor: _JobHistoryColors.slate950,
      body: Center(
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _JobHistoryColors.rose.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.error_outline,
                    color: _JobHistoryColors.rose, size: 48),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: AppSpacing.md),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _loadJobs();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasFilters = _searchController.text.isNotEmpty ||
        _statusFilter != 'All' ||
        _dateFilter != 'All';

    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: _JobHistoryColors.slate900,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: _JobHistoryColors.indigo.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _JobHistoryColors.indigo.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasFilters ? Icons.filter_alt_off_rounded : Icons.history_rounded,
              size: 48,
              color: _JobHistoryColors.indigo,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            hasFilters ? 'No Matching Jobs' : 'No Jobs Yet',
            style: AppTypography.titleLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            hasFilters
                ? 'No jobs match your current filters.\nTry adjusting your search criteria.'
                : 'Start your first lead search to see\nyour job history here',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white60,
              height: 1.5,
            ),
          ),
          if (hasFilters) ...[
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _statusFilter = 'All';
                  _dateFilter = 'All';
                  _sortOption = 'Newest';
                  _applyFilter();
                });
              },
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Clear All Filters'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _JobHistoryColors.indigo,
                side: BorderSide(color: _JobHistoryColors.indigo),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> job) {
    final jobId = job['job_id']?.toString() ?? '';
    final category = job['category']?.toString() ?? 'Unknown';
    final status = job['status']?.toString() ?? 'unknown';
    final createdAt = _formatDate(job['created_at']?.toString());
    final isDownloading = _downloadingJobs.contains(jobId);
    final statusStyle = _statusStyle(status);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: _JobHistoryColors.slate900,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: _JobHistoryColors.indigo.withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 18,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _JobHistoryColors.slate850,
                  borderRadius: AppSpacing.borderRadiusMd,
                  border: Border.all(
                    color: _JobHistoryColors.indigo.withValues(alpha: 0.15),
                  ),
                ),
                child: Icon(
                  _categoryIcon(category),
                  color: _JobHistoryColors.neon,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '#$jobId 	 $createdAt',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white54,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: statusStyle.background,
                      borderRadius: AppSpacing.borderRadiusRound,
                      border: Border.all(
                        color: statusStyle.color.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusStyle.icon,
                            size: 14, color: statusStyle.color),
                        const SizedBox(width: 6),
                        Text(
                          statusStyle.label,
                          style: AppTypography.labelSmall.copyWith(
                            color: statusStyle.color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  // Actions menu
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: Colors.white54,
                      size: 20,
                    ),
                    color: _JobHistoryColors.slate900,
                    onSelected: (value) => _handleJobAction(value, job),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            Icon(Icons.visibility_rounded,
                                size: 18, color: Colors.white70),
                            const SizedBox(width: AppSpacing.xs),
                            Text('View Results',
                                style: AppTypography.bodyMedium
                                    .copyWith(color: Colors.white)),
                          ],
                        ),
                      ),
                      if (status == 'pending' || status == 'running')
                        PopupMenuItem(
                          value: 'cancel',
                          child: Row(
                            children: [
                              Icon(Icons.cancel_rounded,
                                  size: 18, color: _JobHistoryColors.amber),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                'Cancel Job',
                                style: AppTypography.bodyMedium
                                    .copyWith(color: _JobHistoryColors.amber),
                              ),
                            ],
                          ),
                        ),
                      if (status == 'completed')
                        PopupMenuItem(
                          value: 'download',
                          child: Row(
                            children: [
                              Icon(Icons.download_rounded,
                                  size: 18, color: Colors.white70),
                              const SizedBox(width: AppSpacing.xs),
                              Text('Download Excel',
                                  style: AppTypography.bodyMedium
                                      .copyWith(color: Colors.white)),
                            ],
                          ),
                        ),
                      if (status != 'pending' && status != 'running')
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline_rounded,
                                  size: 18, color: _JobHistoryColors.rose),
                              const SizedBox(width: AppSpacing.xs),
                              Text('Delete',
                                  style: AppTypography.bodyMedium
                                      .copyWith(color: _JobHistoryColors.rose)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Job details
          _buildJobDetails(job),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: jobId.isEmpty
                      ? null
                      : () => _openResults(jobId, category),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _JobHistoryColors.neon,
                    side: BorderSide(
                      color: _JobHistoryColors.indigo,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppSpacing.borderRadiusSm,
                    ),
                  ),
                  child: Text(
                    status == 'failed' ? 'View Logs' : 'View Results',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: status == 'completed'
                    ? ElevatedButton.icon(
                        onPressed: jobId.isNotEmpty && !isDownloading
                            ? () => _downloadJob(jobId)
                            : null,
                        icon: isDownloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.download_rounded, size: 18),
                        label: Text(isDownloading
                            ? 'Downloading...'
                            : 'Download Excel'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _JobHistoryColors.indigo,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _JobHistoryColors.slate850,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppSpacing.borderRadiusSm,
                          ),
                        ),
                      )
                    : (status == 'pending' || status == 'running')
                        ? OutlinedButton.icon(
                            onPressed: jobId.isNotEmpty
                                ? () => _showCancelConfirmation(jobId)
                                : null,
                            icon: Icon(Icons.cancel_rounded,
                                size: 18, color: _JobHistoryColors.amber),
                            label: Text(
                              'Cancel Job',
                              style: AppTypography.labelMedium.copyWith(
                                color: _JobHistoryColors.amber,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                  color: _JobHistoryColors.amber
                                      .withValues(alpha: 0.6)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppSpacing.borderRadiusSm,
                              ),
                            ),
                          )
                        : ElevatedButton.icon(
                            onPressed: jobId.isNotEmpty
                                ? () => _showDeleteConfirmation(jobId)
                                : null,
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 18),
                            label: const Text('Delete Job'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _JobHistoryColors.rose,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppSpacing.borderRadiusSm,
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildJobDetails(Map<String, dynamic> job) {
    final resultCount = _resultsCount(job['results']);
    final cities = _citiesList(job['cities']);
    final citiesText = cities.isNotEmpty
        ? cities.take(3).join(', ') + (cities.length > 3 ? '...' : '')
        : 'N/A';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: _JobHistoryColors.slate850.withValues(alpha: 0.5),
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.business_center_rounded,
                size: 16,
                color: _JobHistoryColors.neon,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '$resultCount leads found',
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: [
              Icon(
                Icons.location_city_rounded,
                size: 16,
                color: _JobHistoryColors.indigo,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Cities: $citiesText',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white54,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleJobAction(String action, Map<String, dynamic> job) {
    final jobId = job['job_id']?.toString() ?? '';
    final category = job['category']?.toString() ?? 'Unknown';

    switch (action) {
      case 'view':
        if (jobId.isNotEmpty) {
          _openResults(jobId, category);
        }
        break;
      case 'download':
        if (jobId.isNotEmpty) {
          _downloadJob(jobId);
        }
        break;
      case 'cancel':
        if (jobId.isNotEmpty) {
          _showCancelConfirmation(jobId);
        }
        break;
      case 'delete':
        _showDeleteConfirmation(jobId);
        break;
    }
  }

  void _showCancelConfirmation(String jobId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _JobHistoryColors.slate900,
        title: Text(
          'Cancel Job?',
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
        content: Text(
          'This will request cancellation for the running job. Partial results may still be available.',
          style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Keep running',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelJob(jobId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _JobHistoryColors.amber,
              foregroundColor: Colors.black,
            ),
            child: const Text('Cancel job'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(String jobId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _JobHistoryColors.slate900,
        title: Text(
          'Delete Job?',
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete this job? This action cannot be undone.',
          style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteJob(jobId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _JobHistoryColors.rose,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelJob(String jobId) async {
    try {
      await _apiService.cancelJob(jobId);

      if (!mounted) return;

      setState(() {
        final idx = _jobs.indexWhere((j) => j['job_id']?.toString() == jobId);
        if (idx != -1) {
          final existing = Map<String, dynamic>.from(_jobs[idx]);
          existing['status'] = 'cancelled';
          existing['error'] ??= 'Cancelled by user';
          _jobs[idx] = existing;
        }
      });
      _applyFilter();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cancellation requested'),
          backgroundColor: _JobHistoryColors.amber,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel job: $e'),
          backgroundColor: _JobHistoryColors.rose,
        ),
      );
    }
  }

  Future<void> _deleteJob(String jobId) async {
    try {
      await _apiService.deleteJob(jobId);

      if (mounted) {
        setState(() {
          _jobs.removeWhere((job) => job['job_id'] == jobId);
        });
        _applyFilter();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Job deleted successfully'),
            backgroundColor: _JobHistoryColors.emerald,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete job: $e'),
            backgroundColor: _JobHistoryColors.rose,
          ),
        );
      }
    }
  }
}

class _StatusStyle {
  final String label;
  final Color color;
  final Color background;
  final IconData icon;

  const _StatusStyle({
    required this.label,
    required this.color,
    required this.background,
    required this.icon,
  });
}

class _JobHistoryColors {
  static const Color slate950 = AppColors.backgroundDark;
  static const Color slate900 = AppColors.backgroundDarkAlt;
  static const Color slate850 = AppColors.elevatedCardDark;
  static const Color indigo = AppColors.primaryBlue;
  static const Color neon = AppColors.primaryBlueLight;
  static const Color emerald = AppColors.successGreen;
  static const Color rose = AppColors.dangerRed;
  static const Color amber = AppColors.warningYellow;
}
