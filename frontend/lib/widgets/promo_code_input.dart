import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../services/api_service.dart';

class PromoCodeInput extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>?> onPromoApplied;
  final String appliesTo;
  final int? packageId;
  final int quantity;
  final int? subtotalCents;

  const PromoCodeInput({
    super.key,
    required this.onPromoApplied,
    this.appliesTo = 'packages',
    this.packageId,
    this.quantity = 1,
    this.subtotalCents,
  });

  @override
  State<PromoCodeInput> createState() => _PromoCodeInputState();
}

class _PromoCodeInputState extends State<PromoCodeInput> {
  final _controller = TextEditingController();
  final _apiService = ApiService();
  bool _isValidating = false;
  Map<String, dynamic>? _validPromo;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _validateCode() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isValidating = true;
      _error = null;
      _validPromo = null;
    });

    try {
      final result = await _apiService.validatePromoCode(
        code,
        appliesTo: widget.appliesTo,
        packageId: widget.packageId,
        quantity: widget.quantity,
        subtotalCents: widget.subtotalCents,
      );
      if (mounted) {
        setState(() {
          _validPromo = result;
          _isValidating = false;
        });
        widget.onPromoApplied(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Invalid promo code';
          _isValidating = false;
        });
        widget.onPromoApplied(null);
      }
    }
  }

  void _clearPromo() {
    setState(() {
      _controller.clear();
      _validPromo = null;
      _error = null;
    });
    widget.onPromoApplied(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Promo Code',
          style: AppTypography.labelLarge.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _controller,
                enabled: _validPromo == null,
                textCapitalization: TextCapitalization.characters,
                style: AppTypography.bodyMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
                decoration: InputDecoration(
                  hintText: 'Enter code',
                  hintStyle: AppTypography.bodyMedium.copyWith(
                    color: Colors.white24,
                  ),
                  prefixIcon: Icon(
                    _validPromo != null
                        ? Icons.check_circle
                        : Icons.local_offer_rounded,
                    color: _validPromo != null
                        ? _PromoColors.emerald
                        : Colors.white38,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: _PromoColors.surface.withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: AppSpacing.borderRadiusMd,
                    borderSide: BorderSide(
                      color: _validPromo != null
                          ? _PromoColors.emerald.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppSpacing.borderRadiusMd,
                    borderSide: BorderSide(
                      color: _validPromo != null
                          ? _PromoColors.emerald.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppSpacing.borderRadiusMd,
                    borderSide: const BorderSide(color: _PromoColors.primary),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: AppSpacing.borderRadiusMd,
                    borderSide: BorderSide(
                      color: _PromoColors.emerald.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            if (_validPromo != null)
              GestureDetector(
                onTap: _clearPromo,
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: AppColors.dangerRed.withValues(alpha: 0.15),
                    borderRadius: AppSpacing.borderRadiusMd,
                    border: Border.all(
                      color: AppColors.dangerRed.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(Icons.close, color: AppColors.dangerRed, size: 20),
                ),
              )
            else
              GestureDetector(
                onTap: _isValidating ? null : _validateCode,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue,
                    borderRadius: AppSpacing.borderRadiusMd,
                  ),
                  child: Center(
                    child: _isValidating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text(
                            'Apply',
                            style: AppTypography.labelLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ),
          ],
        ),
        if (_validPromo != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: _PromoColors.emerald.withValues(alpha: 0.1),
              borderRadius: AppSpacing.borderRadiusSm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: _PromoColors.emerald, size: 14),
                const SizedBox(width: 4),
                Text(
                  _promoDescription(),
                  style: AppTypography.labelSmall.copyWith(
                    color: _PromoColors.emerald,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _error!,
            style: AppTypography.bodySmall.copyWith(color: AppColors.dangerRed),
          ),
        ],
      ],
    );
  }

  String _promoDescription() {
    if (_validPromo == null) return '';
    final type = _validPromo!['type'] ?? '';
    switch (type) {
      case 'percentage_off':
        final pctRaw = _validPromo!['discount_percentage'];
        final subtotal = (_validPromo!['subtotal_cents'] ?? 0) as num;
        final discount = (_validPromo!['discount_cents'] ?? 0) as num;
        final pct = pctRaw is num && pctRaw > 0
            ? pctRaw.toDouble()
            : (subtotal > 0 ? (discount / subtotal) * 100.0 : 0.0);
        return '${pct.toStringAsFixed(0)}% off applied!';
      case 'fixed_amount_off':
        final amt = (_validPromo!['discount_amount_cents'] ?? 0) / 100;
        return '\$${amt.toStringAsFixed(2)} off applied!';
      case 'bonus_credits':
        final bonus = _validPromo!['bonus_credits'] ?? 0;
        return '+$bonus bonus credits!';
      default:
        return 'Promo applied!';
    }
  }
}

class _PromoColors {
  static const Color primary = AppColors.primaryBlue;
  static const Color surface = AppColors.inputBackgroundDark;
  static const Color emerald = AppColors.successGreen;
}
