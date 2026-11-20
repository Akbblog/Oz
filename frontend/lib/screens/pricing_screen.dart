import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/responsive_utils.dart';
import '../services/api_service.dart';
import '../providers/credit_provider.dart';
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
  final bool _showSubscriptionOptions = false;
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _packages = [];
  List<Map<String, dynamic>> _plans = [];
  int? _selectedPackageId;
  int? _selectedPlanId;
  int _exampleCities = 1;
  int _exampleLeads = 10;
  int? _exampleCost;
  bool _exampleLoading = false;
  int _exampleRequest = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _showSubscriptionOptions ? 2 : 1,
      vsync: this,
    );
    _loadData();
    CreditProvider.instance.refresh();
    CreditProvider.instance.loadConfig();
    _loadExampleCost();
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
      if (_showSubscriptionOptions) {
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
      } else {
        final packages = await _apiService.getCreditPackages();
        if (mounted) {
          setState(() {
            _packages = packages;
            _plans = [];
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load packages: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadExampleCost() async {
    final request = ++_exampleRequest;
    setState(() {
      _exampleLoading = true;
      _exampleCost = null;
    });
    try {
      final estimate = await _apiService.estimateJobCost(
        numCities: _exampleCities,
        maxResultsPerCity: _exampleLeads,
      );
      if (!mounted || request != _exampleRequest) return;
      final value = estimate['estimated_cost'];
      setState(() {
        _exampleCost = value is num ? value.toInt() : int.tryParse('$value');
        _exampleLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _exampleRequest) return;
      setState(() => _exampleLoading = false);
    }
  }

  void _proceedToCheckout() {
    final isPackage = !_showSubscriptionOptions || _tabController.index == 0;
    final selectedId = isPackage ? _selectedPackageId : _selectedPlanId;
    if (selectedId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPackage
                ? 'Select a credit package'
                : 'Select a subscription plan',
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
        builder: (context) =>
            CheckoutScreen(item: item, isSubscription: !isPackage),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layoutType = AppBreakpoints.getLayoutType(
      MediaQuery.of(context).size.width,
    );

    return Scaffold(
      backgroundColor: _PricingColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            _buildBackground(),
            Column(
              children: [
                _buildHeader(),
                if (_showSubscriptionOptions) _buildTabs(),
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
                                physics: _showSubscriptionOptions
                                    ? null
                                    : const NeverScrollableScrollPhysics(),
                                children: _showSubscriptionOptions
                                    ? [
                                        _buildPackagesTab(layoutType),
                                        _buildPlansTab(layoutType),
                                      ]
                                    : [_buildPackagesTab(layoutType)],
                              ),
                            ),
                ),
                if (!_isLoading &&
                    _error == null &&
                    layoutType == LayoutType.mobile)
                  _buildBottomBar(),
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
              'Packages',
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
        labelStyle: AppTypography.labelLarge.copyWith(
          fontWeight: FontWeight.w700,
        ),
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
          FilledButton(onPressed: _loadData, child: const Text('Retry')),
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

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.all(ResponsiveUtils.getScreenPadding(layoutType)),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 850
                  ? 3
                  : constraints.maxWidth >= 580
                      ? 2
                      : 1;
              final cardWidth =
                  (constraints.maxWidth - (columns - 1) * AppSpacing.md) /
                      columns;
              final starter = _packages.first;
              final starterCredits =
                  (starter['credits'] as num?)?.toDouble() ?? 0;
              final starterCents =
                  (starter['display_price_cents'] as num?)?.toDouble() ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Buy credits', style: AppTypography.headlineSmallDark),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'One-time purchase. Credits never expire.',
                    style: AppTypography.bodyMediumDark.copyWith(
                      color: AppColors.textSecondaryDark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AnimatedBuilder(
                    animation: CreditProvider.instance,
                    builder: (context, _) {
                      final credit = CreditProvider.instance;
                      return Text(
                        credit.hasValue
                            ? 'Current balance: ${credit.balance} credits'
                            : 'Current balance unavailable',
                        style: AppTypography.bodySmallDark,
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: _packages.map((pkg) {
                      final credits = (pkg['credits'] as num?)?.toDouble() ?? 0;
                      final cents =
                          (pkg['display_price_cents'] as num?)?.toDouble() ?? 0;
                      final saving =
                          starterCredits > 0 && starterCents > 0 && credits > 0
                              ? ((1 -
                                          (cents / credits) /
                                              (starterCents / starterCredits)) *
                                      100)
                                  .round()
                              : null;
                      return SizedBox(
                        width: cardWidth,
                        child: CreditPackageCard(
                          package: pkg,
                          isSelected: _selectedPackageId == pkg['id'],
                          isFeatured: pkg['is_featured'] == true,
                          savingsPercent: saving,
                          comparisonName: '${starter['name'] ?? 'Starter'}',
                          onTap: () =>
                              setState(() => _selectedPackageId = pkg['id']),
                        ),
                      );
                    }).toList(),
                  ),
                  if (layoutType != LayoutType.mobile) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _buildCheckoutAction(),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                  _buildCostExample(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildCreditNotes(),
                ],
              );
            },
          ),
        ),
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
          if (layoutType != LayoutType.mobile) ...[
            const SizedBox(height: AppSpacing.lg),
            _buildCheckoutAction(),
          ],
        ],
      ),
    );
  }

  Widget _buildCostExample() {
    final selected = _packages.where((p) => p['id'] == _selectedPackageId);
    final selectedCredits =
        selected.isEmpty ? null : (selected.first['credits'] as num?)?.toInt();
    final cost = _exampleCost;
    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What can credits cover?', style: AppTypography.titleMediumDark),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Example search. Your exact maximum cost appears before you start.',
            style: AppTypography.bodySmallDark,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              _exampleDropdown('Cities', _exampleCities, const [1, 5, 10, 30], (
                value,
              ) {
                setState(() => _exampleCities = value);
                _loadExampleCost();
              }),
              _exampleDropdown(
                'Leads per city',
                _exampleLeads,
                const [10, 25, 50, 100],
                (value) {
                  setState(() => _exampleLeads = value);
                  _loadExampleCost();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_exampleLoading)
            const LinearProgressIndicator(minHeight: 2)
          else if (cost == null)
            Text(
              'Cost example unavailable. Check the exact cost when setting up a search.',
              style: AppTypography.bodySmallDark,
            )
          else ...[
            Text(
              '$cost credits reserved to start this search',
              style: AppTypography.titleMediumDark,
            ),
            if (selectedCredits != null) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                selectedCredits >= cost
                    ? 'The selected pack can start this example search.'
                    : 'The selected pack alone is below this example’s starting cost.',
                style: AppTypography.bodySmallDark,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _exampleDropdown(
    String label,
    int value,
    List<int> choices,
    ValueChanged<int> onChanged,
  ) {
    return SizedBox(
      width: 170,
      child: DropdownButtonFormField<int>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: choices
            .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
            .toList(),
        onChanged: (n) {
          if (n != null) onChanged(n);
        },
      ),
    );
  }

  Widget _buildCreditNotes() {
    return AnimatedBuilder(
      animation: CreditProvider.instance,
      builder: (context, _) {
        final refund = CreditProvider.instance.refundPolicySentence;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How credits work', style: AppTypography.titleMediumDark),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Credits are a one-time purchase and do not expire.',
              style: AppTypography.bodyMediumDark,
            ),
            if (refund != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(refund, style: AppTypography.bodyMediumDark),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCheckoutAction({bool fullWidth = false}) {
    final isPackage = !_showSubscriptionOptions || _tabController.index == 0;
    final items = isPackage ? _packages : _plans;
    final selectedId = isPackage ? _selectedPackageId : _selectedPlanId;
    final selected = items.where((p) => p['id'] == selectedId);
    final item = selected.isEmpty ? null : selected.first;
    final cents = item == null
        ? null
        : (item['display_price_cents'] as num?)?.toInt() ??
            (item['base_price_cents'] as num?)?.toInt();
    final label = item == null
        ? 'Select a ${isPackage ? 'package' : 'plan'} to continue'
        : 'Continue with ${item['name']} · \$${((cents ?? 0) / 100).toStringAsFixed(2)}';
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: fullWidth ? double.infinity : null,
        child: FilledButton.icon(
          onPressed: item == null ? null : _proceedToCheckout,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryBlue,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: _PricingColors.background,
        border: Border(top: BorderSide(color: AppColors.borderDark)),
      ),
      child: _buildCheckoutAction(fullWidth: true),
    );
  }
}

class _PricingColors {
  static const Color primary = AppColors.primaryBlue;
  static const Color background = AppColors.backgroundDark;
  static const Color surface = AppColors.elevatedCardDark;
}
