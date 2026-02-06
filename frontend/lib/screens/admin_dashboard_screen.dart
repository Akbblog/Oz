
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
  Map<String, dynamic> _adminSettings = {};
  int _activePromos = 0;
  int _promoUses = 0;
  final TextEditingController _startingCreditsController =
      TextEditingController();
  bool _isLoading = true;
  int _selectedTab = 0;
  bool _bulkActionInProgress = false;
  final Set<int> _selectedPendingUserIds = {};
  final Set<int> _selectedCreditRequestIds = {};

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
    _startingCreditsController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _apiService.getAdminStats();
      final users = await _apiService.getAllUsers();
      Map<String, dynamic> settings = {};
      try {
        settings = await _apiService.getAdminSettings();
      } catch (_) {
        settings = {};
      }
      List<Map<String, dynamic>> creditReqs = [];
      try {
        creditReqs = await _apiService.getAdminCreditRequests();
      } catch (_) {
        // Ignore credit request failures.
      }
      int activePromos = 0;
      int promoUses = 0;
      try {
        final promosRes = await _apiService.getAdminPromos();
        final promos =
            List<Map<String, dynamic>>.from(promosRes['promos'] ?? const []);
        activePromos = promos.where((p) => p['is_active'] == true).length;
        promoUses = promos.fold<int>(
            0, (acc, p) => acc + ((p['uses_count'] as num? ?? 0).toInt()));
      } catch (_) {
        // Ignore promo loading failures.
      }
      if (mounted) {
        setState(() {
          _stats = stats;
          _users = users;
          _adminSettings = settings;
          _creditRequests = creditReqs;
          _activePromos = activePromos;
          _promoUses = promoUses;
          _selectedPendingUserIds.clear();
          _selectedCreditRequestIds.clear();
          _isLoading = false;
        });
        final starting = settings['starting_credits']?.toString();
        if (starting != null && starting.trim().isNotEmpty) {
          _startingCreditsController.text = starting.trim();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('Error loading data: $e', AppColors.dangerRed);
      }
    }
  }

  Future<void> _approveUser(int userId) async {
    try {
      await _apiService.approveUser(userId);
      _loadData();
      _showSnackBar('User approved successfully', AppColors.successGreen);
    } catch (e) {
      _showSnackBar('Error approving user: $e', AppColors.dangerRed);
    }
  }

  String _getApprovalState(Map<String, dynamic> user) {
    final state = user['approval_state'];
    if (state is String && state.trim().isNotEmpty) {
      return state.trim();
    }
    final isDenied = user['is_denied'] == true;
    if (isDenied) return 'denied';
    return user['is_approved'] == true ? 'approved' : 'pending';
  }

  Future<void> _denyUser(int userId) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape:
              RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusLg),
          title: Text(
            'Deny user?',
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This will mark the account as denied and optionally email the user.',
                style: AppTypography.bodySmall.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: noteController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Optional admin note',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: AppColors.elevatedCardDark,
                  border: OutlineInputBorder(
                    borderRadius: AppSpacing.borderRadiusMd,
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppSpacing.borderRadiusMd,
                    borderSide:
                        BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: AppTypography.labelLarge.copyWith(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dangerRed,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Deny',
                style:
                    AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      noteController.dispose();
      return;
    }

    try {
      final note = noteController.text.trim().isEmpty
          ? null
          : noteController.text.trim();
      await _apiService.denyUser(userId, adminNote: note);
      _loadData();
      _showSnackBar('User denied', AppColors.warningYellow);
    } catch (e) {
      _showSnackBar('Error denying user: $e', AppColors.dangerRed);
    } finally {
      noteController.dispose();
    }
  }

  Future<void> _restoreUser(int userId) async {
    try {
      await _apiService.restoreUser(userId);
      _loadData();
      _showSnackBar('User restored to pending', AppColors.successGreen);
    } catch (e) {
      _showSnackBar('Error restoring user: $e', AppColors.dangerRed);
    }
  }

  bool _settingBool(String key, {bool fallback = false}) {
    final raw = _adminSettings[key];
    if (raw is bool) return raw;
    if (raw is String) return raw.toLowerCase() == 'true';
    return fallback;
  }

  String _settingString(String key, {String fallback = ''}) {
    final raw = _adminSettings[key];
    if (raw == null) return fallback;
    return raw.toString();
  }

  Future<void> _updateSetting(String key, String value) async {
    try {
      await _apiService.updateAdminSetting(key, value);
      if (!mounted) return;
      setState(() {
        _adminSettings = Map<String, dynamic>.from(_adminSettings)
          ..[key] = value;
      });
      _showSnackBar('Updated setting: $key', AppColors.successGreen);
    } catch (e) {
      _showSnackBar('Failed to update setting: $e', AppColors.dangerRed);
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
        _showSnackBar('User deleted successfully', AppColors.successGreen);
      } catch (e) {
        _showSnackBar('Error deleting user: $e', AppColors.dangerRed);
      }
    }
  }

  Future<void> _showManageUserDialog(Map<String, dynamic> user) async {
    final usernameController =
        TextEditingController(text: (user['username'] ?? '').toString());
    final emailController =
        TextEditingController(text: (user['email'] ?? '').toString());
    final phoneController =
        TextEditingController(text: (user['phone'] ?? '').toString());
    bool isAdmin = user['is_admin'] == true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: AppSpacing.paddingMd,
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: AppSpacing.borderRadiusLg,
              border: Border.all(color: AppColors.elevatedCardDark),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Manage User Profile',
                  style:
                      AppTypography.titleMedium.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'User #${user['id']}',
                  style: AppTypography.bodySmall.copyWith(color: Colors.white60),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: usernameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Username',
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: AppColors.elevatedCardDark,
                    border: OutlineInputBorder(
                      borderRadius: AppSpacing.borderRadiusMd,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: emailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Email',
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: AppColors.elevatedCardDark,
                    border: OutlineInputBorder(
                      borderRadius: AppSpacing.borderRadiusMd,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: phoneController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Phone',
                    labelStyle: const TextStyle(color: Colors.white60),
                    filled: true,
                    fillColor: AppColors.elevatedCardDark,
                    border: OutlineInputBorder(
                      borderRadius: AppSpacing.borderRadiusMd,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile.adaptive(
                  value: isAdmin,
                  onChanged: (value) => setDialogState(() => isAdmin = value),
                  title: Text(
                    'Admin Access',
                    style: AppTypography.bodyMedium.copyWith(color: Colors.white),
                  ),
                  activeThumbColor: AppColors.brandPurple,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _smallButton(
                        label: 'Cancel',
                        color: AppColors.elevatedCardDark,
                        textColor: Colors.white,
                        onTap: () => Navigator.pop(context, false),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _smallButton(
                        label: 'Save',
                        color: AppColors.brandPurple,
                        onTap: () async {
                          final username = usernameController.text.trim();
                          final email = emailController.text.trim();
                          final phone = phoneController.text.trim();
                          if (username.length < 3) {
                            _showSnackBar(
                                'Username must be at least 3 characters',
                                AppColors.dangerRed);
                            return;
                          }
                          if (!email.contains('@')) {
                            _showSnackBar('Please enter a valid email',
                                AppColors.dangerRed);
                            return;
                          }
                          try {
                            await _apiService.updateUserProfileAdmin(
                              user['id'],
                              username: username,
                              email: email,
                              phone: phone,
                              isAdmin: isAdmin,
                            );
                            if (context.mounted) Navigator.pop(context, true);
                          } catch (e) {
                            _showSnackBar('Error updating profile: $e',
                                AppColors.dangerRed);
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
      ),
    );

    usernameController.dispose();
    emailController.dispose();
    phoneController.dispose();

    if (result == true) {
      _showSnackBar('User profile updated', AppColors.successGreen);
      _loadData();
    }
  }

  Future<void> _approveCreditRequest(int requestId) async {
    try {
      await _apiService.approveCreditRequest(requestId);
      _loadData();
      _showSnackBar('Credit request approved', AppColors.successGreen);
    } catch (e) {
      _showSnackBar('Error approving request: $e', AppColors.dangerRed);
    }
  }

  Future<void> _denyCreditRequest(int requestId) async {
    try {
      await _apiService.denyCreditRequest(requestId);
      _loadData();
      _showSnackBar('Credit request denied', AppColors.warningYellow);
    } catch (e) {
      _showSnackBar('Error denying request: $e', AppColors.dangerRed);
    }
  }

  Future<void> _bulkApproveSelectedUsers() async {
    if (_bulkActionInProgress || _selectedPendingUserIds.isEmpty) return;

    setState(() => _bulkActionInProgress = true);
    try {
      final ids = _selectedPendingUserIds.toList()..sort();
      final result = await _apiService.bulkApproveUsers(ids);
      final approved = result['approved'] ?? 0;
      final skipped = result['skipped'] ?? 0;
      _showSnackBar(
        'Approved $approved user(s)${skipped > 0 ? ' (skipped $skipped)' : ''}',
        AppColors.successGreen,
      );
      await _loadData();
    } catch (e) {
      _showSnackBar('Bulk approve failed: $e', AppColors.dangerRed);
    } finally {
      if (mounted) setState(() => _bulkActionInProgress = false);
    }
  }

  Future<void> _bulkApproveSelectedCreditRequests() async {
    if (_bulkActionInProgress || _selectedCreditRequestIds.isEmpty) return;

    setState(() => _bulkActionInProgress = true);
    try {
      final ids = _selectedCreditRequestIds.toList()..sort();
      final result = await _apiService.bulkApproveCreditRequests(ids);
      final approved = result['approved'] ?? 0;
      final skipped = result['skipped'] ?? 0;
      _showSnackBar(
        'Approved $approved request(s)${skipped > 0 ? ' (skipped $skipped)' : ''}',
        AppColors.successGreen,
      );
      await _loadData();
    } catch (e) {
      _showSnackBar('Bulk approve failed: $e', AppColors.dangerRed);
    } finally {
      if (mounted) setState(() => _bulkActionInProgress = false);
    }
  }

  Future<void> _bulkDenySelectedCreditRequests() async {
    if (_bulkActionInProgress || _selectedCreditRequestIds.isEmpty) return;

    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusLg),
          title: Text(
            'Deny selected requests?',
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This will deny ${_selectedCreditRequestIds.length} request(s).',
                style: AppTypography.bodySmall.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: noteController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Optional admin note',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: AppColors.elevatedCardDark,
                  border: OutlineInputBorder(
                    borderRadius: AppSpacing.borderRadiusMd,
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppSpacing.borderRadiusMd,
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: AppTypography.labelLarge.copyWith(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dangerRed,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Deny',
                style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      noteController.dispose();
      return;
    }

    setState(() => _bulkActionInProgress = true);
    try {
      final ids = _selectedCreditRequestIds.toList()..sort();
      final note = noteController.text.trim().isEmpty ? null : noteController.text.trim();
      final result = await _apiService.bulkDenyCreditRequests(ids, adminNote: note);
      final denied = result['denied'] ?? 0;
      final skipped = result['skipped'] ?? 0;
      _showSnackBar(
        'Denied $denied request(s)${skipped > 0 ? ' (skipped $skipped)' : ''}',
        AppColors.warningYellow,
      );
      await _loadData();
    } catch (e) {
      _showSnackBar('Bulk deny failed: $e', AppColors.dangerRed);
    } finally {
      noteController.dispose();
      if (mounted) setState(() => _bulkActionInProgress = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == AppColors.successGreen
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
            color: AppColors.elevatedCardDark.withValues(alpha: 0.5),
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
                colors: [AppColors.brandPurple, AppColors.discoveryPurpleDark],
              ),
              borderRadius: AppSpacing.borderRadiusMd,
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandPurple.withValues(alpha: 0.2),
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
            color: AppColors.surfaceDark,
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(color: AppColors.elevatedCardDark),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock, color: AppColors.dangerRed, size: 48),
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
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandPurple),
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
                  : _selectedTab == 2
                      ? _buildCreditsView()
                      : _buildSettingsView(),
        ),
      ],
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.elevatedCardDark),
      ),
      child: Row(
        children: [
          Expanded(child: _buildTab(0, 'Stats', Icons.query_stats)),
          Expanded(child: _buildTab(1, 'Users', Icons.group)),
          Expanded(child: _buildTab(2, 'Credits', Icons.credit_card)),
          Expanded(child: _buildTab(3, 'Settings', Icons.tune_rounded)),
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
          color: isSelected ? AppColors.brandPurple : Colors.transparent,
          borderRadius: AppSpacing.borderRadiusMd,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.brandPurple.withValues(alpha: 0.25),
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
                AppColors.brandPurple,
              ),
              _buildStatCard(
                'Pending',
                _stats!['pending_users'].toString(),
                Icons.pending_actions,
                AppColors.warningYellow,
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
              _buildStatCard(
                'Active Promos',
                _activePromos.toString(),
                Icons.confirmation_number_rounded,
                AppColors.amber,
              ),
              if (layoutType.index >= LayoutType.desktopMedium.index)
                _buildStatCard(
                  'Promo Uses',
                  _promoUses.toString(),
                  Icons.local_offer_rounded,
                  AppColors.brandOrange,
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
                  AppColors.successGreen,
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
                      ..._users.take(5).map(_buildUserPreview),
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
                            ,
                    ],
                  ),
                ),
              ],
            )
          else ...[
            _buildSectionHeader('Recent Users', 'View All'),
            const SizedBox(height: AppSpacing.sm),
            ..._users.take(3).map(_buildUserPreview),
            const SizedBox(height: AppSpacing.lg),
            _buildSectionHeader('Credit Requests', '${_creditRequests.length}'),
            const SizedBox(height: AppSpacing.sm),
            if (_creditRequests.isEmpty)
              _buildEmptyCard('No credit requests')
            else
              ..._creditRequests.take(2).map(_buildCreditRequestCard),
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
            color: AppColors.surfaceDark,
            borderRadius: AppSpacing.borderRadiusRound,
            border: Border.all(color: AppColors.elevatedCardDark),
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
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.elevatedCardDark),
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
    final approvalState = _getApprovalState(user);
    final isApproved = approvalState == 'approved';
    final isPending = approvalState == 'pending';
    final isDenied = approvalState == 'denied';
    final phone = (user['phone'] ?? '').toString().trim();
    final statusColor = isApproved
        ? AppColors.successGreen
        : isDenied
            ? AppColors.dangerRed
            : AppColors.warningYellow;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: isApproved
              ? AppColors.elevatedCardDark
              : statusColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildAvatar(
                user['username'] ?? 'U',
                statusColor,
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
                    if (phone.isNotEmpty)
                      Text(
                        phone,
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white54,
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
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: AppSpacing.borderRadiusRound,
                ),
                child: Text(
                  isApproved
                      ? 'Active'
                      : isDenied
                          ? 'Denied'
                          : 'Pending',
                  style: AppTypography.labelSmall.copyWith(
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (isPending)
                Expanded(
                  child: _smallButton(
                    label: 'Approve',
                    color: AppColors.brandPurple,
                    onTap: () => _approveUser(user['id']),
                  ),
                ),
              if (isPending) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _smallButton(
                  label: isApproved
                      ? 'Grant Credits'
                      : isDenied
                          ? 'Restore'
                          : 'Deny',
                  color: isApproved
                      ? AppColors.elevatedCardDark
                      : isDenied
                          ? AppColors.elevatedCardDark
                          : AppColors.surfaceDark,
                  textColor: Colors.white,
                  onTap: isApproved
                      ? () => _showGrantCreditsDialog(user)
                      : isDenied
                          ? () => _restoreUser(user['id'])
                          : () => _denyUser(user['id']),
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

    final pendingUsers =
        _users.where((u) => _getApprovalState(u) == 'pending').toList(growable: false);

    return Column(
      children: [
        if (pendingUsers.isNotEmpty) _buildBulkUsersBar(pendingUsers),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            itemCount: _users.length,
            itemBuilder: (context, index) {
              final user = _users[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _buildUserCard(user),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBulkUsersBar(List<Map<String, dynamic>> pendingUsers) {
    final pendingIds = pendingUsers
        .map((u) => (u['id'] as num?)?.toInt())
        .whereType<int>()
        .toList();
    final allSelected =
        pendingIds.isNotEmpty && _selectedPendingUserIds.length == pendingIds.length;
    final selectedCount = _selectedPendingUserIds.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.elevatedCardDark),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: _bulkActionInProgress
                ? null
                : (v) {
                    setState(() {
                      _selectedPendingUserIds
                        ..clear()
                        ..addAll(v == true ? pendingIds : const <int>[]);
                    });
                  },
            activeColor: AppColors.brandPurple,
            checkColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              selectedCount == 0 ? '${pendingUsers.length} pending' : '$selectedCount selected',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: selectedCount == 0 || _bulkActionInProgress
                ? null
                : _bulkApproveSelectedUsers,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.brandPurple.withValues(alpha: 0.5)),
              foregroundColor: Colors.white,
            ),
            icon: _bulkActionInProgress
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.done_all_rounded, size: 18),
            label: Text(
              'Approve',
              style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(
            onPressed: selectedCount == 0 || _bulkActionInProgress
                ? null
                : () => setState(() => _selectedPendingUserIds.clear()),
            child: Text(
              'Clear',
              style: AppTypography.labelLarge.copyWith(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final approvalState = _getApprovalState(user);
    final isApproved = approvalState == 'approved';
    final isPending = approvalState == 'pending';
    final isDenied = approvalState == 'denied';
    final isAdmin = user['is_admin'] == true;
    final userId = (user['id'] as num?)?.toInt();
    final phone = (user['phone'] ?? '').toString().trim();
    final isSelected =
        isPending && userId != null && _selectedPendingUserIds.contains(userId);
    final statusColor = isApproved
        ? AppColors.successGreen
        : isDenied
            ? AppColors.dangerRed
            : AppColors.warningYellow;

    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.elevatedCardDark),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildAvatar(
                user['username'] ?? 'U',
                statusColor,
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
                              color: AppColors.brandPurple.withValues(alpha: 0.2),
                              borderRadius: AppSpacing.borderRadiusSm,
                            ),
                            child: Text(
                              'ADMIN',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.brandPurple,
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
                    if (phone.isNotEmpty)
                      Text(
                        phone,
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white54,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _pill(
                          isApproved
                              ? 'Approved'
                              : isDenied
                                  ? 'Denied'
                                  : 'Pending',
                          statusColor,
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
              if (isPending && userId != null)
                Checkbox(
                  value: isSelected,
                  onChanged: _bulkActionInProgress
                      ? null
                      : (v) {
                          setState(() {
                            if (v == true) {
                              _selectedPendingUserIds.add(userId);
                            } else {
                              _selectedPendingUserIds.remove(userId);
                            }
                          });
                        },
                  activeColor: AppColors.brandPurple,
                  checkColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              if (isPending)
                Expanded(
                  child: _smallButton(
                    label: 'Approve',
                    color: AppColors.brandPurple,
                    onTap: () => _approveUser(user['id']),
                  ),
                ),
              if (isPending) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _smallButton(
                  label: isApproved
                      ? 'Grant Credits'
                      : isDenied
                          ? 'Delete'
                          : 'Deny',
                  color: AppColors.elevatedCardDark,
                  textColor: Colors.white,
                  onTap: isApproved
                      ? () => _showGrantCreditsDialog(user)
                      : isDenied
                          ? () => _deleteUser(user['id'])
                          : () => _denyUser(user['id']),
                ),
              ),
              if (isDenied) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _smallButton(
                    label: 'Restore',
                    color: AppColors.brandPurple,
                    onTap: () => _restoreUser(user['id']),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: _smallButton(
              label: 'Manage Profile',
              color: AppColors.elevatedCardDark,
              textColor: Colors.white,
              onTap: () => _showManageUserDialog(user),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildCreditsView() {
    final selectedCount = _selectedCreditRequestIds.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader('Credit Requests', '${_creditRequests.length}'),
          const SizedBox(height: AppSpacing.sm),
          if (_creditRequests.isNotEmpty) _buildBulkCreditRequestsBar(selectedCount),
          if (_creditRequests.isEmpty)
            _buildEmptyCard('No pending requests')
          else
            ..._creditRequests.map(_buildCreditRequestCard),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildSettingsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader('Settings', 'Registration & Emails'),
          const SizedBox(height: AppSpacing.sm),
          _buildSettingCard(
            title: 'User Registration',
            child: Column(
              children: [
                SwitchListTile(
                  value: _settingBool('auto_approve_users', fallback: false),
                  onChanged: (v) =>
                      _updateSetting('auto_approve_users', v ? 'true' : 'false'),
                  activeThumbColor: AppColors.brandPurple,
                  title: Text(
                    'Auto-approve new users',
                    style: AppTypography.titleSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'When OFF, new users must be approved by an admin before they can log in.',
                    style: AppTypography.bodySmall.copyWith(color: Colors.white60),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startingCreditsController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Starting credits',
                          labelStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: AppColors.elevatedCardDark,
                          border: OutlineInputBorder(
                            borderRadius: AppSpacing.borderRadiusMd,
                            borderSide:
                                BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: AppSpacing.borderRadiusMd,
                            borderSide:
                                BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ElevatedButton(
                      onPressed: () {
                        final raw = _startingCreditsController.text.trim();
                        final parsed = int.tryParse(raw);
                        if (parsed == null || parsed < 0) {
                          _showSnackBar('Starting credits must be a number ≥ 0',
                              AppColors.dangerRed);
                          return;
                        }
                        _updateSetting('starting_credits', parsed.toString());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandPurple,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        'Save',
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildSettingCard(
            title: 'Email Notifications',
            child: Column(
              children: [
                SwitchListTile(
                  value: _settingBool('admin_notification_on_signup', fallback: true),
                  onChanged: (v) => _updateSetting(
                      'admin_notification_on_signup', v ? 'true' : 'false'),
                  activeThumbColor: AppColors.brandPurple,
                  title: Text(
                    'Notify admins on signup',
                    style: AppTypography.titleSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Sends an email to admin(s) when a new user registers and is pending approval.',
                    style: AppTypography.bodySmall.copyWith(color: Colors.white60),
                  ),
                ),
                SwitchListTile(
                  value: _settingBool('send_welcome_email', fallback: true),
                  onChanged: (v) =>
                      _updateSetting('send_welcome_email', v ? 'true' : 'false'),
                  activeThumbColor: AppColors.brandPurple,
                  title: Text(
                    'Send welcome email',
                    style: AppTypography.titleSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Sent when users are auto-approved at registration.',
                    style: AppTypography.bodySmall.copyWith(color: Colors.white60),
                  ),
                ),
                SwitchListTile(
                  value: _settingBool('send_approval_email', fallback: true),
                  onChanged: (v) =>
                      _updateSetting('send_approval_email', v ? 'true' : 'false'),
                  activeThumbColor: AppColors.brandPurple,
                  title: Text(
                    'Send approval email',
                    style: AppTypography.titleSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Sent when an admin approves a pending user.',
                    style: AppTypography.bodySmall.copyWith(color: Colors.white60),
                  ),
                ),
                SwitchListTile(
                  value: _settingBool('send_rejection_email', fallback: true),
                  onChanged: (v) =>
                      _updateSetting('send_rejection_email', v ? 'true' : 'false'),
                  activeThumbColor: AppColors.brandPurple,
                  title: Text(
                    'Send rejection email',
                    style: AppTypography.titleSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Sent when an admin denies a pending user.',
                    style: AppTypography.bodySmall.copyWith(color: Colors.white60),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildSettingCard({required String title, required Widget child}) {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.elevatedCardDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }

  Widget _buildBulkCreditRequestsBar(int selectedCount) {
    final allSelected = _creditRequests.isNotEmpty &&
        _selectedCreditRequestIds.length == _creditRequests.length;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.elevatedCardDark),
      ),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: _bulkActionInProgress
                ? null
                : (v) {
                    setState(() {
                      _selectedCreditRequestIds
                        ..clear()
                        ..addAll(
                          v == true
                              ? _creditRequests
                                  .map((r) => (r['id'] as num?)?.toInt())
                                  .whereType<int>()
                              : const <int>[],
                        );
                    });
                  },
            activeColor: AppColors.brandPurple,
            checkColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              selectedCount == 0
                  ? '${_creditRequests.length} pending'
                  : '$selectedCount selected',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: selectedCount == 0 || _bulkActionInProgress
                ? null
                : _bulkApproveSelectedCreditRequests,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.successGreen.withValues(alpha: 0.5)),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: Text(
              'Approve',
              style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: selectedCount == 0 || _bulkActionInProgress
                ? null
                : _bulkDenySelectedCreditRequests,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.warningYellow.withValues(alpha: 0.55)),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.block_rounded, size: 18),
            label: Text(
              'Deny',
              style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(
            onPressed: selectedCount == 0 || _bulkActionInProgress
                ? null
                : () => setState(() => _selectedCreditRequestIds.clear()),
            child: Text(
              'Clear',
              style: AppTypography.labelLarge.copyWith(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreditRequestCard(Map<String, dynamic> request) {
    final requestId = (request['id'] as num?)?.toInt();
    final isSelected =
        requestId != null && _selectedCreditRequestIds.contains(requestId);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.elevatedCardDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildAvatar(request['username'] ?? 'U', AppColors.brandPurple),
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
              if (requestId != null)
                Checkbox(
                  value: isSelected,
                  onChanged: _bulkActionInProgress
                      ? null
                      : (v) {
                          setState(() {
                            if (v == true) {
                              _selectedCreditRequestIds.add(requestId);
                            } else {
                              _selectedCreditRequestIds.remove(requestId);
                            }
                          });
                        },
                  activeColor: AppColors.brandPurple,
                  checkColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.brandPurple.withValues(alpha: 0.12),
                  borderRadius: AppSpacing.borderRadiusRound,
                  border: Border.all(
                    color: AppColors.brandPurple.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  '+${request['amount_requested']} credits',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.brandPurple,
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
                color: AppColors.elevatedCardDark,
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
                  color: AppColors.successGreen,
                  onTap: () => _approveCreditRequest(request['id']),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _smallButton(
                  label: 'Deny',
                  color: AppColors.elevatedCardDark,
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
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.elevatedCardDark),
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
        color: AppColors.elevatedCardDark,
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
          color: AppColors.surfaceDark,
          borderRadius: AppSpacing.borderRadiusLg,
          border: Border.all(color: AppColors.elevatedCardDark),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_rounded, color: AppColors.dangerRed, size: 40),
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
                    color: AppColors.elevatedCardDark,
                    textColor: Colors.white,
                    onTap: () => Navigator.pop(context, false),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _smallButton(
                    label: 'Delete',
                    color: AppColors.dangerRed,
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
            color: AppColors.surfaceDark,
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(color: AppColors.elevatedCardDark),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_card, color: AppColors.successGreen, size: 32),
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
                  fillColor: AppColors.elevatedCardDark,
                  border: OutlineInputBorder(
                    borderRadius: AppSpacing.borderRadiusMd,
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon:
                      const Icon(Icons.monetization_on, color: AppColors.successGreen),
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
                  fillColor: AppColors.elevatedCardDark,
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
                      color: AppColors.elevatedCardDark,
                      textColor: Colors.white,
                      onTap: () => Navigator.pop(context, false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _smallButton(
                      label: 'Grant',
                      color: AppColors.successGreen,
                      onTap: () async {
                        final amount = int.tryParse(amountController.text);
                        if (amount == null || amount <= 0) {
                          _showSnackBar('Please enter a valid amount', AppColors.dangerRed);
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
                          _showSnackBar('Error granting credits: $e', AppColors.dangerRed);
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
      _showSnackBar('Credits granted successfully', AppColors.successGreen);
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
      ..color = AppColors.brandPurple.withValues(alpha: 0.05)
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
