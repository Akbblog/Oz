import 'package:business_scraper_app/widgets/country_flag_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CountryFlagBadge.isoCodeFor', () {
    test('maps the app\'s country keys and display names', () {
      const expected = {
        'USA': 'US',
        'United States': 'US',
        'UK': 'GB',
        'United Kingdom': 'GB',
        'UAE': 'AE',
        'United Arab Emirates': 'AE',
        'KSA': 'SA',
        'Saudi Arabia': 'SA',
        'Australia': 'AU',
        'Canada': 'CA',
        'India': 'IN',
        'Qatar': 'QA',
        'Indonesia': 'ID',
        'Malaysia': 'MY',
        'Singapore': 'SG',
        'China': 'CN',
        'Finland': 'FI',
        'Germany': 'DE',
        'France': 'FR',
      };
      expected.forEach((name, iso) => expect(CountryFlagBadge.isoCodeFor(name), iso, reason: name));
    });

    test('ignores case and spaces; accepts ISO codes', () {
      expect(CountryFlagBadge.isoCodeFor('  canada '), 'CA');
      expect(CountryFlagBadge.isoCodeFor('ca'), 'CA');
      expect(CountryFlagBadge.isoCodeFor('CAN'), 'CA');
      expect(CountryFlagBadge.isoCodeFor('JP'), 'JP');
    });

    test('unknown or empty -> null', () {
      expect(CountryFlagBadge.isoCodeFor(null), isNull);
      expect(CountryFlagBadge.isoCodeFor(''), isNull);
      expect(CountryFlagBadge.isoCodeFor('Atlantis'), isNull);
      expect(CountryFlagBadge.isoCodeFor('ZZ'), isNull);
      expect(CountryFlagBadge.hasFlag('Atlantis'), isFalse);
      expect(CountryFlagBadge.hasFlag('Canada'), isTrue);
    });
  });

  group('CountryFlagBadge widget', () {
    Future<void> pump(WidgetTester tester, Widget child) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));

    testWidgets('fixed 4:3 box, decorative (no semantics)', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(
        tester,
        const Row(mainAxisSize: MainAxisSize.min, children: [
          CountryFlagBadge(countryName: 'Canada', size: 18),
          Text('Canada'),
        ]),
      );
      expect(tester.getSize(find.byType(CountryFlagBadge)), const Size(24, 18));
      expect(find.byKey(const ValueKey<String>('flag-CA')), findsOneWidget);
      // Only the name is announced.
      expect(find.bySemanticsLabel('Canada'), findsOneWidget);
      final excluded = find.descendant(of: find.byType(CountryFlagBadge), matching: find.byType(ExcludeSemantics));
      expect(excluded, findsWidgets);
      handle.dispose();
    });

    testWidgets('unknown country falls back to a globe in the same box', (tester) async {
      await pump(tester, const CountryFlagBadge(countryName: 'Atlantis', size: 20));
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.public_rounded), findsOneWidget);
      expect(tester.getSize(find.byType(CountryFlagBadge)).height, 20);
      await pump(tester, const CountryFlagBadge(countryName: null));
      expect(find.byIcon(Icons.public_rounded), findsOneWidget);
    });
  });
}
