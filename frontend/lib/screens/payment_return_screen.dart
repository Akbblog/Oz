import 'dart:async';

import 'package:flutter/material.dart';

import '../core/error_handler.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../services/api_service.dart';

/// Landing page after Safepay's hosted checkout.
///
/// The browser redirect is never trusted: this screen only shows what the
/// server has confirmed (via Safepay's signed webhook or a server-side tracker
/// check). Until then it shows "Confirming payment".
class PaymentReturnScreen extends StatefulWidget {
  final String transactionId;
  final bool cancelled;

  /// Injected in tests.
  final ApiService? api;

  const PaymentReturnScreen({
    super.key,
    required this.transactionId,
    this.cancelled = false,
    this.api,
  });

  @override
  State<PaymentReturnScreen> createState() => _PaymentReturnScreenState();
}

enum _View { confirming, completed, failed, cancelled, expired, review, delayed, error }

class _PaymentReturnScreenState extends State<PaymentReturnScreen> {
  static const _pollEvery = Duration(seconds: 3);
  static const _patience = Duration(minutes: 2);

  late final ApiService _api = widget.api ?? ApiService();
  _View _view = _View.confirming;
  Map<String, dynamic>? _status;
  String? _error;
  Timer? _timer;
  DateTime _startedAt = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    _startedAt = DateTime.now();
    if (widget.cancelled) {
      try {
        _apply(await _api.cancelSafepayPayment(widget.transactionId));
      } catch (e) {
        _fail(e);
      }
      if (_view == _View.confirming) _schedule();
      return;
    }
    await _poll();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_pollEvery, _poll);
  }

  Future<void> _poll() async {
    if (!mounted || _busy) return;
    _busy = true;
    try {
      _apply(await _api.getSafepayPaymentStatus(widget.transactionId));
    } catch (e) {
      _fail(e);
    } finally {
      _busy = false;
    }
    if (!mounted) return;
    if (_view == _View.confirming || (_view == _View.error && _withinPatience)) {
      if (_withinPatience) {
        _schedule();
      } else if (_view == _View.confirming) {
        setState(() => _view = _View.delayed);
      }
    }
  }

  bool get _withinPatience => DateTime.now().difference(_startedAt) < _patience;

  void _apply(Map<String, dynamic> status) {
    if (!mounted) return;
    final s = (status['status'] ?? 'processing').toString();
    setState(() {
      _status = status;
      _error = null;
      _view = switch (s) {
        'completed' => _View.completed,
        'failed' => _View.failed,
        'cancelled' => _View.cancelled,
        'expired' => _View.expired,
        'review' => _View.review,
        _ => _View.confirming,
      };
    });
  }

  void _fail(Object e) {
    if (!mounted) return;
    final notFound = e is ApiException && (e.statusCode == 404);
    setState(() {
      _error = notFound
          ? 'We could not find this payment on your account.'
          : ErrorHandler.getUserFriendlyMessage(e);
      if (notFound) {
        _view = _View.error;
      } else if (_view == _View.confirming && _withinPatience) {
        // A slow or failed status check is not a payment problem: keep showing
        // "Confirming payment" and try again on the next poll.
      } else if (_status == null) {
        _view = _View.error;
      }
    });
  }

  void _checkAgain() {
    setState(() => _view = _View.confirming);
    _startedAt = DateTime.now();
    _poll();
  }

  String get _amount {
    final cents = (_status?['amount_cents'] as num?)?.toInt();
    if (cents == null) return '';
    final cur = (_status?['currency'] ?? 'USD').toString();
    final value = (cents / 100).toStringAsFixed(2);
    return cur == 'USD' ? 'US\$$value' : '$cur $value';
  }

  int get _credits => (_status?['credits_purchased'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final isSandbox = (_status?['environment'] ?? '') == 'sandbox';
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: AppSpacing.paddingLg,
                decoration: BoxDecoration(
                  color: AppColors.elevatedCardDark.withValues(alpha: 0.5),
                  borderRadius: AppSpacing.borderRadiusLg,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _icon(),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _title(),
                      key: const ValueKey('payment-return-title'),
                      textAlign: TextAlign.center,
                      style: AppTypography.titleLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _message(),
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
                    ),
                    if (isSandbox) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Test payment (Safepay sandbox)',
                        style: AppTypography.labelSmall.copyWith(color: const Color(0xFFF59E0B)),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    ..._actions(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon() {
    switch (_view) {
      case _View.confirming:
        return const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(strokeWidth: 3),
        );
      case _View.completed:
        return const Icon(Icons.check_circle_rounded, color: AppColors.successGreen, size: 56);
      case _View.delayed:
      case _View.review:
        return const Icon(Icons.hourglass_top_rounded, color: Color(0xFFF59E0B), size: 56);
      case _View.cancelled:
        return const Icon(Icons.cancel_outlined, color: Colors.white54, size: 56);
      case _View.failed:
      case _View.expired:
      case _View.error:
        return const Icon(Icons.error_outline_rounded, color: AppColors.dangerRed, size: 56);
    }
  }

  String _title() {
    switch (_view) {
      case _View.confirming:
        return 'Confirming payment';
      case _View.completed:
        return 'Payment confirmed';
      case _View.failed:
        return 'Payment failed';
      case _View.cancelled:
        return 'Payment cancelled';
      case _View.expired:
        return 'Checkout expired';
      case _View.review:
        return 'Payment under review';
      case _View.delayed:
        return 'Still confirming';
      case _View.error:
        return 'Could not check this payment';
    }
  }

  String _message() {
    switch (_view) {
      case _View.confirming:
        return 'We are waiting for Safepay to confirm your payment. This usually takes a few seconds. '
            'Please keep this page open.';
      case _View.completed:
        return '$_credits credits were added to your account${_amount.isEmpty ? '' : ' for $_amount'}.';
      case _View.failed:
        return 'Your card was not charged. You can try again with the same or another card.';
      case _View.cancelled:
        return 'You cancelled the payment. Your card was not charged.';
      case _View.expired:
        return 'The checkout session timed out before payment. Your card was not charged.';
      case _View.review:
        return 'Safepay reported a payment that does not match this order, so no credits were added yet. '
            'Our team will check it; contact support with reference ${widget.transactionId}.';
      case _View.delayed:
        return 'Safepay has not confirmed this payment yet. If you were charged, your credits will be added '
            'automatically as soon as it is confirmed - you can leave this page.';
      case _View.error:
        return _error ?? 'Please check your connection and try again.';
    }
  }

  List<Widget> _actions(BuildContext context) {
    final buttons = <Widget>[];
    void primary(String label, VoidCallback onTap, {Key? key}) {
      buttons.add(SizedBox(
        width: double.infinity,
        child: FilledButton(key: key, onPressed: onTap, child: Text(label)),
      ));
    }

    void secondary(String label, VoidCallback onTap) {
      buttons.add(const SizedBox(height: AppSpacing.xs));
      buttons.add(SizedBox(
        width: double.infinity,
        child: TextButton(onPressed: onTap, child: Text(label)),
      ));
    }

    void go(String route) => Navigator.of(context).pushNamedAndRemoveUntil(route, (r) => false);

    switch (_view) {
      case _View.confirming:
        break;
      case _View.completed:
        primary('Go to Credits', () => go('/credits'), key: const ValueKey('payment-return-credits'));
        secondary('Find leads', () => go('/find'));
        break;
      case _View.failed:
      case _View.cancelled:
      case _View.expired:
        primary('Choose a credit pack', () => go('/pricing'));
        secondary('Back to Credits', () => go('/credits'));
        break;
      case _View.delayed:
      case _View.error:
        primary('Check again', _checkAgain);
        secondary('Back to Credits', () => go('/credits'));
        break;
      case _View.review:
        primary('Back to Credits', () => go('/credits'));
        break;
    }
    return buttons;
  }
}
