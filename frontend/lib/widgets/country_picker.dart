import 'package:flutter/material.dart';

import '../core/countries.dart';
import 'app_shell_common.dart' show UiTokens;
import 'country_flag_badge.dart';

/// Searchable country list (name, code or dial code). Returns the choice.
Future<Country?> showCountryPicker(BuildContext context, {Country? selected}) {
  return showDialog<Country>(
    context: context,
    builder: (ctx) => _CountryPickerDialog(selected: selected),
  );
}

class _CountryPickerDialog extends StatefulWidget {
  final Country? selected;
  const _CountryPickerDialog({this.selected});

  @override
  State<_CountryPickerDialog> createState() => _CountryPickerDialogState();
}

class _CountryPickerDialogState extends State<_CountryPickerDialog> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase().replaceFirst('+', '');
    final list = q.isEmpty
        ? kCountries
        : kCountries
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.iso.toLowerCase() == q ||
                c.dial.startsWith(q))
            .toList();
    return Dialog(
      backgroundColor: UiTokens.card,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: UiTokens.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                style: const TextStyle(color: UiTokens.text, fontSize: 14),
                cursorColor: UiTokens.accent,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: UiTokens.background,
                  hintText: 'Search country or dial code',
                  hintStyle:
                      const TextStyle(color: UiTokens.textMuted, fontSize: 14),
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: UiTokens.textMuted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: UiTokens.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: UiTokens.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: UiTokens.accent),
                  ),
                ),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(
                      child: Text('No country matches',
                          style: TextStyle(color: UiTokens.textMuted)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: list.length,
                      itemBuilder: (ctx, i) {
                        final c = list[i];
                        final on = c.iso == widget.selected?.iso;
                        return InkWell(
                          onTap: () => Navigator.of(ctx).pop(c),
                          child: Container(
                            color: on ? UiTokens.selectedSurface : null,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 11),
                            child: Row(
                              children: [
                                CountryFlagBadge(countryName: c.iso, size: 16),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: UiTokens.text, fontSize: 14)),
                                ),
                                Text('+${c.dial}',
                                    style: const TextStyle(
                                        color: UiTokens.textSecondary,
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The flag + dial code control that sits to the left of a number field.
class CountryDialButton extends StatelessWidget {
  final Country? country;
  final ValueChanged<Country> onChanged;
  final Color background;
  final Color border;
  final Color foreground;
  final double radius;
  final double height;

  const CountryDialButton({
    super.key,
    required this.country,
    required this.onChanged,
    required this.background,
    required this.border,
    required this.foreground,
    this.radius = 8,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    final c = country;
    return Tooltip(
      message: c == null ? 'Choose a country' : c.name,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: () async {
            final picked = await showCountryPicker(context, selected: c);
            if (picked != null) onChanged(picked);
          },
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CountryFlagBadge(countryName: c?.iso, size: 16),
                  const SizedBox(width: 8),
                  Text(c == null ? 'Country' : '+${c.dial}',
                      style: TextStyle(
                          color: foreground,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  Icon(Icons.arrow_drop_down, size: 18, color: foreground),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
