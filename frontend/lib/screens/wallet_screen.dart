import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/responsive_utils.dart';
import '../services/api_service.dart';
import '../widgets/low_balance_alert.dart';
import '../widgets/subscription_status_banner.dart';
import 'pricing_screen.dart';
import 'subscription_management_screen.dart';

class WalletScreen extends StatefulWidget {
  final bool enableLivePayments;
  final int initialTabIndex;

  const WalletScreen({
    super.key,
    this.enableLivePayments = true,
    this.initialTabIndex = 0,
  });

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  bool _isLoading = true;
  String? _error;
  int _creditBalance = 0;
  Map<String, dynamic>? _subscription;
  List<Map<String, dynamic>> _creditHistory = [];
  List<Map<String, dynamic>> _paymentTransactions = [];
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _creditRequests = [];
  bool _alertDismissed = false;

  bool _loadingSubscription = false;
  bool _loadingCreditHistory = false;
  bool _loadingPaymentTransactions = false;
  bool _loadingInvoices = false;
  bool _loadingCreditRequests = false;

  late final List<String> _historyTabs = widget.enableLivePayments
      ? const ['Credits', 'Payments', 'Invoices', 'Requests']
      : const ['Credits', 'Requests'];

  @override
  void initState() {
    super.initState();
    final tabCount = _historyTabs.length;
    final initialIndex = widget.initialTabIndex.clamp(0, tabCount - 1);
    _tabController = TabController(
        length: tabCount, vsync: this, initialIndex: initialIndex);
    _tabController.addListener(_onTabChanged);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _ensureTabLoaded(_tabController.index);
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _subscription = null;
      _creditHistory = [];
      _paymentTransactions = [];
      _invoices = [];
      _creditRequests = [];
      _loadingSubscription = false;
      _loadingCreditHistory = false;
      _loadingPaymentTransactions = false;
      _loadingInvoices = false;
      _loadingCreditRequests = false;
    });

    try {
      // Phase 1 (critical): credit balance
      Map<String, dynamic> creditBalance = {};
      try {
        creditBalance = await _apiService.getCreditBalance();
      } catch (e) {
        print('Failed to load credit balance: $e');
        if (mounted) {
          setState(() {
            final errorStr = e.toString();
            if (errorStr.contains('401') || errorStr.contains('Unauthorized')) {
              _error = 'You must be logged in to view your wallet';
            } else {
              _error = 'Failed to load wallet balance: $e';
            }
            _isLoading = false;
          });
        }
        return;
      }

      if (!mounted) return;
      setState(() {
        final map = Map<String, dynamic>.from(creditBalance);
        final rawBalance = map['balance'];
        _creditBalance = rawBalance is num
            ? rawBalance.toInt()
            : (rawBalance is String ? int.tryParse(rawBalance) ?? 0 : 0);
        _isLoading = false;
      });

      // Phase 2 (non-blocking): load secondary data lazily.
      _loadSubscription();

      // Requests are used for the quick-action badge; load early.
      _loadCreditRequests();

      // Invoices badge is shown in quick actions (when enabled); load early.
      if (widget.enableLivePayments) {
        _loadInvoices();
      }

      _ensureTabLoaded(_tabController.index);
    } catch (e) {
      if (mounted) {
        setState(() {
          // Check if it's likely an auth error
          final errorStr = e.toString();
          if (errorStr.contains('401') || errorStr.contains('Unauthorized')) {
            _error = 'You must be logged in to view your wallet';
          } else {
            _error = 'Failed to load wallet data: $e';
          }
          _isLoading = false;
        });
        print('Wallet error: $e');
      }
    }
  }

  void _ensureTabLoaded(int index) {
    if (widget.enableLivePayments) {
      if (index == 0) _loadCreditHistory();
      if (index == 1) _loadPaymentTransactions();
      if (index == 2) _loadInvoices();
      if (index == 3) _loadCreditRequests();
      return;
    }

    // Live payments disabled: only credits + requests tabs are available.
    if (index == 0) _loadCreditHistory();
    if (index == 1) _loadCreditRequests();
  }

  Future<void> _loadSubscription() async {
    if (_loadingSubscription) return;
    setState(() => _loadingSubscription = true);
    try {
      final sub = await _apiService.getMySubscription();
      if (!mounted) return;
      final map = Map<String, dynamic>.from(sub);
      setState(() {
        _subscription = map.isEmpty ? null : map;
      });
    } catch (e) {
      print('Failed to load subscription: $e');
    } finally {
      if (mounted) setState(() => _loadingSubscription = false);
    }
  }

  Future<void> _loadCreditHistory() async {
    if (_loadingCreditHistory) return;
    setState(() => _loadingCreditHistory = true);
    try {
      final items = await _apiService.getCreditHistory();
      if (!mounted) return;
      setState(() {
        _creditHistory = items;
      });
    } catch (e) {
      print('Failed to load credit history: $e');
    } finally {
      if (mounted) setState(() => _loadingCreditHistory = false);
    }
  }

  Future<void> _loadPaymentTransactions() async {
    if (!widget.enableLivePayments) return;
    if (_loadingPaymentTransactions) return;
    setState(() => _loadingPaymentTransactions = true);
    try {
      final items = await _apiService.getPaymentTransactions();
      if (!mounted) return;
      setState(() {
        _paymentTransactions = items;
      });
    } catch (e) {
      print('Failed to load payment transactions: $e');
    } finally {
      if (mounted) setState(() => _loadingPaymentTransactions = false);
    }
  }

  Future<void> _loadInvoices() async {
    if (!widget.enableLivePayments) return;
    if (_loadingInvoices) return;
    setState(() => _loadingInvoices = true);
    try {
      final items = await _apiService.getInvoices();
      if (!mounted) return;
      setState(() {
        _invoices = items;
      });
    } catch (e) {
      print('Failed to load invoices: $e');
    } finally {
      if (mounted) setState(() => _loadingInvoices = false);
    }
  }

  Future<void> _loadCreditRequests() async {
    if (_loadingCreditRequests) return;
    setState(() => _loadingCreditRequests = true);
    try {
      final items = await _apiService.getMyCreditRequests();
      if (!mounted) return;
      setState(() {
        _creditRequests = items;
      });
    } catch (e) {
      print('Failed to load credit requests: $e');
    } finally {
      if (mounted) setState(() => _loadingCreditRequests = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layoutType =
        AppBreakpoints.getLayoutType(MediaQuery.of(context).size.width);
    final contentPadding = EdgeInsets.all(
      ResponsiveUtils.getScreenPadding(layoutType),
    );

    return Scaffold(
      backgroundColor: _WalletColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            _buildBackground(),
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _isLoading
                      ? const SizedBox.expand(
                          child: Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _WalletColors.primary,
                              ),
                            ),
                          ),
                        )
                      : _error != null
                          ? SizedBox.expand(child: _buildError())
                          : RefreshIndicator(
                              onRefresh: _loadData,
                              child: NestedScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                headerSliverBuilder: (context, _) {
                                  return [
                                    SliverPadding(
                                      padding: contentPadding,
                                      sliver: SliverToBoxAdapter(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (!_alertDismissed)
                                              LowBalanceAlert(
                                                currentBalance: _creditBalance,
                                                onBuyCredits: () => widget
                                                        .enableLivePayments
                                                    ? _navigateToPricing()
                                                    : _showCreditRequestDialog(),
                                                onDismiss: () => setState(() =>
                                                    _alertDismissed = true),
                                              ),
                                            _buildBalanceCard(),
                                            const SizedBox(
                                                height: AppSpacing.md),
                                            SubscriptionStatusBanner(
                                              subscription: _subscription,
                                              onManage: () =>
                                                  Navigator.of(context).push(
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      const SubscriptionManagementScreen(),
                                                ),
                                              ),
                                              onUpgrade: () => widget
                                                      .enableLivePayments
                                                  ? _navigateToPricing()
                                                  : _showCreditRequestDialog(),
                                            ),
                                            const SizedBox(
                                                height: AppSpacing.lg),
                                            _buildQuickActions(),
                                            const SizedBox(
                                                height: AppSpacing.lg),
                                            _buildHistoryHeader(),
                                            const SizedBox(
                                                height: AppSpacing.md),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ];
                                },
                                body: Padding(
                                  padding: contentPadding,
                                  child: TabBarView(
                                    controller: _tabController,
                                    children: widget.enableLivePayments
                                        ? [
                                            _buildCreditHistory(),
                                            _buildPaymentHistory(),
                                            _buildInvoiceList(),
                                            _buildCreditRequestHistory(),
                                          ]
                                        : [
                                            _buildCreditHistory(),
                                            _buildCreditRequestHistory(),
                                          ],
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
    );
  }

  void _navigateToPricing() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const PricingScreen()),
    );
  }

  Widget _buildBackground() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              _WalletColors.primary.withValues(alpha: 0.2),
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
        color: _WalletColors.background.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          Expanded(
            child: Text(
              'Wallet',
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

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingLg,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _WalletColors.primary.withValues(alpha: 0.3),
            _WalletColors.primary.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: _WalletColors.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CREDIT BALANCE',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white60,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$_creditBalance',
                style: AppTypography.displaySmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'credits',
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white54,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: widget.enableLivePayments
                ? _navigateToPricing
                : _showCreditRequestDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: AppSpacing.borderRadiusMd,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.enableLivePayments ? Icons.add : Icons.trending_up,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.enableLivePayments
                        ? 'Buy Credits'
                        : 'Request Credits',
                    style: AppTypography.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final cards = <Widget>[];

    if (widget.enableLivePayments) {
      cards.add(
        _quickActionCard(
          icon: Icons.credit_card,
          label: 'Payment\nMethods',
          onTap: () => Navigator.of(context).pushNamed('/payment-methods'),
        ),
      );
      cards.add(
        _quickActionCard(
          icon: Icons.receipt_long,
          label: 'Invoices',
          badge: _invoices.isNotEmpty ? _invoices.length.toString() : null,
          onTap: () {
            _tabController.animateTo(2);
          },
        ),
      );
    }

    cards.add(
      _quickActionCard(
        icon: Icons.card_giftcard,
        label: 'Referrals',
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Referral program coming soon!')),
          );
        },
      ),
    );

    cards.add(
      _quickActionCard(
        icon: Icons.trending_up,
        label: 'Request\nCredits',
        badge: _creditRequests.isNotEmpty &&
                _creditRequests.any((r) => r['status'] == 'pending')
            ? _creditRequests
                .where((r) => r['status'] == 'pending')
                .length
                .toString()
            : null,
        onTap: _showCreditRequestDialog,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;
        if (isWide) {
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i != cards.length - 1) const SizedBox(width: AppSpacing.sm),
              ],
            ],
          );
        }

        const cardWidth = 152.0;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                SizedBox(width: cardWidth, child: cards[i]),
                if (i != cards.length - 1) const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'History',
          style: AppTypography.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: _WalletColors.surface.withValues(alpha: 0.3),
            borderRadius: AppSpacing.borderRadiusMd,
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: AppSpacing.borderRadiusMd,
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            labelStyle:
                AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w700),
            unselectedLabelStyle: AppTypography.labelMedium,
            tabs: [
              for (final label in _historyTabs) Tab(text: label),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickActionCard({
    required IconData icon,
    required String label,
    String? badge,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: _WalletColors.surface.withValues(alpha: 0.4),
          borderRadius: AppSpacing.borderRadiusLg,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _WalletColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: _WalletColors.primary, size: 22),
                ),
                if (badge != null)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: AppColors.dangerRed,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditHistory() {
    if (_loadingCreditHistory && _creditHistory.isEmpty) {
      return _buildLoadingList();
    }
    if (_creditHistory.isEmpty) {
      return _buildEmptyList('No credit transactions yet.');
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _creditHistory.length,
      itemBuilder: (context, index) {
        final tx = _creditHistory[index];
        final type = tx['type'] ?? '';
        final isCredit = type == 'credit';
        final amount = tx['amount'] ?? 0;
        final description = tx['description'] ?? '';
        final createdAt = tx['created_at'] ?? '';

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          padding: AppSpacing.paddingSm,
          decoration: BoxDecoration(
            color: _WalletColors.surface.withValues(alpha: 0.2),
            borderRadius: AppSpacing.borderRadiusSm,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      (isCredit ? AppColors.successGreen : AppColors.dangerRed)
                          .withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCredit ? Icons.add : Icons.remove,
                  color:
                      isCredit ? AppColors.successGreen : AppColors.dangerRed,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      style: AppTypography.labelMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      createdAt,
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${isCredit ? '+' : '-'}$amount',
                style: AppTypography.labelLarge.copyWith(
                  color:
                      isCredit ? AppColors.successGreen : AppColors.dangerRed,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPaymentHistory() {
    if (!widget.enableLivePayments) {
      return _buildEmptyList('Payments are coming soon.');
    }
    if (_loadingPaymentTransactions && _paymentTransactions.isEmpty) {
      return _buildLoadingList();
    }
    if (_paymentTransactions.isEmpty) {
      return _buildEmptyList('No payment transactions yet.');
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _paymentTransactions.length,
      itemBuilder: (context, index) {
        final tx = _paymentTransactions[index];
        final status = tx['status'] ?? 'pending';
        final amountCents = tx['amount_cents'] ?? 0;
        final amount = (amountCents / 100).toStringAsFixed(2);
        final credits = tx['credits_purchased'] ?? 0;
        final provider = tx['payment_provider'] ?? 'coinbase';
        final createdAt = tx['created_at'] ?? '';

        final statusColor = _getStatusColor(status);

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          padding: AppSpacing.paddingSm,
          decoration: BoxDecoration(
            color: _WalletColors.surface.withValues(alpha: 0.2),
            borderRadius: AppSpacing.borderRadiusSm,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  provider == 'coinbase'
                      ? Icons.currency_bitcoin
                      : Icons.credit_card,
                  color: statusColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$credits credits',
                      style: AppTypography.labelMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          status,
                          style: AppTypography.bodySmall.copyWith(
                            color: statusColor,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          createdAt,
                          style: AppTypography.bodySmall.copyWith(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                '\$$amount',
                style: AppTypography.labelLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInvoiceList() {
    if (!widget.enableLivePayments) {
      return _buildEmptyList('Invoices are coming soon.');
    }
    if (_loadingInvoices && _invoices.isEmpty) {
      return _buildLoadingList();
    }
    if (_invoices.isEmpty) {
      return _buildEmptyList('No invoices yet.');
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _invoices.length,
      itemBuilder: (context, index) {
        final inv = _invoices[index];
        final invoiceNumber = inv['invoice_number'] ?? '';
        final totalCents = inv['total_amount_cents'] ?? 0;
        final total = (totalCents / 100).toStringAsFixed(2);
        final status = inv['status'] ?? 'paid';
        final createdAt = inv['created_at'] ?? '';
        final invoiceId = inv['id'];

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          padding: AppSpacing.paddingSm,
          decoration: BoxDecoration(
            color: _WalletColors.surface.withValues(alpha: 0.2),
            borderRadius: AppSpacing.borderRadiusSm,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _WalletColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.receipt_long,
                  color: _WalletColors.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoiceNumber,
                      style: AppTypography.labelMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '$status - $createdAt',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '\$$total',
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              GestureDetector(
                onTap: () async {
                  if (invoiceId != null) {
                    try {
                      await _apiService.downloadInvoice(invoiceId);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invoice downloaded.')),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Download failed: $e')),
                        );
                      }
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: AppSpacing.borderRadiusSm,
                  ),
                  child: const Icon(
                    Icons.download,
                    color: Colors.white54,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyList(String message) {
    return SizedBox.expand(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_rounded, color: Colors.white24, size: 40),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.bodySmall.copyWith(color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingList() {
    return const SizedBox.expand(
      child: Center(
        child: CircularProgressIndicator(color: _WalletColors.primary),
      ),
    );
  }

  Widget _buildCreditRequestHistory() {
    if (_loadingCreditRequests && _creditRequests.isEmpty) {
      return _buildLoadingList();
    }
    if (_creditRequests.isEmpty) {
      return _buildEmptyList('No credit requests yet.');
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _creditRequests.length,
      itemBuilder: (context, index) {
        final req = _creditRequests[index];
        final id = req['id'];
        final amount = req['amount_requested'] ?? 0;
        final reason = req['reason'] ?? 'No reason provided';
        final status = req['status'] ?? 'pending';
        final adminNote = req['admin_note'];
        final createdAt = req['created_at'] ?? '';

        final statusColor = _getStatusColor(status);

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.xs),
          padding: AppSpacing.paddingSm,
          decoration: BoxDecoration(
            color: _WalletColors.surface.withValues(alpha: 0.2),
            borderRadius: AppSpacing.borderRadiusSm,
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
                      color: statusColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      status == 'approved'
                          ? Icons.check_circle
                          : status == 'denied'
                              ? Icons.cancel
                              : Icons.schedule,
                      color: statusColor,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$amount credits requested',
                          style: AppTypography.labelMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              status,
                              style: AppTypography.bodySmall.copyWith(
                                color: statusColor,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              createdAt,
                              style: AppTypography.bodySmall.copyWith(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Reason: $reason',
                style: AppTypography.bodySmall.copyWith(
                  color: Colors.white70,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (adminNote != null && adminNote.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: AppSpacing.paddingSm,
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: AppSpacing.borderRadiusSm,
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Admin Note',
                        style: AppTypography.labelSmall.copyWith(
                          color: Colors.red.shade400,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        adminNote,
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white70,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

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
              color: _WalletColors.surface,
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
                        _WalletColors.primary.withValues(alpha: 0.12),
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
                              _WalletColors.primary.withValues(alpha: 0.3),
                              _WalletColors.primary.withValues(alpha: 0.15),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _WalletColors.primary.withValues(alpha: 0.3),
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
                                  _WalletColors.primary.withValues(alpha: 0.7),
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
                                  _WalletColors.primary.withValues(alpha: 0.6),
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
                                  _WalletColors.primary.withValues(alpha: 0.6),
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

                                        try {
                                          await _apiService.requestCredits(
                                            amount: amount,
                                            reason:
                                                reasonController.text.isEmpty
                                                    ? null
                                                    : reasonController.text,
                                          );

                                          if (mounted) {
                                            Navigator.pop(context);
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Credit request submitted successfully'),
                                                backgroundColor:
                                                    AppColors.successGreen,
                                              ),
                                            );

                                            await Future.delayed(const Duration(
                                                milliseconds: 1500));
                                            if (mounted) {
                                              Navigator.of(context)
                                                  .pushNamedAndRemoveUntil(
                                                '/home',
                                                (route) => false,
                                              );
                                            }
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            setState(
                                                () => isSubmitting = false);
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    'Failed to submit request: $e'),
                                                backgroundColor:
                                                    AppColors.dangerRed,
                                              ),
                                            );
                                          }
                                        }
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _WalletColors.primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: _WalletColors.primary
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.successGreen;
      case 'pending':
      case 'processing':
        return const Color(0xFFF59E0B);
      case 'failed':
        return AppColors.dangerRed;
      case 'refunded':
        return const Color(0xFF60A5FA);
      default:
        return Colors.white54;
    }
  }
}

class _WalletColors {
  static const Color primary = AppColors.primaryBlue;
  static const Color background = AppColors.backgroundDark;
  static const Color surface = AppColors.elevatedCardDark;
}
