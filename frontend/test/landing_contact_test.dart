import 'dart:convert';

import 'package:business_scraper_app/admin/admin_shell.dart';
import 'package:business_scraper_app/core/error_handler.dart';
import 'package:business_scraper_app/admin/pages/messages_page.dart';
import 'package:business_scraper_app/providers/auth_provider.dart';
import 'package:business_scraper_app/screens/landing/landing_screen.dart';
import 'package:business_scraper_app/services/analytics_service.dart';
import 'package:business_scraper_app/services/api_service.dart';
import 'package:business_scraper_app/widgets/contact_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends ApiService {
  Object? sendError;
  final List<Map<String, dynamic>> sent = [];
  final List<Map<String, dynamic>> updates = [];
  List<Map<String, dynamic>> inbox = [];

  @override
  Future<Map<String, dynamic>> getLocationsSummary() async => {
        'USA': {
          'region_term': 'state',
          'regions': {'Texas': 30, 'Ohio': 12}
        },
        'Canada': {
          'region_term': 'province',
          'regions': {'Quebec': 8}
        },
      };

  @override
  Future<void> sendContactMessage({
    required String name,
    required String email,
    required String message,
    String? phone,
    String? phoneCountry,
    String? topic,
    String? website,
    String? visitorId,
    String? geoCountry,
    String? geoCity,
    String? page,
  }) async {
    if (sendError != null) throw sendError!;
    sent.add({'name': name, 'email': email, 'message': message, 'topic': topic, 'phone': phone});
  }

  @override
  Future<Map<String, dynamic>> getAdminContactMessages(
          {String? status, String? q, int limit = 50, int offset = 0}) async =>
      {
        'messages': inbox,
        'total': inbox.length,
        'counts': {'new': 1, 'read': 0, 'replied': 0, 'archived': 0, 'total': 1},
      };

  @override
  Future<Map<String, dynamic>> getAdminContactSummary() async =>
      {'new': 1, 'read': 0, 'replied': 0, 'archived': 0, 'total': 1};

  @override
  Future<Map<String, dynamic>> updateAdminContactMessage(int id,
      {String? status, String? adminNote}) async {
    updates.add({'id': id, 'status': status, 'note': adminNote});
    return {...inbox.first, if (status != null) 'status': status, 'admin_note': adminNote};
  }

  @override
  Future<Map<String, dynamic>> getAdminOverview(String range) async => {
        'snapshot': {'pending_users': 0, 'pending_credit_requests': 0}
      };
}

final _noNetwork = MockClient((req) async => http.Response('{}', 404));

Future<void> _pump(WidgetTester tester, Widget child,
    {Size size = const Size(1400, 1000), Map<String, WidgetBuilder>? routes}) async {
  SharedPreferences.setMockInitialValues({});
  AnalyticsService.instance.resetGeo();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider(
    create: (_) => AuthProvider(),
    child: MaterialApp(home: child, routes: routes ?? const {}),
  ));
}

