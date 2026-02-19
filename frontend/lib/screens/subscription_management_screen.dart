import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../services/api_service.dart';
import '../widgets/subscription_status_banner.dart';
import 'pricing_screen.dart';

class SubscriptionManagementScreen extends StatefulWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  State<SubscriptionManagementScreen> createState() =>
      _SubscriptionManagementScreenState();
}

class _SubscriptionManagementScreenState
    extends State<SubscriptionManagementScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _subscription;
  bool _isActioning = false;

  @override
  void initState() {
    super.initState();
    _loadSubscription();
  }

  Future<void> _loadSubscription() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _apiService.getMySubscription();
      if (mounted) {
        setState(() {
          _subscription = result.isEmpty ? null : result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load subscription: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _cancelSubscription({bool immediate = false}) async {
    final id = _subscription?['id'];
    if (id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusLg,
        ),
        title: Text(
          immediate ? 'Cancel Immediately?' : 'Cancel Subscription?',
          style: AppTypography.titleLarge.copyWith(color: Colors.white),
        ),
        content: Text(
          immediate
              ? 'Your subscription will end immediately. Unused credits this period will be lost.'
              : 'Your subscription will remain active until the end of the current billing period.',
          style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Keep Subscription',
              style: AppTypography.labelLarge.copyWith(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Cancel',
              style: AppTypography.labelLarge.copyWith(color: AppColors.dangerRed),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isActioning = true);
    try {
      await _apiService.cancelSubscription(id, immediate: immediate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscription cancelled.')),
        );
        _loadSubscription();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  Future<void> _pauseSubscription() async {
    final id = _subscription?['id'];
    if (id == null) return;

    setState(() => _isActioning = true);
    try {
      await _apiService.pauseSubscription(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscription paused.')),
        );
        _loadSubscription();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pause: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  Future<void> _resumeSubscription() async {
    final id = _subscription?['id'];
    if (id == null) return;

    setState(() => _isActioning = true);
    try {
      await _apiService.resumeSubscription(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscription resumed.')),
        );
        _loadSubscription();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resume: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SubColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            _buildBackground(),
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _SubColors.primary,
                            ),
                          ),
                        )
                      : _error != null
                          ? _buildError()
                          : RefreshIndicator(
                              onRefresh: _loadSubscription,
                              child: SingleChildScrollView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.all(AppSpacing.md),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    SubscriptionStatusBanner(
                                      subscription: _subscription,
                                      onUpgrade: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                const PricingScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                    if (_subscription != null) ...[
                                      const SizedBox(height: AppSpacing.lg),
                                      _buildDetails(),
                                      const SizedBox(height: AppSpacing.lg),
                                      _buildActions(),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              _SubColors.primary.withValues(alpha: 0.15),
              Colors.transparent,
            ],
            radius: 1.5,
            center: const Alignment(0, -1.5),
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
        color: _SubColors.background.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          Expanded(
            child: Text(
              'Subscription',
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: AppColors.dangerRed, size: 48),
          const SizedBox(height: AppSpacing.md),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: _loadSubscription,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: AppSpacing.borderRadiusMd,
              ),
              child: Text(
                'Retry',
                style: AppTypography.labelLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails() {
    final status = _subscription?['status'] ?? '';
    final planName = _subscription?['plan_name'] ?? '';
    final interval = _subscription?['billing_interval'] ?? '';
    final periodStart = _subscription?['current_period_start'] ?? '';
    final periodEnd = _subscription?['current_period_end'] ?? '';
    final nextBilling = _subscription?['next_billing_date'] ?? '';
    final creditsUsed = _subscription?['credits_used_this_period'] ?? 0;
    final creditsAllocated =
        _subscription?['credits_allocated_this_period'] ?? 0;
    final rolledOver = _subscription?['credits_rolled_over'] ?? 0;
    final cancelAtEnd = _subscription?['cancel_at_period_end'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline, color: _SubColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Subscription Details',
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
            color: _SubColors.surface.withValues(alpha: 0.4),
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              _infoRow('Plan', planName),
              _infoRow('Billing', interval),
              _infoRow('Status', cancelAtEnd ? 'Cancelling at period end' : status),
              if (periodStart.isNotEmpty) _infoRow('Period Start', periodStart),
              if (periodEnd.isNotEmpty) _infoRow('Period End', periodEnd),
              if (nextBilling.isNotEmpty && !cancelAtEnd)
                _infoRow('Next Billing', nextBilling),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Divider(color: Colors.white12),
              ),
              _infoRow('Credits Used', '$creditsUsed / $creditsAllocated'),
              if (rolledOver > 0)
                _infoRow('Rolled Over', '$rolledOver credits'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.bodyMedium.copyWith(color: Colors.white54),
          ),
          Flexible(
            child: Text(
              value,
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    final status = _subscription?['status'] ?? '';
    final cancelAtEnd = _subscription?['cancel_at_period_end'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tune, color: _SubColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Actions',
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (status == 'active' && !cancelAtEnd) ...[
          _actionButton(
            icon: Icons.swap_horiz,
            label: 'Change Plan',
            subtitle: 'Upgrade or downgrade',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const PricingScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          _actionButton(
            icon: Icons.pause_circle_outline,
            label: 'Pause Subscription',
            subtitle: 'Temporarily pause billing',
            onTap: _isActioning ? null : _pauseSubscription,
          ),
          const SizedBox(height: AppSpacing.sm),
          _actionButton(
            icon: Icons.cancel_rounded,
            label: 'Cancel at Period End',
            subtitle: 'Keep access until billing period ends',
            color: const Color(0xFFF59E0B),
            onTap: _isActioning ? null : () => _cancelSubscription(),
          ),
          const SizedBox(height: AppSpacing.sm),
          _actionButton(
            icon: Icons.close,
            label: 'Cancel Immediately',
            subtitle: 'End subscription now',
            color: AppColors.dangerRed,
            onTap:
                _isActioning ? null : () => _cancelSubscription(immediate: true),
          ),
        ] else if (status == 'paused') ...[
          _actionButton(
            icon: Icons.play_circle_outline,
            label: 'Resume Subscription',
            subtitle: 'Continue your subscription',
            color: AppColors.success,
            onTap: _isActioning ? null : _resumeSubscription,
          ),
        ] else if (cancelAtEnd) ...[
          Container(
            padding: AppSpacing.paddingMd,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
              borderRadius: AppSpacing.borderRadiusLg,
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: Color(0xFFF59E0B), size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Your subscription will end at the current billing period.',
                    style: AppTypography.bodySmall.copyWith(
                      color: const Color(0xFFF59E0B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_isActioning) ...[
          const SizedBox(height: AppSpacing.md),
          const Center(
            child: CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation<Color>(_SubColors.primary),
            ),
          ),
        ],
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    Color? color,
    VoidCallback? onTap,
  }) {
    final c = color ?? _SubColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: AppSpacing.paddingMd,
        decoration: BoxDecoration(
          color: _SubColors.surface.withValues(alpha: 0.3),
          borderRadius: AppSpacing.borderRadiusLg,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.15),
                borderRadius: AppSpacing.borderRadiusSm,
              ),
              child: Icon(icon, color: c, size: 20),
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
                  Text(
                    subtitle,
                    style: AppTypography.bodySmall.copyWith(
                      color: Colors.white54,
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
}

class _SubColors {
  static const Color primary = AppColors.primaryBlue;
  static const Color background = AppColors.backgroundDark;
  static const Color surface = AppColors.elevatedCardDark;
}
