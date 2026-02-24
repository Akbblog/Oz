import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_breakpoints.dart';
import '../services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SimpleBuyCreditsScreen extends StatefulWidget {
  const SimpleBuyCreditsScreen({super.key});

  @override
  State<SimpleBuyCreditsScreen> createState() => _SimpleBuyCreditsScreenState();
}

class _SimpleBuyCreditsScreenState extends State<SimpleBuyCreditsScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _creditController = TextEditingController();
  final TextEditingController _promoController = TextEditingController();

  int _selectedCredits = 100;
  String? _promoApplied;
  Map<String, dynamic>? _promoPreview;
  int _discountCents = 0;
  int _bonusCredits = 0;
  bool _isLoading = false;
  String? _error;
  Timer? _promoDebounce;

  static const double PRICE_PER_CREDIT = 0.10;
  static const int MIN_CREDITS = 100;

  final List<int> quickSelectOptions = [100, 200, 500, 1000];

  @override
  void initState() {
    super.initState();
    _creditController.text = _selectedCredits.toString();
    _creditController.addListener(_onCreditsChanged);
  }

  @override
  void dispose() {
    _promoDebounce?.cancel();
    _creditController.dispose();
    _promoController.dispose();
    super.dispose();
  }

  void _onCreditsChanged() {
    final value = int.tryParse(_creditController.text) ?? _selectedCredits;
    setState(() {
      _selectedCredits = value;
      _discountCents = 0;
      _bonusCredits = 0;
    });

    if (_promoApplied != null) {
      _promoDebounce?.cancel();
      _promoDebounce = Timer(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        _revalidateAppliedPromo();
      });
    } else {
      setState(() {
        _promoPreview = null;
      });
    }
  }

  void _setQuickSelect(int credits) {
    setState(() {
      _selectedCredits = credits;
      _creditController.text = credits.toString();
      _discountCents = 0;
      _bonusCredits = 0;
      _promoApplied = null;
      _promoPreview = null;
      _promoController.clear();
    });
  }

  Future<void> _revalidateAppliedPromo() async {
    final code = _promoApplied?.trim();
    if (code == null || code.isEmpty) return;

    final subtotalCents = _selectedCredits * 10;
    try {
      final preview = await _apiService.validatePromoCode(
        code,
        appliesTo: 'all',
        subtotalCents: subtotalCents,
      );
      if (!mounted) return;
      setState(() {
        _promoPreview = preview;
        _discountCents = (preview['discount_cents'] as num? ?? 0).toInt();
        _bonusCredits = (preview['bonus_credits'] as num? ?? 0).toInt();
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _promoApplied = null;
        _promoPreview = null;
        _discountCents = 0;
        _bonusCredits = 0;
        _error = 'Promo no longer valid for this amount';
      });
    }
  }

  Future<void> _applyPromo() async {
    final code = _promoController.text.trim();
    if (code.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final subtotalCents = _selectedCredits * 10;
      final preview = await _apiService.validatePromoCode(
        code,
        appliesTo: 'all',
        subtotalCents: subtotalCents,
      );

      setState(() {
        _promoApplied = (preview['code'] ?? code).toString();
        _promoPreview = preview;
        _discountCents = (preview['discount_cents'] as num? ?? 0).toInt();
        _bonusCredits = (preview['bonus_credits'] as num? ?? 0).toInt();
        _error = null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _promoApplied = null;
        _promoPreview = null;
        _discountCents = 0;
        _bonusCredits = 0;
        _error = 'Failed to apply promo: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _proceedToCheckout() async {
    if (_selectedCredits < MIN_CREDITS) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Minimum purchase is $MIN_CREDITS credits'),
          backgroundColor: AppColors.dangerRed,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _apiService.simplePurchaseCredits(
        credits: _selectedCredits,
        promoCode: _promoApplied,
      );

      if (!mounted) return;

      final checkoutUrl = result['checkout_url'];
      if (checkoutUrl != null && await canLaunchUrl(Uri.parse(checkoutUrl))) {
        await launchUrl(checkoutUrl, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not launch checkout');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final layoutType =
        AppBreakpoints.getLayoutType(MediaQuery.of(context).size.width);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Stack(
          children: [
            _buildBackground(),
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(
                      layoutType == LayoutType.mobile
                          ? AppSpacing.md
                          : AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildQuickSelectCards(),
                        const SizedBox(height: AppSpacing.lg),
                        _buildCustomAmountSection(),
                        const SizedBox(height: AppSpacing.lg),
                        _buildPricePreview(),
                        const SizedBox(height: AppSpacing.lg),
                        _buildPromoSection(),
                        const SizedBox(height: AppSpacing.xl),
                        _buildCheckoutButton(),
                      ],
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

  Widget _buildBackground() {
    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              AppColors.primaryBlue.withValues(alpha: 0.1),
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
        color: AppColors.backgroundDark.withValues(alpha: 0.8),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          Expanded(
            child: Text(
              'Buy Credits',
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

  Widget _buildQuickSelectCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Select',
          style: AppTypography.labelMedium.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        GridView.count(
          crossAxisCount: 4,
          childAspectRatio: 0.9,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: quickSelectOptions
              .map((credits) => _buildQuickSelectCard(credits))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildQuickSelectCard(int credits) {
    final price = (credits * PRICE_PER_CREDIT).toStringAsFixed(2);
    final isSelected = _selectedCredits == credits;

    return GestureDetector(
      onTap: () => _setQuickSelect(credits),
      child: Container(
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    AppColors.primaryBlue.withValues(alpha: 0.8),
                    AppColors.primaryBlue.withValues(alpha: 0.6),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: !isSelected ? AppColors.elevatedCardDark : null,
          borderRadius: AppSpacing.borderRadiusMd,
          border: Border.all(
            color: isSelected
                ? AppColors.primaryBlue
                : Colors.white.withValues(alpha: 0.1),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$credits',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '\$$price',
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomAmountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Custom Amount',
          style: AppTypography.labelMedium.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _creditController,
          keyboardType: TextInputType.number,
          style: AppTypography.bodyLarge.copyWith(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter credits (min $MIN_CREDITS)',
            hintStyle: AppTypography.bodyMedium.copyWith(color: Colors.white38),
            prefixIcon: const Icon(Icons.card_giftcard,
                color: AppColors.primaryBlue, size: 20),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primaryBlue,
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPricePreview() {
    final subtotalCents = _selectedCredits * 10;
    final totalCents = subtotalCents - _discountCents;
    final subtotal = subtotalCents / 100.0;
    final discount = _discountCents / 100.0;
    final total = totalCents / 100.0;

    return Container(
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Subtotal',
                style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
              ),
              Text(
                '$_selectedCredits credits = \$${subtotal.toStringAsFixed(2)}',
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (_promoApplied != null && _discountCents > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Discount (${_promoApplied ?? ''})',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.successGreen,
                  ),
                ),
                Text(
                  '-\$${discount.toStringAsFixed(2)}',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.successGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Divider(color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (_promoApplied != null && _bonusCredits > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Bonus credits (${_promoApplied ?? ''})',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.successGreen,
                  ),
                ),
                Text(
                  '+$_bonusCredits',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.successGreen,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Divider(color: Colors.white.withValues(alpha: 0.1)),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: AppTypography.titleSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '\$${total.toStringAsFixed(2)}',
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPromoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Have a promo code?',
          style: AppTypography.labelMedium.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _promoController,
                enabled: !_isLoading,
                style: AppTypography.bodyMedium.copyWith(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Enter promo code',
                  hintStyle: AppTypography.bodyMedium.copyWith(
                    color: Colors.white38,
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: AppColors.primaryBlue,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ElevatedButton(
              onPressed: _isLoading ? null : _applyPromo,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                disabledBackgroundColor:
                    AppColors.primaryBlue.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Apply',
                      style: AppTypography.labelMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
        if (_promoApplied != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: AppSpacing.paddingSm,
            decoration: BoxDecoration(
              color: AppColors.successGreen.withValues(alpha: 0.1),
              borderRadius: AppSpacing.borderRadiusSm,
              border: Border.all(
                color: AppColors.successGreen.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.successGreen, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Promo applied: $_promoApplied',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.successGreen,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy code',
                  icon: const Icon(Icons.copy_rounded,
                      color: AppColors.successGreen, size: 18),
                  onPressed: () async {
                    final code = _promoApplied;
                    if (code == null) return;
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied!'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: AppSpacing.paddingSm,
            decoration: BoxDecoration(
              color: AppColors.dangerRed.withValues(alpha: 0.1),
              borderRadius: AppSpacing.borderRadiusSm,
              border: Border.all(
                color: AppColors.dangerRed.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.dangerRed, size: 18),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    _error!,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.dangerRed,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCheckoutButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _proceedToCheckout,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryBlue,
        disabledBackgroundColor: AppColors.primaryBlue.withValues(alpha: 0.5),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: _isLoading
          ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Text(
              'Pay with Coinbase',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}
