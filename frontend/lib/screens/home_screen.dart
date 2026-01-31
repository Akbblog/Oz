import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/scraper_provider.dart';
import '../providers/auth_provider.dart';
import '../core/theme/app_theme.dart';
import 'state_selection_screen.dart';
import 'scraping_screen.dart';
import 'results_screen.dart';
import 'admin_dashboard_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 1; // Start on Scrape tab
  late PageController _pageController;
  late AnimationController _fabAnimationController;

  final List<_NavItem> _navItems = const [
    _NavItem(icon: Icons.location_city_rounded, label: 'Cities'),
    _NavItem(icon: Icons.rocket_launch_rounded, label: 'Scrape'),
    _NavItem(icon: Icons.analytics_rounded, label: 'Results'),
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
                  'Business Scraper',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Pro Edition',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primaryStart,
                  ),
                ),
              ],
            ),
          ),

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
          _showProfileDialog(authProvider);
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

  void _showProfileDialog(AuthProvider authProvider) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusXl,
        ),
        child: Padding(
          padding: AppSpacing.paddingLg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    (authProvider.currentUser?['username'] ?? 'U')[0]
                        .toUpperCase(),
                    style: AppTypography.headlineLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                authProvider.currentUser?['username'] ?? 'User',
                style: AppTypography.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                authProvider.currentUser?['email'] ?? '',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (authProvider.isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: AppSpacing.borderRadiusRound,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Administrator',
                        style: AppTypography.labelMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
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
