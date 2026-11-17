import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_breakpoints.dart';
import '../../providers/search_setup_provider.dart';
import '../../widgets/app_shell_common.dart';
import 'find_common.dart';

/// Sticky selection bar of step 1 (plan §6.3): count, truncated names,
/// [Review list], [Clear all], maximum charge (only when the server gave an
/// estimate) and [Continue with {k} cities].
///
/// It sits below the scrolling content (never on top of it), so the last
/// list item is always reachable; on phones the shell puts it right above
/// the bottom navigation.
class FindSelectionBar extends StatelessWidget {
  final LocationCatalog catalog;
  final int? estimate;
  final String? country;
  final VoidCallback onContinue;

  const FindSelectionBar({
    super.key,
    required this.catalog,
    required this.estimate,
    required this.country,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final setup = context.watch<SearchSetupProvider>();
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < AppBreakpoints.mobile;
    final all = setup.allCities;
    final k = all.length;
    final unlisted = catalog.noLongerListed(setup.cities, country: country);

    final countText = k == 0 ? 'No cities selected yet' : '${citiesLabel(k)} selected';
    final count = Semantics(
      liveRegion: true,
      child: Text(countText, style: const TextStyle(color: UiTokens.text, fontSize: 15, fontWeight: FontWeight.w700)),
    );

    final links = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        if (k > 0)
          Text(cityNamesSummary(all), style: findSecondaryStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (unlisted.isNotEmpty) ...[
          const Text('·', style: findSecondaryStyle),
          Text('${formatCount(unlisted.length)} no longer listed',
              style: const TextStyle(color: UiTokens.partialFg, fontSize: 13)),
        ],
        if (k > 0) ...[
          _LinkButton(label: 'Review list', onPressed: () => showReviewList(context, catalog: catalog, country: country)),
          _LinkButton(label: 'Clear all', onPressed: () => confirmClearAll(context, setup)),
        ],
      ],
    );

    final maxLine = (estimate != null && k > 0)
        ? Text(
            'Up to ${formatCount(estimate!)} credits at ${setup.maxResultsPerCity} leads per city',
            style: findSecondaryStyle,
          )
        : null;

    final button = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: UiTokens.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: UiTokens.border,
        disabledForegroundColor: UiTokens.textSecondary,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      onPressed: k == 0 ? null : onContinue,
      child: Text(k == 0 ? 'Select at least one city' : 'Continue with ${citiesLabel(k)}'),
    );

    Widget body;
    if (phone) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          count,
          if (k > 0 || unlisted.isNotEmpty) links,
          if (maxLine != null) ...[const SizedBox(height: 2), maxLine],
          const SizedBox(height: 8),
          button,
        ],
      );
    } else {
      final left = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [count, if (k > 0 || unlisted.isNotEmpty) links],
      );
      final right = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (maxLine != null) ...[Flexible(child: maxLine), const SizedBox(width: 12)],
          button,
        ],
      );
      body = LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 900) {
          return Row(children: [Expanded(child: left), const SizedBox(width: 16), right]);
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: 8), Align(alignment: Alignment.centerRight, child: right)],
        );
      });
    }

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E21),
        border: Border(top: BorderSide(color: UiTokens.border)),
      ),
      padding: EdgeInsets.symmetric(horizontal: phone ? 16 : 24, vertical: phone ? 10 : 12),
      child: body,
    );
  }
}

class _LinkButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _LinkButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: UiTokens.accent,
        // 48 px tall on phones (touch), 40 px on larger screens.
        minimumSize: Size(48, MediaQuery.sizeOf(context).width < AppBreakpoints.mobile ? 48 : 40),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

/// "Review list": dialog on tablet/desktop, bottom sheet on phones. Chips
/// remove cities one by one; cities that are no longer listed are shown
/// first with the tag and an explicit Remove action.
Future<void> showReviewList(BuildContext context, {required LocationCatalog catalog, String? country}) {
  final phone = MediaQuery.sizeOf(context).width < AppBreakpoints.mobile;
  if (phone) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: UiTokens.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: _ReviewList(catalog: catalog, country: country),
          ),
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      backgroundColor: UiTokens.card,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _ReviewList(catalog: catalog, country: country),
        ),
      ),
    ),
  );
}

class _ReviewList extends StatelessWidget {
  final LocationCatalog catalog;
  final String? country;

  const _ReviewList({required this.catalog, this.country});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: catalog,
      builder: (context, _) {
        final setup = context.watch<SearchSetupProvider>();
        final k = setup.cityCount;
        final unlisted = catalog.noLongerListed(setup.cities, country: country);
        final unlistedKeys = unlisted.map(cityKey).toSet();
        final listed = setup.cities.where((c) => !unlistedKeys.contains(cityKey(c))).toList();
        final extras = setup.extraCities;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      k == 0 ? 'No cities selected' : '${citiesLabel(k)} selected',
                      style: findTitleStyle,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  icon: const Icon(Icons.close_rounded, color: UiTokens.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            if (unlisted.isNotEmpty) ...[
              const SizedBox(height: 8),
              FindNotice(text: noLongerListedNotice(unlisted.length)),
            ],
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final c in unlisted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Flexible(child: Text(c, style: findBodyStyle)),
                            const SizedBox(width: 8),
                            const NoLongerListedTag(),
                            const Spacer(),
                            TextButton(
                              style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(64, 44)),
                              onPressed: () => setup.removeCities([c]),
                              child: Text('Remove', semanticsLabel: 'Remove $c'),
                            ),
                          ],
                        ),
                      ),
                    if (unlisted.isNotEmpty) const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in listed)
                          CityChip(
                            city: c,
                            label: displayCityName(c),
                            note: SearchSetupProvider.regionOf(c),
                            onRemove: () => setup.removeCities([c]),
                          ),
                        for (final c in extras)
                          CityChip(
                            city: c,
                            label: c,
                            note: 'added by you',
                            onRemove: () => setup.removeExtraCity(c),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (k > 0)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(64, 44)),
                    onPressed: () => confirmClearAll(context, setup),
                    child: const Text('Clear all'),
                  ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: UiTokens.primary, minimumSize: const Size(88, 44)),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
