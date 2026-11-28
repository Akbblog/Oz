import 'package:business_scraper_app/app_router.dart';
import 'package:business_scraper_app/core/error_handler.dart';
import 'package:business_scraper_app/main.dart';
import 'package:business_scraper_app/providers/active_searches_provider.dart';
import 'package:business_scraper_app/providers/auth_provider.dart';
import 'package:business_scraper_app/providers/credit_provider.dart';
import 'package:business_scraper_app/providers/scraper_provider.dart';
import 'package:business_scraper_app/providers/search_setup_provider.dart';
import 'package:business_scraper_app/screens/find/location_step.dart';
import 'package:business_scraper_app/screens/landing/landing_screen.dart';
import 'package:business_scraper_app/screens/home_screen.dart';
import 'package:business_scraper_app/screens/login_screen.dart';
import 'package:business_scraper_app/screens/search_detail_screen.dart';
import 'package:business_scraper_app/services/api_service.dart';
import 'package:business_scraper_app/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signed-in session without a server.
class FakeAuth extends AuthProvider {
  FakeAuth({this.admin = false});
  final bool admin;

  @override
  bool get isAuthenticated => true;
  @override
  bool get isRestoring => false;
  @override
  bool get isLoading => false;
  @override
  bool get isAdmin => admin;
  @override
  Map<String, dynamic>? get currentUser => {'username': 'rita', 'email': 'r@example.com'};
}

class FakeApi extends ApiService {
  List<Map<String, dynamic>> active = [];
  List<Map<String, dynamic>> jobs = [];
  int? total;
  Object? jobsError;

  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<List<Map<String, dynamic>>> getActiveJobs() async => active;

  @override
  Future<Map<String, dynamic>> getJobs({int? limit, int? offset, String? status, String? q, DateTime? from, DateTime? to, String? sort}) async {
    if (jobsError != null) throw jobsError!;
    final page = limit == null ? jobs : jobs.take(limit).toList();
    return {'jobs': page, 'total': total ?? jobs.length, 'counts': <String, int>{}, 'paginated': true};
  }
}

String _nowIso() => DateTime.now().toUtc().toIso8601String();

Map<String, dynamic> _job(
  String id,
  String status, {
  String category = 'plumbers',
  int results = 0,
  int charged = 0,
  int refunded = 0,
  bool? settled,
  int done = 0,
  int total = 4,
}) =>
    {
      'job_id': id,
      'status': status,
      'category': category,
      'cities': ['Montreal, Quebec', 'Laval, Quebec', 'Gatineau, Quebec', 'Longueuil, Quebec'],
      'country': 'Canada',
      'total_cities': total,
      'completed_cities': done,
      'result_count': results,
      'credit_charged': charged,
      'credit_refunded': refunded,
      'settled': settled,
      'created_at': _nowIso(),
      'server_time': _nowIso(),
      'max_results_per_city': 10,
    };

