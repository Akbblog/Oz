import 'dart:convert';

import 'package:business_scraper_app/core/crm/crm_filters.dart';
import 'package:business_scraper_app/core/crm/crm_format.dart';
import 'package:business_scraper_app/core/crm/crm_import.dart';
import 'package:business_scraper_app/core/error_handler.dart';
import 'package:business_scraper_app/screens/crm/crm_reports_screen.dart';
import 'package:business_scraper_app/services/crm_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crm_fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'auth_token': 'tok'}));

  group('filters', () {
    test('URL query <-> API query, defaults left out of the URL', () {
      final f = CrmRecordFilters.fromQuery({'source': 'job-9', 'outcome': 'all', 'archived': 'all', 'q': ' acme ', 'due': 'overdue'});
      expect(f.toQuery(), {'q': 'acme', 'outcome': 'all', 'archived': 'all', 'source': 'job-9', 'due': 'overdue'});
      expect(f.toApiQuery(limit: 20, cursor: 'c1'), {
        'q': 'acme',
        'outcome': 'all',
        'archived': 'all',
        'source_job_id': 'job-9',
        'due': 'overdue',
        'sort': 'updated',
        'limit': '20',
        'cursor': 'c1',
      });
      expect(CrmRecordFilters.fromQuery(f.toQuery()), f);
      expect(const CrmRecordFilters().toRoute(), '/crm/leads');
      expect(CrmRecordFilters.fromQuery({'outcome': 'bogus', 'sort': 'x'}).toQuery(), isEmpty);
    });

    test('"View this search in CRM" includes every outcome', () {
      expect(crmSearchRoute('job-1'), '/crm/leads?outcome=all&source=job-1');
      final back = CrmRecordFilters.fromQuery(Uri.parse(crmSearchRoute('job-1')).queryParameters);
      expect(back.sourceJobId, 'job-1');
      expect(back.outcome, 'all');
    });

    test('pipeline filters round trip', () {
      final p = CrmPipelineFilters.fromQuery({'q': 'x', 'tag': 't1', 'stage': 'contacted'});
      expect(p.toRoute(), '/crm?q=x&tag=t1&stage=contacted');
    });
  });

  group('format', () {
    test('money keeps currencies apart and never merges them', () {
      expect(crmMoney(1250.5, 'cad'), 'CAD 1,250.50');
      expect(crmMoney(null, 'CAD'), '');
      expect(
          crmCurrencyTotals([
            {'currency': 'CAD', 'total': 1200},
            {'currency': 'USD', 'total': 300},
          ]),
          'CAD 1,200.00 · USD 300.00');
    });

    test('a picked local date and time is sent as UTC', () {
      final s = crmDueAtUtc(DateTime(2026, 11, 19), const TimeOfDay(hour: 9, minute: 30));
      expect(s.endsWith('Z'), isTrue);
      expect(DateTime.parse(s), DateTime(2026, 11, 19, 9, 30).toUtc());
    });

    test('validation', () {
      expect(crmValidateWebsite('ftp://x.com'), isNotNull);
      expect(crmValidateWebsite('https://x.com'), isNull);
      expect(crmValidateCurrency('', valueSet: true), isNotNull);
      expect(crmValidateCurrency('CA', valueSet: true), isNotNull);
      expect(crmValidateCurrency('cad', valueSet: true), isNull);
      expect(crmValidateProbability('101'), isNotNull);
      expect(crmValidateProbability('40'), isNull);
      expect(crmValidateValue('-1'), isNotNull);
    });

    test('reports with only zeros count as "No data yet"', () {
      expect(crmReportIsEmpty({'imported_companies': 0, 'by_stage': [], 'won_rate': {'value': null}}), isTrue);
      expect(crmReportIsEmpty({'imported_companies': 2}), isFalse);
    });
  });

  group('import', () {
    test('summary text', () {
      expect(crmImportSummary(added: 18, alreadyInCrm: 2, needsReview: 1), '18 added · 2 already in CRM · 1 needs review');
      expect(crmImportSummary(), '0 added');
      expect(crmImportSummary(linked: 1, skipped: 2), '1 linked · 2 skipped');
    });

    test('a retry after a failure reuses the idempotency key; a new submission gets a new one', () async {
      final api = FakeCrmApi()
        ..importResponses = [
          NetworkException('offline'),
          {
            'done': true,
            'created': [
              {'result_id': 1, 'record_id': 'r1'}
            ],
            'already_added': [],
            'possible_matches': [],
            'rejected': [],
          },
        ];
      var n = 0;
      final importer = CrmImporter(api, newKey: () => 'key-${++n}');
      await expectLater(importer.importIds('job-1', [2, 1]), throwsA(isA<NetworkException>()));
      final r = await importer.importIds('job-1', [1, 2]);
      expect(r.created.keys, [1]);
      final keys = [for (final c in api.callsOf('import')) c.args['key']];
      expect(keys, ['key-1', 'key-1']);
      await importer.importIds('job-1', [1, 2]);
      expect(api.callsOf('import').last.args['key'], 'key-2');
    });

    test('"all" repeats the same request until done and merges by result id', () async {
      Map<String, dynamic> page(List<int> created, {required bool done, int remaining = 0}) => {
            'done': done,
            'remaining': remaining,
            'created': [for (final id in created) {'result_id': id, 'record_id': 'r$id'}],
            'already_added': [],
            'possible_matches': [],
            'rejected': [],
          };
      final api = FakeCrmApi()
        ..importResponses = [
          page([1, 2], done: false, remaining: 3),
          page([3, 4], done: false, remaining: 1),
          page([4, 5], done: true),
        ];
      final importer = CrmImporter(api, newKey: () => 'all-key');
      final progress = <int>[];
      final r = await importer.importAll('job-1', onProgress: (p) => progress.add(p.remaining));
      expect(api.callsOf('import').length, 3);
      expect(api.callsOf('import').every((c) => c.args['all'] == true && c.args['key'] == 'all-key'), isTrue);
      expect(r.created.length, 5);
      expect(r.summary, '5 added');
      expect(progress, [3, 1, 0]);
    });

    test('job state parsing', () {
      final s = parseCrmJobState({
        'results': {
          '101': {'state': 'added', 'record_id': 'r1'},
          '102': {'state': 'possible_match', 'candidate_record_ids': ['r9'], 'reasons': ['same_place']},
          '103': {'state': 'not_added'},
        },
      });
      expect(s[101]!.state, CrmLeadState.added);
      expect(s[101]!.recordId, 'r1');
      expect(s[102]!.candidateRecordIds, ['r9']);
      expect(s[103]!.state, CrmLeadState.notAdded);
    });
  });

  group('CrmApi', () {
    test('sends the contract paths and bodies with the token', () async {
      final seen = <http.Request>[];
      final api = CrmApi(
        client: MockClient((req) async {
          seen.add(req);
          return http.Response(jsonEncode({'id': 'rec-1', 'version': 4}), 200);
        }),
      );
      await api.moveStage('rec 1', 's-2', version: 3);
      await api.importResults(jobId: 'job-1', resultIds: [1, 2], idempotencyKey: 'k-12345678');
      await api.getAgenda(bucket: 'today', tzOffsetMinutes: -300);
      expect(seen[0].method, 'POST');
      expect(seen[0].url.path, '/api/crm/records/rec%201/stage');
      expect(jsonDecode(seen[0].body), {'stage_id': 's-2', 'version': 3});
      expect(seen[0].headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(seen[1].body), {'job_id': 'job-1', 'result_ids': [1, 2], 'idempotency_key': 'k-12345678'});
      expect(seen[2].url.queryParameters, {'bucket': 'today', 'tz_offset_minutes': '-300', 'limit': '50'});
    });

    test('errors surface the server detail, code and current record', () async {
      final api = CrmApi(
        client: MockClient((req) async => http.Response(
              jsonEncode({
                'detail': 'This record was changed by someone else.',
                'code': 'version_conflict',
                'current': {'id': 'rec-1', 'version': 9},
              }),
              409,
            )),
      );
      try {
        await api.markWon('rec-1', version: 3);
        fail('should throw');
      } on CrmException catch (e) {
        expect(e.message, 'This record was changed by someone else.');
        expect(e.isVersionConflict, isTrue);
        expect(e.current!['version'], 9);
        expect(crmErrorKind(e), CrmErrorKind.conflict);
      }
    });

    test('crm_disabled and not found are told apart', () async {
      final disabled = CrmApi(
        client: MockClient((_) async => http.Response(jsonEncode({'detail': 'CRM is not enabled', 'code': 'crm_disabled'}), 404)),
      );
      final missing = CrmApi(client: MockClient((_) async => http.Response(jsonEncode({'detail': 'Not found'}), 404)));
      Object? a;
      Object? b;
      try {
        await disabled.getRecord('x');
      } catch (e) {
        a = e;
      }
      try {
        await missing.getRecord('x');
      } catch (e) {
        b = e;
      }
      expect(crmErrorKind(a), CrmErrorKind.disabled);
      expect(crmErrorKind(b), CrmErrorKind.notFound);
    });

    test('idempotency keys look like UUIDs and are unique', () {
      final a = newIdempotencyKey();
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(a), isTrue);
      expect(newIdempotencyKey(), isNot(a));
    });
  });
}
