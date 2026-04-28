import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/analytics_service.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_breakpoints.dart';
import '../widgets/brand_mark.dart';
import '../widgets/analytics_charts.dart';
import 'admin_jobs_screen.dart';

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

  // Activity / Audit state
  List<Map<String, dynamic>> _activityEvents = [];
  int _activityTotal = 0;
  int _activityOffset = 0;
  static const int _activityPageSize = 25;
  bool _activityLoading = false;
  List<String> _activityActions = [];
  List<String> _activityJobTypes = [];
  List<String> _activityStatuses = const [];
  String? _filterAction;
  String? _filterJobType;
  String? _filterStatus;
  String? _filterDateFrom;
  String? _filterDateTo;
  bool _activityInitialized = false;
  final TextEditingController _filterUserIdController = TextEditingController();

  // Analytics toggle state
  bool _showActivityAnalytics = false;
  bool _analyticsLoading = false;
  bool _analyticsInitialized = false;
  bool _analyticsError = false;
  List<Map<String, dynamic>> _dauData = [];
  List<Map<String, dynamic>> _featureData = [];
  List<Map<String, dynamic>> _funnelData = [];
  Map<String, dynamic> _sessionStats = {};

  // User KPIs cache
  final Map<int, Map<String, dynamic>> _userKpis = {};

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
    AnalyticsService.instance.page('#/admin');
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _filterUserIdController.dispose();
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
        // Identify the current admin user in the analytics tracker
        final uid = stats['current_user_id'] as int?;
        if (uid != null) AnalyticsService.instance.identify(uid);
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
    final state = user['account_state'] ?? user['approval_state'];
    if (state is String && state.trim().isNotEmpty) {
      return state.trim().toLowerCase();
    }
    if (user['is_suspended'] == true) return 'suspended';
    final isDenied = user['is_denied'] == true;
    if (isDenied) return 'denied';
    return user['is_approved'] == true ? 'approved' : 'pending';
  }

  Color _userStatusColor(String state) {
    switch (state) {
      case 'approved':
        return AppColors.successGreen;
      case 'denied':
        return AppColors.dangerRed;
      case 'suspended':
        return AppColors.brandOrange;
      default:
        return AppColors.warningYellow;
    }
  }

  String _userStatusLabel(String state, {bool preview = false}) {
    switch (state) {
      case 'approved':
        return preview ? 'Active' : 'Approved';
      case 'denied':
        return 'Denied';
      case 'suspended':
        return 'Suspended';
      default:
        return 'Pending';
    }
  }

  String? _suspensionReason(Map<String, dynamic> user) {
    final raw = user['suspension_reason'];
    if (raw == null) return null;
    final text = raw.toString().trim();
    return text.isEmpty ? null : text;
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
                style: AppTypography.labelLarge
                    .copyWith(fontWeight: FontWeight.w800),
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

  Future<void> _suspendUser(Map<String, dynamic> user) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape:
              RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusLg),
          title: Text(
            'Suspend user?',
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This immediately blocks login and API access. You can restore the account later or permanently delete it.',
                style: AppTypography.bodySmall.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: noteController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Optional suspension reason',
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
                backgroundColor: AppColors.brandOrange,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Suspend',
                style: AppTypography.labelLarge
                    .copyWith(fontWeight: FontWeight.w800),
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
      final reason = noteController.text.trim().isEmpty
          ? null
          : noteController.text.trim();
      await _apiService.suspendUser(user['id'], reason: reason);
      _loadData();
      _showSnackBar('User suspended', AppColors.brandOrange);
    } catch (e) {
      _showSnackBar('Error suspending user: $e', AppColors.dangerRed);
    } finally {
      noteController.dispose();
    }
  }

  Future<void> _unsuspendUser(int userId) async {
    try {
      await _apiService.unsuspendUser(userId);
      _loadData();
      _showSnackBar('User restored successfully', AppColors.successGreen);
    } catch (e) {
      _showSnackBar('Error restoring suspended user: $e', AppColors.dangerRed);
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

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildDeleteDialog(user),
    );

    if (confirmed == true) {
      try {
        await _apiService.deleteUser(user['id']);
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
                  style:
                      AppTypography.bodySmall.copyWith(color: Colors.white60),
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
                    style:
                        AppTypography.bodyMedium.copyWith(color: Colors.white),
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
          shape:
              RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusLg),
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
                style: AppTypography.labelLarge
                    .copyWith(fontWeight: FontWeight.w800),
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
      final note = noteController.text.trim().isEmpty
          ? null
          : noteController.text.trim();
      final result =
          await _apiService.bulkDenyCreditRequests(ids, adminNote: note);
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
              gradient: AppColors.primaryGradient,
              borderRadius: AppSpacing.borderRadiusMd,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.2),
                  blurRadius: 12,
                  spreadRadius: -6,
                ),
              ],
            ),
            child: const Center(
              child: BrandMark(
                tiled: false,
                size: 22,
                hoverGlow: true,
              ),
            ),
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
                Navigator.of(context).pushReplacementNamed('/home');
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
                      : _selectedTab == 3
                          ? _buildActivityView()
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
          Expanded(child: _buildTab(3, 'Activity', Icons.history_rounded)),
          Expanded(child: _buildTab(4, 'Settings', Icons.tune_rounded)),
        ],
      ),
    );
  }

  Widget _buildTab(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => _selectTab(index),
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
            Icon(icon,
                size: 18, color: isSelected ? Colors.white : Colors.white54),
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

  void _selectTab(int index) {
    if (_selectedTab == index) return;
    setState(() => _selectedTab = index);
    if (index == 3) {
      _ensureActivityLoaded();
      AnalyticsService.instance.feature(_tabLabel(index), context: 'admin');
    } else {
      AnalyticsService.instance.feature(_tabLabel(index), context: 'admin');
    }
  }

  String _tabLabel(int index) {
    const labels = ['Stats', 'Users', 'Credits', 'Activity', 'Settings'];
    return index < labels.length ? labels[index] : 'Unknown';
  }

  void _ensureActivityLoaded({bool force = false}) {
    if (_activityInitialized && !force) return;
    _activityInitialized = true;
    _loadActivityFeed(resetOffset: true);
    _loadActivityActions();
  }

  Future<void> _loadAnalytics() async {
    if (_analyticsLoading) return;
    setState(() {
      _analyticsLoading = true;
      _analyticsError = false;
    });
    try {
      final results = await Future.wait([
        _apiService.getAnalyticsDau(days: 30),
        _apiService.getAnalyticsFeatureAdoption(days: 30),
        _apiService.getAnalyticsFunnel(days: 90),
        _apiService.getAnalyticsSessionStats(days: 30),
      ]);
      if (mounted) {
        setState(() {
          _dauData = List<Map<String, dynamic>>.from(results[0]['data'] ?? []);
          _featureData =
              List<Map<String, dynamic>>.from(results[1]['data'] ?? []);
          _funnelData =
              List<Map<String, dynamic>>.from(results[2]['data'] ?? []);
          _sessionStats = Map<String, dynamic>.from(results[3]);
          _analyticsLoading = false;
          _analyticsInitialized = true;
          _analyticsError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _analyticsLoading = false;
          _analyticsError = true;
        });
      }
    }
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
            childAspectRatio:
                layoutType.index >= LayoutType.desktopSmall.index ? 1.5 : 1.15,
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
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AdminJobsScreen(),
                    ),
                  );
                },
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
                        ..._creditRequests.take(3).map(_buildCreditRequestCard),
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

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color accent, {
    VoidCallback? onTap,
  }) {
    final decoration = BoxDecoration(
      color: AppColors.surfaceDark,
      borderRadius: AppSpacing.borderRadiusLg,
      border: Border.all(color: AppColors.elevatedCardDark),
    );
    final content = Column(
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
    );

    if (onTap == null) {
      return Container(
        padding: AppSpacing.paddingMd,
        decoration: decoration,
        child: content,
      );
    }

    bool pressed = false;
    return StatefulBuilder(
      builder: (context, setInnerState) {
        return AnimatedScale(
          duration: AppSpacing.durationFast,
          curve: Curves.easeOut,
          scale: pressed ? 0.985 : 1,
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: decoration,
              child: InkWell(
                borderRadius: AppSpacing.borderRadiusLg,
                splashColor: accent.withValues(alpha: 0.2),
                highlightColor: accent.withValues(alpha: 0.1),
                onHighlightChanged: (isPressed) {
                  setInnerState(() => pressed = isPressed);
                },
                onTap: onTap,
                child: Padding(
                  padding: AppSpacing.paddingMd,
                  child: content,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildUserPreview(Map<String, dynamic> user) {
    final approvalState = _getApprovalState(user);
    final isApproved = approvalState == 'approved';
    final isPending = approvalState == 'pending';
    final isDenied = approvalState == 'denied';
    final isSuspended = approvalState == 'suspended';
    final phone = (user['phone'] ?? '').toString().trim();
    final suspensionReason = _suspensionReason(user);
    final statusColor = _userStatusColor(approvalState);
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
                    if (isSuspended && suspensionReason != null)
                      Text(
                        'Reason: $suspensionReason',
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
                  _userStatusLabel(approvalState, preview: true),
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
                      ? 'Suspend'
                      : (isSuspended || isDenied)
                          ? 'Restore'
                          : 'Deny',
                  color: isApproved
                      ? AppColors.brandOrange
                      : AppColors.elevatedCardDark,
                  textColor: Colors.white,
                  onTap: isApproved
                      ? () => _suspendUser(user)
                      : isSuspended
                          ? () => _unsuspendUser(user['id'])
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

    final pendingUsers = _users
        .where((u) => _getApprovalState(u) == 'pending')
        .toList(growable: false);

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
    final allSelected = pendingIds.isNotEmpty &&
        _selectedPendingUserIds.length == pendingIds.length;
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
              selectedCount == 0
                  ? '${pendingUsers.length} pending'
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
                : _bulkApproveSelectedUsers,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: AppColors.brandPurple.withValues(alpha: 0.5)),
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
              style: AppTypography.labelLarge
                  .copyWith(fontWeight: FontWeight.w800),
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
    final isSuspended = approvalState == 'suspended';
    final isAdmin = user['is_admin'] == true;
    final userId = (user['id'] as num?)?.toInt();
    final phone = (user['phone'] ?? '').toString().trim();
    final suspensionReason = _suspensionReason(user);
    final isSelected =
        isPending && userId != null && _selectedPendingUserIds.contains(userId);
    final statusColor = _userStatusColor(approvalState);

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
                              color:
                                  AppColors.brandPurple.withValues(alpha: 0.2),
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
                    if (isSuspended && suspensionReason != null)
                      Text(
                        'Reason: $suspensionReason',
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white54,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _pill(
                          _userStatusLabel(approvalState),
                          statusColor,
                        ),
                        if (isApproved || isSuspended) ...[
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
              if (isPending) ...[
                Expanded(
                  child: _smallButton(
                    label: 'Approve',
                    color: AppColors.brandPurple,
                    onTap: () => _approveUser(user['id']),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _smallButton(
                    label: 'Deny',
                    color: AppColors.elevatedCardDark,
                    textColor: Colors.white,
                    onTap: () => _denyUser(user['id']),
                  ),
                ),
              ] else if (isApproved) ...[
                Expanded(
                  child: _smallButton(
                    label: 'Suspend',
                    color: AppColors.brandOrange,
                    onTap: () => _suspendUser(user),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _smallButton(
                    label: 'Grant Credits',
                    color: AppColors.elevatedCardDark,
                    textColor: Colors.white,
                    onTap: () => _showGrantCreditsDialog(user),
                  ),
                ),
              ] else ...[
                Expanded(
                  child: _smallButton(
                    label: 'Delete',
                    color: AppColors.dangerRed,
                    onTap: () => _deleteUser(user),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _smallButton(
                    label: 'Restore',
                    color: AppColors.brandPurple,
                    onTap: () => isSuspended
                        ? _unsuspendUser(user['id'])
                        : _restoreUser(user['id']),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _smallButton(
                  label: 'Manage Profile',
                  color: AppColors.elevatedCardDark,
                  textColor: Colors.white,
                  onTap: () => _showManageUserDialog(user),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _smallButton(
                  label: 'Timeline',
                  color: AppColors.elevatedCardDark,
                  textColor: AppColors.brandPurple,
                  onTap: () =>
                      _showUserTimeline(user['id'], user['username'] ?? 'User'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _smallButton(
                  label: 'KPIs',
                  color: AppColors.elevatedCardDark,
                  textColor: AppColors.infoBlue,
                  onTap: () =>
                      _showUserKpis(user['id'], user['username'] ?? 'User'),
                ),
              ),
            ],
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
          if (_creditRequests.isNotEmpty)
            _buildBulkCreditRequestsBar(selectedCount),
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
                  onChanged: (v) => _updateSetting(
                      'auto_approve_users', v ? 'true' : 'false'),
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
                    style:
                        AppTypography.bodySmall.copyWith(color: Colors.white60),
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
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: AppSpacing.borderRadiusMd,
                            borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08)),
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
                  value: _settingBool('admin_notification_on_signup',
                      fallback: true),
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
                    style:
                        AppTypography.bodySmall.copyWith(color: Colors.white60),
                  ),
                ),
                SwitchListTile(
                  value: _settingBool('send_welcome_email', fallback: true),
                  onChanged: (v) => _updateSetting(
                      'send_welcome_email', v ? 'true' : 'false'),
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
                    style:
                        AppTypography.bodySmall.copyWith(color: Colors.white60),
                  ),
                ),
                SwitchListTile(
                  value: _settingBool('send_approval_email', fallback: true),
                  onChanged: (v) => _updateSetting(
                      'send_approval_email', v ? 'true' : 'false'),
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
                    style:
                        AppTypography.bodySmall.copyWith(color: Colors.white60),
                  ),
                ),
                SwitchListTile(
                  value: _settingBool('send_rejection_email', fallback: true),
                  onChanged: (v) => _updateSetting(
                      'send_rejection_email', v ? 'true' : 'false'),
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
                    style:
                        AppTypography.bodySmall.copyWith(color: Colors.white60),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _buildSettingCard(
            title: 'Payment Features',
            child: Column(
              children: [
                SwitchListTile(
                  value: _settingBool('enable_live_payments', fallback: false),
                  onChanged: (v) => _updateSetting(
                      'enable_live_payments', v ? 'true' : 'false'),
                  activeThumbColor: AppColors.successGreen,
                  title: Text(
                    'Live Payment Methods',
                    style: AppTypography.titleSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    'Enable or disable live payment experiences for users.',
                    style:
                        AppTypography.bodySmall.copyWith(color: Colors.white60),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: AppSpacing.paddingSm,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: AppSpacing.borderRadiusMd,
                    border: Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _settingBool('enable_live_payments', fallback: false)
                            ? Icons.check_circle_outline_rounded
                            : Icons.info_outline_rounded,
                        color: _settingBool('enable_live_payments',
                                fallback: false)
                            ? AppColors.successGreen
                            : AppColors.warningYellow,
                        size: 18,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _settingBool('enable_live_payments', fallback: false)
                              ? 'Users can access payment methods and invoices.'
                              : 'Users see Payments Coming Soon and can request credits from admins.',
                          style: AppTypography.bodySmall.copyWith(
                            color: Colors.white70,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: AppSpacing.paddingSm,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withValues(alpha: 0.10),
                    borderRadius: AppSpacing.borderRadiusMd,
                    border: Border.all(
                      color: AppColors.primaryBlue.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline_rounded,
                          color: AppColors.primaryBlue, size: 18),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Tip: When disabled, wallet loads faster and users are guided to request credits.',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.primaryBlue,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
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
              side: BorderSide(
                  color: AppColors.successGreen.withValues(alpha: 0.5)),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.done_all_rounded, size: 18),
            label: Text(
              'Approve',
              style: AppTypography.labelLarge
                  .copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: selectedCount == 0 || _bulkActionInProgress
                ? null
                : _bulkDenySelectedCreditRequests,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: AppColors.warningYellow.withValues(alpha: 0.55)),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.block_rounded, size: 18),
            label: Text('Deny',
                style: AppTypography.labelLarge
                    .copyWith(fontWeight: FontWeight.w800)),
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

  // ==================== ACTIVITY LOG ====================

  Future<void> _loadActivityFeed({bool resetOffset = false}) async {
    if (_activityLoading) return;
    if (resetOffset) _activityOffset = 0;
    setState(() => _activityLoading = true);
    try {
      final userIdText = _filterUserIdController.text.trim();
      final userId = userIdText.isNotEmpty ? int.tryParse(userIdText) : null;
      final data = await _apiService.getAdminJobActivity(
        userId: userId,
        eventType: _filterAction,
        jobType: _filterJobType,
        jobStatus: _filterStatus,
        dateFrom: _filterDateFrom,
        dateTo: _filterDateTo,
        limit: _activityPageSize,
        offset: _activityOffset,
      );
      if (mounted) {
        setState(() {
          _activityEvents =
              List<Map<String, dynamic>>.from(data['events'] ?? []);
          _activityTotal =
              (data['total'] as num?)?.toInt() ?? _activityEvents.length;
          _activityLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _activityLoading = false);
        _showSnackBar('Failed to load activity: $e', AppColors.dangerRed);
      }
    }
  }

  Future<void> _loadActivityActions() async {
    try {
      final data = await _apiService.getAdminJobActivityFilters();
      if (mounted) {
        setState(() {
          _activityActions =
              List<String>.from(data['event_types'] ?? const <String>[]);
          _activityJobTypes =
              List<String>.from(data['job_types'] ?? const <String>[]);
          _activityStatuses =
              List<String>.from(data['job_statuses'] ?? const <String>[]);
        });
      }
    } catch (_) {}
  }

  Future<void> _exportCSV() async {
    if (!kIsWeb) {
      _showSnackBar(
          'CSV export available on web version only', AppColors.warningYellow);
      return;
    }

    _showSnackBar(
        'CSV export feature is available on web platform', AppColors.infoBlue);
  }

  Future<void> _downloadCSVWeb(List<int> bytes) async {
    // Web-only download - not implemented for mobile
    return;
  }

  Future<void> _showUserTimeline(int userId, String username) async {
    showDialog(
      context: context,
      builder: (ctx) => _UserTimelineDialog(
        apiService: _apiService,
        userId: userId,
        username: username,
      ),
    );
  }

  Future<void> _showUserKpis(int userId, String username) async {
    showDialog(
      context: context,
      builder: (ctx) => _UserKpisDialog(
        apiService: _apiService,
        userId: userId,
        username: username,
      ),
    );
  }

  Future<void> _openJobActivityDetails(Map<String, dynamic> event) async {
    final width = MediaQuery.of(context).size.width;
    final useSlideOver = width >= 980;

    if (useSlideOver) {
      await showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Close',
        barrierColor: Colors.black.withValues(alpha: 0.55),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, _, __) {
          return Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: ((width > 1600 ? 1600 : width) * 0.56).toDouble(),
                constraints: const BoxConstraints(maxWidth: 780, minWidth: 420),
                height: double.infinity,
                color: AppColors.surfaceDark,
                child: _JobActivityDetailsPanel(
                  apiService: _apiService,
                  event: event,
                  onClose: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, _, child) {
          final tween =
              Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero);
          return SlideTransition(
            position: tween.animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          );
        },
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final height = MediaQuery.of(ctx).size.height * 0.92;
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(18),
            ),
            border: Border.all(color: AppColors.elevatedCardDark),
          ),
          child: _JobActivityDetailsPanel(
            apiService: _apiService,
            event: event,
            onClose: () => Navigator.of(ctx).pop(),
          ),
        );
      },
    );
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2024),
      lastDate: now,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(primary: AppColors.brandPurple),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final formatted =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        if (isFrom) {
          _filterDateFrom = formatted;
        } else {
          _filterDateTo = formatted;
        }
      });
    }
  }

  Widget _buildActivityView() {
    final currentPage = (_activityOffset ~/ _activityPageSize) + 1;
    final totalPages =
        (_activityTotal / _activityPageSize).ceil().clamp(1, 9999);

    return Column(
      children: [
        // ── Log / Analytics toggle ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
          child: Row(
            children: [
              _ActivityToggleButton(
                label: 'Activity Log',
                icon: Icons.history_rounded,
                selected: !_showActivityAnalytics,
                onTap: () => setState(() => _showActivityAnalytics = false),
              ),
              const SizedBox(width: AppSpacing.xs),
              _ActivityToggleButton(
                label: 'Analytics',
                icon: Icons.bar_chart_rounded,
                selected: _showActivityAnalytics,
                onTap: () {
                  setState(() => _showActivityAnalytics = true);
                  if (!_analyticsInitialized) _loadAnalytics();
                },
              ),
              if (_showActivityAnalytics && _analyticsLoading) ...[
                const SizedBox(width: AppSpacing.sm),
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brandPurple,
                  ),
                ),
              ],
              const Spacer(),
              if (_showActivityAnalytics)
                GestureDetector(
                  onTap: () {
                    setState(() => _analyticsInitialized = false);
                    _loadAnalytics();
                  },
                  child: const Icon(Icons.refresh_rounded,
                      size: 18, color: Colors.white38),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── Conditional body ────────────────────────────────────────────────
        if (_showActivityAnalytics)
          Expanded(child: _buildAnalyticsView())
        else ...[
          // Filters
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: AppSpacing.borderRadiusLg,
              border: Border.all(color: AppColors.elevatedCardDark),
            ),
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _filterUserIdController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'User ID',
                      hintStyle:
                          const TextStyle(color: Colors.white38, fontSize: 13),
                      filled: true,
                      fillColor: AppColors.elevatedCardDark,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
                      border: OutlineInputBorder(
                        borderRadius: AppSpacing.borderRadiusSm,
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                _buildFilterDropdown(
                  value: _filterAction,
                  hint: 'All Events',
                  items: _activityActions,
                  onChanged: (v) => setState(() => _filterAction = v),
                  width: 160,
                ),
                _buildFilterDropdown(
                  value: _filterJobType,
                  hint: 'All Job Types',
                  items: _activityJobTypes,
                  onChanged: (v) => setState(() => _filterJobType = v),
                  width: 170,
                ),
                _buildFilterDropdown(
                  value: _filterStatus,
                  hint: 'All Statuses',
                  items: _activityStatuses,
                  onChanged: (v) => setState(() => _filterStatus = v),
                  width: 150,
                ),
                _buildDateChip('From', _filterDateFrom, () => _pickDate(true),
                    () => setState(() => _filterDateFrom = null)),
                _buildDateChip('To', _filterDateTo, () => _pickDate(false),
                    () => setState(() => _filterDateTo = null)),
                _smallButton(
                  label: 'Filter',
                  color: AppColors.brandPurple,
                  onTap: () => _loadActivityFeed(resetOffset: true),
                ),
                _smallButton(
                  label: 'Export CSV',
                  color: AppColors.elevatedCardDark,
                  textColor: Colors.white,
                  onTap: _exportCSV,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Table
          Expanded(
            child: _activityLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.brandPurple),
                    ),
                  )
                : _activityEvents.isEmpty
                    ? Center(
                        child: Text(
                          'No activity events found',
                          style: AppTypography.bodyMedium
                              .copyWith(color: Colors.white60),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md),
                        itemCount: _activityEvents.length,
                        itemBuilder: (context, index) {
                          final e = _activityEvents[index];
                          return _buildActivityRow(e);
                        },
                      ),
          ),
          // Pagination
          Container(
            padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.sm, horizontal: AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _activityOffset > 0
                      ? () {
                          _activityOffset =
                              (_activityOffset - _activityPageSize)
                                  .clamp(0, _activityTotal);
                          _loadActivityFeed();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left, color: Colors.white70),
                ),
                Text(
                  'Page $currentPage of $totalPages',
                  style:
                      AppTypography.labelSmall.copyWith(color: Colors.white54),
                ),
                IconButton(
                  onPressed:
                      _activityOffset + _activityPageSize < _activityTotal
                          ? () {
                              _activityOffset += _activityPageSize;
                              _loadActivityFeed();
                            }
                          : null,
                  icon: const Icon(Icons.chevron_right, color: Colors.white70),
                ),
              ],
            ),
          ),
        ], // end else (activity log branch)
      ],
    );
  }

  Widget _buildAnalyticsView() {
    if (_analyticsLoading && !_analyticsInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandPurple),
      );
    }
    if (_analyticsError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 36),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Failed to load analytics',
              style: AppTypography.bodyMedium.copyWith(color: Colors.white60),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton.icon(
              onPressed: () {
                setState(() => _analyticsError = false);
                _loadAnalytics();
              },
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style:
                  TextButton.styleFrom(foregroundColor: AppColors.brandPurple),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SessionStatsRow(data: _sessionStats),
          const SizedBox(height: AppSpacing.md),
          DauLineChart(data: _dauData, days: 30),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FeatureAdoptionChart(data: _featureData, days: 30),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ConversionFunnelChart(data: _funnelData, days: 90),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  Widget _buildActivityRow(Map<String, dynamic> e) {
    final status = (e['job_status'] ?? '').toString().toLowerCase();
    final eventType = (e['event_type'] ?? '').toString();
    final jobType = (e['job_type'] ?? '').toString();
    final jobId = (e['job_id'] ?? '').toString();
    final username = (e['username'] ?? '').toString();
    final resultCount = (e['result_count'] as num?)?.toInt() ??
        int.tryParse('${e['result_count'] ?? 0}') ??
        0;

    Color statusColor;
    String statusText;
    switch (status) {
      case 'completed':
        statusColor = AppColors.successGreen;
        statusText = 'COMPLETED';
        break;
      case 'failed':
        statusColor = AppColors.dangerRed;
        statusText = 'FAILED';
        break;
      case 'cancelled':
        statusColor = AppColors.warningYellow;
        statusText = 'CANCELLED';
        break;
      case 'running':
        statusColor = AppColors.infoBlue;
        statusText = 'RUNNING';
        break;
      default:
        statusColor = Colors.white54;
        statusText = status.isEmpty ? 'PENDING' : status.toUpperCase();
        break;
    }

    final createdAt = e['created_at'] ?? '';
    String timeStr = '';
    try {
      final dt = DateTime.parse(createdAt);
      timeStr =
          '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      timeStr = createdAt;
    }

    return InkWell(
      onTap: () => _openJobActivityDetails(e),
      borderRadius: AppSpacing.borderRadiusSm,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: AppSpacing.borderRadiusSm,
          border: Border.all(color: AppColors.elevatedCardDark),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Text(
                timeStr,
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
            ),
            SizedBox(
              width: 88,
              child: Text(
                username.isEmpty ? '#${e['user_id'] ?? '?'}' : username,
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                eventType,
                style: AppTypography.labelSmall.copyWith(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 110,
              child: Text(
                jobType,
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white60,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 92,
              child: Text(
                jobId,
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white38,
                  fontSize: 10,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            SizedBox(
              width: 48,
              child: Text(
                '$resultCount',
                textAlign: TextAlign.center,
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              width: 94,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxs, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: AppSpacing.borderRadiusSm,
              ),
              child: Text(
                statusText,
                style: AppTypography.labelSmall.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    double width = 150,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.elevatedCardDark,
        borderRadius: AppSpacing.borderRadiusSm,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: value,
          hint: Text(hint,
              style: const TextStyle(color: Colors.white38, fontSize: 13)),
          dropdownColor: AppColors.surfaceDark,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text(hint,
                  style: const TextStyle(color: Colors.white38, fontSize: 13)),
            ),
            ...items.map((a) => DropdownMenuItem(
                  value: a,
                  child: Text(a, overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDateChip(
      String label, String? value, VoidCallback onTap, VoidCallback onClear) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs, vertical: AppSpacing.xxs + 2),
        decoration: BoxDecoration(
          color: AppColors.elevatedCardDark,
          borderRadius: AppSpacing.borderRadiusSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value ?? label,
              style: TextStyle(
                color: value != null ? Colors.white : Colors.white38,
                fontSize: 13,
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 14, color: Colors.white54),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteDialog(Map<String, dynamic> user) {
    final username = (user['username'] ?? 'this user').toString();
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
              'Permanently delete $username and all related data? This cannot be undone.',
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
    bool isGranting = false;

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
                Icon(Icons.add_card, color: AppColors.successGreen, size: 32),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Grant Credits',
                  style:
                      AppTypography.titleMedium.copyWith(color: Colors.white),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'to ${user['username']}',
                  style:
                      AppTypography.bodySmall.copyWith(color: Colors.white60),
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
                    prefixIcon: const Icon(Icons.monetization_on,
                        color: AppColors.successGreen),
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
                    prefixIcon: const Icon(Icons.note, color: Colors.white54),
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
                        onTap: isGranting
                            ? () {}
                            : () => Navigator.pop(context, false),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _smallButton(
                        label: isGranting ? 'Granting...' : 'Grant',
                        color: isGranting
                            ? AppColors.successGreen.withValues(alpha: 0.5)
                            : AppColors.successGreen,
                        onTap: isGranting
                            ? () {}
                            : () async {
                                final amount =
                                    int.tryParse(amountController.text);
                                if (amount == null || amount <= 0) {
                                  _showSnackBar('Please enter a valid amount',
                                      AppColors.dangerRed);
                                  return;
                                }
                                setDialogState(() => isGranting = true);
                                try {
                                  await _apiService.grantCredits(
                                    userId: user['id'],
                                    amount: amount,
                                    reason: reasonController.text.isEmpty
                                        ? null
                                        : reasonController.text,
                                  );
                                  if (context.mounted)
                                    Navigator.pop(context, true);
                                } catch (e) {
                                  if (context.mounted) {
                                    setDialogState(() => isGranting = false);
                                    _showSnackBar('Error granting credits: $e',
                                        AppColors.dangerRed);
                                  }
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

// ─── Analytics toggle button ──────────────────────────────────────────────────
class _ActivityToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ActivityToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppSpacing.durationFast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandPurple : AppColors.elevatedCardDark,
          borderRadius: AppSpacing.borderRadiusMd,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 14, color: selected ? Colors.white : Colors.white54),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: selected ? Colors.white : Colors.white54,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobActivityDetailsPanel extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> event;
  final VoidCallback onClose;

  const _JobActivityDetailsPanel({
    required this.apiService,
    required this.event,
    required this.onClose,
  });

  @override
  State<_JobActivityDetailsPanel> createState() =>
      _JobActivityDetailsPanelState();
}

class _JobActivityDetailsPanelState extends State<_JobActivityDetailsPanel> {
  static const int _pageSize = 25;
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _results = [];
  int _total = 0;
  int _offset = 0;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadResults(resetOffset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _jobId => (widget.event['job_id'] ?? '').toString();
  String get _jobType =>
      (widget.event['job_type'] ?? widget.event['category'] ?? '').toString();
  String get _eventType => (widget.event['event_type'] ?? '').toString();
  String get _status => (widget.event['job_status'] ?? '').toString();
  String get _createdAt => (widget.event['created_at'] ?? '').toString();
  int get _resultCount =>
      (widget.event['result_count'] as num?)?.toInt() ??
      int.tryParse('${widget.event['result_count'] ?? 0}') ??
      0;

  Future<void> _loadResults({bool resetOffset = false}) async {
    final jobId = _jobId;
    if (jobId.isEmpty) {
      setState(() {
        _loading = false;
        _results = const [];
        _total = 0;
        _error = 'Missing job id';
      });
      return;
    }

    if (resetOffset) _offset = 0;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await widget.apiService.getJobResultsAdmin(
        jobId,
        limit: _pageSize,
        offset: _offset,
        search: _search,
      );
      if (!mounted) return;
      setState(() {
        _results = List<Map<String, dynamic>>.from(data['results'] ?? const []);
        _total = (data['total'] as num?)?.toInt() ?? _results.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load job results: $e';
      });
    }
  }

  String _formatTimestamp(String value) {
    if (value.isEmpty) return '-';
    try {
      final dt = DateTime.parse(value);
      return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return value;
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return AppColors.successGreen;
      case 'failed':
        return AppColors.dangerRed;
      case 'cancelled':
        return AppColors.warningYellow;
      case 'running':
        return AppColors.infoBlue;
      default:
        return Colors.white70;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(_status);
    final currentPage = (_offset ~/ _pageSize) + 1;
    final totalPages = (_total / _pageSize).ceil().clamp(1, 9999);

    return SafeArea(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              border: Border(
                bottom: BorderSide(color: AppColors.elevatedCardDark),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Job Activity Details',
                        style: AppTypography.titleMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close, color: Colors.white54),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    _metaChip('Job', _jobId, Colors.white70),
                    _metaChip('Type', _jobType, Colors.white70),
                    _metaChip('Event', _eventType, AppColors.brandPurple),
                    _metaChip('Status', _status.toUpperCase(), statusColor),
                    _metaChip('Leads', '$_resultCount', AppColors.infoBlue),
                    _metaChip(
                        'At', _formatTimestamp(_createdAt), Colors.white70),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText:
                              'Search leads by business, city, phone, email...',
                          hintStyle: const TextStyle(
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: AppColors.elevatedCardDark,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: AppSpacing.borderRadiusSm,
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (value) {
                          _search = value.trim();
                          _loadResults(resetOffset: true);
                        },
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _panelButton(
                      label: 'Search',
                      onTap: () {
                        _search = _searchController.text.trim();
                        _loadResults(resetOffset: true);
                      },
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _panelButton(
                      label: 'Refresh',
                      color: AppColors.elevatedCardDark,
                      onTap: () => _loadResults(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.brandPurple,
                      ),
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            _error!,
                            style: AppTypography.bodyMedium
                                .copyWith(color: AppColors.dangerRed),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              child: Text(
                                'No results found for this job.',
                                style: AppTypography.bodyMedium
                                    .copyWith(color: Colors.white60),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final r = _results[index];
                              return Container(
                                margin: const EdgeInsets.only(
                                  bottom: AppSpacing.xs,
                                ),
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color: AppColors.elevatedCardDark,
                                  borderRadius: AppSpacing.borderRadiusSm,
                                  border:
                                      Border.all(color: AppColors.surfaceDark),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (r['business_name'] ?? 'Unknown')
                                          .toString(),
                                      style: AppTypography.labelLarge.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${r['city'] ?? '-'}, ${r['state'] ?? '-'}',
                                      style: AppTypography.labelSmall
                                          .copyWith(color: Colors.white60),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Phone: ${r['phone'] ?? '-'}   Email: ${r['email'] ?? '-'}',
                                      style: AppTypography.labelSmall
                                          .copyWith(color: Colors.white70),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      'Website: ${r['website'] ?? '-'}',
                                      style: AppTypography.labelSmall
                                          .copyWith(color: Colors.white70),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              border: Border(
                top: BorderSide(color: AppColors.elevatedCardDark),
              ),
            ),
            child: Row(
              children: [
                Text(
                  'Page $currentPage / $totalPages',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white60,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _panelButton(
                  label: 'Prev',
                  color: AppColors.elevatedCardDark,
                  onTap: _offset > 0
                      ? () {
                          _offset =
                              ((_offset - _pageSize).clamp(0, _total) as num)
                                  .toInt();
                          _loadResults();
                        }
                      : null,
                ),
                const SizedBox(width: AppSpacing.xs),
                _panelButton(
                  label: 'Next',
                  color: AppColors.elevatedCardDark,
                  onTap: _offset + _pageSize < _total
                      ? () {
                          _offset += _pageSize;
                          _loadResults();
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Text(
        '$label: $value',
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _panelButton({
    required String label,
    required VoidCallback? onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppSpacing.borderRadiusSm,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: color ?? AppColors.brandPurple,
          borderRadius: AppSpacing.borderRadiusSm,
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ==================== USER TIMELINE DIALOG ====================

class _UserTimelineDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String username;

  const _UserTimelineDialog({
    required this.apiService,
    required this.userId,
    required this.username,
  });

  @override
  State<_UserTimelineDialog> createState() => _UserTimelineDialogState();
}

class _UserTimelineDialogState extends State<_UserTimelineDialog> {
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.apiService.getUserTimeline(widget.userId);
      if (mounted) {
        setState(() {
          _events = List<Map<String, dynamic>>.from(data['events'] ?? []);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 560,
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: AppSpacing.borderRadiusLg,
          border: Border.all(color: AppColors.elevatedCardDark),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, color: AppColors.brandPurple, size: 22),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Timeline: ${widget.username}',
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon:
                      const Icon(Icons.close, color: Colors.white54, size: 20),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.brandPurple),
                ),
              )
            else if (_events.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'No activity found for this user.',
                  style:
                      AppTypography.bodyMedium.copyWith(color: Colors.white60),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _events.length,
                  itemBuilder: (context, i) {
                    final e = _events[i];
                    final isSuccess = e['status'] == 'success';
                    final statusColor = isSuccess
                        ? AppColors.successGreen
                        : AppColors.dangerRed;
                    String timeStr = '';
                    try {
                      final dt = DateTime.parse(e['created_at'] ?? '');
                      timeStr =
                          '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                    } catch (_) {
                      timeStr = e['created_at'] ?? '';
                    }
                    return Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.elevatedCardDark,
                        borderRadius: AppSpacing.borderRadiusSm,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e['action'] ?? '',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${e['target_type'] ?? ''}${e['target_id'] != null ? ' #${e['target_id']}' : ''} - $timeStr',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: AppSpacing.borderRadiusSm,
                            ),
                            child: Text(
                              isSuccess ? 'OK' : 'FAIL',
                              style: AppTypography.labelSmall.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== USER KPIs DIALOG ====================

class _UserKpisDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String username;

  const _UserKpisDialog({
    required this.apiService,
    required this.userId,
    required this.username,
  });

  @override
  State<_UserKpisDialog> createState() => _UserKpisDialogState();
}

class _UserKpisDialogState extends State<_UserKpisDialog> {
  Map<String, dynamic>? _kpis;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.apiService.getUserKpis(widget.userId);
      if (mounted) {
        setState(() {
          _kpis = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 420,
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: AppSpacing.borderRadiusLg,
          border: Border.all(color: AppColors.elevatedCardDark),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.insights, color: AppColors.brandPurple, size: 22),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'KPIs: ${widget.username}',
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon:
                      const Icon(Icons.close, color: Colors.white54, size: 20),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.brandPurple),
                ),
              )
            else if (_kpis == null)
              Text('Failed to load KPIs',
                  style:
                      AppTypography.bodyMedium.copyWith(color: Colors.white60))
            else ...[
              _kpiRow('Jobs Run', '${_kpis!['jobs_run'] ?? 0}', Icons.work,
                  AppColors.blue),
              _kpiRow(
                  'Results Generated',
                  '${_kpis!['results_generated'] ?? 0}',
                  Icons.checklist,
                  AppColors.successGreen),
              _kpiRow('Credits Used', '${_kpis!['credits_used'] ?? 0}',
                  Icons.payments, AppColors.warningYellow),
              _kpiRow(
                  'Credits Purchased',
                  '${_kpis!['credits_purchased'] ?? 0}',
                  Icons.add_card,
                  AppColors.brandPurple),
              _kpiRow(
                  'Cost / Result',
                  _kpis!['cost_per_result'] != null
                      ? (_kpis!['cost_per_result'] as num).toStringAsFixed(1)
                      : '-',
                  Icons.trending_down,
                  AppColors.brandOrange),
              _kpiRow('Last Activity', _formatKpiDate(_kpis!['last_activity']),
                  Icons.access_time, Colors.white54),
              _kpiRow('Last Login', _formatKpiDate(_kpis!['last_login']),
                  Icons.login, Colors.white54),
            ],
          ],
        ),
      ),
    );
  }

  String _formatKpiDate(dynamic val) {
    if (val == null) return 'Never';
    try {
      final dt = DateTime.parse(val.toString());
      return '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return val.toString();
    }
  }

  Widget _kpiRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppSpacing.borderRadiusSm,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(color: Colors.white70),
            ),
          ),
          Text(
            value,
            style: AppTypography.titleSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
