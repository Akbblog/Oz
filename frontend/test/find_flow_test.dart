import 'dart:ui' show CheckedState, Tristate;

import 'package:business_scraper_app/providers/active_searches_provider.dart';
import 'package:business_scraper_app/providers/auth_provider.dart';
import 'package:business_scraper_app/providers/credit_provider.dart';
import 'package:business_scraper_app/providers/scraper_provider.dart';
import 'package:business_scraper_app/providers/search_setup_provider.dart';
import 'package:business_scraper_app/screens/find/details_step.dart';
import 'package:business_scraper_app/screens/find/location_step.dart';
import 'package:business_scraper_app/services/api_service.dart';
import 'package:business_scraper_app/widgets/country_flag_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthProvider {
  _Auth(this.signedIn);
  final bool signedIn;

  @override
  bool get isAuthenticated => signedIn;
  @override
  bool get isRestoring => false;
  @override
  bool get isLoading => false;
}

class _Api extends ApiService {
  final Map<String, List<String>> cities = {
    'Quebec': [
      'Montreal, Quebec',
      'Laval, Quebec',
      'Quebec City, Quebec',
      'Saint-Jérôme, Quebec',
      'Saint-Hyacinthe, Quebec',
    ],
    'Ontario': ['Toronto, Ontario', 'Ottawa, Ontario'],
    'Texas': ['Austin, Texas'],
  };
  List<Map<String, dynamic>> jobs = [];
  int? balance;
  final List<List<int>> estimateCalls = [];

  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<List<String>> getCountries() async => ['USA', 'Canada'];

  @override
  Future<Map<String, List<String>>> getStates() async => {
        'USA': ['Texas'],
        'Canada': ['Ontario', 'Quebec'],
      };

  @override
  Future<Map<String, dynamic>> getLocationsSummary() async => {
        'USA': {
          'region_term': 'state',
          'regions': {'Texas': 1},
        },
        'Canada': {
          'region_term': 'province',
          'regions': {'Ontario': 2, 'Quebec': 5},
        },
      };

  @override
  Future<List<String>> getCities(String state) async => cities[state] ?? const [];

  @override
  Future<Map<String, dynamic>> getJobs({int? limit, int? offset, String? status, String? q, DateTime? from, DateTime? to, String? sort}) async =>
      {'jobs': jobs, 'total': jobs.length, 'counts': <String, int>{}, 'paginated': true};

  @override
  Future<Map<String, dynamic>> estimateJobCost({required int numCities, int maxResultsPerCity = 10}) async {
    estimateCalls.add([numCities, maxResultsPerCity]);
    final cost = 10 + numCities * 5 + numCities * maxResultsPerCity;
    return {'estimated_cost': cost, if (balance != null) 'current_balance': balance};
  }

  @override
  Future<List<Map<String, dynamic>>> getActiveJobs() async => [];
}

class _Scraper extends ScraperProvider {
  _Scraper(ApiService api) : super(api: api);
  int calls = 0;
  bool result = true;
  String? error;
  ScrapingJob? _job;

  @override
  Future<bool> startScraping({
    required String category,
    required List<String> citiesData,
    int maxResultsPerCity = 10,
  }) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (result) {
      _job = ScrapingJob(
        jobId: 'j1',
        category: category,
        cities: citiesData,
        createdAt: DateTime.now(),
        totalCities: citiesData.length,
      );
    }
    return result;
  }

  @override
  ScrapingJob? get currentJob => _job;
  @override
  String? get startError => result ? null : error;
}

class _Harness {
  _Harness({this.signedIn = true}) : api = _Api() {
    setup = SearchSetupProvider(autoLoad: false);
    scraper = _Scraper(api);
  }

  final bool signedIn;
  final _Api api;
  late final SearchSetupProvider setup;
  late final _Scraper scraper;
  final List<String> pushed = [];

