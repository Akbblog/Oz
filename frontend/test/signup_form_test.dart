import 'dart:convert';

import 'package:business_scraper_app/core/countries.dart';
import 'package:business_scraper_app/providers/auth_provider.dart';
import 'package:business_scraper_app/screens/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sign-up form: easy to fill in, and it sends clean, structured data.
void main() {
  Future<void> open(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const RegisterScreen())),
                child: const Text('open sign-up'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open sign-up'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(Key('signup-$key')), text);
    await tester.pump();
  }

  test('country helpers', () {
    expect(countryByIso('pk')!.dial, '92');
    expect(countryName('AE'), 'United Arab Emirates');
    expect(countryName('ZZ'), 'ZZ');
    expect(countryFromLocale('en-PK')!.iso, 'PK');
    expect(countryFromLocale('en'), isNull);
    expect(prettyPhone('+923316694449', 'PK'), '+92 3316694449');
    expect(prettyPhone('03316694449', null), '03316694449');
    expect(kCountries.map((c) => c.iso).toSet().length, kCountries.length,
        reason: 'no country listed twice');
  });

  testWidgets('asks for name, email, phone with country and one password', (tester) async {
    await http.runWithClient(() async {
      await open(tester);
      for (final label in ['Full name', 'Work email', 'Phone number', 'Company (optional)', 'Password']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Username'), findsNothing);
      expect(find.text('Confirm Password'), findsNothing);
      // Country preselected from the network location.
      expect(find.text('+92'), findsOneWidget);
    }, () => MockClient((req) async => http.Response(jsonEncode({'country': 'PK'}), 200)));
  });

  testWidgets('says what is missing under each field', (tester) async {
    await http.runWithClient(() async {
      await open(tester);
      await fill(tester, 'email', 'maria@');
      await fill(tester, 'phone', '12');
      await fill(tester, 'password', 'short');
      await tester.tap(find.text('Create Account').last);
      await tester.pumpAndSettle();
      expect(find.text('Please enter your name'), findsOneWidget);
      expect(find.text('That email address does not look complete'), findsOneWidget);
      expect(find.text('That number does not look complete'), findsOneWidget);
      expect(find.text('Use at least 8 characters'), findsOneWidget);
    }, () => MockClient((req) async => http.Response('{"country": null}', 200)));
  });

  testWidgets('sends structured data; a taken sign-in name is retried silently', (tester) async {
    final bodies = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      if (req.url.path == '/api/geo/hint') {
        return http.Response(jsonEncode({'country': 'PK'}), 200);
      }
      if (req.url.path == '/api/auth/register') {
        bodies.add(Map<String, dynamic>.from(jsonDecode(req.body)));
        if (bodies.length == 1) {
          return http.Response(jsonEncode({'detail': 'Username already exists'}), 400,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode({'message': 'Account created'}), 201,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 404);
    });
    await http.runWithClient(() async {
      await open(tester);
      await fill(tester, 'name', 'Maria Lopez');
      await fill(tester, 'email', 'Maria.Lopez@Example.com');
      await fill(tester, 'phone', '0300 1234567');
      await fill(tester, 'company', 'Lopez Dental');
      await fill(tester, 'password', 'UserPass12345!');
      await tester.tap(find.text('Create Account').last);
      await tester.pumpAndSettle();
    }, () => client);

    expect(bodies.length, 2);
    expect(bodies[0]['username'], 'maria.lopez');
    expect(bodies[1]['username'], matches(RegExp(r'^maria\.lopez\d{3}$')));
    final sent = bodies[1];
    expect(sent['email'], 'maria.lopez@example.com');
    expect(sent['full_name'], 'Maria Lopez');
    expect(sent['company'], 'Lopez Dental');
    expect(sent['phone'], '0300 1234567');
    expect(sent['phone_country'], 'PK');
    // Back on the previous page after a successful sign-up.
    expect(find.text('open sign-up'), findsOneWidget);
  });

  testWidgets('a server refusal appears under the field it is about', (tester) async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/auth/register') {
        return http.Response(
            jsonEncode({'detail': 'This phone number is already registered'}), 400,
            headers: {'content-type': 'application/json'});
      }
      return http.Response(jsonEncode({'country': 'US'}), 200);
    });
    await http.runWithClient(() async {
      await open(tester);
      await fill(tester, 'name', 'Omar H');
      await fill(tester, 'email', 'omar@example.com');
      await fill(tester, 'phone', '5125550142');
      await fill(tester, 'password', 'UserPass12345!');
      await tester.tap(find.text('Create Account').last);
      await tester.pumpAndSettle();
      expect(find.text('This phone number is already registered'), findsOneWidget);
      expect(find.text('Full name'), findsOneWidget, reason: 'still on the form');
    }, () => client);
  });
}
