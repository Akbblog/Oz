import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/scraper_provider.dart';
import '../services/api_service.dart';
import '../core/download_helper.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../widgets/gradient_background.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';

class ResultsScreen extends StatefulWidget {
  final String? jobId;
  final List<Map<String, dynamic>>? overrideResults;
  final String? title;

  const ResultsScreen({
    super.key,
    this.jobId,
    this.overrideResults,
    this.title,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  bool _isDownloading = false;
  String? _error;
  List<Map<String, dynamic>> _loadedResults = [];

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: AppSpacing.durationMedium,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();
    _loadIfNeeded();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadIfNeeded() async {
    if (widget.jobId == null || widget.overrideResults != null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await _apiService.getJobResults(widget.jobId!);
      final results = List<Map<String, dynamic>>.from(data['results'] ?? []);
      if (mounted) {
        setState(() {
          _loadedResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load results: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _resolveResults(ScraperProvider scraperProvider) {
    if (widget.overrideResults != null) {
      return widget.overrideResults!;
    }
    if (_loadedResults.isNotEmpty) {
      return _loadedResults;
    }
    return scraperProvider.currentJob?.results ?? [];
  }

  Future<void> _launchUrl(String url) async {
    if (url.isEmpty || url == 'N/A') return;

    // Ensure URL has a scheme
    String finalUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      finalUrl = 'https://$url';
    }

    try {
      final uri = Uri.parse(finalUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open: $url'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening URL: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _launchPhone(String phone) async {
    if (phone.isEmpty || phone == 'N/A') return;

    // Clean phone number
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error launching phone: $e');
    }
  }

  Future<void> _launchMaps(String address) async {
    if (address.isEmpty || address == 'N/A') return;

    final encodedAddress = Uri.encodeComponent(address);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Error launching maps: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scraperProvider = Provider.of<ScraperProvider>(context);
    final results = _resolveResults(scraperProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(results.length),
      body: GradientBackground(
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Column(
              children: [
                // Stats Header
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: _buildStatsHeader(results),
                ),
                // Content
                Expanded(
                  child: _buildContent(results),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(int count) {
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
        widget.title ?? 'Results',
        style: AppTypography.headlineSmallLight,
      ),
      centerTitle: true,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.glassWhite,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: _isDownloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.download, color: Colors.white, size: 20),
            ),
            onPressed: count > 0 && !_isDownloading ? () => _downloadResults(context) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsHeader(List<Map<String, dynamic>> results) {
    // Count unique cities and categories
    final cities = results.map((r) => r['city']).toSet();
    final categories = results.map((r) => r['category']).toSet();

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          _buildStatItem(
            icon: Icons.business,
            value: results.length.toString(),
            label: 'Leads',
            color: AppColors.primaryStart,
          ),
          _buildDivider(),
          _buildStatItem(
            icon: Icons.location_city,
            value: cities.length.toString(),
            label: 'Cities',
            color: AppColors.secondaryStart,
          ),
          _buildDivider(),
          _buildStatItem(
            icon: Icons.category,
            value: categories.length.toString(),
            label: 'Categories',
            color: AppColors.accentStart,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: AppTypography.headlineSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 50,
      width: 1,
      color: Colors.white24,
    );
  }

  Widget _buildContent(List<Map<String, dynamic>> results) {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (results.isEmpty) {
      return _buildEmptyState();
    }

    return _buildResultsList(results);
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.secondaryStart),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Loading results...',
            style: AppTypography.titleMediumLight,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 48,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Failed to Load',
                style: AppTypography.titleLarge.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: Colors.white60),
              ),
              const SizedBox(height: AppSpacing.lg),
              GradientButton(
                text: 'Try Again',
                onPressed: _loadIfNeeded,
                icon: Icons.refresh,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: GlassCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.search_off,
                  color: AppColors.info,
                  size: 48,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'No Results Yet',
                style: AppTypography.titleLarge.copyWith(color: Colors.white),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Start a lead search to see results here',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: Colors.white60),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList(List<Map<String, dynamic>> results) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final business = results[index];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 200 + (index * 50).clamp(0, 300)),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: child,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ModernBusinessCard(
              business: business,
              onWebsiteTap: () => _launchUrl(business['website'] ?? ''),
              onPhoneTap: () => _launchPhone(business['phone'] ?? ''),
              onAddressTap: () => _launchMaps(business['address'] ?? ''),
              onMapsTap: () => _launchUrl(business['google_maps_url'] ?? ''),
            ),
          ),
        );
      },
    );
  }

  Future<void> _downloadResults(BuildContext context) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final scraperProvider = Provider.of<ScraperProvider>(context, listen: false);

    setState(() => _isDownloading = true);

    try {
      final downloadData = widget.jobId != null
          ? await _apiService.downloadResults(widget.jobId!)
          : await scraperProvider.downloadResults();

      final filename = downloadData['filename'] as String;
      final content = downloadData['content'] as String;

      if (!mounted) return;
      await saveExcel(content, filename, context: context);
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text('Failed to download: $e')),
            ],
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }
}

class ModernBusinessCard extends StatelessWidget {
  final Map<String, dynamic> business;
  final VoidCallback? onWebsiteTap;
  final VoidCallback? onPhoneTap;
  final VoidCallback? onAddressTap;
  final VoidCallback? onMapsTap;

