import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/gradient_background.dart';
import '../widgets/infinity_data_table.dart';
import '../widgets/revenue_chart.dart';
import '../widgets/stat_card.dart';

class AdminRevenueDashboardScreen extends StatefulWidget {
  const AdminRevenueDashboardScreen({super.key});

  @override
  State<AdminRevenueDashboardScreen> createState() =>
      _AdminRevenueDashboardScreenState();
}

class _AdminRevenueDashboardScreenState
    extends State<AdminRevenueDashboardScreen> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _dashboard;
  List<RevenueChartPoint> _mrrPoints = const [];

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
      final dashboard = await _api.getAdminRevenueDashboard();
      final mrr = await _api.getAdminMrr();

      final series = (mrr['series'] as List<dynamic>? ?? [])
          .map((e) => RevenueChartPoint(
                label: (e['month'] ?? '').toString(),
                value: ((e['mrr_cents'] ?? 0) as num).toDouble() / 100.0,
              ))
          .toList();

      if (!mounted) return;
      setState(() {
        _dashboard = dashboard;
        _mrrPoints = series;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load revenue dashboard: $e';
      });
      _snack('Failed to load revenue dashboard: $e', AppColors.dangerRed);
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
    final layoutType =
        AppBreakpoints.getLayoutType(MediaQuery.of(context).size.width);

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

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        elevation: 0,
        title: Text(
          'Revenue Dashboard',
          style: AppTypography.titleLarge.copyWith(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: GradientBackground(
        child: SafeArea(
          child: _loading
              ? _buildLoading()
              : _error != null && _dashboard == null
                  ? _buildErrorState()
                  : _buildContent(layoutType),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: SizedBox(
        width: 220,
        child: LinearProgressIndicator(
          backgroundColor: AppColors.surfaceDark,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
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

  Widget _buildContent(LayoutType layoutType) {
    final data = _dashboard ?? {};

    final revenueToday = ((data['revenue_today_cents'] ?? 0) as num).toDouble();
    final revenue7d = ((data['revenue_last_7d_cents'] ?? 0) as num).toDouble();
    final revenue30d = ((data['revenue_last_30d_cents'] ?? 0) as num).toDouble();
    final mrr = ((data['mrr_cents'] ?? 0) as num).toDouble();
    final activeSubs = (data['active_subscriptions'] ?? 0).toString();

    final recent =
        List<Map<String, dynamic>>.from(data['recent_transactions'] ?? const []);
    final top =
        List<Map<String, dynamic>>.from(data['top_customers'] ?? const []);

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primaryBlue,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStats(revenueToday, revenue7d, revenue30d, mrr, activeSubs),
            const SizedBox(height: AppSpacing.lg),
            RevenueChart(
              title: 'MRR (estimated)',
              subtitle: 'Yearly plans normalized to monthly.',
              points: _mrrPoints,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Recent Transactions',
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            InfinityDataTable(
              layoutType: layoutType,
              columns: const [
                InfinityDataColumn(label: 'ID', keyName: 'transaction_id'),
                InfinityDataColumn(label: 'User', keyName: 'username'),
                InfinityDataColumn(label: 'Provider', keyName: 'payment_provider'),
                InfinityDataColumn(label: 'Amount', keyName: 'amount'),
                InfinityDataColumn(label: 'Status', keyName: 'status'),
                InfinityDataColumn(label: 'Created', keyName: 'created_at'),
              ],
              rows: recent.map((t) {
                final cents = (t['amount_cents'] ?? 0) as num;
                return {
                  ...t,
                  'amount': '\$${(cents.toDouble() / 100.0).toStringAsFixed(2)}',
                };
              }).toList(),
              mobileCardBuilder: (row) => _mobileTxnCard(row),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Top Customers',
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            InfinityDataTable(
              layoutType: layoutType,
              columns: const [
                InfinityDataColumn(label: 'User', keyName: 'username'),
                InfinityDataColumn(label: 'Email', keyName: 'email'),
                InfinityDataColumn(label: 'Spent', keyName: 'spent'),
                InfinityDataColumn(label: 'Credits', keyName: 'credits_purchased'),
              ],
              rows: top.map((c) {
                final cents = (c['spent_cents'] ?? 0) as num;
                return {
                  ...c,
                  'spent': '\$${(cents.toDouble() / 100.0).toStringAsFixed(2)}',
                };
              }).toList(),
              mobileCardBuilder: (row) => _mobileCustomerCard(row),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats(double today, double d7, double d30, double mrr, String subs) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        SizedBox(
          width: 260,
          child: StatCard(
            title: 'Today',
            value: _money(today),
            icon: Icons.today_rounded,
            gradient: AppColors.primaryGradient,
          ),
        ),
        SizedBox(
          width: 260,
          child: StatCard(
            title: 'Last 7 days',
            value: _money(d7),
            icon: Icons.date_range_rounded,
            gradient: AppColors.secondaryGradient,
          ),
        ),
        SizedBox(
          width: 260,
          child: StatCard(
            title: 'Last 30 days',
            value: _money(d30),
            icon: Icons.calendar_month_rounded,
            gradient: AppColors.tealGradient,
          ),
        ),
        SizedBox(
          width: 260,
          child: StatCard(
            title: 'MRR (est.)',
            value: _money(mrr),
            icon: Icons.trending_up_rounded,
            gradient: AppColors.pinkGradient,
          ),
        ),
        SizedBox(
          width: 260,
          child: StatCard(
            title: 'Active subs',
            value: subs,
            icon: Icons.subscriptions_rounded,
            gradient: AppColors.primaryGradient,
          ),
        ),
      ],
    );
  }

  String _money(double cents) => '\$${(cents / 100.0).toStringAsFixed(2)}';

  Widget _mobileTxnCard(Map<String, dynamic> row) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.elevatedCardDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row['transaction_id']?.toString() ?? '',
            style: AppTypography.labelLarge.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${row['username'] ?? ''} • ${row['payment_provider'] ?? ''}',
            style: AppTypography.bodySmall.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${row['amount'] ?? ''} • ${row['status'] ?? ''}',
            style: AppTypography.bodySmall.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _mobileCustomerCard(Map<String, dynamic> row) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.elevatedCardDark,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: AppColors.primaryBlue.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row['username']?.toString() ?? '',
            style: AppTypography.labelLarge.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            row['email']?.toString() ?? '',
            style: AppTypography.bodySmall.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Spent: ${row['spent'] ?? ''}',
            style: AppTypography.bodySmall.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
