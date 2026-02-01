import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/scraper_provider.dart';
import '../providers/scraper_provider.dart' show ScrapingStatus;
import '../services/api_service.dart';
import 'state_selection_screen.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../widgets/gradient_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/custom_text_field.dart';
import '../core/download_helper.dart';

class ScrapingScreen extends StatefulWidget {
  final String initialCategory;
  final String initialCities;
  final String initialMaxResults;

  const ScrapingScreen({
    super.key,
    this.initialCategory = '',
    this.initialCities = '',
    this.initialMaxResults = '10',
  });

  @override
  State<ScrapingScreen> createState() => _ScrapingScreenState();
}

class _ScrapingScreenState extends State<ScrapingScreen>
    with TickerProviderStateMixin {
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _citiesController = TextEditingController();
  final TextEditingController _maxResultsController =
      TextEditingController(text: '10');
  final ApiService _apiService = ApiService();

  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;

  // Credit system state
  int _creditBalance = 0;
  int _estimatedCost = 0;
  bool _loadingCredits = true;
  bool _canCreateJob = true;
  int _jobsInHour = 0;
  int _maxJobsPerHour = 5;

  @override
  void initState() {
    super.initState();
    _categoryController.text = widget.initialCategory;
    _citiesController.text = widget.initialCities;
    _maxResultsController.text = widget.initialMaxResults;

    _fadeController = AnimationController(
      vsync: this,
      duration: AppSpacing.durationMedium,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    _loadCreditBalance();
    _citiesController.addListener(_updateCostEstimate);
    _maxResultsController.addListener(_updateCostEstimate);
  }

  Future<void> _loadCreditBalance() async {
    try {
      final data = await _apiService.getCreditBalance();
      if (mounted) {
        setState(() {
          _creditBalance = data['balance'] ?? 0;
          _canCreateJob = data['rate_limits']?['can_create_job'] ?? true;
          _jobsInHour = data['rate_limits']?['jobs_in_hour'] ?? 0;
          _maxJobsPerHour = data['rate_limits']?['max_jobs_per_hour'] ?? 5;
          _loadingCredits = false;
        });
        _updateCostEstimate();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingCredits = false);
      }
    }
  }

  Future<void> _updateCostEstimate() async {
    final citiesText = _citiesController.text;
    final citiesList = citiesText
        .split(';')
        .map((pair) => pair.trim())
        .where((pair) => pair.isNotEmpty)
        .toList();

    if (citiesList.isEmpty) {
      setState(() => _estimatedCost = 0);
      return;
    }

    final maxResults = int.tryParse(_maxResultsController.text) ?? 10;

    try {
      final data = await _apiService.estimateJobCost(
        numCities: citiesList.length,
        maxResultsPerCity: maxResults,
      );
      if (mounted) {
        setState(() {
          _estimatedCost = data['estimated_cost'] ?? 0;
        });
      }
    } catch (e) {
      // Silently fail - estimate will show 0
    }
  }

  @override
  void dispose() {
    _citiesController.removeListener(_updateCostEstimate);
    _maxResultsController.removeListener(_updateCostEstimate);
    _categoryController.dispose();
    _citiesController.dispose();
    _maxResultsController.dispose();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scraperProvider = Provider.of<ScraperProvider>(context);
    final isRunning = scraperProvider.status == ScrapingStatus.running;
    final isCompleted = scraperProvider.status == ScrapingStatus.completed;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: GradientBackground(
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.md),
                  _buildApiStatusCard(scraperProvider),
                  const SizedBox(height: AppSpacing.md),
                  _buildCreditBalanceCard(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildInputSection(),
                  const SizedBox(height: AppSpacing.md),
                  _buildCostEstimateCard(),
                  const SizedBox(height: AppSpacing.xl),
                  _buildActionButtons(scraperProvider, isRunning),
                  const SizedBox(height: AppSpacing.lg),
                  if (isRunning) _buildProgressCard(scraperProvider),
                  if (isCompleted) _buildCompletionCard(scraperProvider),
                  const SizedBox(height: AppSpacing.lg),
                  _buildLogsCard(scraperProvider),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'Start Lead Search',
        style: AppTypography.headlineSmallLight,
      ),
      centerTitle: true,
    );
  }

  Widget _buildApiStatusCard(ScraperProvider provider) {
    final isConnected = provider.isApiConnected;

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Container(
        decoration: BoxDecoration(
          gradient: isConnected
              ? LinearGradient(
                  colors: [
                    AppColors.success.withValues(alpha: 0.3),
                    AppColors.success.withValues(alpha: 0.1),
                  ],
                )
              : LinearGradient(
                  colors: [
                    AppColors.error.withValues(alpha: 0.3),
                    AppColors.error.withValues(alpha: 0.1),
                  ],
                ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: isConnected ? 1.0 : _pulseAnimation.value,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: isConnected
                          ? AppColors.successGradient
                          : AppColors.errorGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isConnected ? AppColors.success : AppColors.error)
                              .withValues(alpha: 0.4),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      isConnected ? Icons.wifi : Icons.wifi_off,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isConnected ? 'API Connected' : 'API Disconnected',
                    style: AppTypography.titleMediumLight,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isConnected
                        ? 'Ready to discover leads'
                        : 'Please check your connection',
                    style: AppTypography.bodySmallLight,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: (isConnected ? AppColors.success : AppColors.error)
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
                border: Border.all(
                  color: isConnected ? AppColors.success : AppColors.error,
                  width: 1,
                ),
              ),
              child: Text(
                isConnected ? 'ONLINE' : 'OFFLINE',
                style: AppTypography.labelSmall.copyWith(
                  color: isConnected ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditBalanceCard() {
    final hasEnoughCredits = _creditBalance >= _estimatedCost || _estimatedCost == 0;

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: hasEnoughCredits ? AppColors.successGradient : AppColors.warningGradient,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(
              Icons.account_balance_wallet,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Credit Balance',
                  style: AppTypography.labelMedium.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 2),
                _loadingCredits
                    ? SizedBox(
                        width: 60,
                        height: 16,
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.white24,
                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryStart),
                        ),
                      )
                    : Text(
                        '$_creditBalance credits',
                        style: AppTypography.titleMediumLight.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: _canCreateJob ? AppColors.success : AppColors.warning,
                ),
                const SizedBox(width: 4),
                Text(
                  '$_jobsInHour/$_maxJobsPerHour jobs/hr',
                  style: AppTypography.labelSmall.copyWith(
                    color: _canCreateJob ? AppColors.success : AppColors.warning,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCostEstimateCard() {
    if (_estimatedCost == 0) return const SizedBox.shrink();

    final hasEnoughCredits = _creditBalance >= _estimatedCost;
    final balanceAfter = _creditBalance - _estimatedCost;

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: hasEnoughCredits
                ? [AppColors.info.withValues(alpha: 0.2), AppColors.info.withValues(alpha: 0.05)]
                : [AppColors.error.withValues(alpha: 0.2), AppColors.error.withValues(alpha: 0.05)],
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calculate,
                  color: hasEnoughCredits ? AppColors.info : AppColors.error,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Search Cost Estimate',
                  style: AppTypography.labelMedium.copyWith(
                    color: hasEnoughCredits ? AppColors.info : AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCostRow('Cost', '$_estimatedCost credits', hasEnoughCredits ? AppColors.info : AppColors.error),
                _buildCostRow('Balance', '$_creditBalance credits', Colors.white70),
                _buildCostRow(
                  'After',
                  '${balanceAfter >= 0 ? balanceAfter : 0} credits',
                  hasEnoughCredits ? AppColors.success : AppColors.error,
                ),
              ],
            ),
            if (!hasEnoughCredits) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, color: AppColors.error, size: 16),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Insufficient credits. Need ${_estimatedCost - _creditBalance} more.',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCostRow(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(color: Colors.white54),
        ),
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildInputSection() {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(Icons.tune, color: Colors.white, size: 20),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Search Configuration', style: AppTypography.titleMediumLight),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // Category Input
          Text(
            'Lead Category',
            style: AppTypography.labelMedium.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.xs),
          CustomTextField(
            controller: _categoryController,
            hint: 'e.g., Restaurants, Hotels, Shops',
            prefixIcon: Icons.search,
          ),
          const SizedBox(height: AppSpacing.md),

          // Cities Input
          Text(
            'Target Cities',
            style: AppTypography.labelMedium.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.xs),
          CustomTextField(
            controller: _citiesController,
            hint: 'Select cities or enter manually',
            prefixIcon: Icons.location_city,
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.md),

          // Max Results Input
          Text(
            'Results per City',
            style: AppTypography.labelMedium.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.xs),
          CustomTextField(
            controller: _maxResultsController,
            hint: 'Number of results',
            prefixIcon: Icons.format_list_numbered,
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(ScraperProvider provider, bool isRunning) {
    return Row(
      children: [
        Expanded(
          child: GlassCard(
            padding: EdgeInsets.zero,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const StateSelectionScreen(),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryStart.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.map,
                          color: AppColors.secondaryStart,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Select Cities',
                        style: AppTypography.labelMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          flex: 2,
          child: GradientButton(
            text: isRunning ? 'Searching...' : 'Start Search',
            onPressed: isRunning ? null : () => _startScraping(provider),
            gradient: isRunning ? null : AppColors.primaryGradient,
            isLoading: isRunning,
            icon: isRunning ? Icons.hourglass_empty : Icons.rocket_launch,
          ),
        ),
      ],
    );
  }

  Widget _buildProgressCard(ScraperProvider provider) {
    final job = provider.currentJob;
    final progress = (job?.progress ?? 0) / 100;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: AppSpacing.durationMedium,
      builder: (context, value, child) {
        return GlassCard(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryStart.withValues(alpha: 0.2),
                  AppColors.secondaryStart.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                Row(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 60,
                          height: 60,
                          child: CircularProgressIndicator(
                            value: value,
                            strokeWidth: 6,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.secondaryStart,
                            ),
                          ),
                        ),
                        Text(
                          '${(value * 100).toInt()}%',
                          style: AppTypography.labelMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Search in Progress',
                            style: AppTypography.titleMediumLight,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
                            child: LinearProgressIndicator(
                              value: value,
                              minHeight: 8,
                              backgroundColor: Colors.white24,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.secondaryStart,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Collecting lead data...',
                            style: AppTypography.bodySmallLight,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (job?.currentCity != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      border: Border.all(
                        color: AppColors.info.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: AppColors.info,
                          size: 16,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'Currently searching: ${job?.currentCity}',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      provider.reset();
                      _showSnackBar('Search stopped', AppColors.warning);
                    },
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Stop Search'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompletionCard(ScraperProvider provider) {
    final resultsCount = provider.currentJob?.results.length ?? 0;

    return GlassCard(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.success.withValues(alpha: 0.3),
              AppColors.success.withValues(alpha: 0.1),
            ],
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: AppColors.successGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.success.withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Search Completed!',
                        style: AppTypography.titleMediumLight,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xxs,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
                            ),
                            child: Text(
                              '$resultsCount results found',
                              style: AppTypography.labelSmall.copyWith(
                                color: Colors.white,
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
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      provider.reset();
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('New Search'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _downloadResults(provider),
                    icon: const Icon(Icons.download, size: 20),
                    label: const Text('Download'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
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

  Widget _buildLogsCard(ScraperProvider provider) {
    final logs = provider.getCurrentLogs();

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  Icons.terminal,
                  color: AppColors.info,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Activity Logs', style: AppTypography.titleMediumLight),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
                ),
                child: Text(
                  '${logs.length} entries',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.info,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.hourglass_empty,
                          color: Colors.white30,
                          size: 32,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'No activity yet',
                          style: AppTypography.bodySmall.copyWith(
                            color: Colors.white30,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final isError = log.toLowerCase().contains('error');
                      final isSuccess = log.toLowerCase().contains('success') ||
                          log.toLowerCase().contains('completed');

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '> ',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: isError
                                    ? AppColors.error
                                    : isSuccess
                                        ? AppColors.success
                                        : AppColors.info,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                log,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: isError
                                      ? AppColors.error.withValues(alpha: 0.9)
                                      : isSuccess
                                          ? AppColors.success.withValues(alpha: 0.9)
                                          : Colors.white70,
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
    );
  }

  Future<void> _startScraping(ScraperProvider provider) async {
    if (_categoryController.text.isEmpty) {
      _showSnackBar('Please enter a search category', AppColors.error);
      return;
    }

    if (_citiesController.text.isEmpty) {
      _showSnackBar('Please select cities', AppColors.error);
      return;
    }

    // Check credit balance
    if (_creditBalance < _estimatedCost) {
      _showSnackBar('Insufficient credits. Need $_estimatedCost, have $_creditBalance', AppColors.error);
      return;
    }

    // Check rate limits
    if (!_canCreateJob) {
      _showSnackBar('Rate limit reached. Try again later.', AppColors.warning);
      return;
    }

    try {
      final citiesText = _citiesController.text;
      final citiesList = citiesText
          .split(';')
          .map((pair) => pair.trim())
          .where((pair) => pair.isNotEmpty)
          .toList();

      if (citiesList.isEmpty) {
        _showSnackBar('No valid cities found', AppColors.error);
        return;
      }

      final maxResults = int.tryParse(_maxResultsController.text) ?? 10;
      if (maxResults <= 0) {
        _showSnackBar('Max results must be greater than 0', AppColors.error);
        return;
      }

      await provider.startScraping(
        category: _categoryController.text,
        citiesData: citiesList,
        maxResultsPerCity: maxResults,
      );

      _showSnackBar('Search started! $_estimatedCost credits charged.', AppColors.success);

      // Refresh credit balance
      _loadCreditBalance();
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('402') || errorMsg.contains('Insufficient credits')) {
        _showSnackBar('Insufficient credits for this job', AppColors.error);
      } else if (errorMsg.contains('429') || errorMsg.contains('Rate limit')) {
        _showSnackBar('Rate limit reached. Try again later.', AppColors.warning);
      } else {
        _showSnackBar('Failed to start search: $e', AppColors.error);
      }
      // Refresh credit balance in case of error
      _loadCreditBalance();
    }
  }

  Future<void> _downloadResults(ScraperProvider provider) async {
    try {
      final csvData = await provider.downloadResults();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'scraping_results_$timestamp';

      if (!mounted) return;

      final success = await saveCsv(jsonEncode(csvData), fileName, context: context);

      if (!success && mounted) {
        _showSnackBar('Download failed', AppColors.error);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to download results: $e', AppColors.error);
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == AppColors.success
                  ? Icons.check_circle
                  : color == AppColors.error
                      ? Icons.error
                      : Icons.info,
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
        margin: const EdgeInsets.all(AppSpacing.md),
      ),
    );
  }
}
