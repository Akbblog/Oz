import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/app_breakpoints.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/responsive_utils.dart';
import '../services/api_service.dart';
import '../widgets/gradient_button.dart';

class WalletComingSoonScreen extends StatefulWidget {
  const WalletComingSoonScreen({super.key});

  @override
  State<WalletComingSoonScreen> createState() => _WalletComingSoonScreenState();
}

class _WalletComingSoonScreenState extends State<WalletComingSoonScreen> {
  final ApiService _apiService = ApiService();

  bool _loading = true;
  int _creditBalance = 0;
  List<String> _methods = const [];
  bool _enableLivePayments = false;

  void _showCreditRequestDialog() {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Request Credits',
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Amount (required)',
                  style: AppTypography.labelMedium.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  style: AppTypography.bodyMedium.copyWith(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Enter credits needed',
                    hintStyle: AppTypography.bodyMedium.copyWith(
                      color: Colors.white38,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppColors.primaryBlue,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Reason (optional)',
                  style: AppTypography.labelMedium.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  style: AppTypography.bodyMedium.copyWith(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Why do you need more credits?',
                    hintStyle: AppTypography.bodyMedium.copyWith(
                      color: Colors.white38,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppColors.primaryBlue,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  isSubmitting ? null : () => Navigator.pop(dialogContext),
              child: Text(
                'Cancel',
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white70,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final amount = int.tryParse(amountController.text);
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter a valid amount'),
                            backgroundColor: AppColors.dangerRed,
                          ),
                        );
                        return;
                      }

                      setState(() => isSubmitting = true);
                      final messenger = ScaffoldMessenger.of(this.context);
                      final navigator = Navigator.of(dialogContext);

                      try {
                        await _apiService.requestCredits(
                          amount: amount,
                          reason: reasonController.text.trim().isEmpty
                              ? null
                              : reasonController.text.trim(),
                        );

                        if (!mounted) return;
                        navigator.pop();
                        await _load();
                        if (!mounted) return;

                        messenger.showSnackBar(
                          const SnackBar(
                            content:
                                Text('Credit request submitted successfully'),
                            backgroundColor: AppColors.successGreen,
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        setState(() => isSubmitting = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Failed to submit request: $e'),
                            backgroundColor: AppColors.dangerRed,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    Map<String, dynamic> balance = {};
    Map<String, dynamic> flags = {};

    try {
      balance = await _apiService.getCreditBalance();
    } catch (_) {
      balance = {};
    }

    try {
      flags = await _apiService.getFeatureFlags();
    } catch (_) {
      flags = {};
    }

    final rawBalance = balance['balance'];
    final creditBalance = rawBalance is num
        ? rawBalance.toInt()
        : (rawBalance is String ? int.tryParse(rawBalance) ?? 0 : 0);

    final rawEnabled = flags['enable_live_payments'];
    final enabled = rawEnabled == true ||
        (rawEnabled is String && rawEnabled.toLowerCase().trim() == 'true');
    final rawMethods = flags['payment_methods_enabled'];
    final methods = rawMethods is List
        ? rawMethods.map((m) => m.toString().trim().toLowerCase()).toList()
        : <String>['stripe', 'paypal', 'coinbase'];

    if (!mounted) return;
    setState(() {
      _creditBalance = creditBalance;
      _enableLivePayments = enabled;
      _methods = methods.where((m) => m.isNotEmpty).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final layoutType =
        AppBreakpoints.getLayoutType(MediaQuery.of(context).size.width);
    final padding = ResponsiveUtils.getScreenPadding(layoutType);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryBlue),
              )
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.primaryBlue,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildBalanceCard(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildComingSoonBanner(),
                      const SizedBox(height: AppSpacing.lg),
                      _buildPaymentMethodsGrid(layoutType),
                      const SizedBox(height: AppSpacing.lg),
                      _buildRequestCreditsCard(),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
        Expanded(
          child: Text(
            'Billing & Payments',
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: AppSpacing.borderRadiusLg,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.28),
            blurRadius: 22,
            spreadRadius: -10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CURRENT BALANCE',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white70,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '$_creditBalance',
                style: AppTypography.displaySmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'credits',
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComingSoonBanner() {
    final title = _enableLivePayments
        ? 'Payments enabled'
        : 'Payment methods coming soon';
    final subtitle = _enableLivePayments
        ? 'Live payments are enabled. You can use the full wallet experience.'
        : 'Live payments are being rolled out. For now, request credits from admins.';

    final icon = _enableLivePayments
        ? Icons.check_circle_outline_rounded
        : Icons.schedule_rounded;
    final color =
        _enableLivePayments ? AppColors.successGreen : AppColors.warningYellow;

    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.titleSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white70,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsGrid(LayoutType layoutType) {
    final methods = _methods.isEmpty
        ? const <String>['stripe', 'paypal', 'coinbase']
        : _methods;

    final crossAxisCount = layoutType == LayoutType.mobile ? 2 : 4;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: methods.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
        childAspectRatio: 1.05,
      ),
      itemBuilder: (context, index) {
        final method = methods[index];
        final spec = _methodSpec(method);
        return _methodCard(spec);
      },
    );
  }

  _MethodSpec _methodSpec(String method) {
    final m = method.trim().toLowerCase();
    switch (m) {
      case 'stripe':
        return const _MethodSpec(
          name: 'Stripe',
          assetPath: 'assets/icons/stripe.svg',
          icon: Icons.payment_rounded,
          color: Color(0xFF635BFF),
        );
      case 'paypal':
        return const _MethodSpec(
          name: 'PayPal',
          assetPath: 'assets/icons/paypal.svg',
          icon: Icons.payments_rounded,
          color: Color(0xFF003087),
        );
      case 'coinbase':
        return const _MethodSpec(
          name: 'Coinbase',
          assetPath: 'assets/icons/coinbase.svg',
          icon: Icons.currency_bitcoin_rounded,
          color: Color(0xFF1652F0),
        );
      case 'bank':
      case 'bank_transfer':
        return const _MethodSpec(
          name: 'Bank Transfer',
          icon: Icons.account_balance_rounded,
          color: Color(0xFF4CAF50),
        );
      default:
        return _MethodSpec(
          name: method.trim().isEmpty ? 'Payment' : method.trim(),
          icon: Icons.lock_clock_rounded,
          color: AppColors.primaryBlue,
        );
    }
  }

  Widget _methodCard(_MethodSpec spec) {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: spec.color.withValues(alpha: 0.10),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: spec.color.withValues(alpha: 0.30)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: spec.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: spec.color.withValues(alpha: 0.28)),
            ),
            child: Center(
              child: spec.assetPath != null
                  ? SvgPicture.asset(
                      spec.assetPath!,
                      width: 22,
                      height: 22,
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                    )
                  : Icon(spec.icon, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            spec.name,
            style: AppTypography.labelMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Coming soon',
            style: AppTypography.labelSmall.copyWith(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCreditsCard() {
    return Container(
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: AppColors.elevatedCardDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up_rounded,
                  color: AppColors.successGreen, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Need credits now?',
                      style: AppTypography.titleSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Request credits from admins while live payments are rolling out.',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          GradientButton(
            text: 'Request Credits',
            icon: Icons.arrow_forward_rounded,
            expanded: true,
            height: 52,
            onPressed: _showCreditRequestDialog,
          ),
        ],
      ),
    );
  }
}

class _MethodSpec {
  final String name;
  final String? assetPath;
  final IconData icon;
  final Color color;

  const _MethodSpec({
    required this.name,
    this.assetPath,
    required this.icon,
    required this.color,
  });
}
