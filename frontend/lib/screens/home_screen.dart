import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
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
    _NavItem(icon: Icons.dashboard_rounded, label: 'Dashboard', pageIndex: 0),
    _NavItem(icon: Icons.location_city_rounded, label: 'Cities', pageIndex: 1),
    _NavItem(icon: Icons.search_rounded, label: 'Search', pageIndex: 2),
    _NavItem(icon: Icons.list_alt_rounded, label: 'Results', pageIndex: 3),
    _NavItem(icon: Icons.history_rounded, label: 'History', pageIndex: 4),
  ];
  List<_NavItem> _navItems = _guestNavItems;

  @override
  void initState() {
    super.initState();
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
    return _navItems.firstWhere(
      (item) => item.pageIndex == _currentIndex,
      orElse: () => _navItems.first,
    );
  }

  void _openLogin() {
    Navigator.of(context).pushNamed('/login');
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final layoutType =
        AppBreakpoints.getLayoutType(MediaQuery.of(context).size.width);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: ResponsiveShell(
        bottomNavigation:
            layoutType == LayoutType.mobile ? _buildBottomNav() : null,
        topBarBuilder: (context, layoutType, isCollapsed, onToggleSidebar) {
          final title = _currentNavItem().label;
          return TopBar(
            title: title,
            showMenuToggle: layoutType == LayoutType.tablet,
            onMenuToggle: onToggleSidebar,
            creditBalance: _creditBalance,
            loadingCredits: _loadingCredits,
            onRefreshCredits: _loadCreditBalance,
            userInitial:
                (authProvider.currentUser?['username'] ?? 'U')[0].toUpperCase(),
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
                MaterialPageRoute(
                  builder: (context) => const ProfileScreen(),
                ),
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
                    label: item.label,
                    pageIndex: item.pageIndex,
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
                MaterialPageRoute(
                  builder: (context) => const ProfileScreen(),
                ),
              );
            },
            onAuthTap: _openLogin,
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: AppSpacing.borderRadiusMd,
              border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.25),
                  blurRadius: 18,
                  spreadRadius: -6,
                ),
              ],
            ),
            child: SvgPicture.asset(
              'assets/logo_mark.svg',
              width: 22,
              height: 22,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
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
                        return FadeTransition(opacity: animation, child: child);
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
            child: Icon(
              icon,
              color: Colors.white,
              size: 18,
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
              const Icon(Icons.person_outline_rounded, size: 18, color: Colors.white),
              const SizedBox(width: AppSpacing.sm),
              Text('Profile', style: AppTypography.bodyMedium.copyWith(color: Colors.white)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              const Icon(Icons.logout_rounded, size: 18, color: AppColors.dangerRed),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Logout',
                style: AppTypography.bodyMedium.copyWith(color: AppColors.dangerRed),
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
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusXl,
        ),
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
        content: const Text('Are you sure you want to logout?', style: TextStyle(color: Colors.white70)),
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
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark.withValues(alpha: 0.9),
        border: Border(
          top: BorderSide(
            color: AppColors.primaryBlue.withValues(alpha: 0.2),
          ),
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
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryBlue.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: AppSpacing.borderRadiusMd,
                    border: isSelected
                        ? Border.all(
                            color: AppColors.primaryBlue.withValues(alpha: 0.35),
                          )
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        color: isSelected ? AppColors.primaryBlueLight : Colors.white54,
                        size: 24,
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        item.label,
                        style: AppTypography.labelSmall.copyWith(
                          color: isSelected ? AppColors.primaryBlueLight : Colors.white54,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
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
  final String label;
  final int pageIndex;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.pageIndex,
  });
}

// ---------------------------------------------------------------------------
// Credit Pill – animated header widget
// ---------------------------------------------------------------------------

class _CreditPill extends StatefulWidget {
  final int balance;
  final int maxBalance;
  final bool loading;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  const _CreditPill({
    required this.balance,
    this.maxBalance = 100,
    required this.loading,
    required this.onTap,
    required this.onRefresh,
  });

  @override
  State<_CreditPill> createState() => _CreditPillState();
}

class _CreditPillState extends State<_CreditPill>
    with TickerProviderStateMixin {
  static const _teal = Color(0xFF2C5F6D);
  static const _ochre = Color(0xFFD69446);
  static const _rose = Color(0xFFB86E6E);

  bool _isHovered = false;

  // Pulsing glow – high balance
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Breathing border – low balance
  late final AnimationController _breatheCtrl;
  late final Animation<double> _breatheAnim;

  // Refresh icon spin
  late final AnimationController _spinCtrl;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseAnim = Tween<double>(begin: 0.25, end: 0.55).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _breatheCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _breatheAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _breatheCtrl, curve: Curves.easeInOut),
    );

    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant _CreditPill old) {
    super.didUpdateWidget(old);
    if (old.balance != widget.balance) _syncAnimations();
  }

  void _syncAnimations() {
    if (widget.balance > 50) {
      _pulseCtrl.repeat(reverse: true);
      _breatheCtrl
        ..stop()
        ..value = 0;
    } else if (widget.balance <= 10) {
      _pulseCtrl
        ..stop()
        ..value = 0;
      _breatheCtrl.repeat(reverse: true);
    } else {
      _pulseCtrl
        ..stop()
        ..value = 0;
      _breatheCtrl
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _breatheCtrl.dispose();
    _spinCtrl.dispose();
    super.dispose();
  }

  Color get _color {
    if (widget.balance > 50) return _teal;
    if (widget.balance > 10) return _ochre;
    return _rose;
  }

  void _handleRefresh() {
    _spinCtrl.forward(from: 0);
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final fill = widget.maxBalance > 0
        ? (widget.balance / widget.maxBalance).clamp(0.0, 1.0)
        : 0.0;
    final color = _color;
    final isHigh = widget.balance > 50;
    final isLow = widget.balance <= 10;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulseCtrl, _breatheCtrl]),
          builder: (context, _) {
            // --- glow intensity ---
            final glowAlpha = isHigh
                ? _pulseAnim.value
                : (_isHovered ? 0.45 : 0.30);
            final glowSpread = isHigh
                ? -6.0 + (_pulseAnim.value * 8)
                : (_isHovered ? -2.0 : -6.0);

            // --- border colour ---
            final borderCol = isLow
                ? Color.lerp(
                    color.withValues(alpha: 0.4),
                    const Color(0xFFFF5555).withValues(alpha: 0.9),
                    _breatheAnim.value,
                  )!
                : color.withValues(alpha: _isHovered ? 0.7 : 0.5);

            return AnimatedScale(
              scale: _isHovered ? 1.05 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.20),
                  borderRadius: AppSpacing.borderRadiusRound,
                  border: Border.all(
                    color: borderCol,
                    width: isLow ? 1.5 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: glowAlpha),
                      blurRadius: _isHovered ? 18 : 12,
                      spreadRadius: glowSpread,
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // Progress fill
                    Positioned.fill(
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: fill,
                        child: Container(color: color),
                      ),
                    ),

                    // Content
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.account_balance_wallet,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (widget.loading)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          else
                            Text(
                              '${widget.balance} Cr',
                              style: AppTypography.labelSmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (!widget.loading) ...[
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: _handleRefresh,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                child: RotationTransition(
                                  turns: _spinCtrl,
                                  child: const Icon(
                                    Icons.refresh_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
