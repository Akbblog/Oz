import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../widgets/gradient_background.dart';
import '../widgets/glass_card.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _creditRequests = [];
  bool _isLoading = true;
  int _selectedTab = 0;

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
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _apiService.getAdminStats();
      final users = await _apiService.getAllUsers();
      List<Map<String, dynamic>> creditReqs = [];
      try {
        creditReqs = await _apiService.getAdminCreditRequests();
      } catch (_) {
        // Credit requests endpoint may fail, continue without it
      }
      if (mounted) {
        setState(() {
          _stats = stats;
          _users = users;
          _creditRequests = creditReqs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error loading data: $e', AppColors.error);
      }
    }
  }

  Future<void> _approveUser(int userId) async {
    try {
      await _apiService.approveUser(userId);
      _loadData();
      _showSnackBar('User approved successfully', AppColors.success);
    } catch (e) {
      _showSnackBar('Error approving user: $e', AppColors.error);
    }
  }

  Future<void> _deleteUser(int userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildDeleteDialog(),
    );

    if (confirmed == true) {
      try {
        await _apiService.deleteUser(userId);
        _loadData();
        _showSnackBar('User deleted successfully', AppColors.success);
      } catch (e) {
        _showSnackBar('Error deleting user: $e', AppColors.error);
      }
    }
  }

  Widget _buildDeleteDialog() {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_rounded,
                color: AppColors.error,
                size: 40,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Delete User',
              style: AppTypography.titleLarge.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Are you sure you want to delete this user?\nThis action cannot be undone.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white30),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == AppColors.success
                  ? Icons.check_circle
                  : Icons.error_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (!authProvider.isAdmin) {
      return _buildAccessDenied();
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(authProvider),
      body: GradientBackground(
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: _isLoading ? _buildLoading() : _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildAccessDenied() {
    return Scaffold(
      body: GradientBackground(
        child: Center(
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock,
                    color: AppColors.error,
                    size: 48,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Access Denied',
                  style: AppTypography.headlineSmall.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'You do not have permission to access this area.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AuthProvider authProvider) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Admin Dashboard',
        style: AppTypography.headlineSmallLight,
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.glassWhite,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: const Icon(Icons.refresh, color: Colors.white, size: 20),
          ),
          onPressed: _loadData,
        ),
        const SizedBox(width: AppSpacing.xs),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.glassWhite,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: const Icon(Icons.logout, color: Colors.white, size: 20),
          ),
          onPressed: () async {
            await authProvider.logout();
            if (mounted) {
              Navigator.of(context).pushReplacementNamed('/login');
            }
          },
        ),
        const SizedBox(width: AppSpacing.md),
      ],
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.secondaryStart),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Loading dashboard...',
            style: AppTypography.titleMediumLight,
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // Tab Selector
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _buildTabSelector(),
        ),
        // Content
        Expanded(
          child: _selectedTab == 0
              ? _buildStatsView()
              : _selectedTab == 1
                  ? _buildUsersView()
                  : _buildCreditsView(),
        ),
      ],
    );
  }

  Widget _buildTabSelector() {
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: _buildTab(0, 'Stats', Icons.analytics)),
          Expanded(child: _buildTab(1, 'Users', Icons.people)),
          Expanded(child: _buildTab(2, 'Credits', Icons.account_balance_wallet)),
        ],
      ),
    );
  }

  Widget _buildTab(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: AnimatedContainer(
        duration: AppSpacing.durationFast,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.white60,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: AppTypography.labelLarge.copyWith(
                color: isSelected ? Colors.white : Colors.white60,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsView() {
    if (_stats == null) {
      return Center(
        child: Text(
          'No data available',
          style: AppTypography.bodyMedium.copyWith(color: Colors.white60),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stats Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: 1.1,
            children: [
              _buildStatCard(
                'Total Users',
                _stats!['total_users'].toString(),
                Icons.people,
                AppColors.blueGradient,
              ),
              _buildStatCard(
                'Approved',
                _stats!['approved_users'].toString(),
                Icons.check_circle,
                AppColors.tealGradient,
              ),
              _buildStatCard(
                'Pending',
                _stats!['pending_users'].toString(),
                Icons.pending,
                AppColors.orangeGradient,
              ),
              _buildStatCard(
                'Total Jobs',
                _stats!['total_jobs'].toString(),
                Icons.work,
                AppColors.purpleGradient,
              ),
              _buildStatCard(
                'Completed',
                _stats!['completed_jobs'].toString(),
                Icons.done_all,
                AppColors.secondaryGradient,
              ),
              _buildStatCard(
                'Results',
                _stats!['total_results'].toString(),
                Icons.list_alt,
                AppColors.pinkGradient,
              ),
              _buildStatCard(
                'Total Credits',
                _stats!['total_credits']?.toString() ?? '0',
                Icons.account_balance_wallet,
                AppColors.successGradient,
              ),
              _buildStatCard(
                'Credit Requests',
                _stats!['pending_credit_requests']?.toString() ?? '0',
                Icons.request_quote,
                AppColors.warningGradient,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          // Recent Jobs Section
          _buildRecentJobsSection(),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    LinearGradient gradient,
  ) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              style: AppTypography.headlineMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentJobsSection() {
    final recentJobs = _stats!['recent_jobs'] as List? ?? [];

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  Icons.history,
                  color: AppColors.info,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Recent Jobs', style: AppTypography.titleMediumLight),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (recentJobs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'No recent jobs',
                  style: AppTypography.bodyMedium.copyWith(color: Colors.white60),
                ),
              ),
            )
          else
            ...recentJobs.map((job) => _buildJobItem(job)),
        ],
      ),
    );
  }

  Widget _buildJobItem(Map<String, dynamic> job) {
    final isCompleted = job['status'] == 'completed';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (isCompleted ? AppColors.success : AppColors.warning)
                  .withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCompleted ? Icons.check_circle : Icons.pending,
              color: isCompleted ? AppColors.success : AppColors.warning,
              size: 16,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job['category'] ?? 'Unknown',
                  style: AppTypography.labelMedium.copyWith(color: Colors.white),
                ),
                Text(
                  '${job['username']} • ${job['status']}',
                  style: AppTypography.bodySmall.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
          Text(
            _formatDate(job['created_at']),
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersView() {
    if (_users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              color: Colors.white30,
              size: 64,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No users found',
              style: AppTypography.titleMediumLight,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 200 + (index * 50).clamp(0, 300)),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _buildUserCard(user),
          ),
        );
      },
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final isApproved = user['is_approved'] == true;
    final isAdmin = user['is_admin'] == true;

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              gradient: isApproved
                  ? AppColors.successGradient
                  : AppColors.warningGradient,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (user['username'] as String? ?? 'U')[0].toUpperCase(),
                style: AppTypography.titleLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // User Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user['username'] ?? 'Unknown',
                        style: AppTypography.titleMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isAdmin) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentStart.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'ADMIN',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.accentStart,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  user['email'] ?? '',
                  style: AppTypography.bodySmall.copyWith(color: Colors.white60),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: (isApproved ? AppColors.success : AppColors.warning)
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
                        border: Border.all(
                          color: (isApproved ? AppColors.success : AppColors.warning)
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        isApproved ? 'Approved' : 'Pending',
                        style: AppTypography.labelSmall.copyWith(
                          color: isApproved ? AppColors.success : AppColors.warning,
                        ),
                      ),
                    ),
                    if (isApproved) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xxs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.account_balance_wallet, size: 12, color: AppColors.info),
                            const SizedBox(width: 4),
                            Text(
                              '${user['credit_balance'] ?? 0}',
                              style: AppTypography.labelSmall.copyWith(color: AppColors.info),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isApproved)
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: AppColors.success,
                      size: 16,
                    ),
                  ),
                  onPressed: () => _approveUser(user['id']),
                  tooltip: 'Approve',
                ),
              if (isApproved)
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_card,
                      color: AppColors.info,
                      size: 16,
                    ),
                  ),
                  onPressed: () => _showGrantCreditsDialog(user),
                  tooltip: 'Grant Credits',
                ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.delete,
                    color: AppColors.error,
                    size: 16,
                  ),
                ),
                onPressed: () => _deleteUser(user['id']),
                tooltip: 'Delete',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreditsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Credit Stats Summary
          _buildCreditStatsCard(),
          const SizedBox(height: AppSpacing.lg),
          // Pending Credit Requests
          _buildCreditRequestsSection(),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildCreditStatsCard() {
    final totalCredits = _stats?['total_credits'] ?? 0;
    final pendingRequests = _stats?['pending_credit_requests'] ?? 0;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: AppColors.successGradient,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Credit System Overview', style: AppTypography.titleMediumLight),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _buildCreditStatItem(
                  'Total Credits',
                  totalCredits.toString(),
                  Icons.monetization_on,
                  AppColors.success,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildCreditStatItem(
                  'Pending Requests',
                  pendingRequests.toString(),
                  Icons.pending_actions,
                  pendingRequests > 0 ? AppColors.warning : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreditStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: AppTypography.headlineSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditRequestsSection() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(Icons.request_quote, color: AppColors.warning, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Pending Credit Requests', style: AppTypography.titleMediumLight),
              const Spacer(),
              if (_creditRequests.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
                  ),
                  child: Text(
                    '${_creditRequests.length}',
                    style: AppTypography.labelSmall.copyWith(color: AppColors.warning),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_creditRequests.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline, color: AppColors.success, size: 48),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'No pending requests',
                      style: AppTypography.bodyMedium.copyWith(color: Colors.white60),
                    ),
                  ],
                ),
              ),
            )
          else
            ...List.generate(_creditRequests.length, (index) {
              final request = _creditRequests[index];
              return _buildCreditRequestItem(request);
            }),
        ],
      ),
    );
  }

  Widget _buildCreditRequestItem(Map<String, dynamic> request) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: AppColors.warningGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    (request['username'] as String? ?? 'U')[0].toUpperCase(),
                    style: AppTypography.titleMedium.copyWith(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['username'] ?? 'Unknown',
                      style: AppTypography.labelMedium.copyWith(color: Colors.white),
                    ),
                    Text(
                      request['email'] ?? '',
                      style: AppTypography.bodySmall.copyWith(color: Colors.white60),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
                ),
                child: Text(
                  '+${request['amount_requested']} credits',
                  style: AppTypography.labelSmall.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (request['reason'] != null && (request['reason'] as String).isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.message, size: 14, color: Colors.white38),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      request['reason'],
                      style: AppTypography.bodySmall.copyWith(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _denyCreditRequest(request['id']),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Deny'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _approveCreditRequest(request['id']),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _approveCreditRequest(int requestId) async {
    try {
      await _apiService.approveCreditRequest(requestId);
      _loadData();
      _showSnackBar('Credit request approved', AppColors.success);
    } catch (e) {
      _showSnackBar('Error approving request: $e', AppColors.error);
    }
  }

  Future<void> _denyCreditRequest(int requestId) async {
    try {
      await _apiService.denyCreditRequest(requestId);
      _loadData();
      _showSnackBar('Credit request denied', AppColors.warning);
    } catch (e) {
      _showSnackBar('Error denying request: $e', AppColors.error);
    }
  }

  Future<void> _showGrantCreditsDialog(Map<String, dynamic> user) async {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppColors.successGradient,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_card, color: Colors.white, size: 32),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Grant Credits',
                style: AppTypography.titleLarge.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'to ${user['username']}',
                style: AppTypography.bodyMedium.copyWith(color: Colors.white60),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  labelStyle: TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(Icons.monetization_on, color: AppColors.success),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: reasonController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Reason (optional)',
                  labelStyle: TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(Icons.note, color: Colors.white38),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white30),
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final amount = int.tryParse(amountController.text);
                        if (amount == null || amount <= 0) {
                          _showSnackBar('Please enter a valid amount', AppColors.error);
                          return;
                        }
                        try {
                          await _apiService.grantCredits(
                            userId: user['id'],
                            amount: amount,
                            reason: reasonController.text.isEmpty ? null : reasonController.text,
                          );
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (e) {
                          _showSnackBar('Error granting credits: $e', AppColors.error);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      ),
                      child: const Text('Grant'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      _loadData();
      _showSnackBar('Credits granted successfully', AppColors.success);
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }
}
