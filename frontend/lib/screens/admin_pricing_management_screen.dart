import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_background.dart';

class AdminPricingManagementScreen extends StatefulWidget {
  const AdminPricingManagementScreen({super.key});

  @override
  State<AdminPricingManagementScreen> createState() =>
      _AdminPricingManagementScreenState();
}

class _AdminPricingManagementScreenState
    extends State<AdminPricingManagementScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _packages = [];
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _tiers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final packages = await _api.getAdminCreditPackages();
      final plans = await _api.getAdminSubscriptionPlans();
      final tiers = await _api.getPricingTiers();

      if (!mounted) return;
      setState(() {
        final pkgList = (packages['packages'] as List<dynamic>?) ?? const [];
        final planList = (plans['plans'] as List<dynamic>?) ?? const [];
        _packages = List<Map<String, dynamic>>.from(pkgList);
        _plans = List<Map<String, dynamic>>.from(planList);
        _tiers = List<Map<String, dynamic>>.from(tiers);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load pricing data: $e';
      });
      _snack('Failed to load pricing data: $e', AppColors.dangerRed);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (!auth.isAdmin) {
      return Scaffold(
        body: GradientBackground(
          child: Center(
            child: Text(
              'Admin access required',
              style: AppTypography.titleMedium.copyWith(color: Colors.white),
            ),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        appBar: AppBar(
          backgroundColor: AppColors.backgroundDark,
          elevation: 0,
          title: Text(
            'Pricing Management',
            style: AppTypography.titleLarge.copyWith(color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
                onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
            const SizedBox(width: AppSpacing.sm),
          ],
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: AppColors.primaryBlue,
            tabs: const [
              Tab(text: 'Packages'),
              Tab(text: 'Plans'),
              Tab(text: 'Tiers'),
            ],
          ),
        ),
        body: GradientBackground(
          child: SafeArea(
            child: _loading
                ? Center(
                    child: SizedBox(
                      width: 220,
                      child: LinearProgressIndicator(
                        backgroundColor: AppColors.surfaceDark,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primaryBlue),
                      ),
                    ),
                  )
                : _error != null
                    ? _buildErrorState()
                    : TabBarView(
                        children: [
                          _packagesTab(),
                          _plansTab(),
                          _tiersTab(),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: AppSpacing.paddingLg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: AppColors.dangerRed, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton.icon(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: AppSpacing.paddingLg,
        child: Container(
          padding: AppSpacing.paddingLg,
          decoration: BoxDecoration(
            color: AppColors.elevatedCardDark,
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: AppColors.primaryBlueLight, size: 44),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(color: Colors.white60),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _packagesTab() {
    return _listScaffold(
      title: 'Credit Packages',
      onAdd: () => _showPackageDialog(),
      child: _packages.isEmpty
          ? _buildEmptyState(
              icon: Icons.local_mall_rounded,
              title: 'No packages yet',
              subtitle: 'Create a credit package to sell one-time credits.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _packages.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) => _packageTile(_packages[i]),
            ),
    );
  }

  Widget _plansTab() {
    return _listScaffold(
      title: 'Subscription Plans',
      onAdd: () => _showPlanDialog(),
      child: _plans.isEmpty
          ? _buildEmptyState(
              icon: Icons.subscriptions_rounded,
              title: 'No plans yet',
              subtitle:
                  'Create a subscription plan to offer recurring credits.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _plans.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) => _planTile(_plans[i]),
            ),
    );
  }

  Widget _tiersTab() {
    return _listScaffold(
      title: 'Pricing Tiers',
      onAdd: () => _showTierDialog(),
      child: _tiers.isEmpty
          ? _buildEmptyState(
              icon: Icons.stacked_line_chart_rounded,
              title: 'No tiers yet',
              subtitle: 'Create pricing tiers for subscription credit pricing.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _tiers.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) => _tierTile(_tiers[i]),
            ),
    );
  }

  Widget _listScaffold({
    required String title,
    required VoidCallback onAdd,
    required Widget child,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: Row(
            children: [
              Text(
                title,
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppSpacing.borderRadiusMd,
                  ),
                ),
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(child: child),
      ],
    );
  }

  Widget _packageTile(Map<String, dynamic> pkg) {
    final id = (pkg['id'] as num).toInt();
    final name = pkg['name'] ?? '';
    final credits = pkg['credits'] ?? 0;
    final price = ((pkg['display_price_cents'] ?? 0) as num).toDouble() / 100.0;
    final active = pkg['is_active'] == true;
    return DarkGlassCard(
      child: Row(
        children: [
          Icon(
            Icons.local_offer_rounded,
            color: active ? AppColors.successGreen : Colors.white38,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.toString(),
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$credits credits • \$${price.toStringAsFixed(2)}',
                  style:
                      AppTypography.bodySmall.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: () => _showPackageDialog(existing: pkg),
            icon: const Icon(Icons.edit_rounded, color: Colors.white70),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surfaceDark,
                  title: Text('Delete Package',
                      style: AppTypography.titleMedium
                          .copyWith(color: Colors.white)),
                  content: Text('Delete "$name"? This cannot be undone.',
                      style: AppTypography.bodyMedium
                          .copyWith(color: Colors.white70)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.dangerRed,
                          foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              try {
                await _api.deleteCreditPackage(id);
                if (!mounted) return;
                setState(() => _packages
                    .removeWhere((p) => (p['id'] as num).toInt() == id));
              } catch (e) {
                _snack('Failed to delete package: $e', AppColors.dangerRed);
              }
            },
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.dangerRed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _planTile(Map<String, dynamic> plan) {
    final id = (plan['id'] as num).toInt();
    final name = plan['name'] ?? '';
    final interval = plan['billing_interval'] ?? 'monthly';
    final credits = plan['credits_per_period'] ?? 0;
    final price = ((plan['base_price_cents'] ?? 0) as num).toDouble() / 100.0;
    final active = plan['is_active'] == true;
    return DarkGlassCard(
      child: Row(
        children: [
          Icon(
            Icons.subscriptions_rounded,
            color: active ? AppColors.primaryBlueLight : Colors.white38,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.toString(),
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$credits / $interval • \$${price.toStringAsFixed(2)}',
                  style:
                      AppTypography.bodySmall.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: () => _showPlanDialog(existing: plan),
            icon: const Icon(Icons.edit_rounded, color: Colors.white70),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surfaceDark,
                  title: Text('Delete Plan',
                      style: AppTypography.titleMedium
                          .copyWith(color: Colors.white)),
                  content: Text('Delete "$name"? This cannot be undone.',
                      style: AppTypography.bodyMedium
                          .copyWith(color: Colors.white70)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.dangerRed,
                          foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              try {
                await _api.deleteSubscriptionPlan(id);
                if (!mounted) return;
                setState(() =>
                    _plans.removeWhere((p) => (p['id'] as num).toInt() == id));
              } catch (e) {
                _snack('Failed to delete plan: $e', AppColors.dangerRed);
              }
            },
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.dangerRed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tierTile(Map<String, dynamic> tier) {
    final name = tier['name'] ?? '';
    final min = tier['min_monthly_credits'] ?? 0;
    final max = tier['max_monthly_credits'];
    final ppc = (tier['price_per_credit_cents'] ?? 0).toString();
    final active = tier['is_active'] == true;
    return DarkGlassCard(
      child: Row(
        children: [
          Icon(
            Icons.stacked_line_chart_rounded,
            color: active ? AppColors.secondaryStart : Colors.white38,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.toString(),
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$min - ${max ?? '∞'} credits/mo • $ppc¢/credit',
                  style:
                      AppTypography.bodySmall.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: () => _showTierDialog(existing: tier),
            icon: const Icon(Icons.edit_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Future<void> _showPackageDialog({Map<String, dynamic>? existing}) async {
    final name =
        TextEditingController(text: existing?['name']?.toString() ?? '');
    final credits =
        TextEditingController(text: (existing?['credits'] ?? '').toString());
    final display = TextEditingController(
        text: (existing?['display_price_cents'] ?? '').toString());
    final active =
        ValueNotifier<bool>(existing?['is_active'] == true || existing == null);

    final ok = await _simpleDialog(
      title: existing == null ? 'Create Package' : 'Edit Package',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(name, 'Name'),
          const SizedBox(height: AppSpacing.sm),
          _field(credits, 'Credits', keyboardType: TextInputType.number),
          const SizedBox(height: AppSpacing.sm),
          _field(display, 'Display Price (cents)',
              keyboardType: TextInputType.number),
          const SizedBox(height: AppSpacing.sm),
          ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, v, __) => SwitchListTile(
              value: v,
              onChanged: (nv) => active.value = nv,
              title: Text('Active',
                  style:
                      AppTypography.bodySmall.copyWith(color: Colors.white70)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final creditsVal = int.tryParse(credits.text) ?? 0;
    final priceVal = int.tryParse(display.text) ?? 0;
    if (creditsVal <= 0 || priceVal <= 0 || name.text.trim().isEmpty) {
      _snack('Please enter valid package fields', AppColors.dangerRed);
      return;
    }

    if (existing == null) {
      await _api.createCreditPackage(
        name: name.text.trim(),
        credits: creditsVal,
        basePriceCents: priceVal,
        displayPriceCents: priceVal,
        isActive: active.value,
      );
    } else {
      final id = (existing['id'] as num).toInt();
      await _api.updateCreditPackage(
        id,
        name: name.text.trim(),
        credits: creditsVal,
        basePriceCents: priceVal,
        displayPriceCents: priceVal,
        isActive: active.value,
      );
    }
    _load();
  }

  Future<void> _showPlanDialog({Map<String, dynamic>? existing}) async {
    final name =
        TextEditingController(text: existing?['name']?.toString() ?? '');
    final interval = ValueNotifier<String>(
        existing?['billing_interval']?.toString() ?? 'monthly');
    final credits = TextEditingController(
        text: (existing?['credits_per_period'] ?? '').toString());
    final price = TextEditingController(
        text: (existing?['base_price_cents'] ?? '').toString());
    final stripePriceId = TextEditingController(
        text: existing?['stripe_price_id']?.toString() ?? '');
    final active =
        ValueNotifier<bool>(existing?['is_active'] == true || existing == null);

    final ok = await _simpleDialog(
      title: existing == null ? 'Create Plan' : 'Edit Plan',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(name, 'Name'),
          const SizedBox(height: AppSpacing.sm),
          ValueListenableBuilder<String>(
            valueListenable: interval,
            builder: (_, v, __) => DropdownButtonFormField<String>(
              initialValue: v,
              dropdownColor: AppColors.surfaceDark,
              decoration: _inputDecoration('Billing interval'),
              items: const [
                DropdownMenuItem(value: 'monthly', child: Text('monthly')),
                DropdownMenuItem(value: 'yearly', child: Text('yearly')),
              ],
              onChanged: (nv) => interval.value = nv ?? 'monthly',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _field(credits, 'Credits per period',
              keyboardType: TextInputType.number),
          const SizedBox(height: AppSpacing.sm),
          _field(price, 'Price (cents)', keyboardType: TextInputType.number),
          const SizedBox(height: AppSpacing.sm),
          _field(stripePriceId, 'Stripe price id (optional)'),
          const SizedBox(height: AppSpacing.sm),
          ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, v, __) => SwitchListTile(
              value: v,
              onChanged: (nv) => active.value = nv,
              title: Text('Active',
                  style:
                      AppTypography.bodySmall.copyWith(color: Colors.white70)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final creditsVal = int.tryParse(credits.text) ?? 0;
    final priceVal = int.tryParse(price.text) ?? 0;
    if (creditsVal <= 0 || priceVal <= 0 || name.text.trim().isEmpty) {
      _snack('Please enter valid plan fields', AppColors.dangerRed);
      return;
    }

    final stripeId =
        stripePriceId.text.trim().isEmpty ? null : stripePriceId.text.trim();
    if (existing == null) {
      await _api.createSubscriptionPlan(
        name: name.text.trim(),
        billingInterval: interval.value,
        creditsPerPeriod: creditsVal,
        basePriceCents: priceVal,
        stripePriceId: stripeId,
        isActive: active.value,
      );
    } else {
      final id = (existing['id'] as num).toInt();
      await _api.updateSubscriptionPlan(
        id,
        name: name.text.trim(),
        billingInterval: interval.value,
        creditsPerPeriod: creditsVal,
        basePriceCents: priceVal,
        stripePriceId: stripeId,
        isActive: active.value,
      );
    }
    _load();
  }

  Future<void> _showTierDialog({Map<String, dynamic>? existing}) async {
    final name =
        TextEditingController(text: existing?['name']?.toString() ?? '');
    final min = TextEditingController(
        text: (existing?['min_monthly_credits'] ?? 0).toString());
    final max = TextEditingController(
        text: (existing?['max_monthly_credits'] ?? '').toString());
    final ppc = TextEditingController(
        text: (existing?['price_per_credit_cents'] ?? '').toString());
    final active =
        ValueNotifier<bool>(existing?['is_active'] == true || existing == null);

    final ok = await _simpleDialog(
      title: existing == null ? 'Create Tier' : 'Edit Tier',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(name, 'Name'),
          const SizedBox(height: AppSpacing.sm),
          _field(min, 'Min monthly credits',
              keyboardType: TextInputType.number),
          const SizedBox(height: AppSpacing.sm),
          _field(max, 'Max monthly credits (blank = unlimited)',
              keyboardType: TextInputType.number),
          const SizedBox(height: AppSpacing.sm),
          _field(ppc, 'Price per credit (cents)',
              keyboardType: TextInputType.number),
          const SizedBox(height: AppSpacing.sm),
          ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, v, __) => SwitchListTile(
              value: v,
              onChanged: (nv) => active.value = nv,
              title: Text('Active',
                  style:
                      AppTypography.bodySmall.copyWith(color: Colors.white70)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final minVal = int.tryParse(min.text) ?? 0;
    final maxVal = max.text.trim().isEmpty ? null : int.tryParse(max.text);
    final ppcVal = double.tryParse(ppc.text) ?? 0;
    if (name.text.trim().isEmpty || ppcVal <= 0) {
      _snack('Please enter valid tier fields', AppColors.dangerRed);
      return;
    }

    if (existing == null) {
      await _api.createPricingTier(
        name: name.text.trim(),
        minMonthlyCredits: minVal,
        maxMonthlyCredits: maxVal,
        pricePerCreditCents: ppcVal,
        isActive: active.value,
      );
    } else {
      final id = (existing['id'] as num).toInt();
      await _api.updatePricingTier(
        id,
        name: name.text.trim(),
        minMonthlyCredits: minVal,
        maxMonthlyCredits: maxVal,
        pricePerCreditCents: ppcVal,
        isActive: active.value,
      );
    }
    _load();
  }

  Future<bool?> _simpleDialog(
      {required String title, required Widget content}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text(title,
            style: AppTypography.titleMedium.copyWith(color: Colors.white)),
        content: SizedBox(width: 520, child: content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(label),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      filled: true,
      fillColor: AppColors.surfaceDark.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: AppSpacing.borderRadiusMd,
        borderSide: BorderSide.none,
      ),
    );
  }
}
