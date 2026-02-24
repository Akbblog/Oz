import 'package:flutter/material.dart';

import '../core/download_helper.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/responsive_utils.dart';
import '../services/api_service.dart';
import '../widgets/infinity_data_table.dart';
import '../widgets/job_completion_card.dart';
import 'results_screen.dart';

class AdminJobsScreen extends StatefulWidget {
  final bool showHeader;

  const AdminJobsScreen({super.key, this.showHeader = true});

  @override
  State<AdminJobsScreen> createState() => _AdminJobsScreenState();
}

class _AdminJobsScreenState extends State<AdminJobsScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _bulkDownloading = false;
  String? _error;

  List<Map<String, dynamic>> _jobs = [];
  List<Map<String, dynamic>> _filteredJobs = [];
  Map<String, dynamic> _summary = const {};

  final Set<int> _selectedRows = {};
  final Set<String> _downloadingJobs = {};

  String _statusFilter = 'All';
  String _dateFilter = 'All';
  String _sortOption = 'Newest';
  String _viewMode = 'Cards';

  int _page = 1;
  static const int _pageSize = 20;
  int _totalJobs = 0;
  int _totalPages = 1;

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

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String? _statusToQuery() {
    if (_statusFilter == 'All') return null;
    return _statusFilter.toLowerCase();
  }

  Future<void> _loadJobs({bool animate = true}) async {
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.getAdminAllJobs(
        status: _statusToQuery(),
        page: _page,
        limit: _pageSize,
      );
      final jobs = List<Map<String, dynamic>>.from(data['jobs'] ?? const []);
      final statsRaw = data['stats'];
      final stats = statsRaw is Map
          ? Map<String, dynamic>.from(statsRaw)
          : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _summary = stats;
        _totalJobs = _asInt(data['total']);
        _totalPages = (_asInt(data['total_pages']) <= 0)
            ? 1
            : _asInt(data['total_pages']);
        _error = null;
        _isLoading = false;
      });
      _applyFilter();
      if (animate) _animationController.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load admin jobs: $e';
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase().trim();

    final filtered = _jobs.where((job) {
      if (query.isNotEmpty) {
        final jobId = job['job_id']?.toString().toLowerCase() ?? '';
        final category = job['category']?.toString().toLowerCase() ?? '';
        final username = job['username']?.toString().toLowerCase() ?? '';
        if (!jobId.contains(query) &&
            !category.contains(query) &&
            !username.contains(query)) {
          return false;
        }
      }

      if (_dateFilter != 'All') {
        final createdAt = DateTime.tryParse(
          job['created_at']?.toString() ?? '',
        );
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

    if (_sortOption == 'Oldest') {
      filtered.sort((a, b) {
        final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return dateA.compareTo(dateB);
      });
    } else if (_sortOption == 'Most Results') {
      filtered.sort((a, b) => _resultsCount(b).compareTo(_resultsCount(a)));
    } else {
      filtered.sort((a, b) {
        final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });
    }

    if (!mounted) return;
    setState(() {
      _filteredJobs = filtered;
      _selectedRows.clear();
    });
  }

  int _resultsCount(Map<String, dynamic> job) {
    return _asInt(job['result_count'] ?? job['results'] ?? 0);
  }

  Future<List<Map<String, dynamic>>> _fetchAllResultsForJob(
    String jobId,
  ) async {
    const fetchLimit = 500;
    final rows = <Map<String, dynamic>>[];
    int offset = 0;
    int total = 0;

    while (true) {
      final data = await _apiService.getJobResultsAdmin(
        jobId,
        limit: fetchLimit,
        offset: offset,
      );
      final chunk = List<Map<String, dynamic>>.from(
        data['results'] ?? const [],
      );
      total = _asInt(data['total']);
      if (chunk.isEmpty) break;
      rows.addAll(chunk);
      offset += chunk.length;
      if (total > 0 && rows.length >= total) break;
      if (chunk.length < fetchLimit) break;
    }

    return rows;
  }

  Future<void> _openResults(Map<String, dynamic> job) async {
    final jobId = (job['job_id'] ?? '').toString();
    if (jobId.isEmpty) return;

    final category = (job['category'] ?? 'Unknown').toString();
    final username = (job['username'] ?? 'unknown').toString();

    try {
      final results = await _fetchAllResultsForJob(jobId);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ResultsScreen(
            jobId: jobId,
            overrideResults: results,
            title: '$category - $username (${results.length})',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load results: $e'),
          backgroundColor: _AdminJobsColors.rose,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _escapeCsvValue(Object? value) {
    final text = (value ?? '').toString();
    final escaped = text.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n') ||
        escaped.contains('\r')) {
      return '"$escaped"';
    }
    return escaped;
  }

  Future<void> _downloadJob(Map<String, dynamic> job) async {
    final jobId = (job['job_id'] ?? '').toString();
    final username = (job['username'] ?? 'unknown').toString();
    if (jobId.isEmpty || _downloadingJobs.contains(jobId)) return;

    setState(() => _downloadingJobs.add(jobId));
    try {
      final rows = await _fetchAllResultsForJob(jobId);
      final csv = StringBuffer();
      csv.writeln(
        'job_id,username,business_name,phone,whatsapp,website,whatsapp_url,email,address,category,city,state,google_maps_url',
      );
      for (final row in rows) {
        csv.writeln(
          [
            _escapeCsvValue(jobId),
            _escapeCsvValue(username),
            _escapeCsvValue(row['business_name']),
            _escapeCsvValue(row['phone']),
            _escapeCsvValue(row['whatsapp']),
            _escapeCsvValue(row['website']),
            _escapeCsvValue(row['whatsapp_url']),
            _escapeCsvValue(row['email']),
            _escapeCsvValue(row['address']),
            _escapeCsvValue(row['category']),
            _escapeCsvValue(row['city']),
            _escapeCsvValue(row['state']),
            _escapeCsvValue(row['google_maps_url']),
          ].join(','),
        );
      }
      if (!mounted) return;
      await saveCsv(
        csv.toString(),
        'admin_job_${jobId}_results',
        context: context,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to download CSV: $e'),
          backgroundColor: _AdminJobsColors.rose,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _downloadingJobs.remove(jobId));
      }
    }
  }

  Future<void> _downloadSelectedJobs() async {
    if (_selectedRows.isEmpty || _bulkDownloading) return;

    setState(() => _bulkDownloading = true);
    try {
      final selectedJobs = _selectedRows
          .where((i) => i >= 0 && i < _filteredJobs.length)
          .map((i) => _filteredJobs[i])
          .toList();

      final csv = StringBuffer();
      csv.writeln(
        'job_id,username,business_name,phone,whatsapp,website,whatsapp_url,email,address,category,city,state,google_maps_url',
      );

      for (final job in selectedJobs) {
        final jobId = (job['job_id'] ?? '').toString();
        final username = (job['username'] ?? 'unknown').toString();
        if (jobId.isEmpty) continue;

        final rows = await _fetchAllResultsForJob(jobId);
        for (final row in rows) {
          csv.writeln(
            [
              _escapeCsvValue(jobId),
              _escapeCsvValue(username),
              _escapeCsvValue(row['business_name']),
              _escapeCsvValue(row['phone']),
              _escapeCsvValue(row['whatsapp']),
              _escapeCsvValue(row['website']),
              _escapeCsvValue(row['whatsapp_url']),
              _escapeCsvValue(row['email']),
              _escapeCsvValue(row['address']),
              _escapeCsvValue(row['category']),
              _escapeCsvValue(row['city']),
              _escapeCsvValue(row['state']),
              _escapeCsvValue(row['google_maps_url']),
            ].join(','),
          );
        }
      }

      if (!mounted) return;
      await saveCsv(
        csv.toString(),
        'admin_jobs_bulk_page_${_page}_${DateTime.now().millisecondsSinceEpoch}',
        context: context,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bulk download failed: $e'),
          backgroundColor: _AdminJobsColors.rose,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _bulkDownloading = false);
      }
    }
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '--';
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
      'Dec',
    ];
    return months[(month - 1).clamp(0, 11)];
  }

  String _pad(int value) => value.toString().padLeft(2, '0');

  String _formatDurationCompact(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 9999999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  _StatusStyle _statusStyle(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return _StatusStyle(
          label: 'Completed',
          color: _AdminJobsColors.emerald,
          background: _AdminJobsColors.emerald.withValues(alpha: 0.12),
          icon: Icons.check_circle_rounded,
        );
      case 'failed':
        return _StatusStyle(
          label: 'Failed',
          color: _AdminJobsColors.rose,
          background: _AdminJobsColors.rose.withValues(alpha: 0.12),
          icon: Icons.error_rounded,
        );
      case 'cancelled':
        return _StatusStyle(
          label: 'Cancelled',
          color: _AdminJobsColors.rose,
          background: _AdminJobsColors.rose.withValues(alpha: 0.12),
          icon: Icons.cancel_rounded,
        );
      case 'running':
        return _StatusStyle(
          label: 'Running',
          color: _AdminJobsColors.indigo,
          background: _AdminJobsColors.indigo.withValues(alpha: 0.12),
          icon: Icons.sync_rounded,
        );
      case 'pending':
        return _StatusStyle(
          label: 'Pending',
          color: _AdminJobsColors.amber,
          background: _AdminJobsColors.amber.withValues(alpha: 0.12),
          icon: Icons.schedule_rounded,
        );
      default:
        return _StatusStyle(
          label: status.isEmpty ? 'Unknown' : status,
          color: Colors.white60,
          background: Colors.white10,
          icon: Icons.help_outline_rounded,
        );
    }
  }

  void _goToPage(int page) {
    if (page < 1 || page > _totalPages || page == _page) return;
    setState(() => _page = page);
    _loadJobs(animate: false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final layoutType = AppBreakpoints.getLayoutType(
      MediaQuery.of(context).size.width,
    );

    if (_isLoading) {
      return Scaffold(
        backgroundColor: _AdminJobsColors.slate950,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(_AdminJobsColors.indigo),
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: _AdminJobsColors.slate950,
        body: Center(
          child: Padding(
            padding: AppSpacing.paddingLg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: _AdminJobsColors.rose,
                  size: 42,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton.icon(
                  onPressed: _loadJobs,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _AdminJobsColors.indigo,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _AdminJobsColors.slate950,
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
                  onRefresh: () => _loadJobs(animate: false),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.xl,
                    ),
                    children: [
                      _buildSummary(layoutType),
                      const SizedBox(height: AppSpacing.md),
                      _buildSearchField(),
                      const SizedBox(height: AppSpacing.sm),
                      _buildFilters(layoutType),
                      if (_selectedRows.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _buildBulkBar(),
                      ],
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
        color: _AdminJobsColors.slate950.withValues(alpha: 0.9),
        border: Border(
          bottom: BorderSide(
            color: _AdminJobsColors.indigo.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            'All Jobs (Admin)',
            style: AppTypography.titleLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => _loadJobs(animate: false),
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(LayoutType layoutType) {
    final cards = [
      _summaryCard(
        'Total Jobs',
        _asInt(_summary['total_jobs']).toString(),
        Icons.work_rounded,
        _AdminJobsColors.indigo,
      ),
      _summaryCard(
        'Completed',
        _asInt(_summary['completed']).toString(),
        Icons.check_circle_rounded,
        _AdminJobsColors.emerald,
      ),
      _summaryCard(
        'Failed',
        _asInt(_summary['failed']).toString(),
        Icons.error_rounded,
        _AdminJobsColors.rose,
      ),
      _summaryCard(
        'Running',
        _asInt(_summary['running']).toString(),
        Icons.sync_rounded,
        _AdminJobsColors.amber,
      ),
    ];

    if (layoutType.index >= LayoutType.desktopSmall.index) {
      return Row(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            Expanded(child: cards[i]),
            if (i != cards.length - 1) const SizedBox(width: AppSpacing.sm),
          ],
        ],
      );
    }

    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 1.8,
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards,
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: _AdminJobsColors.slate900,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: AppSpacing.borderRadiusSm,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white54,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTypography.titleLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
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
        hintText: 'Search by Job ID, Category, or Username...',
        hintStyle: AppTypography.bodySmall.copyWith(color: Colors.white54),
        prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54),
        filled: true,
        fillColor: _AdminJobsColors.slate900,
        border: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          borderSide: BorderSide(
            color: _AdminJobsColors.indigo.withValues(alpha: 0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          borderSide: BorderSide(
            color: _AdminJobsColors.indigo.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppSpacing.borderRadiusMd,
          borderSide: BorderSide(
            color: _AdminJobsColors.indigo.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(LayoutType layoutType) {
    final canTable = ResponsiveUtils.shouldUseTableView(layoutType);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _statusChip('All'),
              const SizedBox(width: AppSpacing.xs),
              _statusChip('Completed'),
              const SizedBox(width: AppSpacing.xs),
              _statusChip('Failed'),
              const SizedBox(width: AppSpacing.xs),
              _statusChip('Running'),
              const SizedBox(width: AppSpacing.xs),
              _statusChip('Pending'),
              const SizedBox(width: AppSpacing.xs),
              _statusChip('Cancelled'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: PopupMenuButton<String>(
                initialValue: _dateFilter,
                color: _AdminJobsColors.slate900,
                onSelected: (value) {
                  setState(() => _dateFilter = value);
                  _applyFilter();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'All', child: Text('All Dates')),
                  PopupMenuItem(value: 'Today', child: Text('Today')),
                  PopupMenuItem(value: 'This Week', child: Text('This Week')),
                  PopupMenuItem(value: 'This Month', child: Text('This Month')),
                ],
                child: _dropdownLike(Icons.calendar_today_rounded, _dateFilter),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: PopupMenuButton<String>(
                initialValue: _sortOption,
                color: _AdminJobsColors.slate900,
                onSelected: (value) {
                  setState(() => _sortOption = value);
                  _applyFilter();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'Newest', child: Text('Newest')),
                  PopupMenuItem(value: 'Oldest', child: Text('Oldest')),
                  PopupMenuItem(
                    value: 'Most Results',
                    child: Text('Most Results'),
                  ),
                ],
                child: _dropdownLike(Icons.sort_rounded, _sortOption),
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

  Widget _statusChip(String label) {
    final active = _statusFilter == label;
    return GestureDetector(
      onTap: () {
        if (_statusFilter == label) return;
        setState(() {
          _statusFilter = label;
          _page = 1;
        });
        _loadJobs(animate: false);
      },
      child: AnimatedContainer(
        duration: AppSpacing.durationFast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: active
              ? _AdminJobsColors.indigo.withValues(alpha: 0.22)
              : _AdminJobsColors.slate900,
          borderRadius: AppSpacing.borderRadiusSm,
          border: Border.all(
            color: active
                ? _AdminJobsColors.indigo.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: active ? Colors.white : Colors.white70,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _dropdownLike(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: _AdminJobsColors.slate900,
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _AdminJobsColors.indigo, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Icon(
            Icons.arrow_drop_down_rounded,
            color: Colors.white54,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _viewToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _AdminJobsColors.slate900,
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          _viewChip('Cards', Icons.view_agenda_rounded),
          _viewChip('Table', Icons.table_chart_rounded),
        ],
      ),
    );
  }

  Widget _viewChip(String label, IconData icon) {
    final active = _viewMode == label;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = label),
      child: AnimatedContainer(
        duration: AppSpacing.durationFast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: active
              ? _AdminJobsColors.indigo.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: AppSpacing.borderRadiusSm,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 14,
              color: active ? _AdminJobsColors.indigo : Colors.white54,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: active ? Colors.white : Colors.white54,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulkBar() {
    return Container(
      padding: AppSpacing.paddingSm,
      decoration: BoxDecoration(
        color: _AdminJobsColors.slate900,
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_selectedRows.length} selected',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: _bulkDownloading ? null : _downloadSelectedJobs,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            icon: _bulkDownloading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded, size: 16),
            label: Text(
              _bulkDownloading ? 'Exporting...' : 'Download selected',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJobsContent(LayoutType layoutType) {
    final canTable = ResponsiveUtils.shouldUseTableView(layoutType);

    if (canTable && _viewMode == 'Table') {
      final rows = _filteredJobs
          .map(
            (job) => {
              'job_id': job['job_id'] ?? '',
              'username': job['username'] ?? '',
              'category': job['category'] ?? '',
              'status': job['status'] ?? '',
              'results': _resultsCount(job),
              'date': _formatDate(job['created_at']?.toString()),
              '_raw': job,
            },
          )
          .toList();

      return Column(
        children: [
          InfinityDataTable(
            layoutType: layoutType,
            columns: [
              const InfinityDataColumn(label: 'Job ID', keyName: 'job_id'),
              const InfinityDataColumn(label: 'User', keyName: 'username'),
              const InfinityDataColumn(label: 'Category', keyName: 'category'),
              const InfinityDataColumn(label: 'Status', keyName: 'status'),
              const InfinityDataColumn(
                label: 'Results',
                keyName: 'results',
                numeric: true,
              ),
              const InfinityDataColumn(label: 'Date', keyName: 'date'),
              InfinityDataColumn(
                label: 'View',
                keyName: 'view',
                cellBuilder: (row) {
                  final raw = row['_raw'];
                  if (raw is! Map<String, dynamic>) {
                    return const SizedBox.shrink();
                  }
                  return TextButton(
                    onPressed: () => _openResults(raw),
                    child: const Text('View'),
                  );
                },
              ),
            ],
            rows: rows,
            showCheckboxes: true,
            selectedRows: _selectedRows,
            onSelectionChanged: (updated) {
              setState(() {
                _selectedRows
                  ..clear()
                  ..addAll(updated);
              });
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _buildPagination(),
        ],
      );
    }

    return Column(
      children: [
        ..._filteredJobs.map(_buildJobCard),
        const SizedBox(height: AppSpacing.md),
        _buildPagination(),
      ],
    );
  }

  Widget _buildPagination() {
    if (_totalPages <= 1) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: _AdminJobsColors.slate900,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          OutlinedButton(
            onPressed: _page > 1 ? () => _goToPage(_page - 1) : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: const Text('Previous'),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Page $_page of $_totalPages  -  $_totalJobs total jobs',
              textAlign: TextAlign.center,
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton(
            onPressed: _page < _totalPages ? () => _goToPage(_page + 1) : null,
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

  Widget _buildJobCard(Map<String, dynamic> job) {
    final jobId = (job['job_id'] ?? '').toString();
    final category = (job['category'] ?? 'Unknown').toString();
    final username = (job['username'] ?? 'unknown').toString();
    final statusRaw = (job['status'] ?? 'unknown').toString().toLowerCase();
    if (statusRaw == 'completed') {
      return _buildCompletedJobCard(job);
    }
    final resultCount = _resultsCount(job);
    final createdAt = _formatDate(job['created_at']?.toString());
    final status = _statusStyle((job['status'] ?? 'unknown').toString());
    final isDownloading = _downloadingJobs.contains(jobId);
    final cityCount = _asInt(job['total_cities']);
    final createdAtDate =
        DateTime.tryParse(job['created_at']?.toString() ?? '') ??
            DateTime.now();
    return JobStatusCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      category: category,
      jobId: jobId,
      timestamp: createdAtDate,
      statusLabel: status.label,
      statusColor: status.color,
      statusBackground: status.background,
      statusIcon: status.icon,
      primaryInfo: 'Owner: @$username',
      secondaryInfo: '$resultCount results • $cityCount cities',
      metaItems: [
        JobCardMetaItem(
          icon: Icons.calendar_today_rounded,
          text: createdAt,
        ),
        JobCardMetaItem(
          icon: Icons.list_alt_rounded,
          text: '$resultCount results',
        ),
        JobCardMetaItem(
          icon: Icons.location_city_rounded,
          text: '$cityCount cities',
        ),
      ],
      isDownloading: isDownloading,
      onViewResults: () => _openResults(job),
      onDownload: () => _downloadJob(job),
      downloadLabel: 'Download CSV',
    );
  }

  Widget _buildCompletedJobCard(Map<String, dynamic> job) {
    final jobId = (job['job_id'] ?? '').toString();
    final category = (job['category'] ?? 'Unknown').toString();
    final username = (job['username'] ?? 'unknown').toString();
    final resultCount = _resultsCount(job);
    final totalCities = _asInt(job['total_cities']);
    final createdAt = DateTime.tryParse(job['created_at']?.toString() ?? '');
    final completedAt =
        DateTime.tryParse(job['completed_at']?.toString() ?? '') ??
            createdAt ??
            DateTime.now();
    final duration = createdAt != null && completedAt.isAfter(createdAt)
        ? completedAt.difference(createdAt)
        : Duration.zero;
    final avgPerCity = totalCities > 0 ? resultCount / totalCities : 0.0;
    final isDownloading = _downloadingJobs.contains(jobId);

    return JobCompletionCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      category: category,
      jobId: jobId,
      completedAt: completedAt,
      leadCount: resultCount,
      citiesText: totalCities > 0 ? '$totalCities cities' : 'N/A',
      durationText: _formatDurationCompact(duration),
      topCityText: 'Owner: @$username',
      avgPerCityText: totalCities > 0
          ? 'Avg: ~${avgPerCity.toStringAsFixed(1)}/city'
          : 'Avg: N/A',
      isDownloading: isDownloading,
      onViewResults: () => _openResults(job),
      onDownload: () => _downloadJob(job),
      downloadLabel: 'Download CSV',
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: _AdminJobsColors.slate900,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 42,
            color: Colors.white.withValues(alpha: 0.35),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No jobs found for this filter.',
            style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
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

class _AdminJobsColors {
  static const Color slate950 = AppColors.backgroundDark;
  static const Color slate900 = AppColors.backgroundDarkAlt;
  static const Color indigo = AppColors.primaryBlue;
  static const Color emerald = AppColors.successGreen;
  static const Color rose = AppColors.dangerRed;
  static const Color amber = AppColors.warningYellow;
}
