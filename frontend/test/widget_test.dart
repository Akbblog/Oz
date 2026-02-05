// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:business_scraper_app/main.dart';
import 'package:business_scraper_app/providers/auth_provider.dart';
import 'package:business_scraper_app/providers/scraper_provider.dart';
import 'package:business_scraper_app/providers/theme_provider.dart';

void main() {
  testWidgets('App boots to auth wrapper', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ScraperProvider()),
        ],
        child: const MyApp(),
      ),
    );

    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Smoke assertion: we should render something without crashing.
    expect(find.byType(MyApp), findsOneWidget);
  });
}
