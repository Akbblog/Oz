import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/analytics_service.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/responsive_utils.dart';
import 'state_selection_screen.dart';
import 'scraping_screen.dart';
import 'results_screen.dart';
import 'job_history_screen.dart';
import 'dashboard_screen.dart';
import 'admin_dashboard_screen.dart';
import 'profile_screen.dart';
import '../widgets/sidebar_navigation.dart';
import '../widgets/top_bar.dart';
import '../widgets/responsive_shell.dart';
import '../widgets/credit_pill.dart';
import '../widgets/brand_mark.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 1; // Guest starts on Cities
  late PageController _pageController;
  late final AuthProvider _authProvider;
  final ApiService _apiService = ApiService();
  bool _isAuthenticated = false;
  int _creditBalance = 0;
  bool _loadingCredits = true;
  String _scrapeInitialCategory = '';
  String _scrapeInitialCities = '';
  String _scrapeInitialMaxResults = '50';

  static const List<_NavItem> _guestNavItems = [
    _NavItem(icon: Icons.location_city_rounded, label: 'Cities', pageIndex: 1),
    _NavItem(icon: Icons.search_rounded, label: 'Search', pageIndex: 2),
  ];
  static const List<_NavItem> _authenticatedNavItems = [
    _NavItem(
      icon: Icons.home_rounded,
      selectedIcon: Icons.home_rounded,
      label: 'Home',
      pageIndex: 0,
    ),
    _NavItem(
      icon: Icons.location_city_rounded,
      selectedIcon: Icons.location_city_rounded,
      label: 'Cities',
      pageIndex: 1,
      activePageIndexes: [1, 2, 3],
      emphasized: true,
    ),
    _NavItem(
      icon: Icons.history_rounded,
      selectedIcon: Icons.history_rounded,
      label: 'History',
      pageIndex: 4,
    ),
  ];
  List<_NavItem> _navItems = _guestNavItems;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.page('/home');
    _pageController = PageController(initialPage: _currentIndex);
    _authProvider = Provider.of<AuthProvider>(context, listen: false);
    _authProvider.addListener(_handleAuthStateChanged);
    _syncAuthState(_authProvider.isAuthenticated, force: true);
  }

  void _handleAuthStateChanged() {
    if (!mounted) return;
    _syncAuthState(_authProvider.isAuthenticated);
  }

  void _syncAuthState(bool isAuthenticated, {bool force = false}) {
    if (!force && _isAuthenticated == isAuthenticated) return;

    final targetPage = isAuthenticated ? 0 : 1;
    setState(() {
      _isAuthenticated = isAuthenticated;
      _navItems = isAuthenticated ? _authenticatedNavItems : _guestNavItems;
      _currentIndex = targetPage;
      _loadingCredits = isAuthenticated;
      if (!isAuthenticated) {
        _creditBalance = 0;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(targetPage);
    });

    if (isAuthenticated) {
      _loadCreditBalance();
    }
  }

  Future<void> _loadCreditBalance() async {
    if (!_isAuthenticated) {
      if (mounted) {
        setState(() {
          _creditBalance = 0;
          _loadingCredits = false;
        });
      }
      return;
    }

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
    _authProvider.removeListener(_handleAuthStateChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    setState(() => _currentIndex = index);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: AppSpacing.durationMedium,
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _startSearchFromCities(String citiesText, String maxResults) {
    setState(() {
      _scrapeInitialCategory = '';
      _scrapeInitialCities = citiesText;
      _scrapeInitialMaxResults = maxResults;
    });
    _onNavTap(2);
  }

  _NavItem _currentNavItem() {
    if (_navItems.isEmpty) {
      return _guestNavItems.first;
    }

    for (final item in _navItems) {
      if (item.pageIndex == _currentIndex) {
        return item;
      }
    }

    for (final item in _navItems) {
      if (item.activePageIndexes.contains(_currentIndex)) {
        return item;
      }
    }

    return _navItems.first;
  }

  void _openLogin() {
    Navigator.of(context).pushNamed('/login');
  }

  Future<void> _openWallet() async {
    if (!_isAuthenticated) {
      _openLogin();
      return;
    }
    await Navigator.of(context).pushNamed('/wallet');
    if (mounted) {
      _loadCreditBalance();
    }
  }

  void _openProfile() {
    if (!_isAuthenticated) {
      _openLogin();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const ProfileScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final layoutType = AppBreakpoints.getLayoutType(
      MediaQuery.of(context).size.width,
    );

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: ResponsiveShell(
        bottomNavigation: layoutType == LayoutType.mobile
            ? _buildBottomNav()
            : null,
        topBarBuilder: (context, layoutType, isCollapsed, onToggleSidebar) {
          final title = _currentNavItem().label;
          return TopBar(
            title: title,
            showMenuToggle: layoutType == LayoutType.tablet,
            onMenuToggle: onToggleSidebar,
            creditBalance: _creditBalance,
            loadingCredits: _loadingCredits,
            onRefreshCredits: _loadCreditBalance,
            userInitial: (authProvider.currentUser?['username'] ?? 'U')[0]
                .toUpperCase(),
            isAuthenticated: _isAuthenticated,
            isAdmin: authProvider.isAdmin,
            onAdminTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const AdminDashboardScreen(),
                ),
              );
            },
            onProfileTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
            onLogoutTap: () async {
              _showLogoutDialog(authProvider);
            },
            onAuthTap: _openLogin,
          );
        },
        sidebarBuilder: (context, layoutType, isCollapsed) {
          return SidebarNavigation(
            currentIndex: _currentIndex,
            onTabSelected: _onNavTap,
            navItems: _navItems
                .map(
                  (item) => SidebarNavItem(
                    icon: item.icon,
                    selectedIcon: item.selectedIcon,
                    label: item.label,
                    pageIndex: item.pageIndex,
                    activePageIndexes: item.activePageIndexes,
                    emphasized: item.emphasized,
                  ),
                )
                .toList(),
            collapsed: isCollapsed,
            hidden: AppBreakpoints.isSidebarHidden(layoutType),
            isAuthenticated: _isAuthenticated,
            isAdmin: authProvider.isAdmin,
            onAdminTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const AdminDashboardScreen(),
                ),
              );
            },
            onProfileTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
            onAuthTap: _openLogin,
            onWalletTap: _openWallet,
            username: authProvider.currentUser?['username'] ?? 'User',
            email: authProvider.currentUser?['email'] ?? 'Pro Account',
          );
        },
        child: Stack(
          children: [
            _buildBackground(),
            layoutType == LayoutType.mobile
                ? Column(
                    children: [
                      _buildHeader(authProvider),
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          physics: _isAuthenticated
                              ? const PageScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                          onPageChanged: (index) {
                            setState(() => _currentIndex = index);
                          },
                          children: [
                            DashboardScreen(
                              showHeader: false,
                              onNavigateToTab: _onNavTap,
                            ),
                            StateSelectionScreen(
                              showHeader: false,
                              onContinueToSearch: _startSearchFromCities,
                            ),
                            ScrapingScreen(
                              showHeader: false,
                              initialCategory: _scrapeInitialCategory,
                              initialCities: _scrapeInitialCities,
                              initialMaxResults: _scrapeInitialMaxResults,
                              onBackToCities: () => _onNavTap(1),
                            ),
                            const ResultsScreen(showHeader: false),
                            const JobHistoryScreen(showHeader: false),
                          ],
                        ),
                      ),
                    ],
                  )
                : Padding(
                    padding: EdgeInsets.all(
                      ResponsiveUtils.getScreenPadding(layoutType),
                    ),
                    child: _buildDesktopContent(),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.backgroundDark, AppColors.backgroundDark],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -120,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryBlue.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -140,
            left: -120,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryBlueLight.withValues(alpha: 0.06),
              ),
            ),
          ),
        ],
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
        color: AppColors.backgroundDark.withValues(alpha: 0.9),
        border: Border(
          bottom: BorderSide(
            color: AppColors.primaryBlue.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: AppSpacing.borderRadiusMd,
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.25),
                  blurRadius: 18,
                  spreadRadius: -6,
                ),
              ],
            ),
            child: const Center(child: BrandMark(size: 32, hoverGlow: true)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Infinity',
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Leads v2.0',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primaryBlue.withValues(alpha: 0.7),
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          if (_isAuthenticated) ...[
            CreditPill(
              balance: _creditBalance,
              loading: _loadingCredits,
              onTap: () => Navigator.of(context).pushNamed('/wallet'),
              onRefresh: _loadCreditBalance,
            ),
            const SizedBox(width: AppSpacing.sm),
            if (authProvider.isAdmin)
              _iconButton(
                icon: Icons.shield_rounded,
                tooltip: 'Admin Dashboard',
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
              ),
            const SizedBox(width: AppSpacing.xs),
            _buildProfileMenu(authProvider),
          ] else ...[
            OutlinedButton.icon(
              onPressed: _openLogin,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: AppColors.primaryBlue.withValues(alpha: 0.45),
                ),
              ),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text(
                'Sign in',
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _iconButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppSpacing.borderRadiusMd,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: AppSpacing.borderRadiusMd,
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileMenu(AuthProvider authProvider) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 50),
      shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusLg),
      color: AppColors.surfaceDark,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: AppSpacing.borderRadiusMd,
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.3),
          ),
        ),
        child: Center(
          child: Text(
            (authProvider.currentUser?['username'] ?? 'U')[0].toUpperCase(),
            style: AppTypography.titleSmall.copyWith(
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
            MaterialPageRoute(builder: (context) => const ProfileScreen()),
          );
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'profile',
          child: Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Profile',
                style: AppTypography.bodyMedium.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              const Icon(
                Icons.logout_rounded,
                size: 18,
                color: AppColors.dangerRed,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Logout',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.dangerRed,
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
        backgroundColor: AppColors.backgroundDark,
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusXl),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.dangerRed.withValues(alpha: 0.1),
                borderRadius: AppSpacing.borderRadiusMd,
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: AppColors.dangerRed,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const Text('Logout', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dangerRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await authProvider.logout();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    if (!_isAuthenticated) {
      return _buildGuestBottomNav();
    }

    final homeActive = _currentIndex == 0;
    final historyActive = _currentIndex == 4;
    final citiesFlowActive =
        _currentIndex == 1 || _currentIndex == 2 || _currentIndex == 3;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: SizedBox(
          height: 96,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                left: 24,
                right: 24,
                bottom: 6,
                child: IgnorePointer(
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: RadialGradient(
                        center: Alignment.topCenter,
                        radius: 1.3,
                        colors: [
                          AppColors.primaryBlue.withValues(alpha: 0.22),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: 78,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.elevatedCardDark.withValues(alpha: 0.9),
                            AppColors.backgroundDark.withValues(alpha: 0.9),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.09),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.44),
                            blurRadius: 28,
                            spreadRadius: -14,
                            offset: const Offset(0, 14),
                          ),
                          BoxShadow(
                            color: AppColors.primaryBlue.withValues(alpha: 0.2),
                            blurRadius: 24,
                            spreadRadius: -16,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildDockNavItem(
                              icon: Icons.home_rounded,
                              selectedIcon: Icons.home_rounded,
                              label: 'Home',
                              isSelected: homeActive,
                              onTap: () => _onNavTap(0),
                            ),
                          ),
                          Expanded(
                            child: _buildDockNavItem(
                              icon: Icons.history_rounded,
                              selectedIcon: Icons.history_rounded,
                              label: 'History',
                              isSelected: historyActive,
                              onTap: () => _onNavTap(4),
                            ),
                          ),
                          Expanded(
                            child: _buildDockNavItem(
                              icon: Icons.add_rounded,
                              selectedIcon: Icons.add_rounded,
                              label: 'New',
                              isSelected: citiesFlowActive,
                              onTap: () => _onNavTap(1),
                            ),
                          ),
                          Expanded(
                            child: _buildDockNavItem(
                              icon: Icons.account_balance_wallet_rounded,
                              selectedIcon: Icons.account_balance_wallet_rounded,
                              label: 'Wallet',
                              isSelected: false,
                              onTap: _openWallet,
                            ),
                          ),
                          Expanded(
                            child: _buildDockNavItem(
                              icon: Icons.person_outline_rounded,
                              selectedIcon: Icons.person_rounded,
                              label: 'Profile',
                              isSelected: false,
                              onTap: _openProfile,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 1,
                left: 18,
                right: 18,
                child: IgnorePointer(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.primaryBlueLight.withValues(alpha: 0.22),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuestBottomNav() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark.withValues(alpha: 0.9),
        border: Border(
          top: BorderSide(color: AppColors.primaryBlue.withValues(alpha: 0.2)),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.backgroundDark,
          borderRadius: AppSpacing.borderRadiusLg,
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(_navItems.length, (index) {
            final item = _navItems[index];
            final isSelected = _currentIndex == item.pageIndex;

            return Expanded(
              child: GestureDetector(
                onTap: () => _onNavTap(item.pageIndex),
                child: AnimatedContainer(
                  duration: AppSpacing.durationFast,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryBlue.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: AppSpacing.borderRadiusMd,
                    border: isSelected
                        ? Border.all(
                            color: AppColors.primaryBlue.withValues(
                              alpha: 0.35,
                            ),
                          )
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAdaptiveIcon(
                        icon: isSelected
                            ? (item.selectedIcon ?? item.icon)
                            : item.icon,
                        color: isSelected
                            ? AppColors.primaryBlueLight
                            : Colors.white54,
                        size: 24,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        item.label,
                        style: AppTypography.labelSmall.copyWith(
                          color: isSelected
                              ? AppColors.primaryBlueLight
                              : Colors.white54,
                          fontWeight: isSelected
                              ? FontWeight.w700
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

  Widget _buildDockNavItem({
    required IconData icon,
    IconData? selectedIcon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final resolvedIcon = isSelected ? (selectedIcon ?? icon) : icon;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: AppSpacing.durationMedium,
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.primaryBlue.withValues(alpha: 0.24),
                      AppColors.primaryBlue.withValues(alpha: 0.1),
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? AppColors.primaryBlueLight.withValues(alpha: 0.36)
                  : Colors.white.withValues(alpha: 0.02),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 30,
                height: 30,
                child: Center(
                  child: _buildAdaptiveIcon(
                    icon: resolvedIcon,
                    color: isSelected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.6),
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: isSelected
                      ? AppColors.primaryBlueLight
                      : Colors.white60,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 11.5,
                  letterSpacing: 0.12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              AnimatedContainer(
                duration: AppSpacing.durationMedium,
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.only(top: 2),
                width: isSelected ? 16 : 0,
                height: 2,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: AppColors.primaryBlueLight.withValues(alpha: 0.95),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdaptiveIcon({
    required IconData icon,
    required Color color,
    required double size,
  }) {
    return Icon(icon, color: color, size: size);
  }

  Widget _buildDesktopContent() {
    switch (_currentIndex) {
      case 0:
        return DashboardScreen(showHeader: false, onNavigateToTab: _onNavTap);
      case 1:
        return StateSelectionScreen(
          showHeader: false,
          onContinueToSearch: _startSearchFromCities,
        );
      case 2:
        return ScrapingScreen(
          showHeader: false,
          initialCategory: _scrapeInitialCategory,
          initialCities: _scrapeInitialCities,
          initialMaxResults: _scrapeInitialMaxResults,
          onBackToCities: () => _onNavTap(1),
        );
      case 3:
        return const ResultsScreen(showHeader: false);
      case 4:
        return const JobHistoryScreen(showHeader: false);
      default:
        return ScrapingScreen(
          showHeader: false,
          initialCategory: _scrapeInitialCategory,
          initialCities: _scrapeInitialCities,
          initialMaxResults: _scrapeInitialMaxResults,
          onBackToCities: () => _onNavTap(1),
        );
    }
  }
}

class _NavItem {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final int pageIndex;
  final List<int> activePageIndexes;
  final bool emphasized;

  const _NavItem({
    required this.icon,
    this.selectedIcon,
    required this.label,
    required this.pageIndex,
    this.activePageIndexes = const [],
    this.emphasized = false,
  });
}
