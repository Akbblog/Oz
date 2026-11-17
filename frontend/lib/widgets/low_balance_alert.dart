import 'package:flutter/material.dart';

import 'app_shell_common.dart';

/// Low / empty balance notice with a real action button.
///
/// The action reads "Get credits" when live payments are on and
/// "Request credits" when they are off ([livePayments]).
class LowBalanceAlert extends StatelessWidget {
  final int currentBalance;
  final int threshold;
  final VoidCallback? onBuyCredits;
  final bool dismissible;
  final VoidCallback? onDismiss;

  /// Live payments enabled (decides the action label).
  final bool livePayments;

  const LowBalanceAlert({
    super.key,
    required this.currentBalance,
    this.threshold = 10,
    this.onBuyCredits,
    this.dismissible = true,
    this.onDismiss,
    this.livePayments = true,
  });

  bool get shouldShow => currentBalance <= threshold;

  String get actionLabel => livePayments ? 'Get credits' : 'Request credits';

  @override
  Widget build(BuildContext context) {
    if (!shouldShow) return const SizedBox.shrink();

    final isZero = currentBalance <= 0;
    final fg = isZero ? UiTokens.failedFg : UiTokens.partialFg;
    final bg = isZero ? UiTokens.failedBg : UiTokens.partialBg;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(UiTokens.radius),
          border: Border.all(color: fg.withValues(alpha: 0.5)),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(isZero ? Icons.error_outline : Icons.warning_amber_rounded, color: fg, size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isZero ? 'No credits left' : 'Low credit balance',
                        style: const TextStyle(color: UiTokens.text, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isZero
                            ? 'You need credits to start a search.'
                            : 'You have ${plural(currentBalance, 'credit', 'credits')} left.',
                        style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (onBuyCredits != null)
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: UiTokens.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(44, 44),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onPressed: onBuyCredits,
                child: Text(actionLabel),
              ),
            if (dismissible && onDismiss != null)
              IconButton(
                tooltip: 'Dismiss',
                style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, color: UiTokens.textSecondary, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}
