
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_breakpoints.dart';

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
        // Ignore credit request failures.
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
        _showSnackBar('Error loading data: $e', AppColors.rose);
      }
    }
  }

  Future<void> _approveUser(int userId) async {
    try {
      await _apiService.approveUser(userId);
      _loadData();
      _showSnackBar('User approved successfully', AppColors.emerald);
    } catch (e) {
      _showSnackBar('Error approving user: $e', AppColors.rose);
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
        _showSnackBar('User deleted successfully', AppColors.emerald);
      } catch (e) {
        _showSnackBar('Error deleting user: $e', AppColors.rose);
      }
    }
  }

  Future<void> _approveCreditRequest(int requestId) async {
    try {
      await _apiService.approveCreditRequest(requestId);
      _loadData();
      _showSnackBar('Credit request approved', AppColors.emerald);
    } catch (e) {
      _showSnackBar('Error approving request: $e', AppColors.rose);
    }
  }

  Future<void> _denyCreditRequest(int requestId) async {
    try {
      await _apiService.denyCreditRequest(requestId);
      _loadData();
      _showSnackBar('Credit request denied', AppColors.amber);
    } catch (e) {
      _showSnackBar('Error denying request: $e', AppColors.rose);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == AppColors.emerald
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
    final layoutType =
        AppBreakpoints.getLayoutType(MediaQuery.of(context).size.width);

    if (!authProvider.isAdmin) {
      return _buildAccessDenied();
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Stack(
            children: [
              _buildBackgroundPattern(),
              Column(
                children: [
                  _buildHeader(authProvider),
                  Expanded(
                    child: _isLoading
                        ? _buildLoading()
                        : _buildContent(layoutType),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildBackgroundPattern() {
    return Positioned.fill(
      child: CustomPaint(
        painter: _GeoPatternPainter(),
      ),
    );
  }

  Widget _buildHeader(AuthProvider authProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: AppColors.cardDarkHighlight.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.purplePrimary, AppColors.purpleDark],
              ),
              borderRadius: AppSpacing.borderRadiusMd,
              boxShadow: [
                BoxShadow(
                  color: AppColors.purplePrimary.withValues(alpha: 0.2),
                  blurRadius: 12,
                  spreadRadius: -6,
                ),
              ],
            ),
            child: const Icon(Icons.all_inclusive, color: Colors.white),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Infinity Leads',
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Admin Dashboard',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Revenue',
            onPressed: () => Navigator.of(context).pushNamed('/admin/revenue'),
            icon: const Icon(Icons.show_chart_rounded, color: Colors.white70),
          ),
          IconButton(
            tooltip: 'Pricing',
            onPressed: () => Navigator.of(context).pushNamed('/admin/pricing'),
            icon: const Icon(Icons.tune_rounded, color: Colors.white70),
          ),
          IconButton(
            tooltip: 'Promos',
            onPressed: () => Navigator.of(context).pushNamed('/admin/promos'),
            icon: const Icon(Icons.confirmation_number_rounded,
                color: Colors.white70),
          ),
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
          ),
          IconButton(
            onPressed: () async {
              await authProvider.logout();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
            icon: const Icon(Icons.logout_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildAccessDenied() {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Center(
        child: Container(
          padding: AppSpacing.paddingLg,
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(color: AppColors.cardDarkHighlight),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock, color: AppColors.rose, size: 48),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Access Denied',
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'You do not have permission to access this area.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.purplePrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Loading dashboard...',
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(LayoutType layoutType) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: _buildTabs(),
        ),
        Expanded(
          child: _selectedTab == 0
              ? _buildStatsView(layoutType)
              : _selectedTab == 1
                  ? _buildUsersView()
                  : _buildCreditsView(),
        ),
      ],
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.cardDarkHighlight),
      ),
      child: Row(
        children: [
          Expanded(child: _buildTab(0, 'Stats', Icons.query_stats)),
          Expanded(child: _buildTab(1, 'Users', Icons.group)),
          Expanded(child: _buildTab(2, 'Credits', Icons.credit_card)),
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
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.purplePrimary : Colors.transparent,
          borderRadius: AppSpacing.borderRadiusMd,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.purplePrimary.withValues(alpha: 0.25),
                    blurRadius: 12,
                    spreadRadius: -6,
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: isSelected ? Colors.white : Colors.white54),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: isSelected ? Colors.white : Colors.white54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildStatsView(LayoutType layoutType) {
    if (_stats == null) {
      return Center(
        child: Text(
          'No data available',
          style: AppTypography.bodyMedium.copyWith(color: Colors.white60),
        ),
      );
    }

    final crossAxisCount = layoutType == LayoutType.desktopLarge
        ? 6
        : layoutType == LayoutType.desktopMedium
            ? 4
            : layoutType == LayoutType.desktopSmall
                ? 3
                : 2;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader('Overview', 'Last 24h'),
          const SizedBox(height: AppSpacing.sm),
          GridView.count(
            crossAxisCount: crossAxisCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
            childAspectRatio: layoutType.index >= LayoutType.desktopSmall.index
                ? 1.5
                : 1.15,
            children: [
              _buildStatCard(
                'Total Users',
                _stats!['total_users'].toString(),
                Icons.group_add,
                AppColors.purplePrimary,
              ),
              _buildStatCard(
                'Pending',
                _stats!['pending_users'].toString(),
                Icons.pending_actions,
                AppColors.amber,
              ),
              _buildStatCard(
                'Total Jobs',
                _stats!['total_jobs'].toString(),
                Icons.work,
                AppColors.blue,
              ),
              _buildStatCard(
                'Credits',
                (_stats!['total_credits'] ?? 0).toString(),
                Icons.payments,
                AppColors.purple,
              ),
              if (layoutType.index >= LayoutType.desktopMedium.index)
                _buildStatCard(
                  'Active Sessions',
                  (_stats!['active_sessions'] ?? 0).toString(),
                  Icons.online_prediction,
                  AppColors.blue,
                ),
              if (layoutType.index >= LayoutType.desktopMedium.index)
                _buildStatCard(
                  'API Health',
                  (_stats!['api_health'] ?? 'OK').toString(),
                  Icons.health_and_safety_rounded,
                  AppColors.emerald,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (layoutType.index >= LayoutType.desktopSmall.index)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 55,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSectionHeader('Recent Users', 'View All'),
                      const SizedBox(height: AppSpacing.sm),
                      ..._users.take(5).map(_buildUserPreview).toList(),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  flex: 45,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSectionHeader(
                          'Credit Requests', '${_creditRequests.length}'),
                      const SizedBox(height: AppSpacing.sm),
                      if (_creditRequests.isEmpty)
                        _buildEmptyCard('No credit requests')
                      else
                        ..._creditRequests
                            .take(3)
                            .map(_buildCreditRequestCard)
                            .toList(),
                    ],
                  ),
                ),
              ],
            )
          else ...[
            _buildSectionHeader('Recent Users', 'View All'),
            const SizedBox(height: AppSpacing.sm),
            ..._users.take(3).map(_buildUserPreview).toList(),
            const SizedBox(height: AppSpacing.lg),
            _buildSectionHeader('Credit Requests', '${_creditRequests.length}'),
            const SizedBox(height: AppSpacing.sm),
            if (_creditRequests.isEmpty)
              _buildEmptyCard('No credit requests')
            else
              ..._creditRequests.take(2).map(_buildCreditRequestCard).toList(),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String trailing) {
    return Row(
      children: [
        Text(
          title,
          style: AppTypography.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: AppSpacing.borderRadiusRound,
            border: Border.all(color: AppColors.cardDarkHighlight),
          ),
          child: Text(
            trailing,
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white54,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color accent) {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.cardDarkHighlight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              if (title == 'Pending')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: AppSpacing.borderRadiusSm,
                  ),
                  child: Text(
                    'Action',
                    style: AppTypography.labelSmall.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title.toUpperCase(),
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white54,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.headlineSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildUserPreview(Map<String, dynamic> user) {
    final isApproved = user['is_approved'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: isApproved
              ? AppColors.cardDarkHighlight
              : AppColors.amber.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildAvatar(
                user['username'] ?? 'U',
                isApproved ? AppColors.emerald : AppColors.amber,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user['username'] ?? 'Unknown',
                      style: AppTypography.titleSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      user['email'] ?? '',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: isApproved
                      ? AppColors.emerald.withValues(alpha: 0.12)
                      : AppColors.amber.withValues(alpha: 0.12),
                  borderRadius: AppSpacing.borderRadiusRound,
                ),
                child: Text(
                  isApproved ? 'Active' : 'Pending',
                  style: AppTypography.labelSmall.copyWith(
                    color: isApproved ? AppColors.emerald : AppColors.amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (!isApproved)
                Expanded(
                  child: _smallButton(
                    label: 'Approve',
                    color: AppColors.purplePrimary,
                    onTap: () => _approveUser(user['id']),
                  ),
                ),
              if (!isApproved) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _smallButton(
                  label: isApproved ? 'Grant Credits' : 'Reject',
                  color: isApproved
                      ? AppColors.cardDarkHighlight
                      : AppColors.cardDark,
                  textColor: isApproved ? Colors.white : Colors.white70,
                  onTap: isApproved
                      ? () => _showGrantCreditsDialog(user)
                      : () => _deleteUser(user['id']),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUsersView() {
    if (_users.isEmpty) {
      return Center(
        child: Text(
          'No users found',
          style: AppTypography.titleMedium.copyWith(color: Colors.white60),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _buildUserCard(user),
        );
      },
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final isApproved = user['is_approved'] == true;
    final isAdmin = user['is_admin'] == true;

    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.cardDarkHighlight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildAvatar(
                user['username'] ?? 'U',
                isApproved ? AppColors.emerald : AppColors.amber,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user['username'] ?? 'Unknown',
                            style: AppTypography.titleSmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isAdmin) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.purplePrimary.withValues(alpha: 0.2),
                              borderRadius: AppSpacing.borderRadiusSm,
                            ),
                            child: Text(
                              'ADMIN',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.purplePrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      user['email'] ?? '',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _pill(
                          isApproved ? 'Approved' : 'Pending',
                          isApproved ? AppColors.emerald : AppColors.amber,
                        ),
                        if (isApproved) ...[
                          const SizedBox(width: 6),
                          _pill(
                            '${user['credit_balance'] ?? 0} Credits',
                            AppColors.blue,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (!isApproved)
                Expanded(
                  child: _smallButton(
                    label: 'Approve',
                    color: AppColors.purplePrimary,
                    onTap: () => _approveUser(user['id']),
                  ),
                ),
              if (!isApproved) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _smallButton(
                  label: isApproved ? 'Grant Credits' : 'Delete',
                  color: AppColors.cardDarkHighlight,
                  textColor: Colors.white,
                  onTap: isApproved
                      ? () => _showGrantCreditsDialog(user)
                      : () => _deleteUser(user['id']),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  Widget _buildCreditsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader('Credit Requests', '${_creditRequests.length}'),
          const SizedBox(height: AppSpacing.sm),
          if (_creditRequests.isEmpty)
            _buildEmptyCard('No pending requests')
          else
            ..._creditRequests.map(_buildCreditRequestCard).toList(),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildCreditRequestCard(Map<String, dynamic> request) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.cardDarkHighlight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildAvatar(request['username'] ?? 'U', AppColors.purplePrimary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request['username'] ?? 'Unknown',
                      style: AppTypography.titleSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      request['email'] ?? '',
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
                  color: AppColors.purplePrimary.withValues(alpha: 0.12),
                  borderRadius: AppSpacing.borderRadiusRound,
                  border: Border.all(
                    color: AppColors.purplePrimary.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  '+${request['amount_requested']} credits',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.purplePrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (request['reason'] != null &&
              (request['reason'] as String).isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.cardDarkHighlight,
                borderRadius: AppSpacing.borderRadiusSm,
              ),
              child: Text(
                request['reason'],
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.white70,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _smallButton(
                  label: 'Approve',
                  color: AppColors.emerald,
                  onTap: () => _approveCreditRequest(request['id']),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _smallButton(
                  label: 'Deny',
                  color: AppColors.cardDarkHighlight,
                  textColor: Colors.white,
                  onTap: () => _denyCreditRequest(request['id']),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String label) {
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.cardDarkHighlight),
      ),
      child: Center(
        child: Text(
          label,
          style: AppTypography.bodyMedium.copyWith(color: Colors.white60),
        ),
      ),
    );
  }

  Widget _buildAvatar(String name, Color accent) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.cardDarkHighlight,
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'U',
          style: AppTypography.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppSpacing.borderRadiusRound,
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _smallButton({
    required String label,
    required Color color,
    Color? textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: color,
          borderRadius: AppSpacing.borderRadiusMd,
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: textColor ?? Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteDialog() {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: AppSpacing.borderRadiusLg,
          border: Border.all(color: AppColors.cardDarkHighlight),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_rounded, color: AppColors.rose, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Delete User',
              style: AppTypography.titleMedium.copyWith(color: Colors.white),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Are you sure you want to delete this user?',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _smallButton(
                    label: 'Cancel',
                    color: AppColors.cardDarkHighlight,
                    textColor: Colors.white,
                    onTap: () => Navigator.pop(context, false),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _smallButton(
                    label: 'Delete',
                    color: AppColors.rose,
                    onTap: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGrantCreditsDialog(Map<String, dynamic> user) async {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: AppSpacing.paddingMd,
          decoration: BoxDecoration(
            color: AppColors.cardDark,
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(color: AppColors.cardDarkHighlight),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_card, color: AppColors.emerald, size: 32),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Grant Credits',
                style: AppTypography.titleMedium.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'to ${user['username']}',
                style: AppTypography.bodySmall.copyWith(color: Colors.white60),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  labelStyle: const TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: AppColors.cardDarkHighlight,
                  border: OutlineInputBorder(
                    borderRadius: AppSpacing.borderRadiusMd,
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon:
                      const Icon(Icons.monetization_on, color: AppColors.emerald),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: reasonController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Reason (optional)',
                  labelStyle: const TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: AppColors.cardDarkHighlight,
                  border: OutlineInputBorder(
                    borderRadius: AppSpacing.borderRadiusMd,
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon:
                      const Icon(Icons.note, color: Colors.white54),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _smallButton(
                      label: 'Cancel',
                      color: AppColors.cardDarkHighlight,
                      textColor: Colors.white,
                      onTap: () => Navigator.pop(context, false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _smallButton(
                      label: 'Grant',
                      color: AppColors.emerald,
                      onTap: () async {
                        final amount = int.tryParse(amountController.text);
                        if (amount == null || amount <= 0) {
                          _showSnackBar('Please enter a valid amount', AppColors.rose);
                          return;
                        }
                        try {
                          await _apiService.grantCredits(
                            userId: user['id'],
                            amount: amount,
                            reason: reasonController.text.isEmpty
                                ? null
                                : reasonController.text,
                          );
                          if (context.mounted) Navigator.pop(context, true);
                        } catch (e) {
                          _showSnackBar('Error granting credits: $e', AppColors.rose);
                        }
                      },
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
      _showSnackBar('Credits granted successfully', AppColors.emerald);
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

// Colors now consolidated in AppColors

class _GeoPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.purplePrimary.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    const spacing = 60.0;
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
