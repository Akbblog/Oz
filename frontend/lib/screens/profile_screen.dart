
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/responsive_utils.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _error;
  int _totalJobs = 0;
  int _completedJobs = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final jobs = await _apiService.getUserJobs();
      final completed =
          jobs
              .where((job) =>
                  (job['status']?.toString().toLowerCase() ?? '') ==
                  'completed')
              .length;

      if (mounted) {
        setState(() {
          _totalJobs = jobs.length;
          _completedJobs = completed;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load profile stats: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final username = authProvider.currentUser?['username'] ?? 'User';
    final email = authProvider.currentUser?['email'] ?? '';
    final layoutType =
        AppBreakpoints.getLayoutType(MediaQuery.of(context).size.width);

    return Scaffold(
      backgroundColor: _ProfileColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            _buildBackground(),
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.primaryBlue,
                    backgroundColor: AppColors.surfaceDark,
                    onRefresh: _loadStats,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        ResponsiveUtils.getScreenPadding(layoutType),
                        ResponsiveUtils.getScreenPadding(layoutType),
                        ResponsiveUtils.getScreenPadding(layoutType),
                        layoutType == LayoutType.mobile ? 140 : AppSpacing.xl,
                      ),
                      child: layoutType == LayoutType.mobile
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildProfileHeader(username, email),
                                const SizedBox(height: AppSpacing.lg),
                                _buildStatsGrid(layoutType),
                                const SizedBox(height: AppSpacing.lg),
                                _buildMilestones(),
                                const SizedBox(height: AppSpacing.lg),
                                _buildAccountSection(),
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: layoutType == LayoutType.desktopSmall
                                      ? 40
                                      : 35,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildProfileHeader(username, email),
                                      const SizedBox(height: AppSpacing.lg),
                                      _buildStatsGrid(layoutType),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(
                                  flex: layoutType == LayoutType.desktopSmall
                                      ? 60
                                      : 65,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildMilestones(),
                                      const SizedBox(height: AppSpacing.lg),
                                      _buildAccountSection(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
            if (layoutType == LayoutType.mobile) _buildLogoutBar(authProvider),
          ],
        ),
      ),
    );
  }
  Widget _buildBackground() {
    return Positioned.fill(
      child: CustomPaint(
        painter: _ProfileGridPainter(),
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                _ProfileColors.primary.withValues(alpha: 0.35),
                Colors.transparent,
              ],
              radius: 1.2,
              center: const Alignment(0, -1.2),
            ),
          ),
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
        color: _ProfileColors.background.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderDarkAlt.withValues(alpha: 0.6),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          Expanded(
            child: Text(
              'Profile',
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: null,
            child: Text(
              'Edit',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white24,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader(String username, String email) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [_ProfileColors.primary, _ProfileColors.primaryLight],
            ),
          ),
          child: CircleAvatar(
            radius: 64,
            backgroundColor: _ProfileColors.background,
            child: Text(
              username.isNotEmpty ? username[0].toUpperCase() : 'U',
              style: AppTypography.displaySmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          username,
          style: AppTypography.headlineSmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          email,
          style: AppTypography.bodyMedium.copyWith(
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: _ProfileColors.primary.withValues(alpha: 0.15),
            borderRadius: AppSpacing.borderRadiusRound,
            border: Border.all(
              color: _ProfileColors.primary.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.verified, color: _ProfileColors.primary, size: 14),
              const SizedBox(width: 6),
              Text(
                'Pro Member',
                style: AppTypography.labelSmall.copyWith(
                  color: _ProfileColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsGrid(LayoutType layoutType) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryBlue),
      );
    }

    if (_error != null) {
      return Column(
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: () {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _loadStats();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryBlueLight,
            ),
            child: const Text('Retry'),
          ),
        ],
      );
    }

    final cards = [
      _statCard(
        icon: Icons.search,
        label: 'Total Searches',
        value: _totalJobs.toString(),
        color: _ProfileColors.primary,
      ),
      _statCard(
        icon: Icons.check_circle,
        label: 'Completed',
        value: _completedJobs.toString(),
        color: _ProfileColors.emerald,
      ),
      if (layoutType != LayoutType.mobile)
        _statCard(
          icon: Icons.bolt_rounded,
          label: 'Success Rate',
          value: _totalJobs == 0
              ? '0%'
              : '${((_completedJobs / _totalJobs) * 100).round()}%',
          color: _ProfileColors.amber,
        ),
    ];

    if (layoutType == LayoutType.mobile) {
      return Row(
        children: [
          Expanded(child: cards[0]),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: cards[1]),
        ],
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: layoutType == LayoutType.tablet ? 3 : 2,
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.6,
      children: cards,
    );
  }
  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: _ProfileColors.surface.withValues(alpha: 0.4),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: _ProfileColors.primary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            label.toUpperCase(),
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white60,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
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

  Widget _buildMilestones() {
    final weeklyGoal = 1000;
    final progress = weeklyGoal == 0
        ? 0.0
        : (_completedJobs / weeklyGoal).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bar_chart, color: _ProfileColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Statistics',
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: AppSpacing.paddingMd,
          decoration: BoxDecoration(
            color: _ProfileColors.surface.withValues(alpha: 0.3),
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weekly Goal',
                        style: AppTypography.labelLarge.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Leads Exported',
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${(progress * 100).round()}%',
                    style: AppTypography.labelLarge.copyWith(
                      color: _ProfileColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: AppSpacing.borderRadiusRound,
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: progress,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _ProfileColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0', style: AppTypography.labelSmall.copyWith(color: Colors.white38)),
                  Text(
                    '$_completedJobs / $weeklyGoal',
                    style: AppTypography.labelSmall.copyWith(color: Colors.white38),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: AppSpacing.paddingMd,
          decoration: BoxDecoration(
            color: _ProfileColors.surface.withValues(alpha: 0.3),
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _ProfileColors.amber.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _ProfileColors.amber.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(Icons.emoji_events, color: _ProfileColors.amber, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Top Performer',
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Top 5% of users this month',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.manage_accounts, color: _ProfileColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Account',
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Opacity(
          opacity: 0.5,
          child: _menuButton(
            icon: Icons.settings,
            label: 'General Settings',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Coming soon')),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Opacity(
          opacity: 0.5,
          child: _menuButton(
            icon: Icons.lock,
            label: 'Security & Password',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Coming soon')),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _menuButton(
          icon: Icons.credit_card,
          label: 'Billing & Plan',
          subtitle: 'Manage credits & subscription',
          onTap: () {
            Navigator.of(context).pushNamed('/wallet');
          },
        ),
      ],
    );
  }

  Widget _menuButton({
    required IconData icon,
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: _ProfileColors.surface.withValues(alpha: 0.3),
          borderRadius: AppSpacing.borderRadiusLg,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _ProfileColors.surface,
                borderRadius: AppSpacing.borderRadiusSm,
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Icon(icon, color: _ProfileColors.primary, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: AppTypography.labelSmall.copyWith(
                        color: _ProfileColors.emerald,
                      ),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutBar(AuthProvider authProvider) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xl,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              _ProfileColors.background,
              _ProfileColors.background.withValues(alpha: 0.95),
              Colors.transparent,
            ],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: GestureDetector(
          onTap: () async {
            await authProvider.logout();
            if (mounted) {
              Navigator.of(context).pushReplacementNamed('/home');
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            decoration: BoxDecoration(
              color: _ProfileColors.rose,
              borderRadius: AppSpacing.borderRadiusLg,
              boxShadow: [
                BoxShadow(
                  color: _ProfileColors.rose.withValues(alpha: 0.4),
                  blurRadius: 14,
                  spreadRadius: -6,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  'Log Out',
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileColors {
  static const Color primary = AppColors.primaryBlue;
  static const Color primaryLight = AppColors.primaryBlueLight;
  static const Color background = AppColors.backgroundDark;
  static const Color surface = AppColors.elevatedCardDark;
  static const Color emerald = AppColors.successGreen;
  static const Color amber = AppColors.warningYellow;
  static const Color rose = AppColors.dangerRed;
}

class _ProfileGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    const spacing = 64.0;
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
