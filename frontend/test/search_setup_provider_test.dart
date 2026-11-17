import 'dart:convert';

import 'package:business_scraper_app/core/error_handler.dart';
import 'package:business_scraper_app/providers/auth_provider.dart';
import 'package:business_scraper_app/providers/search_setup_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle([int ms = 350]) => Future<void>.delayed(Duration(milliseconds: ms));

Future<SearchSetupProvider> _loaded() async {
  final p = SearchSetupProvider(autoLoad: false);
  await p.load();
  return p;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('selection semantics', () {
    test('addCities is a union that keeps order and skips duplicates', () async {
      final p = await _loaded();
      p.addCities(['Montreal, Quebec', 'Laval, Quebec']);
      p.addCities(['laval, quebec', 'Gatineau, Quebec']);
      expect(p.cities, ['Montreal, Quebec', 'Laval, Quebec', 'Gatineau, Quebec']);
    });

    test('removeCities removes only the cities shown', () async {
      final p = await _loaded();
      p.addCities(['Montreal, Quebec', 'Laval, Quebec', 'Toronto, Ontario']);
      // The user filtered the list to "La..." and pressed "Clear shown".
      p.removeCities(['Laval, Quebec']);
      expect(p.cities, ['Montreal, Quebec', 'Toronto, Ontario']);
      p.toggleCity('Montreal, Quebec');
      expect(p.cities, ['Toronto, Ontario']);
      p.toggleCity('Montreal, Quebec');
      expect(p.cities.last, 'Montreal, Quebec');
    });

    test('changing region or country never drops cities by itself', () async {
      final p = await _loaded();
      p.setCountry('Canada');
      p.setRegion('Quebec');
      p.addCities(['Montreal, Quebec', 'Laval, Quebec']);

      p.setRegion('Ontario');
      expect(p.cities, hasLength(2));
      expect(p.citiesOutside('Ontario'), ['Montreal, Quebec', 'Laval, Quebec']);
      expect(p.citiesOutside('Quebec'), isEmpty);

      p.setCountry('USA');
      expect(p.region, isNull, reason: 'regions belong to a country');
      expect(p.hasSelection, isTrue);
      expect(p.cities, hasLength(2));

      // Only after the user confirms does the UI discard.
      p.discardCities(p.citiesOutside('Texas'));
      expect(p.cities, isEmpty);
    });

    test('discardCities() without arguments keeps hand-added cities', () async {
      final p = await _loaded();
      p.addCities(['Montreal, Quebec']);
      p.addExtraCity('Ottawa, Ontario');
      p.discardCities();
      expect(p.cities, isEmpty);
      expect(p.extraCities, ['Ottawa, Ontario']);
      p.clearAll();
      expect(p.hasSelection, isFalse);
    });

    test('allCities merges list and hand-added cities without duplicates', () async {
      final p = await _loaded();
      p.addCities(['Montreal, Quebec']);
      p.addExtraCity('montreal, quebec');
      p.addExtraCity('Ottawa, Ontario');
      expect(p.allCities, ['Montreal, Quebec', 'Ottawa, Ontario']);
    });
  });

  group('leads per city', () {
    test('legacy values are capped at 100 and flagged, never increased', () {
      expect(SearchSetupProvider.normalizeMaxResults(500), (value: 100, capped: true));
      expect(SearchSetupProvider.normalizeMaxResults(100), (value: 100, capped: false));
      expect(SearchSetupProvider.normalizeMaxResults(30), (value: 20, capped: false));
      expect(SearchSetupProvider.normalizeMaxResults(5), (value: 10, capped: false));
      expect(SearchSetupProvider.normalizeMaxResults(null), (value: 10, capped: false));
    });

    test('choosing a value clears the capped note', () async {
      final p = await _loaded();
      p.loadFromJob({'cities': ['Doha, Qatar'], 'category': 'gyms', 'max_results_per_city': 250});
      expect(p.maxResultsPerCity, 100);
      expect(p.maxResultsWasCapped, isTrue);
      p.setMaxResultsPerCity(50);
      expect(p.maxResultsPerCity, 50);
      expect(p.maxResultsWasCapped, isFalse);
    });
  });

  group('drafts', () {
    test('loads legacy drafts from both keys (max_results 500 -> 100, flagged)', () async {
      SharedPreferences.setMockInitialValues({
        SearchSetupProvider.locationDraftKey: jsonEncode({
          'country': 'Canada',
          'state': 'Quebec',
          'cities': ['Montreal', 'Laval, Quebec'],
          'include_suburbs': true,
          'saved_at': '2026-11-01T10:00:00',
        }),
        SearchSetupProvider.searchDraftKey: jsonEncode({
          'category': 'dentists',
          'cities_text': 'Montreal, Quebec; Ottawa, Ontario',
          'max_results': 500,
        }),
      });
      final p = await _loaded();
      expect(p.restoredFromDraft, isTrue);
      expect(p.country, 'Canada');
      expect(p.region, 'Quebec');
      expect(p.cities, ['Montreal, Quebec', 'Laval, Quebec']);
      expect(p.extraCities, ['Ottawa, Ontario'], reason: 'free-text cities are kept, never dropped');
      expect(p.category, 'dentists');
      expect(p.maxResultsPerCity, 100);
      expect(p.maxResultsWasCapped, isTrue);
    });

    test('a search draft without a location draft becomes the selection', () async {
      SharedPreferences.setMockInitialValues({
        SearchSetupProvider.searchDraftKey: jsonEncode({
          'category': 'gyms',
          'cities_text': 'Doha, Qatar\nLusail, Qatar',
          'max_results': 20,
        }),
      });
      final p = await _loaded();
      expect(p.cities, ['Doha, Qatar', 'Lusail, Qatar']);
      expect(p.maxResultsPerCity, 20);
      expect(p.maxResultsWasCapped, isFalse);
    });

    test('changes are written to the legacy keys', () async {
      final p = await _loaded();
      p.setCountry('Canada');
      p.setRegion('Quebec');
      p.addCities(['Montreal, Quebec']);
      p.setCategory('plumbers');
      p.setMaxResultsPerCity(50);
      await _settle();
      final prefs = await SharedPreferences.getInstance();
      final location = jsonDecode(prefs.getString(SearchSetupProvider.locationDraftKey)!);
      final search = jsonDecode(prefs.getString(SearchSetupProvider.searchDraftKey)!);
      expect(location['country'], 'Canada');
      expect(location['state'], 'Quebec');
      expect(location['cities'], ['Montreal, Quebec']);
      expect(location['include_suburbs'], isFalse);
      expect(search['category'], 'plumbers');
      expect(search['cities_text'], 'Montreal, Quebec');
      expect(search['max_results'], 50);
    });

    test('loadFromJob uses the job\'s own fields', () async {
      final p = await _loaded();
      p.addCities(['Somewhere, Else']);
      p.loadFromJob({
        'category': 'law firms',
        'cities': ['Montreal, Quebec', 'Laval, Quebec'],
        'max_results_per_city': 20,
        'country': 'Canada',
      });
      expect(p.cities, ['Montreal, Quebec', 'Laval, Quebec']);
      expect(p.category, 'law firms');
      expect(p.maxResultsPerCity, 20);
      expect(p.country, 'Canada');
      expect(p.region, 'Quebec', reason: 'inferred from the cities when the API has no region');
    });

    test('clear() empties the setup and deletes both drafts', () async {
      final p = await _loaded();
      p.addCities(['Montreal, Quebec']);
      p.setCategory('plumbers');
      await _settle();
      await p.clear();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(SearchSetupProvider.locationDraftKey), isNull);
      expect(prefs.getString(SearchSetupProvider.searchDraftKey), isNull);
      expect(p.hasSelection, isFalse);
      expect(p.category, isEmpty);
    });
  });

  test('sign-out clears drafts and runs every sign-out hook', () async {
    SharedPreferences.setMockInitialValues({
      SearchSetupProvider.locationDraftKey: '{"country":"Canada","state":"Quebec","cities":[]}',
      SearchSetupProvider.searchDraftKey: '{"category":"gyms"}',
      'active_job_id_v1': 'job-1',
    });
    final auth = AuthProvider();
    final setup = await _loaded();
    expect(setup.category, 'gyms');
    var hookRuns = 0;
    auth.addSignOutHook(() async {
      hookRuns++;
      await setup.clear();
    });
    await auth.logout();
    final prefs = await SharedPreferences.getInstance();
    expect(hookRuns, 1);
    expect(prefs.getString(SearchSetupProvider.locationDraftKey), isNull);
    expect(prefs.getString(SearchSetupProvider.searchDraftKey), isNull);
    expect(prefs.getString('active_job_id_v1'), isNull);
    expect(setup.category, isEmpty);
    expect(auth.isAuthenticated, isFalse);
  });

  group('error messages', () {
    String messageFor(int status, String body) {
      try {
        ErrorHandler.handleHttpError(http.Response(body, status), context: 'Create search');
      } catch (e) {
        return ErrorHandler.getUserFriendlyMessage(e);
      }
      fail('no exception');
    }

    test('FastAPI detail strings are shown as-is', () {
      expect(messageFor(402, '{"detail":"Insufficient credits. Required: 70, Available: 5"}'),
          'Insufficient credits. Required: 70, Available: 5');
    });

    test('422 validation lists become a readable sentence', () {
      final body = jsonEncode({
        'detail': [
          {
            'loc': ['body', 'max_results_per_city'],
            'msg': 'ensure this value is less than or equal to 100',
            'type': 'value_error',
          },
        ],
      });
      expect(messageFor(422, body), 'Max results per city: ensure this value is less than or equal to 100.');
    });

    test('raw HTML/JSON bodies are never shown', () {
      final m = messageFor(418, '<html><body>Bad gateway</body></html>');
      expect(m, isNot(contains('<html>')));
      expect(m, contains('418'));
    });
  });
}
