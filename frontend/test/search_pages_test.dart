import 'dart:io';

import 'package:business_scraper_app/core/download_helper.dart';
import 'package:business_scraper_app/providers/active_searches_provider.dart';
import 'package:business_scraper_app/providers/credit_provider.dart';
import 'package:business_scraper_app/providers/scraper_provider.dart';
import 'package:business_scraper_app/providers/search_setup_provider.dart';
import 'package:business_scraper_app/screens/my_searches_screen.dart';
import 'package:business_scraper_app/screens/search_detail_screen.dart';
import 'package:business_scraper_app/services/api_service.dart';
import 'package:business_scraper_app/widgets/app_shell_common.dart';
import 'package:business_scraper_app/widgets/job_log_panel.dart';
import 'package:business_scraper_app/widgets/search_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _iso(DateTime t) => t.toUtc().toIso8601String();

Map<String, dynamic> _payload({
  String id = 'job-1',
  String status = 'completed',
  int leads = 0,
  int charged = 70,
  int refunded = 0,
  bool settled = true,
  String? error,
  int done = 4,
  int failedCities = 0,
  List<Map<String, dynamic>>? results,
}) {
  final created = DateTime.now().subtract(const Duration(minutes: 3));
  return {
    'job_id': id,
    'status': status,
    'category': 'plumbers',
    'cities': ['Montreal, Quebec', 'Laval, Quebec', 'Gatineau, Quebec', 'Longueuil, Quebec'],
    'country': 'Canada',
    'region': 'Quebec',
    'max_results_per_city': 10,
    'total_cities': 4,
    'completed_cities': done,
    'failed_cities': failedCities,
    'current_city': '',
    'result_count': leads,
    'results': results ?? const [],
    'results_included': results != null,
    'error': error,
    'created_at': _iso(created),
    'completed_at': status == 'running' || status == 'pending' ? null : _iso(created.add(const Duration(seconds: 32))),
    'server_time': _iso(DateTime.now()),
    'credit_charged': charged,
    'credit_refunded': refunded,
    'settled': settled,
    'logs': ['Job started', 'Searching Montreal'],
    'log_entries': [
      {'id': 1, 'message': 'Job started', 'created_at': _iso(created)},
      {'id': 2, 'message': 'Searching Montreal', 'created_at': _iso(created)},
    ],
    'next_log_cursor': 2,
  };
}

List<Map<String, dynamic>> _leads(int n) => [
      for (var i = 0; i < n; i++)
        {
          'business_name': 'Biz $i',
          'phone': '+1 450 555 010$i',
          'city': 'Montreal',
          'state': 'Quebec',
          'address': '$i Rue X',
          'google_maps_url': 'https://maps.google.com/?cid=$i',
        },
    ];

class FakeApi extends ApiService {
  Map<String, dynamic> Function(bool includeResults) status = (_) => _payload();
  Map<String, dynamic> jobsPage = {'jobs': <Map<String, dynamic>>[], 'total': 0, 'counts': <String, int>{}};
  final List<String?> statusQueries = [];

  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<List<Map<String, dynamic>>> getActiveJobs() async => const [];

  @override
  Future<Map<String, dynamic>> getJobStatus(
    String jobId, {
    bool includeResults = true,
    int? logsAfter,
    Duration? requestTimeout,
  }) async =>
      Map<String, dynamic>.from(status(includeResults));

  @override
  Future<Map<String, dynamic>> getJobs({int? limit, int? offset, String? status}) async {
    statusQueries.add(status);
    return jobsPage;
  }
}

Widget _host(FakeApi api, Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => ScraperProvider(api: api, pollInterval: const Duration(milliseconds: 10))),
      ChangeNotifierProvider<CreditProvider>.value(value: CreditProvider.instance),
      ChangeNotifierProvider(create: (_) => SearchSetupProvider(autoLoad: false)),
      ChangeNotifierProvider(create: (_) => ActiveSearchesProvider(api: api)),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester, {int steps = 10}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Loads the real Roboto (from the Flutter SDK) so layout measurements use
/// real glyph widths instead of the 1-em-wide test font.
Future<bool> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return false;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return false;
  final loader = FontLoader('Roboto');
  var any = false;
  for (final f in ['roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf']) {
    final file = File('${dir.path}/$f');
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    any = true;
  }
  if (!any) return false;
  await loader.load();
  return true;
}

