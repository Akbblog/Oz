import 'package:flutter/material.dart';

import '../core/theme/app_breakpoints.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/responsive_utils.dart';
import '../services/api_service.dart';
import '../widgets/stat_card.dart';
import '../widgets/gradient_button.dart';
import 'results_screen.dart';

class DashboardScreen extends StatefulWidget {
  final bool showHeader;
  final void Function(int index)? onNavigateToTab;

  const DashboardScreen({
    super.key,
    this.showHeader = true,
    this.onNavigateToTab,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  int _credits = 0;
  List<Map<String, dynamic>> _jobs = const [];

  late final AnimationController _fadeController = AnimationController(
    vsync: this,
    duration: AppSpacing.durationMedium,
  );
  late final Animation<double> _fadeAnimation = CurvedAnimation(
    parent: _fadeController,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _api.getCreditBalance(),
        _api.getUserJobs(),
      ]);

      final creditData = results[0] as Map<String, dynamic>;
      final jobs = List<Map<String, dynamic>>.from(results[1] as List);

      if (!mounted) return;
      setState(() {
        _credits = creditData['balance'] ?? 0;
        _jobs = jobs;
        _loading = false;
      });
      _fadeController.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load dashboard: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final layoutType =
        AppBreakpoints.getLayoutType(MediaQuery.of(context).size.width);
    final padding = ResponsiveUtils.getScreenPadding(layoutType);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        top: widget.showHeader,
        bottom: false,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: RefreshIndicator(
            onRefresh: _load,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                padding,
                padding,
                padding,
                AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.showHeader) _buildHeader(),
                  if (widget.showHeader) const SizedBox(height: AppSpacing.lg),
                  if (_error != null) _buildErrorCard(_error!),
                  if (_error != null) const SizedBox(height: AppSpacing.lg),
                  _loading
                      ? _buildLoading(layoutType)
                      : _buildContent(layoutType),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Text(
          'Dashboard',
          style: AppTypography.headlineSmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.dangerRed.withValues(alpha: 0.12),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.dangerRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.dangerRed),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(LayoutType layoutType) {
    final isMobile = layoutType == LayoutType.mobile;
    final crossAxisCount = layoutType == LayoutType.desktopLarge
        ? 4
        : layoutType == LayoutType.desktopMedium
            ? 4
            : layoutType == LayoutType.desktopSmall
                ? 2
                : 2;
    final statAspectRatio = isMobile
        ? 1.1
        : layoutType.index >= LayoutType.desktopSmall.index
            ? 2.0
            : 1.55;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          childAspectRatio: statAspectRatio,
          children: List.generate(
            4,
            (index) => Container(
              decoration: BoxDecoration(
                color: AppColors.elevatedCardDark,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: AppColors.elevatedCardDark,
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(LayoutType layoutType) {
    final isMobile = layoutType == LayoutType.mobile;
    final totalJobs = _jobs.length;
    final completedJobs = _jobs
        .where(
            (j) => (j['status'] ?? '').toString().toLowerCase() == 'completed')
        .length;
    final runningJobs = _jobs
        .where((j) => (j['status'] ?? '').toString().toLowerCase() == 'running')
        .length;

    final createdSparkline = _jobSparkline(dateField: 'created_at');
    final completedSparkline = _jobSparkline(
      dateField: 'completed_at',
      requireStatus: 'completed',
    );
    final runningSparkline = _jobSparkline(
      dateField: 'created_at',
      requireStatus: 'running',
    );

    final crossAxisCount = layoutType == LayoutType.desktopLarge
        ? 4
        : layoutType == LayoutType.desktopMedium
            ? 4
            : layoutType == LayoutType.desktopSmall
                ? 2
                : 2;
    final statAspectRatio = isMobile
        ? 1.1
        : layoutType.index >= LayoutType.desktopSmall.index
            ? 2.0
            : 1.55;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          childAspectRatio: statAspectRatio,
          children: [
            StatCard(
              title: 'Credits',
              value: '$_credits',
              icon: Icons.account_balance_wallet_rounded,
              gradient: AppColors.deepTealGradient,
              subtitle: isMobile
                  ? null
                  : (runningJobs > 0 ? '$runningJobs active' : null),
              onTap: () => Navigator.of(context).pushNamed('/wallet'),
            ),
            StatCard(
              title: 'Total Jobs',
              value: '$totalJobs',
              icon: Icons.work_outline_rounded,
              gradient: AppColors.lavenderGradient,
              subtitle: isMobile
                  ? null
                  : (completedJobs > 0 ? '$completedJobs done' : null),
              sparkline: isMobile ? null : createdSparkline,
              onTap: () => widget.onNavigateToTab?.call(4),
            ),
            StatCard(
              title: 'Completed',
              value: '$completedJobs',
              icon: Icons.check_circle_outline_rounded,
              gradient: AppColors.ochreGradient,
              sparkline: isMobile ? null : completedSparkline,
              onTap: () => widget.onNavigateToTab?.call(3),
            ),
            StatCard(
              title: 'Running',
              value: '$runningJobs',
              icon: Icons.autorenew_rounded,
              gradient: AppColors.dustyRoseGradient,
              sparkline: isMobile ? null : runningSparkline,
              enabled: runningJobs > 0,
              onTap: () => widget.onNavigateToTab?.call(4),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildQuickActions(layoutType),
        const SizedBox(height: AppSpacing.lg),
        _buildActivityFeed(layoutType),
      ],
    );
  }

  Widget _buildQuickActions(LayoutType layoutType) {
    final isMobile = layoutType == LayoutType.mobile;
    final columns = layoutType.index >= LayoutType.desktopSmall.index ? 4 : 2;
    final actionAspectRatio = columns == 4 ? 3.1 : (isMobile ? 1.95 : 2.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: AppTypography.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          childAspectRatio: actionAspectRatio,
          children: [
            _actionCard(
              icon: Icons.rocket_launch_rounded,
              label: 'New Search',
              subtitle: 'Start scraping',
              onTap: () => widget.onNavigateToTab?.call(2),
            ),
            _actionCard(
              icon: Icons.location_city_rounded,
              label: 'Pick Cities',
              subtitle: 'Target markets',
              onTap: () => widget.onNavigateToTab?.call(1),
            ),
            _actionCard(
              icon: Icons.list_alt_rounded,
              label: 'Results',
              subtitle: 'View leads',
              onTap: () => widget.onNavigateToTab?.call(3),
            ),
            _actionCard(
              icon: Icons.history_rounded,
              label: 'History',
              subtitle: 'Past jobs',
              onTap: () => widget.onNavigateToTab?.call(4),
            ),
          ],
        ),
      ],
    );
  }

  List<double> _jobSparkline({
    required String dateField,
    String? requireStatus,
  }) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(const Duration(days: 6));
    final buckets = List<int>.filled(7, 0);

    for (final job in _jobs) {
      if (requireStatus != null) {
        final status = (job['status'] ?? '').toString().toLowerCase();
        if (status != requireStatus) continue;
      }

      final raw = job[dateField]?.toString();
      if (raw == null || raw.isEmpty) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) continue;

      final day = DateTime(parsed.year, parsed.month, parsed.day);
      if (day.isBefore(start) || day.isAfter(end)) continue;

      final idx = day.difference(start).inDays;
      if (idx < 0 || idx >= buckets.length) continue;
      buckets[idx] += 1;
    }

    return buckets.map((c) => c.toDouble()).toList();
  }

  Widget _actionCard({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.elevatedCardDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.25),
                ),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: AppTypography.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white54,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white38, size: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityFeed(LayoutType layoutType) {
    final recent = _jobs.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Recent Activity',
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => widget.onNavigateToTab?.call(4),
              child: Text(
                'View all',
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (recent.isEmpty)
          Container(
            padding: AppSpacing.paddingLg,
            decoration: BoxDecoration(
              color: AppColors.elevatedCardDark,
              borderRadius: AppSpacing.borderRadiusLg,
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              children: [
                const Icon(Icons.rocket_launch_rounded,
                    color: Colors.white54, size: 36),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'No jobs yet',
                  style: AppTypography.titleSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Create your first scraping job to get started.',
                  style:
                      AppTypography.bodySmall.copyWith(color: Colors.white60),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                GradientButton(
                  text: 'Create Job',
                  icon: Icons.add_rounded,
                  expanded: false,
                  height: 52,
                  onPressed: () => widget.onNavigateToTab?.call(2),
                ),
              ],
            ),
          )
        else
          ...recent.map(_activityItem),
      ],
    );
  }

