import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

/// A small, fixed-size country flag (SVG, from `country_flags`), meant to sit
/// next to the country's name.
///
/// * Decorative: it is excluded from semantics, so always show the country
///   name beside it (the name carries the meaning, never the flag alone).
/// * Fixed size ([size] = height, width = 4:3), so rows never jump while the
///   SVG loads or when the country is unknown.
/// * A subtle 1 px border and rounded corners keep white or dark flags
///   visible on any background.
/// * Unknown countries fall back to a neutral globe icon in the same box.
///
/// [countryName] accepts what the app uses: API keys ("USA", "UK", "UAE",
/// "KSA", "Canada", ...), display names ("United States", "Saudi Arabia",
/// ...), common aliases, and ISO 3166 alpha-2/alpha-3 codes. Case and
/// surrounding spaces are ignored.
///
/// ```dart
/// Row(children: [
///   CountryFlagBadge(countryName: 'Canada', size: 20),
///   SizedBox(width: 8),
///   Text('Canada'),
/// ])
/// ```
class CountryFlagBadge extends StatelessWidget {
  /// Country key, display name, alias or ISO code. Null/unknown shows a globe.
  final String? countryName;

  /// Flag height in logical pixels; the width is `size * 4 / 3`.
  final double size;

  const CountryFlagBadge({super.key, required this.countryName, this.size = 20});

  /// Hairline drawn over the flag edges so white or dark flags don't blend
  /// into the background.
  static const Color borderColor = Color(0x66A9B4C2);

  /// Globe colour for unknown countries.
  static const Color fallbackColor = Color(0xFFA9B4C2);

  static const Map<String, String> _aliases = {
    // API keys the backend uses.
    'usa': 'US',
    'uk': 'GB',
    'uae': 'AE',
    'ksa': 'SA',
    // Display names and common aliases.
    'united states': 'US',
    'united states of america': 'US',
    'america': 'US',
    'u.s.': 'US',
    'u.s.a.': 'US',
    'united kingdom': 'GB',
    'great britain': 'GB',
    'britain': 'GB',
    'england': 'GB',
    'scotland': 'GB',
    'wales': 'GB',
    'northern ireland': 'GB',
    'united arab emirates': 'AE',
    'emirates': 'AE',
    'saudi arabia': 'SA',
    'kingdom of saudi arabia': 'SA',
    'saudi': 'SA',
    'australia': 'AU',
    'canada': 'CA',
    'india': 'IN',
    'qatar': 'QA',
    'indonesia': 'ID',
    'malaysia': 'MY',
    'singapore': 'SG',
    'china': 'CN',
    "people's republic of china": 'CN',
    'finland': 'FI',
    'germany': 'DE',
    'deutschland': 'DE',
    'france': 'FR',
  };

  /// ISO 3166 alpha-2 code for [country] ("Canada" -> "CA", "USA" -> "US",
  /// "United Kingdom" -> "GB"), or null when unknown.
  static String? isoCodeFor(String? country) {
    if (country == null) return null;
    final key = country.trim().toLowerCase();
    if (key.isEmpty) return null;
    final alias = _aliases[key];
    if (alias != null) return alias;
    final code = key.toUpperCase();
    if (!RegExp(r'^[A-Z]{2,3}$').hasMatch(code)) return null;
    // The package maps alpha-2 and alpha-3 codes to its flag files, which are
    // named after the lower-case alpha-2 code.
    final flag = FlagCode.fromCountryCode(code);
    return (flag != null && flag.length == 2) ? flag.toUpperCase() : null;
  }

  /// True when a real flag (not the globe) would be shown for [country].
  static bool hasFlag(String? country) {
    final iso = isoCodeFor(country);
    return iso != null && FlagCode.fromCountryCode(iso) != null;
  }

  @override
  Widget build(BuildContext context) {
    final height = size;
    final width = size * 4 / 3;
    final radius = BorderRadius.circular(size <= 16 ? 2 : 3);
    final iso = isoCodeFor(countryName);
    final known = iso != null && FlagCode.fromCountryCode(iso) != null;

    final Widget content = known
        ? CountryFlag.fromCountryCode(
            iso,
            key: ValueKey<String>('flag-$iso'),
            theme: ImageTheme(width: width, height: height, shape: const Rectangle()),
          )
        : Center(
            key: const ValueKey<String>('flag-unknown'),
            child: Icon(Icons.public_rounded, size: height, color: fallbackColor),
          );

    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: known
            ? ClipRRect(
                borderRadius: radius,
                child: DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: borderColor, width: 1),
                  ),
                  child: content,
                ),
              )
            : content,
      ),
    );
  }
}
