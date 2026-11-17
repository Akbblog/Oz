import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/credit_provider.dart';
import 'app_shell_common.dart';

/// Credit balance in the top bar. A real button (keyboard focus, Enter/Space,
/// screen-reader label): refreshes the balance and opens `/credits`.
class CreditPill extends StatelessWidget {
  /// Called instead of the default navigation (tests, custom hosts).
  final VoidCallback? onPressed;

  const CreditPill({super.key, this.onPressed});

  static String labelFor(CreditProvider credits) {
    if (credits.hasValue) return plural(credits.balance, 'credit', 'credits');
    return credits.refreshing ? 'Credits…' : 'Credits';
  }

  @override
  Widget build(BuildContext context) {
    final credits = context.watch<CreditProvider>();
    final min = credits.minJobCost;
    final low = credits.hasValue && min != null && credits.balance < min;
    final label = labelFor(credits);

    void open() {
      unawaited(CreditProvider.instance.refresh());
      if (onPressed != null) {
        onPressed!();
        return;
      }
      final current = ModalRoute.of(context)?.settings.name ?? '';
      final path = Uri.tryParse(current)?.path ?? current;
      if (path == '/credits' || path == '/wallet') return;
      Navigator.of(context).pushNamed('/credits');
    }

    return Semantics(
      button: true,
      label: low ? '$label, not enough for a search. Open credits' : '$label. Open credits',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Open credits',
        child: Material(
          color: UiTokens.card,
          shape: StadiumBorder(
            side: BorderSide(color: low ? UiTokens.partialFg : UiTokens.border),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: open,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (low) ...[
                      const Icon(Icons.warning_amber_rounded, size: 16, color: UiTokens.partialFg),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      label,
                      style: const TextStyle(
                        color: UiTokens.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
