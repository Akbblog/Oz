import 'package:business_scraper_app/app_router.dart';
import 'package:business_scraper_app/config/business_info.dart';
import 'package:business_scraper_app/providers/auth_provider.dart';
import 'package:business_scraper_app/screens/landing/landing_screen.dart';
import 'package:business_scraper_app/screens/legal/policies.dart';
import 'package:business_scraper_app/screens/legal/policy_screen.dart';
import 'package:business_scraper_app/services/analytics_service.dart';
import 'package:business_scraper_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends ApiService {
  @override
  Future<Map<String, dynamic>> getLocationsSummary() async => {
        'USA': {
          'region_term': 'state',
          'regions': {'Texas': 30}
        },
      };

  @override
  Future<Map<String, dynamic>> getPublicCreditPacks() async => {
        'currency': 'USD',
        'packs': [
          {'id': 4, 'name': 'Starter', 'credits': 500, 'price_cents': 2500, 'is_featured': false},
          {'id': 5, 'name': 'Growth', 'credits': 2500, 'price_cents': 10000, 'is_featured': true},
          {'id': 3, 'name': 'Bulk', 'credits': 15000, 'price_cents': 45000, 'is_featured': false},
        ],
      };
}

final _noNetwork = MockClient((req) async => http.Response('{}', 404));

Future<void> _settle(WidgetTester tester, [int ms = 2400]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpApp(WidgetTester tester, Widget home, {Size size = const Size(1400, 1000)}) async {
  SharedPreferences.setMockInitialValues({});
  AnalyticsService.instance.resetGeo();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider(
    create: (_) => AuthProvider(),
    child: MaterialApp(
      home: home,
      routes: {
        for (final d in Policies.all) d.route: (_) => PolicyScreen(doc: d),
        '/contact': (_) => const Scaffold(body: Text('CONTACT PAGE')),
        '/pricing': (_) => const Scaffold(body: Text('PRICING PAGE')),
      },
    ),
  ));
}

void main() {
  testWidgets('landing shows public prices and links every policy from the footer', (tester) async {
    await http.runWithClient(() async {
      await _pumpApp(tester, LandingScreen(api: _Api()));
      await _settle(tester);
      expect(find.text('Buy credits once, use them any time'), findsOneWidget);
      expect(find.text('US\$25.00'), findsOneWidget);
      expect(find.text('US\$100.00'), findsOneWidget);
      expect(find.text('US\$450.00'), findsOneWidget);
      expect(find.text('500 credits · US\$0.05 per credit'), findsOneWidget);
      expect(find.text('Credits never expire'), findsNWidgets(3));
      for (final label in [
        'Terms and Conditions',
        'Privacy Policy',
        'Refund and Cancellation',
        'Delivery Policy',
      ]) {
        expect(find.descendant(of: find.byKey(const ValueKey('landing-footer')), matching: find.text(label)),
            findsOneWidget, reason: label);
      }
      expect(find.textContaining(BusinessInfo.email), findsWidgets);
      final link = find.descendant(
          of: find.byKey(const ValueKey('landing-footer')), matching: find.text('Refund and Cancellation'));
      await tester.ensureVisible(link);
      await tester.tap(link);
      await _settle(tester, 800);
      expect(find.text('Refund and Cancellation Policy'), findsWidgets);
    }, () => _noNetwork);
  });

  testWidgets('each policy states the commitments Safepay reviews', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    String textOf(PolicyDoc d) => d.sections.expand((s) => [s.heading, ...s.paragraphs]).join('\n');

    final refund = textOf(Policies.refund);
    expect(refund, contains('within 7 days'));
    expect(refund, contains('none of that pack\'s credits have been used'));
    expect(refund, contains('Cancel payment'));
    expect(refund, contains('no subscriptions'));
    final terms = textOf(Policies.terms);
    expect(terms, contains('Purchased credits do not expire'));
    expect(terms, contains('processed by Safepay'));
    expect(terms, contains('US dollars'));
    final delivery = textOf(Policies.delivery);
    expect(delivery, contains('Nothing is shipped'));
    expect(delivery, contains('Payment confirmed'));
    expect(textOf(Policies.privacy), contains('never receive or store your full card number'));

    for (final d in Policies.all) {
      await tester.pumpWidget(MaterialApp(home: PolicyScreen(doc: d)));
      await tester.pump();
      expect(find.text(d.title), findsOneWidget);
      expect(find.byKey(const ValueKey('merchant-card')), findsOneWidget);
      // Nothing half-filled is ever shown.
      expect(find.textContaining('TODO'), findsNothing);
      expect(find.textContaining(', ,'), findsNothing);
    }
  });

  testWidgets('policy URLs open for signed-out visitors', (tester) async {
    SharedPreferences.setMockInitialValues({});
    for (final d in Policies.all) {
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: MaterialApp(onGenerateRoute: AppRouter.onGenerateRoute, initialRoute: d.route),
      ));
      await tester.pump();
      expect(find.text(d.title), findsOneWidget, reason: d.route);
    }
    for (final alias in ['/cancellation-policy', '/terms-and-conditions', '/privacy']) {
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: MaterialApp(onGenerateRoute: AppRouter.onGenerateRoute, initialRoute: alias),
      ));
      await tester.pump();
      expect(find.byType(PolicyScreen), findsOneWidget, reason: alias);
    }
  });
}