  Widget app(String initialRoute) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(signedIn)),
        ChangeNotifierProvider<ScraperProvider>.value(value: scraper),
        ChangeNotifierProvider<CreditProvider>.value(value: CreditProvider.instance),
        ChangeNotifierProvider<SearchSetupProvider>.value(value: setup),
        ChangeNotifierProvider(create: (_) => ActiveSearchesProvider(api: api)),
      ],
      child: MaterialApp(
        initialRoute: initialRoute,
        onGenerateRoute: (settings) {
          pushed.add(settings.name ?? '');
          final path = Uri.parse(settings.name ?? '/').path;
          Widget page;
          if (path == '/find') {
            page = FindLocationStep(api: api);
          } else if (path == '/find/details') {
            page = FindDetailsStep(api: api);
          } else {
            page = Text('page ${settings.name}');
          }
          return MaterialPageRoute<void>(settings: settings, builder: (_) => Scaffold(body: page));
        },
      ),
    );
  }
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

SemanticsNode? _semanticsNode(SemanticsNode node, bool Function(SemanticsNode) test) {
  if (test(node)) return node;
  SemanticsNode? hit;
  node.visitChildren((child) {
    hit ??= _semanticsNode(child, test);
    return hit == null;
  });
  return hit;
}

Finder _fieldWithHint(String hint) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);

Finder _buttonWithText(String text) => find.ancestor(of: find.text(text), matching: find.byType(FilledButton));