  Widget _activityItem(Map<String, dynamic> job) {
    final status = (job['status'] ?? '').toString().toLowerCase();
    final jobId = (job['job_id'] ?? '').toString();
    final category = (job['category'] ?? 'Job').toString();
    final chargedRaw = job['credit_charged'] ?? job['credit_estimate'];
    final charged = chargedRaw is num
        ? chargedRaw.toInt()
        : (chargedRaw is String ? int.tryParse(chargedRaw) : null);

    Color color;
    IconData icon;
    String label;

    switch (status) {
      case 'completed':
        color = AppColors.successGreen;
        icon = Icons.check_circle_rounded;
        label = 'Completed';
        break;
      case 'failed':
      case 'cancelled':
        color = AppColors.dangerRed;
        icon = Icons.error_rounded;
        label = status == 'cancelled' ? 'Cancelled' : 'Failed';
        break;
      case 'running':
      case 'pending':
        color = AppColors.infoBlue;
        icon = Icons.autorenew_rounded;
        label = 'Running';
        break;
      default:
        color = Colors.white38;
        icon = Icons.circle_outlined;
        label = status.isEmpty ? 'Unknown' : status;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.elevatedCardDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: AppSpacing.borderRadiusMd,
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category,
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  charged != null && charged > 0
                      ? 'Job $jobId - $label • $charged credits'
                      : 'Job $jobId - $label',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white54,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (status == 'completed' && jobId.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ResultsScreen(jobId: jobId),
                  ),
                );
              },
              child: Text(
                'View',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.primaryBlueLight,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