Widget _app({
  required AuthProvider auth,
  required FakeApi api,
  required ActiveSearchesProvider active,
  Widget? home,
  String initialRoute = '/',
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider(create: (_) => ScraperProvider(api: api)),
      ChangeNotifierProvider<CreditProvider>.value(value: CreditProvider.instance),
      ChangeNotifierProvider(create: (_) => SearchSetupProvider(autoLoad: false)),
      ChangeNotifierProvider<ActiveSearchesProvider>.value(value: active),
    ],
    child: MaterialApp(
      home: home,
      initialRoute: home == null ? initialRoute : null,
      onGenerateRoute: AppRouter.onGenerateRoute,
    ),
  );
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CreditProvider.instance.clear();
  });

  testWidgets('guest opening / sees the landing page; its button opens Find leads with guest navigation',
      (tester) async {
    _size(tester, const Size(1440, 900));
    await tester.pumpWidget(MultiProvider(providers: buildAppProviders(), child: const MyApp()));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(LandingScreen), findsOneWidget);
    expect(find.text('Find every business'), findsOneWidget);
    await tester.tap(find.byKey(const Key('hero-find')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(FindLocationStep), findsOneWidget);
    expect(find.text('Find leads'), findsWidgets);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('My searches'), findsNothing, reason: 'guests only see Find leads + Sign in');
    expect(find.textContaining('v2.'), findsNothing, reason: 'one wordmark, no version strings');
  });

  testWidgets('desktop shell: sidebar labels, live chip and "1 live" count', (tester) async {
    _size(tester, const Size(1440, 900));
    final api = FakeApi()..active = [_job('j1', 'running', done: 2, results: 9, charged: 70)];
    final active = ActiveSearchesProvider(api: api);
    CreditProvider.instance.setBalance(4102);
    await tester.pumpWidget(_app(
      auth: FakeAuth(admin: true),
      api: api,
      active: active,
      home: const AppShell(section: ShellSection.home, title: 'Home', child: SizedBox()),
    ));
    active.start();
    await tester.pump();
    await tester.pump();

    for (final label in ['Home', 'Find leads', 'My searches', 'Credits', 'Account', 'Admin', 'Infinity Leads']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('1 live'), findsOneWidget);
    expect(find.text('Searching · plumbers · 2 of 4 cities'), findsOneWidget);
    expect(find.text('4,102 credits'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'4,102 credits\. Open credits')), findsOneWidget);
    active.stop();
  });

  testWidgets('phone shell: bottom bar labels and live banner', (tester) async {
    _size(tester, const Size(390, 844));
    final api = FakeApi()..active = [_job('j1', 'pending')];
    final active = ActiveSearchesProvider(api: api);
    await tester.pumpWidget(_app(
      auth: FakeAuth(),
      api: api,
      active: active,
      home: const AppShell(section: ShellSection.home, title: 'Home', child: SizedBox()),
    ));
    active.start();
    await tester.pump();
    await tester.pump();
    for (final label in ['Home', 'Find leads', 'Searches', 'Credits', 'Account']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Queued · plumbers'), findsOneWidget);
    active.stop();
  });

  testWidgets('Home: recent searches with truthful credits and next steps', (tester) async {
    _size(tester, const Size(1440, 1400));
    final api = FakeApi()
      ..jobs = [
        _job('a', 'running', results: 9, charged: 70, done: 2),
        _job('b', 'completed', category: 'gyms', results: 7, charged: 40, refunded: 13, settled: true),
        _job('c', 'cancelled', category: 'law firms', results: 3, charged: 70, settled: false),
        _job('d', 'failed', results: 0, charged: 30, refunded: 30, settled: true),
      ];
    final active = ActiveSearchesProvider(api: api);
    CreditProvider.instance.setBalance(10);
    CreditProvider.instance.setConfig({'min_job_cost': 25});
    await tester.pumpWidget(_app(
      auth: FakeAuth(),
      api: api,
      active: active,
      home: HomeScreen(api: api),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Find business leads'), findsOneWidget);
    expect(find.text('Run "plumbers · Quebec" again'), findsOneWidget);
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('View progress'), findsOneWidget);
    expect(find.text('Open results'), findsOneWidget);
    expect(find.text('View partial results'), findsOneWidget);
    expect(find.text('See why'), findsOneWidget);
    expect(find.text('9 so far'), findsOneWidget);
    expect(find.text('70 charged'), findsOneWidget);
    expect(find.textContaining('(13 returned)'), findsOneWidget);
    expect(find.text('70 charged · refund pending'), findsOneWidget);
    expect(find.text('Montreal +3 · Quebec, Canada'), findsWidgets);
    expect(find.text('This month: 4 searches · 19 leads · 167 credits used'), findsOneWidget);
    expect(
      find.text('Not enough for a search — the smallest search costs 25 credits.'),
      findsOneWidget,
    );
    expect(find.text('Get credits'), findsOneWidget);
    expect(find.textContaining('About'), findsNothing, reason: 'no capacity estimates');
  });

  testWidgets('Home: error state never shows zero tiles', (tester) async {
    _size(tester, const Size(1440, 900));
    final api = FakeApi()..jobsError = NetworkException('offline');
    final active = ActiveSearchesProvider(api: api);
    await tester.pumpWidget(_app(auth: FakeAuth(), api: api, active: active, home: HomeScreen(api: api)));
    await tester.pump();
    await tester.pump();
    expect(find.text("We couldn't load your searches. Your data is safe."), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('This month'), findsNothing);
  });

  testWidgets('Home: first visit shows the empty state', (tester) async {
    _size(tester, const Size(390, 844));
    final api = FakeApi();
    final active = ActiveSearchesProvider(api: api);
    await tester.pumpWidget(_app(auth: FakeAuth(), api: api, active: active, home: HomeScreen(api: api)));
    await tester.pump();
    await tester.pump();
    expect(find.text('Find your first leads'), findsOneWidget);
    expect(find.text('Recent searches'), findsNothing);
  });

  testWidgets('deep link /searches/<id> opens the search page inside the shell', (tester) async {
    _size(tester, const Size(1440, 900));
    final api = FakeApi();
    final active = ActiveSearchesProvider(api: api);
    await tester.pumpWidget(_app(auth: FakeAuth(), api: api, active: active, initialRoute: '/searches/abc-123'));
    await tester.pump();
    final page = tester.widget<SearchDetailScreen>(find.byType(SearchDetailScreen));
    expect(page.jobId, 'abc-123');
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('signed-out /credits shows sign-in in place', (tester) async {
    _size(tester, const Size(1440, 900));
    final api = FakeApi();
    final active = ActiveSearchesProvider(api: api);
    final auth = AuthProvider();
    await tester.pumpWidget(_app(auth: auth, api: api, active: active, initialRoute: '/credits'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final login = tester.widget<LoginScreen>(find.byType(LoginScreen));
    expect(login.inline, isTrue);
  });

  test('return routes only accept in-app paths', () {
    expect(AppRouter.safeReturnRoute('/searches/abc'), '/searches/abc');
    expect(AppRouter.safeReturnRoute('//evil.example'), isNull);
    expect(AppRouter.safeReturnRoute('https://evil.example'), isNull);
    expect(AppRouter.safeReturnRoute('/login'), isNull);
  });

  test('cities summary and local time formats', () {
    expect(jobCitiesSummary(_job('x', 'completed')), 'Montreal +3 · Quebec, Canada');
    final now = DateTime(2026, 11, 17, 15, 0);
    expect(formatLocalDateTime(DateTime(2026, 11, 17, 13, 4), now: now), 'Today 13:04');
    expect(formatLocalDateTime(DateTime(2026, 11, 16, 9, 10), now: now), 'Yesterday 09:10');
    expect(formatLocalDateTime(DateTime(2026, 11, 2, 13, 4), now: now), 'Nov 2, 13:04');
  });
}