  const ModernBusinessCard({
    super.key,
    required this.business,
    this.onWebsiteTap,
    this.onPhoneTap,
    this.onAddressTap,
    this.onMapsTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhone = business['phone'] != null && business['phone'] != 'N/A' && business['phone'].toString().isNotEmpty;
    final hasWebsite = business['website'] != null && business['website'] != 'N/A' && business['website'].toString().isNotEmpty;
    final hasAddress = business['address'] != null && business['address'] != 'N/A' && business['address'].toString().isNotEmpty;
    final hasMapsUrl = business['google_maps_url'] != null && business['google_maps_url'] != 'N/A' && business['google_maps_url'].toString().isNotEmpty;

    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Business Icon
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  Icons.storefront,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Business Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      business['business_name'] ?? 'Unknown Business',
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.white60,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${business['city'] ?? 'Unknown'}, ${business['state'] ?? ''}',
                            style: AppTypography.bodySmall.copyWith(
                              color: Colors.white60,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Category Chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.secondaryStart.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusRound),
                  border: Border.all(
                    color: AppColors.secondaryStart.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  business['category'] ?? 'Unknown',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.secondaryStart,
                  ),
                ),
              ),
            ],
          ),

          // Address - Clickable to open Google Maps
          if (hasAddress) ...[
            const SizedBox(height: AppSpacing.md),
            InkWell(
              onTap: onAddressTap,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.map_outlined,
                      size: 16,
                      color: AppColors.info,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        business['address'],
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.info,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: AppColors.info.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Contact Row - Clickable buttons
          if (hasPhone || hasWebsite || hasMapsUrl) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (hasPhone) ...[
                  Expanded(
                    child: _buildContactButton(
                      icon: Icons.phone,
                      label: business['phone'],
                      color: AppColors.success,
                      onTap: onPhoneTap,
                    ),
                  ),
                  if (hasWebsite || hasMapsUrl) const SizedBox(width: AppSpacing.sm),
                ],
                if (hasWebsite) ...[
                  Expanded(
                    child: _buildContactButton(
                      icon: Icons.language,
                      label: 'Website',
                      color: AppColors.info,
                      onTap: onWebsiteTap,
                    ),
                  ),
                  if (hasMapsUrl) const SizedBox(width: AppSpacing.sm),
                ],
                if (hasMapsUrl)
                  Expanded(
                    child: _buildContactButton(
                      icon: Icons.place,
                      label: 'Maps',
                      color: AppColors.accentStart,
                      onTap: onMapsTap,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContactButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: AppSpacing.xxs),
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.labelSmall.copyWith(color: color),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