void main() {
  var realFont = false;
  setUpAll(() async {
    realFont = await _loadRoboto();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CreditProvider.instance.clear();
    CreditProvider.instance.setConfig({'refund_policy': 'delivered'});
  });

  group('status copy (brief)', () {
    test('headlines per final state', () {
      expect(finishedSearchHeadline(_payload(status: 'completed', leads: 17)), '17 leads from 4 cities.');
      expect(finishedSearchHeadline(_payload(status: 'cancelled', leads: 3)),
          'You cancelled this search. 3 leads were saved.');
      expect(finishedSearchHeadline(_payload(status: 'cancelled', leads: 1)),
          'You cancelled this search. 1 lead was saved.');
      expect(finishedSearchHeadline(_payload(status: 'failed', leads: 0, error: 'Boom')),
          "This search couldn't finish: Boom.");
      expect(finishedSearchHeadline(_payload(status: 'failed', leads: 6, error: 'Boom.')),
          'This search stopped early: Boom. 6 leads were saved.');
      expect(finishedSearchHeadline(_payload(status: 'failed', error: 'Every city timed out without results')),
          "This search couldn't finish: Google Maps didn't respond for any of the cities.");
      expect(failureReasonWasReworded('RuntimeError: x'), isTrue);
      expect(failureReasonWasReworded('Boom'), isFalse);
    });

    test('refund lines: settled, no refund, not settled', () {
      expect(searchRefundLine(charged: 70, refunded: 23, settled: true), '70 credits charged, 23 returned — 47 used.');
      expect(searchRefundLine(charged: 70, refunded: 0, settled: true), '70 credits used.');
      expect(searchRefundLine(charged: 70, refunded: 0, settled: false), '70 credits charged · calculating refund…');
    });

    test('running credits line uses the configured policy and never guesses', () {
      expect(searchRunningCreditsLine(70, CreditProvider.refundPolicySentenceFor('none')),
          '70 credits charged at start. Credits are not returned after the search starts.');
      expect(searchRunningCreditsLine(70, CreditProvider.refundPolicySentenceFor('delivered')),
          startsWith('70 credits charged at start. You pay for what we deliver.'));
      expect(searchRunningCreditsLine(70, CreditProvider.refundPolicySentenceFor(null)), '70 credits charged at start.');
      expect(searchRunningCreditsLine(70, CreditProvider.refundPolicySentenceFor('weird')), '70 credits charged at start.');
    });

    test('badges: partial completed, failed with leads, cancelled is neutral, stopping', () {
      expect(searchPageStatus(_payload(status: 'completed', leads: 5), zeroCities: 1).label,
          'Completed · 1 city found nothing');
      expect(searchPageStatus(_payload(status: 'completed', leads: 5, failedCities: 2)).label,
          'Completed · 2 cities found nothing');
      expect(searchPageStatus(_payload(status: 'completed', leads: 5)).label, 'Completed');
      expect(searchPageStatus(_payload(status: 'failed', leads: 3)).label, 'Failed · partial results');
      expect(searchPageStatus(_payload(status: 'failed', leads: 0)).label, 'Failed');
      final cancelled = searchPageStatus(_payload(status: 'cancelled'));
      expect(cancelled.label, 'Cancelled');
      expect(cancelled.foreground, UiTokens.cancelledFg);
      expect(searchPageStatus(_payload(status: 'running'), stopping: true).label, 'Stopping…');
      expect(searchPageStatus(_payload(status: 'pending')).label, 'Queued');
    });

    test('city lead matching ignores spacing and case', () {
      final counts = leadCountsByCity(_leads(3));
      expect(leadsForCity('Montreal, Quebec', counts), 3);
      expect(leadsForCity('montreal ,quebec', counts), 3);
      expect(leadsForCity('Laval, Quebec', counts), 0);
    });
  });

  group('CSV export', () {
    test('RFC 4180 quoting', () {
      expect(csvCell('plain'), 'plain');
      expect(csvCell('a,b'), '"a,b"');
      expect(csvCell('say "hi"'), '"say ""hi"""');
      expect(csvCell('line1\nline2'), '"line1\nline2"');
      expect(csvCell('cr\rhere'), '"cr\rhere"');
      expect(csvCell(null), '');
      expect(csvCell(42), '42');
    });

    test('formula protection', () {
      expect(csvCell('=HYPERLINK("http://x","y")'), '"\'=HYPERLINK(""http://x"",""y"")"');
      expect(csvCell('+1 450 555 0101'), "'+1 450 555 0101");
      expect(csvCell('-5'), "'-5");
      expect(csvCell('@SUM(A1)'), "'@SUM(A1)");
      expect(csvCell('\tTab'), "'\tTab");
      expect(csvCell('\rx'), '"\'\rx"');
      expect(csvCell('a=b'), 'a=b');
    });

    test('leadsToCsv writes a header and CRLF rows', () {
      final csv = leadsToCsv([
        {'business_name': '=evil', 'city': 'Montréal, QC', 'phone': '555'},
      ]);
      final lines = csv.split('\r\n');
      expect(lines.first, leadCsvColumns.join(','));
      expect(lines[1], startsWith("'=evil,,\"Montréal, QC\",,555,"));
      expect(csv.endsWith('\r\n'), isTrue);
    });
  });

  testWidgets('download helper revokes the object URL only after the delay', (tester) async {
    final revoked = <String>[];
    scheduleObjectUrlRevoke('blob:abc', revoke: revoked.add);
    await tester.pump(const Duration(seconds: 1));
    expect(revoked, isEmpty);
    await tester.pump(downloadRevokeDelay);
    expect(revoked, ['blob:abc']);
    expect(downloadRevokeDelay, greaterThanOrEqualTo(const Duration(seconds: 10)));
  });

  test('log filters and search', () {
    final entries = JobLogEntry.fromLines(['Job started', 'Error: boom', 'Retry city', 'Done']);
    expect(filterJobLog(entries, JobLogFilter.errors, '').map((e) => e.message), ['Error: boom']);
    expect(filterJobLog(entries, JobLogFilter.warnings, '').map((e) => e.message), ['Retry city']);
    expect(filterJobLog(entries, JobLogFilter.info, '').length, 2);
    expect(filterJobLog(entries, JobLogFilter.all, 'DONE').map((e) => e.message), ['Done']);
    final timed = JobLogEntry.fromPayload([
      {'id': 1, 'message': 'x', 'created_at': '2026-11-17T10:00:05Z'},
    ]);
    expect(timed.single.time!.isUtc, isFalse);
  });

  testWidgets('failed search with leads offers Download Excel and the partial badge', (tester) async {
    _size(tester, const Size(1280, 900));
    final api = FakeApi()
      ..status = (include) => _payload(
            status: 'failed',
            leads: 3,
            error: 'Boom',
            done: 2,
            charged: 70,
            refunded: 40,
            settled: true,
            results: include ? _leads(3) : null,
          );
    await tester.pumpWidget(_host(api, SearchDetailScreen(jobId: 'job-1', api: api)));
    await _settle(tester);

    expect(find.text('Failed · partial results'), findsOneWidget);
    expect(find.text('This search stopped early: Boom. 3 leads were saved.'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('Download Excel'), matching: find.byWidgetPredicate((w) => w is FilledButton)),
      findsOneWidget,
    );
    expect(find.text('70 credits charged, 40 returned — 30 used.'), findsOneWidget);
    expect(find.text('Biz 0'), findsOneWidget);
    expect(find.text('Verified Lead'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('phone: the first lead is on the first screen', (tester) async {
    _size(tester, const Size(390, 844));
    final api = FakeApi()
      ..status = (include) => _payload(
            status: 'completed',
            leads: 3,
            refunded: 40,
            results: include ? _leads(3) : null,
          );
    await tester.pumpWidget(_host(api, SearchDetailScreen(jobId: 'job-1', api: api)));
    await _settle(tester);
    if (!realFont) {
      markTestSkipped('Roboto not found in the Flutter SDK; layout measurement skipped.');
      await tester.pumpWidget(const SizedBox());
      return;
    }
    // The shell takes ~56 px (top bar) and ~80 px (bottom bar) of 844 px.
    expect(find.text('Biz 0'), findsOneWidget);
    final top = tester.getTopLeft(find.text('Biz 0')).dy;
    expect(top + 56 + 24, lessThan(844 - 80), reason: 'first lead name starts at $top px');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed search without leads has no download and says why', (tester) async {
    _size(tester, const Size(1280, 900));
    final api = FakeApi()
      ..status = (include) => _payload(status: 'failed', leads: 0, error: 'Boom', done: 0, refunded: 70,
          results: include ? const [] : null);
    await tester.pumpWidget(_host(api, SearchDetailScreen(jobId: 'job-1', api: api)));
    await _settle(tester);

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text("This search couldn't finish: Boom."), findsOneWidget);
    expect(find.text('Download Excel'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('refund line keeps polling until the refund is settled', (tester) async {
    _size(tester, const Size(1280, 900));
    var settled = false;
    final api = FakeApi()
      ..status = (include) => _payload(
            status: 'cancelled',
            leads: 2,
            done: 1,
            refunded: settled ? 50 : 0,
            settled: settled,
            results: include ? _leads(2) : null,
          );
    await tester.pumpWidget(_host(api, SearchDetailScreen(jobId: 'job-1', api: api)));
    await _settle(tester);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('You cancelled this search. 2 leads were saved.'), findsOneWidget);
    expect(find.text('70 credits charged · calculating refund…'), findsOneWidget);

    settled = true;
    await tester.pump(const Duration(seconds: 3));
    await _settle(tester);
    expect(find.text('70 credits charged, 50 returned — 20 used.'), findsOneWidget);

    // Let the provider's delayed balance refresh fire before tear-down.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('running search: cities progress, no percentage, cancel confirmation copy', (tester) async {
    _size(tester, const Size(1280, 900));
    final api = FakeApi()
      ..status = (include) => {
            ..._payload(status: 'running', leads: 9, done: 2, settled: false),
            'current_city': 'Gatineau, Quebec',
          };
    await tester.pumpWidget(_host(api, SearchDetailScreen(jobId: 'job-1', api: api)));
    await _settle(tester, steps: 4);

    expect(find.text('Searching'), findsOneWidget);
    expect(find.text('plumbers in 4 cities'), findsOneWidget);
    expect(find.text('2 of 4 cities done'), findsOneWidget);
    expect(find.text('Now searching Gatineau, Quebec'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('70 credits charged at start. You pay for what we deliver.'), findsOneWidget);
    expect(find.text('Technical log (2 lines)'), findsOneWidget);

    await tester.tap(find.text('Cancel search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Cancel this search?'), findsOneWidget);
    expect(find.text('It stops after the current business. Leads found so far are kept.'), findsOneWidget);
    await tester.tap(find.text('Keep searching'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('My searches: tab counts from the API and lead counts in the table', (tester) async {
    _size(tester, const Size(1440, 900));
    final api = FakeApi()
      ..jobsPage = {
        'jobs': [
          {..._payload(id: 'a', status: 'completed', leads: 17, refunded: 23), 'top_city': 'Montreal (9)'},
          _payload(id: 'b', status: 'running', leads: 2, done: 1, settled: false),
          _payload(id: 'c', status: 'failed', leads: 0, error: 'Boom', refunded: 70),
        ],
        'total': 3,
        'counts': {'all': 3, 'active': 1, 'completed': 1, 'cancelled': 0, 'failed': 1},
      };
    await tester.pumpWidget(_host(api, const SizedBox()));
    await tester.pumpWidget(_host(api, MySearchesScreen(api: api)));
    await _settle(tester);

    expect(find.text('All (3)'), findsOneWidget);
    expect(find.text('Running (1)'), findsOneWidget);
    expect(find.text('Completed (1)'), findsOneWidget);
    expect(find.text('Cancelled (0)'), findsOneWidget);
    expect(find.text('Failed (1)'), findsOneWidget);
    expect(find.text('Leads'), findsOneWidget); // desktop table header
    expect(find.text('17'), findsOneWidget); // result_count, not `results`
    expect(find.text('2 so far'), findsOneWidget);
    expect(find.text('View Logs'), findsNothing);
    expect(api.statusQueries.last, 'all');

    await tester.tap(find.text('Completed (1)'));
    await tester.pump(const Duration(milliseconds: 500));
    await _settle(tester);
    expect(api.statusQueries.last, 'completed');
  });

  testWidgets('My searches: empty account shows "No searches yet" with Find leads', (tester) async {
    _size(tester, const Size(390, 844));
    final api = FakeApi()
      ..jobsPage = {
        'jobs': <Map<String, dynamic>>[],
        'total': 0,
        'counts': {'all': 0, 'active': 0, 'completed': 0, 'cancelled': 0, 'failed': 0},
      };
    await tester.pumpWidget(_host(api, MySearchesScreen(api: api)));
    await _settle(tester);
    expect(find.text('No searches yet'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('Find leads'), matching: find.byWidgetPredicate((w) => w is FilledButton)),
      findsOneWidget,
    );
  });
}
