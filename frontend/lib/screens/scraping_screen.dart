import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../providers/scraper_provider.dart';
import '../services/api_service.dart';
import '../core/download_helper.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/responsive_utils.dart';
import '../widgets/progress_stepper.dart';
import 'results_screen.dart';

class ScrapingScreen extends StatefulWidget {
  final String initialCategory;
  final String initialCities;
  final String initialMaxResults;
  final bool showHeader;
  final VoidCallback? onBackToCities;

  const ScrapingScreen({
    super.key,
    this.initialCategory = '',
    this.initialCities = '',
    this.initialMaxResults = '50',
    this.showHeader = true,
    this.onBackToCities,
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
  String _logFilter = 'All'; // All, Errors
  bool _attemptedStart = false;
  bool _draftLoaded = false;

  static const String _searchDraftKey = 'wizard_search_draft_v1';

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _categoryController.text = widget.initialCategory;
    _citiesController.text = widget.initialCities;
    _maxResults = int.tryParse(widget.initialMaxResults) ?? 50;
    _loadSearchDraftIfNeeded();

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

  @override
  void didUpdateWidget(covariant ScrapingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final provider = Provider.of<ScraperProvider>(context, listen: false);
    final isRunning = provider.status == ScrapingStatus.running;
    if (isRunning) return;

    final citiesChanged = widget.initialCities != oldWidget.initialCities &&
        widget.initialCities.trim().isNotEmpty;
    final categoryChanged = widget.initialCategory != oldWidget.initialCategory &&
        widget.initialCategory.trim().isNotEmpty;
    final maxChanged = widget.initialMaxResults != oldWidget.initialMaxResults &&
        widget.initialMaxResults.trim().isNotEmpty;

    if (!citiesChanged && !categoryChanged && !maxChanged) return;

    setState(() {
      if (citiesChanged) _citiesController.text = widget.initialCities;
      if (categoryChanged) _categoryController.text = widget.initialCategory;
      if (maxChanged) {
        _maxResults = int.tryParse(widget.initialMaxResults) ?? _maxResults;
      }
      _attemptedStart = false;
    });
    _updateCostEstimate();
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

  String? _validationMessage() {
    final category = _categoryController.text.trim();
    final cities = _parseCities();

    if (category.isEmpty) {
      return 'Enter a lead category to continue.';
    }

    if (cities.isEmpty) {
      return 'Add at least one target city to continue.';
    }

    if (!_canCreateJob) {
      return 'Rate limit reached. Try again later.';
    }

    if (!_loadingCredits && _estimatedCost > 0 && _creditBalance < _estimatedCost) {
      return 'Insufficient credits. Required: $_estimatedCost, Available: $_creditBalance';
    }

    return null;
  }

  Future<Map<String, dynamic>?> _readSearchDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_searchDraftKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Ignore draft read errors.
    }
    return null;
  }

  Future<void> _loadSearchDraftIfNeeded() async {
    final hasInitial =
        widget.initialCategory.trim().isNotEmpty || widget.initialCities.trim().isNotEmpty;
    if (hasInitial) return;

    if (_categoryController.text.trim().isNotEmpty ||
        _citiesController.text.trim().isNotEmpty) {
      return;
    }

    final draft = await _readSearchDraft();
    if (draft == null) return;

    if (!mounted) return;
    setState(() {
      _categoryController.text = (draft['category'] as String?) ?? '';
      _citiesController.text = (draft['cities_text'] as String?) ?? '';
      _maxResults = (draft['max_results'] as int?) ?? _maxResults;
      _draftLoaded = true;
    });
    _updateCostEstimate();
  }

  Future<void> _saveSearchDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'category': _categoryController.text.trim(),
        'cities_text': _citiesController.text.trim(),
        'max_results': _maxResults,
        'saved_at': DateTime.now().toIso8601String(),
      };
      await prefs.setString(_searchDraftKey, jsonEncode(payload));
      if (!mounted) return;
      setState(() => _draftLoaded = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draft saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      // Ignore save errors.
    }
  }

  Future<void> _clearSearchDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_searchDraftKey);
    } catch (_) {
      // Ignore clear errors.
    }
    if (!mounted) return;
    setState(() => _draftLoaded = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Draft cleared'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openReviewSheet(ScraperProvider provider) async {
    setState(() => _attemptedStart = true);

    final validation = _validationMessage();
    if (validation != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validation),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final category = _categoryController.text.trim();
    final cities = _parseCities();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ReviewSheet(
          category: category,
          cities: cities,
          maxResults: _maxResults,
          estimatedCost: _estimatedCost,
          creditBalance: _creditBalance,
        );
      },
    );

    if (confirmed == true) {
      await _startScraping(provider);
    }
  }

  Future<void> _startScraping(ScraperProvider provider) async {
    final category = _categoryController.text.trim();
    final cities = _parseCities();

    setState(() => _attemptedStart = true);
    final validation = _validationMessage();
    if (validation != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validation),
          behavior: SnackBarBehavior.floating,
        ),
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
                    if (widget.showHeader)
                      WorkflowStepper(currentStep: isRunning ? 2 : 1),
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
                            _buildWizardActions(scraperProvider, isRunning),
                            const SizedBox(height: AppSpacing.lg),
                            _buildActivitySection(scraperProvider, layoutType),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    if (widget.showHeader) _buildHeader(),
                    if (widget.showHeader)
                      WorkflowStepper(currentStep: isRunning ? 2 : 1),
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
                                      _buildWizardActions(
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
                                      scraperProvider, layoutType),
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

  Widget _buildWizardActions(ScraperProvider provider, bool isRunning) {
    final validation = _validationMessage();
    final canReview = !isRunning && validation == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_draftLoaded)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            decoration: BoxDecoration(
              color: _ScrapeColors.primary.withValues(alpha: 0.12),
              borderRadius: AppSpacing.borderRadiusLg,
              border: Border.all(
                color: _ScrapeColors.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.save_rounded, color: Colors.white70, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Draft loaded',
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearSearchDraft,
                  child: Text(
                    'Clear',
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (!isRunning) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                final cb = widget.onBackToCities;
                if (cb != null) {
                  cb();
                } else {
                  Navigator.maybePop(context);
                }
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xxs,
                ),
                foregroundColor: Colors.white70,
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text(
                'Back to Cities',
                style: AppTypography.labelSmall.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isRunning ? null : _saveSearchDraft,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                ),
                icon: const Icon(Icons.bookmark_add_rounded, size: 18),
                label: Text(
                  'Save draft',
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: canReview ? () => _openReviewSheet(provider) : () {
                  setState(() => _attemptedStart = true);
                  if (validation != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(validation),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: AnimatedContainer(
                  duration: AppSpacing.durationFast,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: canReview
                          ? [_ScrapeColors.primary, _ScrapeColors.primaryLight]
                          : [Colors.white24, Colors.white10],
                    ),
                    borderRadius: AppSpacing.borderRadiusLg,
                    boxShadow: canReview
                        ? [
                            BoxShadow(
                              color: _ScrapeColors.primary.withValues(alpha: 0.4),
                              blurRadius: 18,
                              spreadRadius: -8,
                            ),
                          ]
                        : null,
                    border: canReview
                        ? null
                        : Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isRunning ? Icons.autorenew_rounded : Icons.rocket_launch_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        isRunning ? 'Running...' : 'Review & Start',
                        style: AppTypography.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_attemptedStart && validation != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            validation,
            style: AppTypography.bodySmall.copyWith(
              color: _ScrapeColors.rose,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActivitySection(
      ScraperProvider scraperProvider, LayoutType layoutType) {
    final job = scraperProvider.currentJob;
    final isRunning = scraperProvider.status == ScrapingStatus.running;
    final progress = job?.progress ?? 0;
    final logs = scraperProvider.getCurrentLogs();
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
          const SizedBox(height: AppSpacing.sm),
          _buildJobControls(scraperProvider),
          const SizedBox(height: AppSpacing.sm),
          _buildJobStages(job),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _buildProgressCircle(progress, isRunning),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildLogBox(logs, jobId: job?.jobId),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _buildJobStats(job),
          const SizedBox(height: AppSpacing.md),
          _buildCityProgress(job, layoutType),
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

  Widget _buildLogBox(List<String> logs, {String? jobId}) {
    final filtered = _filteredLogs(logs);
    final displayLogs = filtered.isEmpty
        ? ['> Waiting for logs...']
        : filtered.take(10).toList();

    return Container(
      padding: AppSpacing.paddingSm,
      decoration: BoxDecoration(
        color: _ScrapeColors.terminal,
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _logFilterChip('All'),
              const SizedBox(width: AppSpacing.xs),
              _logFilterChip('Errors'),
              const Spacer(),
              IconButton(
                tooltip: 'Export logs',
                onPressed: (jobId == null || logs.isEmpty)
                    ? null
                    : () => _exportLogs(logs, jobId),
                icon: Icon(
                  Icons.download_rounded,
                  color: (jobId == null || logs.isEmpty)
                      ? Colors.white24
                      : Colors.white60,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          SizedBox(
            height: 110,
            child: ListView.builder(
              itemCount: displayLogs.length,
              itemBuilder: (context, index) {
                final line = displayLogs[index];
                final color = _isErrorLogLine(line)
                    ? _ScrapeColors.rose
                    : line.toLowerCase().contains('starting')
                        ? _ScrapeColors.primaryLight
                        : Colors.white70;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    line,
                    style: AppTypography.labelSmall.copyWith(
                      color: color,
                      fontFamily: 'monospace',
                      height: 1.2,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _logFilterChip(String label) {
    final isActive = _logFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _logFilter = label),
      child: AnimatedContainer(
        duration: AppSpacing.durationFast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? _ScrapeColors.primary.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: AppSpacing.borderRadiusSm,
          border: Border.all(
            color: isActive
                ? _ScrapeColors.primaryLight
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: isActive ? Colors.white : Colors.white70,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  List<String> _filteredLogs(List<String> logs) {
    if (_logFilter == 'Errors') {
      return logs.where(_isErrorLogLine).toList();
    }
    return logs;
  }

  bool _isErrorLogLine(String line) {
    final l = line.toLowerCase();
    return l.contains('error') || l.contains('failed') || l.contains('timeout');
  }

  Future<void> _exportLogs(List<String> logs, String jobId) async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final content = logs.join('\n');
    await saveCsv(content, 'job_logs_${jobId}_$stamp', context: context);
  }

  Widget _buildJobControls(ScraperProvider scraperProvider) {
    final job = scraperProvider.currentJob;
    final status = job?.status ?? ScrapingStatus.idle;
    final isRunning = status == ScrapingStatus.running;

    Color pillColor;
    String label;
    IconData icon;

    switch (status) {
      case ScrapingStatus.running:
        pillColor = _ScrapeColors.primaryLight;
        label = 'Running';
        icon = Icons.autorenew_rounded;
        break;
      case ScrapingStatus.completed:
        pillColor = _ScrapeColors.emerald;
        label = 'Completed';
        icon = Icons.check_circle_rounded;
        break;
      case ScrapingStatus.cancelled:
        pillColor = _ScrapeColors.rose;
        label = 'Cancelled';
        icon = Icons.cancel_rounded;
        break;
      case ScrapingStatus.failed:
        pillColor = _ScrapeColors.rose;
        label = 'Failed';
        icon = Icons.error_rounded;
        break;
      case ScrapingStatus.idle:
        pillColor = Colors.white38;
        label = 'Idle';
        icon = Icons.pause_circle_filled_rounded;
        break;
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: pillColor.withValues(alpha: 0.15),
            borderRadius: AppSpacing.borderRadiusRound,
            border: Border.all(color: pillColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: pillColor, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            job?.currentCity.isNotEmpty == true
                ? 'Current: ${job!.currentCity}'
                : 'Ready to start a search',
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white54,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (isRunning)
          OutlinedButton.icon(
            onPressed: () => _confirmCancel(scraperProvider),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _ScrapeColors.rose.withValues(alpha: 0.7)),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
            ),
            icon: const Icon(Icons.stop_circle_rounded, size: 18),
            label: Text(
              'Cancel',
              style: AppTypography.labelSmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmCancel(ScraperProvider scraperProvider) async {
    final jobId = scraperProvider.currentJob?.jobId;
    if (jobId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _ScrapeColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: AppSpacing.borderRadiusLg,
        ),
        title: Text(
          'Cancel job?',
          style: AppTypography.titleMedium.copyWith(color: Colors.white),
        ),
        content: Text(
          'This will stop the current scraping job. Partial results will remain available.',
          style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep running'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _ScrapeColors.rose,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel job'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await scraperProvider.cancelCurrentJob();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cancellation requested'),
          backgroundColor: _ScrapeColors.rose,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel: $e'),
          backgroundColor: _ScrapeColors.rose,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildJobStages(ScrapingJob? job) {
    if (job == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: AppSpacing.borderRadiusMd,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Text(
          'No active job',
          style: AppTypography.labelSmall.copyWith(color: Colors.white54),
        ),
      );
    }

    final status = job.status;
    final isDone = status == ScrapingStatus.completed ||
        status == ScrapingStatus.failed ||
        status == ScrapingStatus.cancelled;

    final stages = [
      _StageItem(
        label: 'Queued',
        state: job.progress > 0 || isDone ? _StageState.completed : _StageState.active,
      ),
      _StageItem(
        label: 'Scraping',
        state: status == ScrapingStatus.running
            ? _StageState.active
            : isDone
                ? _StageState.completed
                : _StageState.pending,
      ),
      _StageItem(
        label: status == ScrapingStatus.completed
            ? 'Complete'
            : status == ScrapingStatus.cancelled
                ? 'Cancelled'
                : status == ScrapingStatus.failed
                    ? 'Failed'
                    : 'Finish',
        state: status == ScrapingStatus.completed
            ? _StageState.completed
            : status == ScrapingStatus.cancelled || status == ScrapingStatus.failed
                ? _StageState.completed
                : _StageState.pending,
      ),
    ];

    return Row(
      children: List.generate(stages.length, (index) {
        final item = stages[index];
        return Expanded(
          child: Row(
            children: [
              _stageDot(item),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.label,
                  style: AppTypography.labelSmall.copyWith(
                    color: item.state == _StageState.pending
                        ? Colors.white38
                        : Colors.white70,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (index != stages.length - 1)
                Container(
                  width: 22,
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _stageDot(_StageItem item) {
    Color color;
    Widget? child;

    switch (item.state) {
      case _StageState.completed:
        color = _ScrapeColors.emerald;
        child = const Icon(Icons.check, size: 12, color: Colors.white);
        break;
      case _StageState.active:
        color = _ScrapeColors.primaryLight;
        child = const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );
        break;
      case _StageState.pending:
        color = Colors.white24;
        child = null;
        break;
    }

    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _buildJobStats(ScrapingJob? job) {
    if (job == null) return const SizedBox.shrink();

    final now = DateTime.now();
    final end = job.completedAt ?? now;
    final elapsed = end.difference(job.createdAt);

    final activeIndex = job.currentCity.isNotEmpty
        ? job.cities.indexOf(job.currentCity)
        : -1;

    final completedCities = job.status == ScrapingStatus.completed
        ? job.totalCities
        : activeIndex >= 0
            ? activeIndex
            : 0;

    final remainingCities = (job.totalCities - completedCities).clamp(0, job.totalCities);
    final avgPerCity = completedCities > 0
        ? elapsed ~/ completedCities
        : const Duration(seconds: 0);
    final estRemaining = job.status == ScrapingStatus.running && completedCities > 0
        ? avgPerCity * remainingCities
        : null;

    final stats = [
      _MiniStat(label: 'Elapsed', value: _formatDuration(elapsed)),
      _MiniStat(
        label: 'Est. Remaining',
        value: estRemaining == null ? '—' : _formatDuration(estRemaining),
      ),
      _MiniStat(label: 'Leads', value: '${job.results.length}'),
      _MiniStat(
        label: 'Cities',
        value: '${completedCities.clamp(0, job.totalCities)}/${job.totalCities}',
      ),
    ];

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: stats.map((s) => _miniStatChip(s)).toList(),
    );
  }

  Widget _miniStatChip(_MiniStat stat) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            stat.label,
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white54,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            stat.value,
            style: AppTypography.labelLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCityProgress(ScrapingJob? job, LayoutType layoutType) {
    if (job == null || job.cities.isEmpty) return const SizedBox.shrink();

    final activeIndex = job.currentCity.isNotEmpty
        ? job.cities.indexOf(job.currentCity)
        : -1;

    final cityCounts = <String, int>{};
    for (final result in job.results) {
      final city = (result['city'] ?? '').toString().trim();
      final state = (result['state'] ?? '').toString().trim();
      if (city.isEmpty) continue;
      final key = state.isEmpty ? city : '$city, $state';
      cityCounts[key] = (cityCounts[key] ?? 0) + 1;
    }

    final maxHeight = layoutType == LayoutType.mobile ? 220.0 : 260.0;

    return Container(
      padding: AppSpacing.paddingSm,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'City Progress',
            style: AppTypography.labelLarge.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: maxHeight,
            child: ListView.builder(
              itemCount: job.cities.length,
              itemBuilder: (context, index) {
                final cityState = job.cities[index];
                final isCompleted = job.status == ScrapingStatus.completed ||
                    (activeIndex >= 0 && index < activeIndex);
                final isActive = job.status == ScrapingStatus.running &&
                    activeIndex >= 0 &&
                    index == activeIndex;
                final isFailedOrCancelled = (job.status == ScrapingStatus.failed ||
                        job.status == ScrapingStatus.cancelled) &&
                    activeIndex >= 0 &&
                    index == activeIndex;

                final count = cityCounts[cityState] ?? 0;

                IconData statusIcon;
                Color statusColor;
                String statusLabel;

                if (isCompleted) {
                  statusIcon = Icons.check_circle_rounded;
                  statusColor = _ScrapeColors.emerald;
                  statusLabel = '$count leads';
                } else if (isFailedOrCancelled) {
                  statusIcon = Icons.error_rounded;
                  statusColor = _ScrapeColors.rose;
                  statusLabel = job.status == ScrapingStatus.cancelled
                      ? 'Cancelled'
                      : 'Failed';
                } else if (isActive) {
                  statusIcon = Icons.autorenew_rounded;
                  statusColor = _ScrapeColors.primaryLight;
                  statusLabel = 'Scraping...';
                } else {
                  statusIcon = Icons.circle_outlined;
                  statusColor = Colors.white24;
                  statusLabel = 'Pending';
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: isActive ? 0.06 : 0.03),
                    borderRadius: AppSpacing.borderRadiusSm,
                    border: Border.all(
                      color: statusColor.withValues(alpha: isActive ? 0.45 : 0.18),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(statusIcon, color: statusColor, size: 18),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          cityState,
                          style: AppTypography.labelSmall.copyWith(
                            color: Colors.white70,
                            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        statusLabel,
                        style: AppTypography.labelSmall.copyWith(
                          color: statusColor == Colors.white24
                              ? Colors.white38
                              : statusColor.withValues(alpha: 0.95),
                          fontWeight: FontWeight.w700,
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

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds.clamp(0, 9999999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}

enum _StageState { pending, active, completed }

class _StageItem {
  final String label;
  final _StageState state;

  const _StageItem({required this.label, required this.state});
}

class _MiniStat {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});
}

class _ScrapeColors {
  static const Color background = AppColors.backgroundDark;
  static const Color card = AppColors.surfaceDark;
  static const Color input = AppColors.inputBackgroundDark;
  static const Color primary = AppColors.primaryBlue;
  static const Color primaryLight = AppColors.primaryBlueLight;
  static const Color emerald = AppColors.successGreen;
  static const Color rose = AppColors.dangerRed;
  static const Color terminal = AppColors.backgroundDarkAlt;
}

class _ReviewSheet extends StatelessWidget {
  final String category;
  final List<String> cities;
  final int maxResults;
  final int estimatedCost;
  final int creditBalance;

  const _ReviewSheet({
    required this.category,
    required this.cities,
    required this.maxResults,
    required this.estimatedCost,
    required this.creditBalance,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = (creditBalance - estimatedCost).clamp(0, 999999999);
    final hasEstimate = estimatedCost > 0;
    final topCities = cities.take(6).toList();
    final extraCount = (cities.length - topCities.length).clamp(0, cities.length);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.md),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: _ScrapeColors.card,
          borderRadius: AppSpacing.borderRadiusXl,
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 22,
              spreadRadius: -10,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: AppSpacing.borderRadiusRound,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Text(
                    'Review Your Job',
                    style: AppTypography.titleLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _sectionTitle('Target Market'),
              const SizedBox(height: AppSpacing.xs),
              _infoRow('Cities', '${cities.length} selected'),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  ...topCities.map(_chip),
                  if (extraCount > 0)
                    _chip('+$extraCount more', muted: true),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _sectionTitle('Category'),
              const SizedBox(height: AppSpacing.xs),
              _valueCard(category, icon: Icons.business_center_rounded),
              const SizedBox(height: AppSpacing.lg),
              _sectionTitle('Configuration'),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      label: 'Max / City',
                      value: '$maxResults',
                      icon: Icons.tune_rounded,
                      color: _ScrapeColors.primaryLight,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _metricCard(
                      label: 'Est. Cost',
                      value: hasEstimate ? '$estimatedCost credits' : '—',
                      icon: Icons.payments_rounded,
                      color: _ScrapeColors.emerald,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      label: 'Balance',
                      value: '$creditBalance',
                      icon: Icons.account_balance_wallet_rounded,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _metricCard(
                      label: 'After',
                      value: hasEstimate ? '$remaining' : '—',
                      icon: Icons.trending_down_rounded,
                      color: hasEstimate ? Colors.white70 : Colors.white38,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                      ),
                      child: Text(
                        'Back',
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _ScrapeColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppSpacing.borderRadiusLg,
                        ),
                      ),
                      icon: const Icon(Icons.rocket_launch_rounded),
                      label: Text(
                        'Start scraping',
                        style: AppTypography.labelLarge.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'By continuing, credits are charged immediately and the job starts in the background.',
                style: AppTypography.labelSmall.copyWith(color: Colors.white38),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: AppTypography.labelSmall.copyWith(
        color: Colors.white60,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(color: Colors.white54),
        ),
        const Spacer(),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, {bool muted = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: muted ? 0.05 : 0.08),
        borderRadius: AppSpacing.borderRadiusRound,
        border: Border.all(
          color: Colors.white.withValues(alpha: muted ? 0.08 : 0.12),
        ),
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: muted ? Colors.white54 : Colors.white70,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _valueCard(String value, {required IconData icon}) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _ScrapeColors.input,
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodyMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white54,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
