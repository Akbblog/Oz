import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/scraper_provider.dart';
import '../services/api_service.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/responsive_utils.dart';
import 'results_screen.dart';

class ScrapingScreen extends StatefulWidget {
  final String initialCategory;
  final String initialCities;
  final String initialMaxResults;
  final bool showHeader;

  const ScrapingScreen({
    super.key,
    this.initialCategory = '',
    this.initialCities = '',
    this.initialMaxResults = '50',
    this.showHeader = true,
  });

  @override
  State<ScrapingScreen> createState() => _ScrapingScreenState();
}

class _ScrapingScreenState extends State<ScrapingScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _citiesController = TextEditingController();
  final ApiService _apiService = ApiService();

  int _maxResults = 50;
  int _creditBalance = 0;
  int _estimatedCost = 0;
  bool _loadingCredits = true;
  bool _canCreateJob = true;
  String? _lastCompletedJobId; // Track job completion for auto-navigation

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _categoryController.text = widget.initialCategory;
    _citiesController.text = widget.initialCities;
    _maxResults = int.tryParse(widget.initialMaxResults) ?? 50;

    _fadeController = AnimationController(
      vsync: this,
      duration: AppSpacing.durationMedium,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    _loadCreditBalance();
    _citiesController.addListener(_updateCostEstimate);

    // Listen for job completion to auto-navigate
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupJobCompletionListener();
    });
  }

  void _setupJobCompletionListener() {
    final provider = Provider.of<ScraperProvider>(context, listen: false);
    provider.addListener(() {
      final job = provider.currentJob;
      if (job != null &&
          job.status == ScrapingStatus.completed &&
          _lastCompletedJobId != job.jobId) {
        _lastCompletedJobId = job.jobId;
        _navigateToResults(job.jobId);
      }
    });
  }

  void _navigateToResults(String jobId) {
    if (!mounted) return;

    // Auto-navigate with animation
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return ResultsScreen(jobId: jobId, showHeader: widget.showHeader);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.3),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );

    // Show success toast
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('Search completed! Navigating to results...'),
            ],
          ),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  void dispose() {
    _citiesController.removeListener(_updateCostEstimate);
    _categoryController.dispose();
    _citiesController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadCreditBalance() async {
    try {
      final data = await _apiService.getCreditBalance();
      if (mounted) {
        setState(() {
          _creditBalance = data['balance'] ?? 0;
          _canCreateJob = data['rate_limits']?['can_create_job'] ?? true;
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

  List<String> _parseCities() {
    final text = _citiesController.text.trim();
    if (text.isEmpty) return [];
    return text
        .split(RegExp(r'[;\n]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<void> _updateCostEstimate() async {
    final cities = _parseCities();
    if (cities.isEmpty) {
      setState(() => _estimatedCost = 0);
      return;
    }

    try {
      final data = await _apiService.estimateJobCost(
        numCities: cities.length,
        maxResultsPerCity: _maxResults,
      );
      if (mounted) {
        setState(() {
          _estimatedCost = data['estimated_cost'] ?? 0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _estimatedCost = 0);
      }
    }
  }

  Future<void> _startScraping(ScraperProvider provider) async {
    final category = _categoryController.text.trim();
    final cities = _parseCities();

    if (category.isEmpty || cities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter category and cities')),
      );
      return;
    }

    if (!_canCreateJob) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rate limit reached. Try again later.')),
      );
      return;
    }

    await provider.startScraping(
      category: category,
      citiesData: cities,
      maxResultsPerCity: _maxResults,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final scraperProvider = Provider.of<ScraperProvider>(context);
    final isRunning = scraperProvider.status == ScrapingStatus.running;
    final progress = scraperProvider.currentJob?.progress ?? 0;
    final logs = scraperProvider.getCurrentLogs();
    final layoutType =
        AppBreakpoints.getLayoutType(MediaQuery.of(context).size.width);

    return Scaffold(
      backgroundColor: _ScrapeColors.background,
      body: SafeArea(
        top: widget.showHeader,
        bottom: false,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: layoutType == LayoutType.mobile
              ? Column(
                  children: [
                    if (widget.showHeader) _buildHeader(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.md,
                          AppSpacing.xl,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildStatsRow(scraperProvider, layoutType),
                            const SizedBox(height: AppSpacing.lg),
                            _buildConfigSection(),
                            const SizedBox(height: AppSpacing.lg),
                            _buildStartButton(scraperProvider, isRunning),
                            const SizedBox(height: AppSpacing.lg),
                            _buildActivitySection(progress, logs, isRunning),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    if (widget.showHeader) _buildHeader(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          ResponsiveUtils.getScreenPadding(layoutType),
                          ResponsiveUtils.getScreenPadding(layoutType),
                          ResponsiveUtils.getScreenPadding(layoutType),
                          AppSpacing.xl,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildStatsRow(scraperProvider, layoutType),
                            const SizedBox(height: AppSpacing.lg),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: layoutType == LayoutType.desktopSmall
                                      ? 45
                                      : 40,
                                  child: Column(
                                    children: [
                                      _buildConfigSection(),
                                      const SizedBox(height: AppSpacing.lg),
                                      _buildStartButton(
                                          scraperProvider, isRunning),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(
                                  flex: layoutType == LayoutType.desktopSmall
                                      ? 55
                                      : 60,
                                  child: _buildActivitySection(
                                      progress, logs, isRunning),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
        color: _ScrapeColors.background.withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _ScrapeColors.card,
              borderRadius: AppSpacing.borderRadiusRound,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: const Icon(
              Icons.search_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Scrape Config',
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(ScraperProvider provider, LayoutType layoutType) {
    final apiOnline = provider.isApiConnected;
    final cards = [
      _statCard(
        title: 'API Status',
        value: apiOnline ? 'ONLINE' : 'OFFLINE',
        icon: Icons.wifi,
        accent: apiOnline ? _ScrapeColors.emerald : _ScrapeColors.rose,
        extra: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: apiOnline ? _ScrapeColors.emerald : _ScrapeColors.rose,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              apiOnline ? 'Connected' : 'Disconnected',
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
      _statCard(
        title: 'Est. Cost',
        value: _loadingCredits ? '...' : '$_estimatedCost Credits',
        icon: Icons.monetization_on_rounded,
        accent: _ScrapeColors.primary,
        extra: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: _creditBalance == 0
                    ? 0
                    : (_estimatedCost / _creditBalance).clamp(0, 1),
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(
                  _ScrapeColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
      _statCard(
        title: 'Credit Balance',
        value: _loadingCredits ? '...' : '$_creditBalance Credits',
        icon: Icons.account_balance_wallet_rounded,
        accent: _ScrapeColors.primaryLight,
      ),
      _statCard(
        title: 'Results/City',
        value: '$_maxResults Leads',
        icon: Icons.list_alt_rounded,
        accent: _ScrapeColors.emerald,
      ),
    ];

    if (layoutType == LayoutType.mobile || layoutType == LayoutType.tablet) {
      return Row(
        children: [
          Expanded(child: cards[0]),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: cards[1]),
        ],
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: layoutType == LayoutType.desktopSmall ? 3 : 4,
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.6,
      children: cards,
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accent,
    Widget? extra,
  }) {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: _ScrapeColors.card,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: accent.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 14,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white70,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(icon, color: accent, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (extra != null) extra,
        ],
      ),
    );
  }

  Widget _buildConfigSection() {
    final cities = _parseCities();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tune_rounded, color: _ScrapeColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'Target Criteria',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white70,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _buildInputField(
          label: 'Lead Category',
          controller: _categoryController,
          hint: 'Software Companies',
          icon: Icons.business_center_rounded,
        ),
        const SizedBox(height: AppSpacing.md),
        _buildInputField(
          label: 'Target Cities',
          controller: _citiesController,
          hint: 'Add location...',
          icon: Icons.location_on_rounded,
        ),
        if (cities.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: cities.map((city) => _cityChip(city)).toList(),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        _buildSlider(),
      ],
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: AppTypography.bodyMedium.copyWith(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTypography.bodySmall.copyWith(
              color: Colors.white54,
            ),
            filled: true,
            fillColor: _ScrapeColors.input,
            border: OutlineInputBorder(
              borderRadius: AppSpacing.borderRadiusLg,
              borderSide: BorderSide(
                color: _ScrapeColors.primary.withValues(alpha: 0.3),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppSpacing.borderRadiusLg,
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppSpacing.borderRadiusLg,
              borderSide: BorderSide(
                color: _ScrapeColors.primary,
              ),
            ),
            suffixIcon: Icon(icon, color: _ScrapeColors.primary),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
          ),
          onChanged: (_) => _updateCostEstimate(),
        ),
      ],
    );
  }

  Widget _cityChip(String city) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: _ScrapeColors.primary.withValues(alpha: 0.12),
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(
          color: _ScrapeColors.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            city,
            style: AppTypography.labelSmall.copyWith(
              color: _ScrapeColors.primaryLight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Results per City',
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$_maxResults Leads',
              style: AppTypography.bodySmall.copyWith(
                color: _ScrapeColors.primaryLight,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: _ScrapeColors.input,
            borderRadius: AppSpacing.borderRadiusLg,
            border: Border.all(
              color: _ScrapeColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Slider(
            value: _maxResults.toDouble(),
            min: 10,
            max: 500,
            divisions: 49,
            activeColor: _ScrapeColors.primary,
            inactiveColor: Colors.white24,
            onChanged: (value) {
              setState(() {
                _maxResults = value.round();
              });
              _updateCostEstimate();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStartButton(ScraperProvider provider, bool isRunning) {
    return GestureDetector(
      onTap: isRunning ? null : () => _startScraping(provider),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_ScrapeColors.primary, _ScrapeColors.primaryLight],
          ),
          borderRadius: AppSpacing.borderRadiusLg,
          boxShadow: [
            BoxShadow(
              color: _ScrapeColors.primary.withValues(alpha: 0.4),
              blurRadius: 18,
              spreadRadius: -8,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.rocket_launch_rounded, color: Colors.white),
            const SizedBox(width: AppSpacing.sm),
            Text(
              isRunning ? 'Running...' : 'Start Search',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivitySection(
      int progress, List<String> logs, bool isRunning) {
    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: _ScrapeColors.card,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _ScrapeColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Activity Log',
                    style: AppTypography.labelLarge.copyWith(
                      color: Colors.white70,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              Text(
                'v2.4.1',
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white54,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _buildProgressCircle(progress, isRunning),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildLogBox(logs),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCircle(int progress, bool isRunning) {
    final value = (progress / 100).clamp(0.0, 1.0);
    return Column(
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: value,
                strokeWidth: 6,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _ScrapeColors.primary,
                ),
              ),
              Text(
                '${progress.clamp(0, 100)}%',
                style: AppTypography.labelLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isRunning ? 'Processing' : 'Idle',
          style: AppTypography.labelSmall.copyWith(
            color: _ScrapeColors.primaryLight,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildLogBox(List<String> logs) {
    final displayLogs = logs.isEmpty
        ? ['> Waiting for job to start...']
        : logs.take(6).toList();

    return Container(
      padding: AppSpacing.paddingSm,
      decoration: BoxDecoration(
        color: _ScrapeColors.terminal,
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: SizedBox(
        height: 96,
        child: ListView.builder(
          itemCount: displayLogs.length,
          itemBuilder: (context, index) {
            final line = displayLogs[index];
            final color = line.contains('error')
                ? _ScrapeColors.rose
                : line.contains('Extracting')
                    ? _ScrapeColors.primary
                    : Colors.white70;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: AppTypography.labelSmall.copyWith(
                  color: color,
                  fontFamily: 'monospace',
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ScrapeColors {
  static const Color background = Color(0xFF0F111A);
  static const Color card = Color(0xFF161826);
  static const Color input = Color(0xFF1E2133);
  static const Color primary = Color(0xFF311FF9);
  static const Color primaryLight = Color(0xFF6366F1);
  static const Color emerald = Color(0xFF10B981);
  static const Color rose = Color(0xFFFB7185);
  static const Color terminal = Color(0xFF0A0C14);
}
