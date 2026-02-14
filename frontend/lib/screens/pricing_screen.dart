import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/responsive_utils.dart';
import '../services/api_service.dart';
import '../widgets/credit_package_card.dart';
import '../widgets/subscription_plan_card.dart';
import 'checkout_screen.dart';

class PricingScreen extends StatefulWidget {
  const PricingScreen({super.key});

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends State<PricingScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _packages = [];
  List<Map<String, dynamic>> _plans = [];
  int? _selectedPackageId;
  int? _selectedPlanId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _apiService.getCreditPackages(),
        _apiService.getSubscriptionPlans(),
      ]);

      if (mounted) {
        setState(() {
          _packages = results[0];
          _plans = results[1];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load pricing: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _proceedToCheckout() {
    final isPackage = _tabController.index == 0;
    final selectedId = isPackage ? _selectedPackageId : _selectedPlanId;
    if (selectedId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPackage ? 'Select a credit package' : 'Select a subscription plan',
          ),
          backgroundColor: AppColors.dangerRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final item = isPackage
        ? _packages.firstWhere((p) => p['id'] == selectedId)
        : _plans.firstWhere((p) => p['id'] == selectedId);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CheckoutScreen(
          item: item,
          isSubscription: !isPackage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layoutType =
        AppBreakpoints.getLayoutType(MediaQuery.of(context).size.width);

    return Scaffold(
      backgroundColor: _PricingColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            _buildBackground(),
            Column(
              children: [
                _buildHeader(),
                _buildTabs(),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _PricingColors.primary,
                            ),
                          ),
                        )
                      : _error != null
                          ? _buildError()
                          : RefreshIndicator(
                              color: AppColors.primaryBlue,
                              backgroundColor: AppColors.surfaceDark,
                              onRefresh: _loadData,
                              child: TabBarView(
                                controller: _tabController,
                                children: [
                                  _buildPackagesTab(layoutType),
                                  _buildPlansTab(layoutType),
                                ],
                              ),
                            ),
                ),
                if (!_isLoading && _error == null) _buildBottomBar(),
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
              _PricingColors.primary.withValues(alpha: 0.2),
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
        color: _PricingColors.background.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderDarkAlt.withValues(alpha: 0.6),
          ),
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
              'Pricing',
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

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      decoration: BoxDecoration(
        color: _PricingColors.surface.withValues(alpha: 0.4),
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: AppColors.borderDarkAlt),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: AppColors.primaryBlue,
          borderRadius: AppSpacing.borderRadiusMd,
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        labelStyle: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: AppTypography.labelLarge,
        tabs: const [
          Tab(text: 'Credit Packages'),
          Tab(text: 'Subscriptions'),
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
            onTap: _loadData,
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

  Widget _buildPackagesTab(LayoutType layoutType) {
    if (_packages.isEmpty) {
      return Center(
        child: Text(
          'No credit packages available.',
          style: AppTypography.bodyMedium.copyWith(color: Colors.white54),
        ),
      );
    }

    final padding = ResponsiveUtils.getScreenPadding(layoutType);
    final crossAxisCount = layoutType == LayoutType.mobile
        ? 1
        : layoutType == LayoutType.tablet
            ? 2
            : 3;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buy Credits',
            style: AppTypography.headlineSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'One-time purchase. Credits never expire.',
            style: AppTypography.bodySmall.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: AppSpacing.lg),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              childAspectRatio: crossAxisCount == 1 ? 2.2 : 1.1,
            ),
            itemCount: _packages.length,
            itemBuilder: (context, index) {
              final pkg = _packages[index];
              return CreditPackageCard(
                package: pkg,
                isSelected: _selectedPackageId == pkg['id'],
                isFeatured: pkg['is_featured'] == true,
                onTap: () {
                  setState(() => _selectedPackageId = pkg['id']);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlansTab(LayoutType layoutType) {
    if (_plans.isEmpty) {
      return Center(
        child: Text(
          'No subscription plans available.',
          style: AppTypography.bodyMedium.copyWith(color: Colors.white54),
        ),
      );
    }

    final padding = ResponsiveUtils.getScreenPadding(layoutType);
    final crossAxisCount = layoutType == LayoutType.mobile
        ? 1
        : layoutType == LayoutType.tablet
            ? 2
            : 3;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Subscribe & Save',
            style: AppTypography.headlineSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Get credits every month at a discounted rate.',
            style: AppTypography.bodySmall.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: AppSpacing.lg),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              childAspectRatio: crossAxisCount == 1 ? 2.0 : 1.0,
            ),
            itemCount: _plans.length,
            itemBuilder: (context, index) {
              final plan = _plans[index];
              return SubscriptionPlanCard(
                plan: plan,
                isSelected: _selectedPlanId == plan['id'],
                onTap: () {
                  setState(() => _selectedPlanId = plan['id']);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final isPackage = _tabController.index == 0;
    final hasSelection = isPackage
        ? _selectedPackageId != null
        : _selectedPlanId != null;

    return AnimatedBuilder(
      animation: _tabController.animation!,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: _PricingColors.background,
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: GestureDetector(
            onTap: hasSelection ? _proceedToCheckout : null,
            child: AnimatedContainer(
              duration: AppSpacing.durationMedium,
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                color: hasSelection
                    ? AppColors.primaryBlue
                    : AppColors.disabledDark,
                borderRadius: AppSpacing.borderRadiusMd,
                boxShadow: hasSelection
                    ? [
                        BoxShadow(
                          color: AppColors.primaryBlue.withValues(alpha: 0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  'Continue to Checkout',
                  style: AppTypography.labelLarge.copyWith(
                    color: hasSelection ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PricingColors {
  static const Color primary = AppColors.primaryBlue;
  static const Color background = AppColors.backgroundDark;
  static const Color surface = AppColors.elevatedCardDark;
}
