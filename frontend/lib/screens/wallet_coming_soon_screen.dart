import 'package:flutter/material.dart';
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
      barrierColor: Colors.black54,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.xxl,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 30,
                  spreadRadius: -5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with gradient accent
                Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryBlue.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primaryBlue.withValues(alpha: 0.3),
                              AppColors.primaryBlue.withValues(alpha: 0.15),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primaryBlue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.toll_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Request Credits',
                              style: AppTypography.titleMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'An admin will review your request',
                              style: AppTypography.bodySmall.copyWith(
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: isSubmitting
                            ? null
                            : () => Navigator.pop(dialogContext),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white38,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Divider
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                // Form content
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Amount',
                        style: AppTypography.labelMedium.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        style: AppTypography.bodyMedium.copyWith(
                          color: Colors.white,
                        ),
                        decoration: InputDecoration(
                          hintText: 'How many credits do you need?',
                          hintStyle: AppTypography.bodyMedium.copyWith(
                            color: Colors.white24,
                          ),
                          prefixIcon: Padding(
                            padding: const EdgeInsets.only(left: 12, right: 8),
                            child: Icon(
                              Icons.stars_rounded,
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.7),
                              size: 20,
                            ),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 0,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.04),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.6),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
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
                        style: AppTypography.bodyMedium.copyWith(
                          color: Colors.white,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Tell us why you need more credits...',
                          hintStyle: AppTypography.bodyMedium.copyWith(
                            color: Colors.white24,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.04),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color:
                                  AppColors.primaryBlue.withValues(alpha: 0.6),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: OutlinedButton(
                                onPressed: isSubmitting
                                    ? null
                                    : () => Navigator.pop(dialogContext),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                  foregroundColor: Colors.white54,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: AppTypography.labelMedium.copyWith(
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 46,
                              child: ElevatedButton.icon(
                                onPressed: isSubmitting
                                    ? null
                                    : () async {
                                        final amount =
                                            int.tryParse(amountController.text);
                                        if (amount == null || amount <= 0) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Please enter a valid amount'),
                                              backgroundColor:
                                                  AppColors.dangerRed,
                                            ),
                                          );
                                          return;
                                        }

                                        setState(() => isSubmitting = true);
                                        final messenger =
                                            ScaffoldMessenger.of(this.context);
                                        final navigator =
                                            Navigator.of(dialogContext);

                                        try {
                                          await _apiService.requestCredits(
                                            amount: amount,
                                            reason: reasonController.text
                                                    .trim()
                                                    .isEmpty
                                                ? null
                                                : reasonController.text.trim(),
                                          );

                                          if (!mounted) return;
                                          navigator.pop();

                                          messenger.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Credit request submitted successfully'),
                                              backgroundColor:
                                                  AppColors.successGreen,
                                            ),
                                          );

                                          await Future.delayed(const Duration(
                                              milliseconds: 1500));
                                          if (!mounted) return;
                                          Navigator.of(this.context)
                                              .pushNamedAndRemoveUntil(
                                            '/home',
                                            (route) => false,
                                          );
                                        } catch (e) {
                                          if (!mounted) return;
                                          setState(() => isSubmitting = false);
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Failed to submit request: $e'),
                                              backgroundColor:
                                                  AppColors.dangerRed,
                                            ),
                                          );
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryBlue,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: AppColors.primaryBlue
                                      .withValues(alpha: 0.4),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                icon: isSubmitting
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              const AlwaysStoppedAnimation<
                                                  Color>(Colors.white),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.send_rounded,
                                        size: 18,
                                      ),
                                label: Text(
                                  isSubmitting
                                      ? 'Submitting...'
                                      : 'Submit Request',
                                  style: AppTypography.labelLarge.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
        : <String>['coinbase'];

    if (!mounted) return;
    setState(() {
      _creditBalance = creditBalance;
      _enableLivePayments = enabled;
      final filtered = methods.where((m) => m == 'coinbase').toSet().toList();
      _methods = filtered.isEmpty ? const ['coinbase'] : filtered;
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
        child: Stack(
          children: [
            // Background gradient
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primaryBlue.withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                    radius: 1.5,
                    center: const Alignment(0, -1.5),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryBlue,
                          ),
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
                                _buildBalanceCard(),
                                const SizedBox(height: AppSpacing.md),
                                _buildComingSoonBanner(),
                                const SizedBox(height: AppSpacing.lg),
                                _buildRequestCreditsCard(),
                                const SizedBox(height: AppSpacing.xl),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
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
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlue.withValues(alpha: 0.35),
            AppColors.primaryBlueDark.withValues(alpha: 0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.2),
            blurRadius: 24,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'CURRENT BALANCE',
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white60,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$_creditBalance',
                style: AppTypography.displaySmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 40,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'credits',
                style: AppTypography.bodyLarge.copyWith(
                  color: Colors.white54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Balance indicator bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 4,
              value: _creditBalance > 0
                  ? (_creditBalance / 500).clamp(0.0, 1.0)
                  : 0.0,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white70),
            ),
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
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '$title - $subtitle',
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white70,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsSection(LayoutType layoutType) {
    final methods = _methods.isEmpty ? const <String>['coinbase'] : _methods;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.credit_card_rounded,
              color: Colors.white54,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              'Payment Methods',
              style: AppTypography.titleSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warningYellow.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.warningYellow.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                'Coming soon',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.warningYellow,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ...methods.map((method) {
          final spec = _methodSpec(method);
          return _methodListTile(spec);
        }),
      ],
    );
  }

  _MethodSpec _methodSpec(String method) {
    final m = method.trim().toLowerCase();
    switch (m) {
      case 'stripe':
        return const _MethodSpec(
          name: 'Stripe',
          description: 'Credit & debit cards',
          icon: Icons.credit_card_rounded,
          color: Color(0xFF9B8FFF),
        );
      case 'paypal':
        return const _MethodSpec(
          name: 'PayPal',
          description: 'PayPal account',
          icon: Icons.account_balance_wallet_rounded,
          color: Color(0xFF4DA6E8),
        );
      case 'coinbase':
        return const _MethodSpec(
          name: 'Coinbase',
          description: 'Cryptocurrency',
          icon: Icons.currency_bitcoin_rounded,
          color: Color(0xFF5B8DEF),
        );
      case 'bank':
      case 'bank_transfer':
        return const _MethodSpec(
          name: 'Bank Transfer',
          description: 'Direct bank payment',
          icon: Icons.account_balance_rounded,
          color: Color(0xFF66BB6A),
        );
      default:
        return _MethodSpec(
          name: method.trim().isEmpty ? 'Payment' : method.trim(),
          description: 'Payment method',
          icon: Icons.lock_clock_rounded,
          color: AppColors.primaryBlueLight,
        );
    }
  }

  Widget _methodListTile(_MethodSpec spec) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.elevatedCardDark.withValues(alpha: 0.6),
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: spec.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: spec.color.withValues(alpha: 0.25),
              ),
            ),
            child: Icon(spec.icon, color: spec.color, size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          // Name and description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.name,
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  spec.description,
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ),
          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: AppColors.warningYellow.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Soon',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white38,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCreditsCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlue.withValues(alpha: 0.1),
            AppColors.primaryBlueDark.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: AppColors.primaryBlueLight,
                  size: 22,
                ),
              ),
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
                    const SizedBox(height: 2),
                    Text(
                      'Request credits from admins while live payments are rolling out.',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white54,
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
            icon: Icons.send_rounded,
            expanded: true,
            height: 48,
            onPressed: _showCreditRequestDialog,
          ),
        ],
      ),
    );
  }
}

class _MethodSpec {
  final String name;
  final String description;
  final IconData icon;
  final Color color;

  const _MethodSpec({
    required this.name,
    this.description = '',
    required this.icon,
    required this.color,
  });
}
