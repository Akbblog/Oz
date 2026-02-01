import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/scraper_provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../core/theme/app_theme.dart';
import 'state_selection_screen.dart';
import 'scraping_screen.dart';
import 'results_screen.dart';
import 'job_history_screen.dart';
import 'admin_dashboard_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 1; // Start on Scrape tab
  late PageController _pageController;
  late AnimationController _fabAnimationController;
  final ApiService _apiService = ApiService();
  int _creditBalance = 0;
  bool _loadingCredits = true;

  final List<_NavItem> _navItems = const [
    _NavItem(icon: Icons.location_city_rounded, label: 'Cities'),
    _NavItem(icon: Icons.rocket_launch_rounded, label: 'Search'),
    _NavItem(icon: Icons.analytics_rounded, label: 'Results'),
    _NavItem(icon: Icons.history_rounded, label: 'History'),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    _fabAnimationController = AnimationController(
      duration: AppSpacing.durationMedium,
      vsync: this,
    );
    _fabAnimationController.forward();
    _loadCreditBalance();
  }

  Future<void> _loadCreditBalance() async {
    try {
      final data = await _apiService.getCreditBalance();
      if (mounted) {
        setState(() {
          _creditBalance = data['balance'] ?? 0;
          _loadingCredits = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingCredits = false);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fabAnimationController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: AppSpacing.durationMedium,
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _buildCreditBadge() {
    return GestureDetector(
      onTap: _loadCreditBalance,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.success.withValues(alpha: 0.15),
              AppColors.success.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: AppSpacing.borderRadiusRound,
          border: Border.all(
            color: AppColors.success.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.account_balance_wallet,
              size: 16,
              color: AppColors.success,
            ),
            const SizedBox(width: 4),
            _loadingCredits
                ? SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.success),
                    ),
                  )
                : Text(
                    '$_creditBalance',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      body: SafeArea(
        child: Column(
          children: [
            // Custom App Bar
            _buildAppBar(authProvider),

            // Page Content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentIndex = index);
                },
                children: [
                  StateSelectionScreen(),
                  ScrapingScreen(),
                  ResultsScreen(),
                  JobHistoryScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildAppBar(AuthProvider authProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryStart.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Logo
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: AppSpacing.borderRadiusMd,
            ),
            child: const Icon(
              Icons.business_center_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Infinity Leads',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Lead Discovery',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primaryStart,
                  ),
                ),
              ],
            ),
          ),

          // Credit Balance
          _buildCreditBadge(),
          const SizedBox(width: AppSpacing.sm),

          // Admin Button
          if (authProvider.isAdmin)
            _buildIconButton(
              icon: Icons.admin_panel_settings_rounded,
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        AdminDashboardScreen(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                      return FadeTransition(
                        opacity: animation,
                        child: child,
                      );
                    },
                    transitionDuration: AppSpacing.durationMedium,
                  ),
                );
              },
              tooltip: 'Admin Dashboard',
              gradient: AppColors.accentGradient,
            ),
          const SizedBox(width: AppSpacing.xs),

          // Profile Menu
          _buildProfileMenu(authProvider),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    LinearGradient? gradient,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppSpacing.borderRadiusMd,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: gradient ?? AppColors.primaryGradient,
              borderRadius: AppSpacing.borderRadiusMd,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileMenu(AuthProvider authProvider) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 50),
      shape: RoundedRectangleBorder(
        borderRadius: AppSpacing.borderRadiusLg,
      ),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: AppColors.secondaryGradient,
          borderRadius: AppSpacing.borderRadiusMd,
        ),
        child: Center(
          child: Text(
            (authProvider.currentUser?['username'] ?? 'U')[0].toUpperCase(),
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      onSelected: (value) async {
        if (value == 'logout') {
          _showLogoutDialog(authProvider);
        } else if (value == 'profile') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const ProfileScreen(),
            ),
          );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'profile',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.primaryStart.withValues(alpha: 0.1),
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  size: 18,
                  color: AppColors.primaryStart,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Profile', style: AppTypography.bodyMedium),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.1),
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  size: 18,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Logout',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showLogoutDialog(AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusXl,
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: AppSpacing.borderRadiusMd,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: AppColors.error,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const Text('Logout'),
          ],
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await authProvider.logout();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryStart.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: AppSpacing.borderRadiusLg,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(_navItems.length, (index) {
            final item = _navItems[index];
            final isSelected = _currentIndex == index;

            return Expanded(
              child: GestureDetector(
                onTap: () => _onNavTap(index),
                child: AnimatedContainer(
                  duration: AppSpacing.durationFast,
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    gradient: isSelected ? AppColors.primaryGradient : null,
                    borderRadius: AppSpacing.borderRadiusMd,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textMuted,
                        size: 24,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        item.label,
                        style: AppTypography.labelSmall.copyWith(
                          color: isSelected
                              ? Colors.white
                              : AppColors.textMuted,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem({required this.icon, required this.label});
}