/// The landing page animates forever, so settle by time instead.
Future<void> _settle(WidgetTester tester, [int ms = 2400]) async {
  for (var i = 0; i < ms ~/ 100; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('landing page', () {
    testWidgets('shows the offer, live coverage numbers and leads to the search', (tester) async {
      await http.runWithClient(() async {
        await _pump(tester, LandingScreen(api: _FakeApi()),
            routes: {'/find': (_) => const Scaffold(body: Text('FIND PAGE'))});
        await _settle(tester);
        expect(find.text('Find every business'), findsOneWidget);
        expect(find.text('you could sell to.'), findsOneWidget);
        // From the live location data: 2 countries.
        expect(find.text('Local business leads in 2 countries'), findsOneWidget);
        expect(find.text('Sample results for illustration'), findsOneWidget,
            reason: 'the hero animation is labelled as sample data');
        await tester.tap(find.byKey(const Key('hero-find')));
        await _settle(tester, 600);
        expect(find.text('FIND PAGE'), findsOneWidget);
      }, () => _noNetwork);
    });

    for (final size in const [Size(390, 844), Size(820, 1100)]) {
      testWidgets('lays out at ${size.width.toInt()}px without overflow', (tester) async {
        await http.runWithClient(() async {
          await _pump(tester, LandingScreen(api: _FakeApi()), size: size);
          await _settle(tester);
          expect(find.text('Find every business'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }, () => _noNetwork);
      });
    }
  });

  group('contact form', () {
    Future<void> fill(WidgetTester tester, String key, String text) async {
      await tester.enterText(find.byKey(Key('contact-$key')), text);
      await tester.pump();
    }

    Widget host(_FakeApi api) => Scaffold(
          body: SingleChildScrollView(
              padding: const EdgeInsets.all(24), child: ContactForm(api: api)),
        );

    testWidgets('says what is missing, then sends and confirms', (tester) async {
      final api = _FakeApi();
      await http.runWithClient(() async {
        await _pump(tester, host(api), size: const Size(900, 1400));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('contact-send')));
        await tester.pumpAndSettle();
        expect(find.text('Please tell us your name'), findsOneWidget);
        expect(find.text('Enter an email we can reply to'), findsOneWidget);
        expect(find.text('Please write a little more so we can help'), findsOneWidget);
        expect(api.sent, isEmpty);

        await fill(tester, 'name', 'Maria Lopez');
        await fill(tester, 'email', 'maria@example.com');
        await fill(tester, 'message', 'Do you cover dentists in Karachi?');
        await tester.tap(find.text('Sales'));
        await tester.pump();
        await tester.tap(find.byKey(const Key('contact-send')));
        await tester.pumpAndSettle();
        expect(api.sent.single, {
          'name': 'Maria Lopez',
          'email': 'maria@example.com',
          'message': 'Do you cover dentists in Karachi?',
          'topic': 'sales',
          'phone': '',
        });
        expect(find.text('Message sent'), findsOneWidget);
      }, () => _noNetwork);
    });

    testWidgets('a refusal from the server is shown and the text is kept', (tester) async {
      final api = _FakeApi()..sendError = ApiException('You have sent several messages already.');
      await http.runWithClient(() async {
        await _pump(tester, host(api), size: const Size(900, 1400));
        await tester.pumpAndSettle();
        await fill(tester, 'name', 'Omar H');
        await fill(tester, 'email', 'omar@example.com');
        await fill(tester, 'message', 'A long enough message.');
        await tester.tap(find.byKey(const Key('contact-send')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('contact-error')), findsOneWidget);
        expect(find.textContaining('several messages already'), findsOneWidget);
        expect(find.text('A long enough message.'), findsOneWidget);
        expect(find.text('Message sent'), findsNothing);
      }, () => _noNetwork);
    });
  });

  group('admin messages', () {
    testWidgets('lists messages; opening a new one marks it read; replying closes it', (tester) async {
      final api = _FakeApi()
        ..inbox = [
          {
            'id': 7, 'user_id': null, 'username': null, 'name': 'Maria Lopez',
            'email': 'maria@example.com', 'phone': '+923001234567', 'topic': 'sales',
            'message': 'Do you cover dentists in Karachi?', 'status': 'new', 'admin_note': null,
            'handled_at': null, 'ip_address': '203.0.113.7', 'country': 'PK', 'city': 'Lahore',
            'device': 'Chrome · Windows · desktop', 'page': '/', 'created_at': '2026-01-10T09:00:00+00:00',
          }
        ];
      AdminBadges.apiFactory = () => api;
      addTearDown(() => AdminBadges.apiFactory = ApiService.new);
      await http.runWithClient(() async {
        await _pump(tester, AdminMessagesPage(api: api), size: const Size(1500, 1400));
        await tester.pumpAndSettle();
        expect(find.text('Maria Lopez'), findsOneWidget);
        expect(find.text('Do you cover dentists in Karachi?'), findsOneWidget);
        expect(AdminBadges.instance.newMessages, 1);

        await tester.tap(find.text('Maria Lopez'));
        await tester.pumpAndSettle();
        expect(api.updates.first, {'id': 7, 'status': 'read', 'note': null});
        expect(find.text('Reply by email'), findsOneWidget);
        expect(find.text('WhatsApp'), findsOneWidget);
        expect(find.text('Lahore, Pakistan'), findsOneWidget);

        await tester.tap(find.text('Mark as replied'));
        await tester.pumpAndSettle();
        expect(api.updates.last['status'], 'replied');
        expect(find.text('Reply by email'), findsNothing, reason: 'the record closes');
      }, () => _noNetwork);
    });
  });
}