const _config = {
  'base': 10,
  'per_city': 5,
  'per_result': 1,
  'min_job': 15,
  'refund_policy': 'delivered',
  'min_job_cost': 25,
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CreditProvider.instance.clear();
  });

  group('Location step', () {
    testWidgets('"Select N shown" adds to the selection and keeps earlier picks', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      h.setup
        ..setCountry('Canada')
        ..setRegion('Quebec');
      await tester.pumpWidget(h.app('/find?country=Canada'));
      await _settle(tester);

      await tester.tap(find.text('Montreal'));
      await tester.tap(find.text('Quebec City'));
      await tester.pump();
      expect(h.setup.cities, ['Montreal, Quebec', 'Quebec City, Quebec']);

      await tester.enterText(_fieldWithHint('Search cities in Quebec'), 'saint');
      await tester.pump();
      expect(find.text('2 of 5 cities match “saint”. Your other selections are kept.'), findsOneWidget);
      await tester.tap(find.text('Select 2 shown'));
      await tester.pump();

      expect(h.setup.cities.length, 4);
      expect(h.setup.cities, containsAll(['Montreal, Quebec', 'Quebec City, Quebec']));
      expect(find.text('Select 2 shown'), findsNothing, reason: 'hidden when every shown city is selected');
      expect(find.text('4 cities selected'), findsOneWidget);
      expect(find.text('Continue with 4 cities'), findsOneWidget);
      await _settle(tester);
    });

    testWidgets('"Clear shown" removes only the shown cities', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      h.setup
        ..setCountry('Canada')
        ..setRegion('Quebec')
        ..addCities(['Montreal, Quebec', 'Saint-Jérôme, Quebec', 'Saint-Hyacinthe, Quebec']);
      await tester.pumpWidget(h.app('/find?country=Canada'));
      await _settle(tester);

      await tester.enterText(_fieldWithHint('Search cities in Quebec'), 'saint');
      await tester.pump();
      await tester.tap(find.text('Clear shown'));
      await tester.pump();

      expect(h.setup.cities, ['Montreal, Quebec']);
      expect(find.text('1 city selected'), findsOneWidget);
      await _settle(tester);
    });

    testWidgets('switching region asks first; "Stay" keeps the cities', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      h.setup
        ..setCountry('Canada')
        ..setRegion('Quebec')
        ..addCities(['Montreal, Quebec', 'Laval, Quebec']);
      await tester.pumpWidget(h.app('/find?country=Canada'));
      await _settle(tester);

      await tester.tap(find.text('Ontario'));
      await tester.pumpAndSettle();
      expect(find.text('Switch to Ontario?'), findsOneWidget);
      expect(find.text('Your 2 Quebec cities will be removed from this search.'), findsOneWidget);

      await tester.tap(find.text('Stay in Quebec'));
      await tester.pumpAndSettle();
      expect(h.setup.cities, ['Montreal, Quebec', 'Laval, Quebec']);
      expect(h.setup.region, 'Quebec');

      await tester.tap(find.text('Ontario'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch and remove'));
      await _settle(tester);
      expect(h.setup.cities, isEmpty);
      expect(h.setup.region, 'Ontario');
      expect(find.text('Toronto'), findsOneWidget);
    });

    testWidgets('changing country with a selection asks first', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      h.setup
        ..setCountry('Canada')
        ..setRegion('Quebec')
        ..addCities(['Montreal, Quebec']);
      await tester.pumpWidget(h.app('/find'));
      await _settle(tester);

      expect(find.text('United States'), findsOneWidget, reason: 'full name for display');
      expect(find.text('2 provinces'), findsOneWidget);
      await tester.tap(find.text('United States'));
      await tester.pumpAndSettle();
      expect(find.text('Change country?'), findsOneWidget);
      expect(find.text('Your 1 selected city in Canada will be removed.'), findsOneWidget);
      await tester.tap(find.text('Keep Canada'));
      await tester.pumpAndSettle();
      expect(h.setup.cities, ['Montreal, Quebec']);
      expect(h.setup.country, 'Canada');
      expect(h.pushed.where((r) => r.contains('country=USA')), isEmpty);
    });

    testWidgets('a city no longer listed is tagged, kept, and removed only on request', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      h.setup
        ..setCountry('Canada')
        ..setRegion('Quebec')
        ..addCities(['Montreal, Quebec', 'Atlantis, Quebec']);
      await tester.pumpWidget(h.app('/find?country=Canada'));
      await _settle(tester);

      expect(find.text('1 of your cities is no longer in our list. It may return no results.'), findsOneWidget);
      expect(find.text('1 no longer listed'), findsOneWidget);
      expect(h.setup.cities, contains('Atlantis, Quebec'), reason: 'never auto-removed');

      await tester.tap(find.text('Review list').last);
      await tester.pumpAndSettle();
      expect(find.text('Atlantis, Quebec'), findsOneWidget);
      expect(find.text('No longer listed'), findsOneWidget);
      expect(h.setup.cities, contains('Atlantis, Quebec'));

      await tester.tap(find.bySemanticsLabel('Remove Atlantis, Quebec'));
      await tester.pumpAndSettle();
      expect(h.setup.cities, ['Montreal, Quebec']);
      await _settle(tester);
    });

    testWidgets('"Clear all" with more than 5 cities asks first', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      h.setup
        ..setCountry('Canada')
        ..setRegion('Quebec')
        ..addCities(h.api.cities['Quebec']!)
        ..addExtraCity('Gatineau, Quebec');
      await tester.pumpWidget(h.app('/find?country=Canada'));
      await _settle(tester);

      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();
      expect(find.text('Clear all 6 selected cities?'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(h.setup.cityCount, 6);
    });

    testWidgets('recents come from previous searches; missing regions are disabled', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      h.api.jobs = [
        {'category': 'dentists', 'cities': ['Laval, Quebec'], 'country': 'Canada'},
        {'category': 'gyms', 'cities': ['Laval, Quebec', 'Montreal, Quebec'], 'country': 'Canada'},
        {'category': 'cafes', 'cities': ['Springfield, Nowhere'], 'country': 'USA'},
      ];
      await tester.pumpWidget(h.app('/find'));
      await _settle(tester);

      expect(find.text('Canada · Quebec'), findsOneWidget);
      expect(find.text('United States · Nowhere — No longer available'), findsOneWidget);

      await tester.tap(find.text('Canada · Quebec'));
      await _settle(tester);
      expect(h.setup.region, 'Quebec');
      expect(h.setup.cities, isEmpty, reason: 'recents jump to the region with nothing selected');
      expect(h.pushed.last, '/find?country=Canada&region=Quebec');
    });

    testWidgets('locations error shows Try again and no invented data', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      h.api.cities.clear();
      final failing = _FailingApi();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(false)),
          ChangeNotifierProvider<SearchSetupProvider>.value(value: h.setup),
        ],
        child: MaterialApp(home: Scaffold(body: FindLocationStep(api: failing))),
      ));
      await _settle(tester);
      expect(find.text("Locations didn't load."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Canada'), findsNothing);
    });

    testWidgets('country rows show the flag beside the full name and region count', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      await tester.pumpWidget(h.app('/find'));
      await _settle(tester);

      expect(find.text('United States'), findsOneWidget);
      expect(find.text('Canada'), findsOneWidget);
      expect(find.byType(CountryFlagBadge), findsNWidgets(2));
      expect(find.text('CA'), findsNothing, reason: 'no two-letter code in place of the flag');
      final row = find.ancestor(of: find.text('Canada'), matching: find.byType(Row)).first;
      expect(find.descendant(of: row, matching: find.byType(CountryFlagBadge)), findsOneWidget);
      expect(find.bySemanticsLabel('Canada, 2 provinces'), findsOneWidget);
    });

    for (final width in [360.0, 390.0, 430.0]) {
      testWidgets('phone ${width.toInt()} px: city header stacks instead of truncating', (tester) async {
        _size(tester, Size(width, 800));
        final h = _Harness();
        h.setup
          ..setCountry('Canada')
          ..setRegion('Quebec');
        await tester.pumpWidget(h.app('/find?country=Canada&region=Quebec'));
        await _settle(tester);

        expect(tester.takeException(), isNull, reason: 'no overflow');
        final country = tester.widget<Text>(find.text('Canada'));
        expect(country.maxLines, isNull, reason: 'country name wraps, never ellipsised');
        expect(find.text('Quebec'), findsOneWidget);
        expect(find.byType(CountryFlagBadge), findsOneWidget);
        // Country line sits above the region title.
        expect(tester.getTopLeft(find.text('Canada')).dy, lessThan(tester.getTopLeft(find.text('Quebec')).dy));
        // Back button is a 48 px target.
        final back = find.ancestor(of: find.text('Provinces'), matching: find.byWidgetPredicate((w) => w is TextButton));
        expect(tester.getSize(back).height, greaterThanOrEqualTo(48));
        await tester.enterText(_fieldWithHint('Search cities in Quebec'), 'saint');
        await tester.pump();
        expect(tester.getSize(find.byTooltip('Clear search')).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(find.ancestor(of: find.text('Select 2 shown'), matching: find.byType(OutlinedButton))).height,
            greaterThanOrEqualTo(48));
        await _settle(tester);
      });
    }

    testWidgets('city rows: checkbox semantics, focusable, 48 px; Space and Enter toggle from the keyboard',
        (tester) async {
      final handle = tester.ensureSemantics();
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      h.setup
        ..setCountry('Canada')
        ..setRegion('Quebec');
      await tester.pumpWidget(h.app('/find?country=Canada'));
      await _settle(tester);

      final montrealText = find.descendant(of: find.byType(GridView), matching: find.text('Montreal'));
      final montreal = find.descendant(of: find.byType(GridView), matching: find.bySemanticsLabel('Montreal'));
      expect(montreal, findsOneWidget);
      final data = tester.getSemantics(montreal).getSemanticsData();
      expect(data.flagsCollection.isChecked, CheckedState.isFalse);
      expect(data.flagsCollection.isFocused, isNot(Tristate.none), reason: 'focusable');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(tester.getSize(find.ancestor(of: montrealText, matching: find.byType(InkWell)).first).height,
          greaterThanOrEqualTo(48));

      // Tab from the city search stays in the city panel ("Select 5 shown"),
      // not the region list to its left.
      await tester.tap(_fieldWithHint('Search cities in Quebec'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(find.ancestor(of: find.byWidget(focused.widget), matching: find.byType(OutlinedButton)), findsOneWidget);

      // Keyboard: focus Montreal's row, Space toggles, Enter toggles back.
      Focus.of(tester.element(montrealText)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(h.setup.cities, ['Montreal, Quebec']);
      expect(tester.getSemantics(montreal).getSemanticsData().flagsCollection.isChecked, CheckedState.isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(h.setup.cities, isEmpty);
      await _settle(tester);
      handle.dispose();
    });

    testWidgets(
        'accessibility mode: ticking a city via the screen reader moves focus off the search, '
        'so focusing the search again opens a fresh editing session and typing filters', (tester) async {
      final handle = tester.ensureSemantics();
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      h.setup.setCountry('Canada');
      await tester.pumpWidget(h.app('/find?country=Canada'));
      await _settle(tester);

      // Tapping a region focuses its city search (keyboard flow).
      await tester.tap(find.text('Quebec'));
      await _settle(tester);
      final search = _fieldWithHint('Search cities in Quebec');
      final searchFocus = tester.widget<TextField>(search).focusNode!;
      expect(searchFocus.hasFocus, isTrue);

      // Screen reader "tap" on the Montreal checkbox row: what Flutter web
      // sends when the semantics DOM element is clicked. The browser moves
      // DOM focus to that element, which ends the field's editing session.
      final owner = tester.binding.renderViews.first.owner!.semanticsOwner!;
      owner.performAction(tester.getSemantics(find.bySemanticsLabel('Montreal')).id, SemanticsAction.tap);
      await tester.pump();
      expect(h.setup.cities, ['Montreal, Quebec']);
      expect(searchFocus.hasFocus, isFalse,
          reason: 'focus follows the activated row; before the fix it stayed on the search field, so the '
              'web engine never re-activated the field and typed text was lost');
      expect(Focus.of(tester.element(find.descendant(of: find.byType(GridView), matching: find.text('Montreal')))).hasFocus,
          isTrue);

      // Screen reader focuses the search again -> real focus change -> typing works.
      final field = _semanticsNode(owner.rootSemanticsNode!, (n) {
        final d = n.getSemanticsData();
        return d.flagsCollection.isTextField && '${d.label} ${d.hint}'.contains('Search cities in Quebec');
      });
      expect(field, isNotNull);
      expect(field!.getSemanticsData().hasAction(SemanticsAction.focus), isTrue);
      owner.performAction(field.id, SemanticsAction.focus);
      await tester.pump();
      expect(searchFocus.hasFocus, isTrue);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      tester.testTextInput.enterText('saint');
      await tester.pump();
      expect(find.text('2 of 5 cities match “saint”. Your other selections are kept.'), findsOneWidget);
      expect(find.text('Select 2 shown'), findsOneWidget);
      await _settle(tester);
      handle.dispose();
    });

    testWidgets('selection count is a polite live region', (tester) async {
      final handle = tester.ensureSemantics();
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      h.setup
        ..setCountry('Canada')
        ..setRegion('Quebec');
      await tester.pumpWidget(h.app('/find?country=Canada'));
      await _settle(tester);
      await tester.tap(find.text('Laval'));
      await tester.pump();
      final data = tester.getSemantics(find.text('1 city selected')).getSemanticsData();
      expect(data.flagsCollection.isLiveRegion, isTrue);
      await _settle(tester);
      handle.dispose();
    });

    testWidgets('phone: region level drills into the city level via the URL', (tester) async {
      _size(tester, const Size(390, 844));
      final h = _Harness();
      await tester.pumpWidget(h.app('/find?country=Canada'));
      await _settle(tester);

      expect(find.text('Countries'), findsOneWidget);
      await tester.tap(find.text('Quebec'));
      await _settle(tester);
      expect(h.pushed.last, '/find?country=Canada&region=Quebec');
      expect(find.text('Provinces'), findsOneWidget);
      // Stacked header: back + step, then flag + country, then the region.
      expect(find.text('Step 1 of 2'), findsOneWidget);
      expect(find.text('Canada'), findsOneWidget);
      expect(find.byType(CountryFlagBadge), findsOneWidget);
      expect(find.text('Quebec'), findsOneWidget);
      await tester.tap(find.text('Laval'));
      await tester.pump();
      expect(h.setup.cities, ['Laval, Quebec']);
      expect(find.text('1 city selected'), findsOneWidget);
      await _settle(tester);
    });
  });

  group('Details step', () {
    testWidgets('Start is disabled with a visible reason', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      CreditProvider.instance
        ..setConfig(_config)
        ..setBalance(12);
      await tester.pumpWidget(h.app('/find/details'));
      await _settle(tester);

      expect(find.text('Enter a business type'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'plumbers');
      await _settle(tester);
      expect(find.text('Select at least one city'), findsOneWidget);

      h.setup.addCities(['Montreal, Quebec', 'Laval, Quebec', 'Saint-Jérôme, Quebec', 'Saint-Hyacinthe, Quebec']);
      await _settle(tester);
      expect(find.text('Not enough credits — you need 70, you have 12'), findsOneWidget);
      expect(find.text('Get credits'), findsOneWidget);
      final button = tester.widget<FilledButton>(_buttonWithText('Start search · 70 credits'));
      expect(button.onPressed, isNull);
    });

    testWidgets('cost lines come from the config and the estimate', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      CreditProvider.instance
        ..setConfig(_config)
        ..setBalance(4102);
      h.setup
        ..setCategory('plumbers')
        ..addCities(['Montreal, Quebec', 'Laval, Quebec', 'Saint-Jérôme, Quebec', 'Saint-Hyacinthe, Quebec']);
      await tester.pumpWidget(h.app('/find/details'));
      await _settle(tester);

      expect(h.api.estimateCalls.last, [4, 10]);
      expect(find.text('Job fee'), findsOneWidget);
      expect(find.text('4 cities × 5'), findsOneWidget);
      expect(find.text('Up to 40 leads × 1'), findsOneWidget);
      expect(find.text('Charged now'), findsOneWidget);
      expect(find.text('70'), findsOneWidget);
      expect(find.text('Balance after'), findsOneWidget);
      expect(find.text('4,032'), findsOneWidget);
      expect(find.text(CreditProvider.refundPolicySentenceFor('delivered')!), findsOneWidget);
      expect(
        find.text('Google Maps often has fewer businesses than this in small towns. You only pay for leads delivered.'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(_buttonWithText('Start search · 70 credits'));
      expect(button.onPressed, isNotNull);

      // Leads per city 20 -> new estimate (debounced), stale values replaced.
      await tester.tap(find.descendant(of: find.byType(SegmentedButton<int>), matching: find.text('20')));
      await _settle(tester);
      expect(h.api.estimateCalls.last, [4, 20]);
      expect(find.text('Start search · 110 credits'), findsOneWidget);
    });

    testWidgets('policy "none": no delivered-only wording, its own sentence', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      CreditProvider.instance
        ..setConfig({..._config, 'refund_policy': 'none'})
        ..setBalance(500);
      h.setup
        ..setCategory('plumbers')
        ..addCities(['Montreal, Quebec']);
      await tester.pumpWidget(h.app('/find/details'));
      await _settle(tester);

      expect(find.text('Google Maps often has fewer businesses than this in small towns.'), findsOneWidget);
      expect(find.text('Credits are not returned after the search starts.'), findsOneWidget);
    });

    testWidgets('Start: one request, then replaces the form with the search page', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      CreditProvider.instance
        ..setConfig(_config)
        ..setBalance(4102);
      h.setup
        ..setCategory('plumbers')
        ..addCities(['Montreal, Quebec']);
      await tester.pumpWidget(h.app('/find/details'));
      await _settle(tester);

      final start = _buttonWithText('Start search · 25 credits');
      await tester.tap(start);
      await tester.pump();
      expect(find.text('Starting your search…'), findsOneWidget);
      // A second press while starting does nothing.
      await tester.tap(start, warnIfMissed: false);
      await _settle(tester);
      expect(h.scraper.calls, 1);
      expect(h.pushed.last, '/searches/j1');
      expect(find.text('page /searches/j1'), findsOneWidget);
    });

    testWidgets('Start error is shown as readable text under the button', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      h.scraper
        ..result = false
        ..error = 'You have reached the limit of 5 searches per hour.';
      CreditProvider.instance
        ..setConfig(_config)
        ..setBalance(4102);
      h.setup
        ..setCategory('plumbers')
        ..addCities(['Montreal, Quebec']);
      await tester.pumpWidget(h.app('/find/details'));
      await _settle(tester);
      await tester.tap(_buttonWithText('Start search · 25 credits'));
      await _settle(tester);
      expect(find.text('You have reached the limit of 5 searches per hour.'), findsOneWidget);
    });

    testWidgets('guest Start opens the sign-in sheet', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness(signedIn: false);
      h.setup
        ..setCategory('plumbers')
        ..addCities(['Montreal, Quebec']);
      await tester.pumpWidget(h.app('/find/details'));
      await _settle(tester);

      await tester.tap(_buttonWithText('Sign in to start'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in required'), findsOneWidget);
      await tester.tap(find.text('Sign in to continue'));
      await tester.pumpAndSettle();
      expect(h.pushed.last, '/login?next=${Uri.encodeComponent('/find/details')}');
    });

    testWidgets('"Add a city not listed" needs "City, Region"', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      await tester.pumpWidget(h.app('/find/details'));
      await _settle(tester);

      await tester.tap(find.text('Add a city not listed'));
      await tester.pump();
      final field = _fieldWithHint('City, Region');
      await tester.enterText(field, 'Laval');
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(find.text("Use the format City, Region — for example 'Laval, Quebec'."), findsOneWidget);
      expect(h.setup.extraCities, isEmpty);

      await tester.enterText(field, 'Laval ,  Quebec');
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(h.setup.extraCities, ['Laval, Quebec']);
      expect(find.text('added by you'), findsOneWidget);
      await _settle(tester);
    });

    testWidgets('a capped legacy value shows "Maximum is 100 leads per city."', (tester) async {
      _size(tester, const Size(1440, 900));
      SharedPreferences.setMockInitialValues({
        SearchSetupProvider.searchDraftKey: '{"category":"x","cities_text":"Laval, Quebec","max_results":500}',
      });
      final h = _Harness();
      await tester.pumpWidget(h.app('/find/details'));
      await _settle(tester);
      expect(h.setup.maxResultsPerCity, 100);
      expect(find.text('Maximum is 100 leads per city.'), findsOneWidget);
    });
  });

  group('country screen', () {
    testWidgets('search also finds states and regions and opens them directly', (tester) async {
      _size(tester, const Size(1440, 900));
      final h = _Harness();
      await tester.pumpWidget(h.app('/find'));
      await _settle(tester);

      await tester.enterText(find.byType(TextField).first, 'queb');
      await tester.pump();
      expect(find.textContaining('States and regions matching'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^Quebec, Canada')), findsOneWidget);
      expect(find.text('0 of 2 countries match “queb”'), findsOneWidget);
      expect(find.text('No country has that name. Pick one of the regions above.'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(RegExp(r'^Quebec, Canada')));
      await _settle(tester);
      expect(h.setup.country, 'Canada');
      expect(h.setup.region, 'Quebec');
      expect(find.text('Montreal'), findsOneWidget, reason: 'the region opens with its cities');
    });

    testWidgets('wide screens explain the steps; visitors are offered an account', (tester) async {
      _size(tester, const Size(1600, 900));
      final guest = _Harness(signedIn: false);
      await tester.pumpWidget(guest.app('/find'));
      await _settle(tester);
      expect(find.text('How a search works'), findsOneWidget);
      expect(find.text('Every lead includes'), findsOneWidget);
      expect(find.text('Create a free account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('signed-in users are not asked to sign up; narrower screens drop the panel', (tester) async {
      _size(tester, const Size(1600, 900));
      final h = _Harness();
      await tester.pumpWidget(h.app('/find'));
      await _settle(tester);
      expect(find.text('How a search works'), findsOneWidget);
      expect(find.text('Create a free account'), findsNothing);

      _size(tester, const Size(1100, 900));
      await tester.pump();
      expect(find.text('How a search works'), findsNothing);
      expect(find.text('Canada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone width lays the country cards out without overflow', (tester) async {
      _size(tester, const Size(390, 800));
      final h = _Harness();
      await tester.pumpWidget(h.app('/find'));
      await _settle(tester);
      expect(find.text('United States'), findsOneWidget);
      expect(find.bySemanticsLabel('Canada, 2 provinces'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _FailingApi extends _Api {
  @override
  Future<List<String>> getCountries() async => throw Exception('offline');
}
