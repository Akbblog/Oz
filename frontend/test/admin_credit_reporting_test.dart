import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:business_scraper_app/screens/admin_credit_account_dialog.dart';
import 'package:business_scraper_app/services/api_service.dart';
import 'package:business_scraper_app/widgets/admin_overview_panel.dart';

// --------------------------------------------------------------------------
// fixtures (synthetic: no real accounts, searches or payments)
// --------------------------------------------------------------------------

Map<String, dynamic> _tx(int id, String cat, String label, int amount, int after,
        {bool chainOk = true, Map<String, dynamic>? job, Map<String, dynamic>? payment}) =>
    {
      'id': id,
      'created_at': '2026-01-10T09:00:00',
      'transaction_type': amount < 0 ? 'debit' : 'credit',
      'category': cat,
      'category_label': label,
      'amount': amount,
      'balance_after': after,
      'expected_balance_after': after,
      'chain_ok': chainOk,
      'reason': '$label reason',
      'granted_by': null,
      'job': job,
      'payment': payment,
    };

const _headline = [
  'Free signup credits',
  'Paid credits',
  'Search charges',
  'Search refunds',
  'Net search usage',
  'Current balance',
];

/// Synthetic replica of the reported case: same amounts and order only.
Map<String, dynamic> replicaReport() {
  final jobA = {'job_id': 'search-aaaa-0001', 'exists': true, 'status': 'completed', 'category': 'Restaurants',
    'leads': 20, 'credit_charged': 65, 'credit_refunded': 30};
  final jobB = {...jobA, 'job_id': 'search-bbbb-0002'};
  return {
    'user_id': 501,
    'username': 'replica_case',
    'summary': <String, dynamic>{
      'starting_credits': 100, 'paid_credits': 0, 'job_charges_gross': 130, 'job_refunds': 60,
      'job_charges_net': 70, 'current_balance': 30,
      'admin_grants': 0, 'sandbox_test_credits': 0, 'unverified_payment_credits': 0, 'promo_bonus_credits': 0,
      'subscription_credits': 0, 'other_credits': 0, 'other_debits': 0,
      'searches_on_file': 2, 'leads_on_file': 40,
      'net_credits_per_lead_on_file': 1.75, 'charged_searches_since_deleted': 0,
    },
    'reconciliation': {'status': 'reconciled', 'ledger_sum': 30, 'current_balance': 30, 'difference': 0,
      'chain_breaks': 0, 'first_chain_break': null},
    'transactions': [
      _tx(5, 'job_refund', 'Search refund', 30, 30, job: jobB),
      _tx(4, 'job_charge', 'Search charge', -65, 0, job: jobB),
      _tx(3, 'job_refund', 'Search refund', 30, 65, job: jobA),
      _tx(2, 'job_charge', 'Search charge', -65, 35, job: jobA),
      _tx(1, 'starting_credits', 'Free signup credits', 100, 100),
    ],
    'pagination': {'page': 1, 'page_size': 25, 'total': 5, 'pages': 1},
    'definitions': {},
  };
}

class FakeAdminApi extends ApiService {
  Map<String, dynamic> Function(int page)? report;
  Object? reportError;
  final List<int> pagesRequested = [];
  Completer<void>? reportGate;
  final Map<int, Completer<void>> pageGates = {};
  Map<String, dynamic>? staleResponse; // returned by a gated (slow) request

  Map<String, dynamic> Function(String range)? overview;
  Object? overviewError;
  final List<String> rangesRequested = [];
  final Map<String, Completer<void>> rangeGates = {};
  Map<String, dynamic>? health;
  Object? healthError;
  int? probeMs;
  Object? probeError;
  http.Client? probeClient; // when set, run the REAL probe against this client

  @override
  Future<Map<String, dynamic>> getUserCreditReport(int userId, {int page = 1, int pageSize = 25}) async {
    pagesRequested.add(page);
    if (reportGate != null) await reportGate!.future;
    final gate = pageGates.remove(page);
    if (gate != null) {
      await gate.future;
      if (staleResponse != null) return staleResponse!;
    }
    if (reportError != null) throw reportError!;
    return report!(page);
  }

  @override
  Future<Map<String, dynamic>> getUserKpis(int userId) async =>
      {'last_login': '2026-01-10T09:01:00', 'last_activity': '2026-01-10T09:22:05'};

  @override
  Future<Map<String, dynamic>> getAdminOverview(String range) async {
    rangesRequested.add(range);
    final gate = rangeGates.remove(range);
    if (gate != null) await gate.future;
    if (overviewError != null) throw overviewError!;
    return overview!(range);
  }

  @override
  Future<Map<String, dynamic>> getAdminHealth() async {
    if (healthError != null) throw healthError!;
    return health!;
  }

  @override
  Future<int> probePublicApi({http.Client? client}) async {
    if (probeClient != null) return super.probePublicApi(client: probeClient);
    if (probeError != null) throw probeError!;
    return probeMs!;
  }
}

Future<void> _pump(WidgetTester tester, Widget child, {Size size = const Size(1280, 1000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

Widget _dialog(FakeAdminApi api) =>
    AdminCreditAccountDialog(apiService: api, userId: 501, username: 'replica_case');

String _figure(WidgetTester tester, String label) =>
    tester.widget<Text>(find.byKey(Key('figure-value-$label'))).data!;

void main() {
  // ------------------------------------------------------------------------
  // credit account dialog
  // ------------------------------------------------------------------------
  group('credit account dialog', () {
    testWidgets('replica shows 100 / 0 / 130 / 60 / 70 / 30 in the required order', (tester) async {
      final api = FakeAdminApi()..report = (_) => replicaReport();
      await _pump(tester, _dialog(api));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reconciliation-reconciled')), findsOneWidget);
      expect([for (final l in _headline) _figure(tester, l)], ['100', '0', '130', '60', '70', '30']);
      // Rendered in reading order: left-to-right, then top-to-bottom.
      final pos = [for (final l in _headline) tester.getTopLeft(find.byKey(Key('figure-$l')))];
      for (var i = 1; i < pos.length; i++) {
        expect(pos[i].dy > pos[i - 1].dy || (pos[i].dy == pos[i - 1].dy && pos[i].dx > pos[i - 1].dx), isTrue,
            reason: '${_headline[i]} should follow ${_headline[i - 1]}');
      }
      expect(_figure(tester, 'Staff grants'), '0');
      expect(find.text('Credits Purchased'), findsNothing);
      expect(find.text('Cost / Result'), findsNothing);
      for (final id in [1, 2, 3, 4, 5]) {
        expect(find.byKey(Key('ledger-row-$id')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('missing figures show Unavailable, never 0', (tester) async {
      final api = FakeAdminApi()
        ..report = (_) {
          final r = replicaReport();
          (r['summary'] as Map)
            ..['paid_credits'] = null
            ..remove('sandbox_test_credits');
          r.remove('reconciliation');
          return r;
        };
      await _pump(tester, _dialog(api));
      await tester.pumpAndSettle();
      expect(_figure(tester, 'Paid credits'), 'Unavailable');
      expect(_figure(tester, 'Sandbox test credits (not paid)'), 'Unavailable');
      expect(find.text('Reconciliation unavailable'), findsOneWidget);
      expect(find.text('History reconciles to the current balance'), findsNothing);
    });

    testWidgets('loading then error then retry', (tester) async {
      final api = FakeAdminApi()
        ..reportGate = Completer<void>()
        ..reportError = Exception('Failed to load credit history (500)');
      await _pump(tester, _dialog(api));
      await tester.pump();
      expect(find.byKey(const Key('credit-account-loading')), findsOneWidget);

      api.reportGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load this account's credit history."), findsOneWidget);

      api
        ..reportGate = null
        ..reportError = null
        ..report = (_) => replicaReport();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reconciliation-reconciled')), findsOneWidget);
    });

    testWidgets('empty account', (tester) async {
      final api = FakeAdminApi()
        ..report = (_) => {
              ...replicaReport(),
              'summary': {...replicaReport()['summary'], 'current_balance': 0, 'net_credits_per_lead_on_file': null},
              'reconciliation': {'status': 'no_history', 'ledger_sum': 0, 'current_balance': 0, 'difference': 0,
                'chain_breaks': 0},
              'transactions': [],
              'pagination': {'page': 1, 'page_size': 25, 'total': 0, 'pages': 1},
            };
      await _pump(tester, _dialog(api));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reconciliation-no_history')), findsOneWidget);
      expect(find.byKey(const Key('credit-history-empty')), findsOneWidget);
    });

    testWidgets('mismatch is flagged with the difference and chain break', (tester) async {
      final api = FakeAdminApi()
        ..report = (_) => {
              ...replicaReport(),
              'reconciliation': {'status': 'mismatch', 'ledger_sum': 100, 'current_balance': 150, 'difference': 50,
                'chain_breaks': 1,
                'first_chain_break': {'entry_id': 2, 'expected_balance_after': 35, 'recorded_balance_after': 90}},
              'transactions': [_tx(2, 'job_charge', 'Search charge', -65, 90, chainOk: false)],
            };
      await _pump(tester, _dialog(api));
      await tester.pumpAndSettle();
      expect(find.text('History does NOT reconcile'), findsOneWidget);
      expect(find.textContaining('+50 not explained by any entry'), findsOneWidget);
      expect(find.textContaining('first at entry #2'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('large ledger pages through the server; a stale page response is ignored', (tester) async {
      final api = FakeAdminApi()
        ..report = (page) => {
              ...replicaReport(),
              'transactions': [
                for (var i = 0; i < 25; i++) _tx(10000 - (page - 1) * 25 - i, 'job_charge', 'Search charge', -5, 10)
              ],
              'pagination': {'page': page, 'page_size': 25, 'total': 3000, 'pages': 120},
            };
      await _pump(tester, _dialog(api));
      await tester.pumpAndSettle();
      expect(find.text('Transaction history · 3,000 entries'), findsOneWidget);
      expect(find.text('Page 1 of 120'), findsOneWidget);

      // Page 2 is slow; the admin presses Refresh (page 1) before it answers.
      final slow = api.pageGates[2] = Completer<void>();
      api.staleResponse = {
        ...replicaReport(),
        'transactions': [_tx(77777, 'job_charge', 'Search charge', -5, 10)],
        'pagination': {'page': 2, 'page_size': 25, 'total': 3000, 'pages': 120},
      };
      await tester.ensureVisible(find.byTooltip('Older entries'));
      await tester.tap(find.byTooltip('Older entries'));
      await tester.pump();
      api.pageGates.clear(); // the later request is not gated
      final refresh = tester.widget<IconButton>(
          find.ancestor(of: find.byIcon(Icons.refresh), matching: find.byType(IconButton)).first);
      expect(refresh.onPressed, isNull, reason: 'refresh is disabled while paging');
      // The admin presses "Older entries" again; this newer request answers first.
      await tester.tap(find.byTooltip('Older entries'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 120'), findsOneWidget);
      slow.complete(); // the first (stale) page-2 request answers last
      await tester.pumpAndSettle();
      expect(api.pagesRequested, [1, 2, 2]);
      expect(find.text('Page 2 of 120'), findsOneWidget);
      expect(find.byKey(const Key('ledger-row-9975')), findsOneWidget);
      expect(find.byKey(const Key('ledger-row-77777')), findsNothing, reason: 'stale answer must be discarded');
      expect(tester.takeException(), isNull);
    });

    testWidgets('phone width renders without overflow', (tester) async {
      final api = FakeAdminApi()..report = (_) => replicaReport();
      await _pump(tester, _dialog(api), size: const Size(390, 844));
      await tester.pumpAndSettle();
      expect(_figure(tester, 'Net search usage'), '70');
      expect(find.text('DATE'), findsNothing); // the wide table header is not used on phones
      expect(tester.takeException(), isNull);
    });

    testWidgets('job chip opens search details', (tester) async {
      final api = FakeAdminApi()..report = (_) => replicaReport();
      await _pump(tester, _dialog(api));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Search search-a · completed').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search search-a · completed').first);
      await tester.pumpAndSettle();
      expect(find.text('Net cost'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------
  // overview panel
  // ------------------------------------------------------------------------

  Map<String, dynamic> overview(String range) => {
        'window': {'range': range, 'label': range, 'start': range == 'all' ? null : '2026-01-09T12:00:00+00:00',
          'end': '2026-01-10T12:00:00+00:00'},
        'metrics': <String, dynamic>{
          'new_users': range == '24h' ? 1 : 7, 'active_users': 3, 'searches_started': 2,
          'searches_by_status': {'completed': 2}, 'leads_delivered': 40, 'credits_charged_gross': 130,
          'credits_refunded': 60, 'credits_charged_net': 70, 'paid_credits': 0, 'starting_credits': 100,
          'admin_grants': 0, 'sandbox_test_credits': 0,
        },
        'snapshot': <String, dynamic>{'total_users': 9, 'pending_users': 0, 'credits_in_circulation': 3000,
          'searches_in_progress': 0, 'pending_credit_requests': 0},
        'unavailable': [],
        'definitions': {},
      };

  Map<String, dynamic> okHealth() => {
        'status': 'ok',
        'checks': {
          'database': {'status': 'ok', 'latency_ms': 12.5},
          'migrations': {'status': 'ok', 'applied': '018'},
          'job_runner': {'status': 'ok', 'last_pass_seconds_ago': 2.0},
          'tunnel_connector': {'status': 'unknown', 'detail': 'Not monitored from the backend'},
        },
      };

  Widget panel(FakeAdminApi api, {int? promos = 1, int? uses = 4}) => SingleChildScrollView(
      child: AdminOverviewPanel(apiService: api, activePromos: promos, promoUses: uses));

  int newUsersShown(WidgetTester tester) {
    final card = find.ancestor(of: find.text('New users'), matching: find.byType(Column)).first;
    final texts = tester.widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)));
    return int.parse(texts.map((t) => t.data ?? '').firstWhere((d) => RegExp(r'^\d+$').hasMatch(d)));
  }

  group('overview panel', () {
    testWidgets('range selector requests filtered data with the required labels', (tester) async {
      final api = FakeAdminApi()
        ..overview = overview
        ..health = okHealth()
        ..probeMs = 120;
      await _pump(tester, panel(api));
      await tester.pumpAndSettle();
      expect(find.text('ACTIVITY · LAST 24 HOURS'), findsOneWidget);
      for (final label in ['Free signup credits', 'Paid credits', 'Search charges', 'Search refunds',
          'Net search usage', 'Staff grants']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Last 24h'), findsNothing);
      expect(find.text('Active Sessions'), findsNothing);

      await tester.tap(find.byKey(const Key('range-7d')));
      await tester.pumpAndSettle();
      expect(api.rangesRequested, ['24h', '7d']);
      expect(find.text('ACTIVITY · LAST 7 DAYS'), findsOneWidget);
      expect(newUsersShown(tester), 7);
      expect(find.byKey(const Key('health-ok')), findsOneWidget);
      expect(find.text('Reachable · 120 ms'), findsOneWidget);
    });

    testWidgets('a slow response for a previous range is ignored', (tester) async {
      final api = FakeAdminApi()
        ..overview = overview
        ..health = okHealth()
        ..probeMs = 50;
      await _pump(tester, panel(api));
      await tester.pumpAndSettle();
      expect(newUsersShown(tester), 1);

      final slow = api.rangeGates['7d'] = Completer<void>();
      await tester.tap(find.byKey(const Key('range-7d')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('range-24h')));
      await tester.pumpAndSettle();
      slow.complete(); // the 7d answer arrives after 24h was re-selected
      await tester.pumpAndSettle();
      expect(api.rangesRequested, ['24h', '7d', '24h']);
      expect(find.text('ACTIVITY · LAST 24 HOURS'), findsOneWidget);
      expect(newUsersShown(tester), 1, reason: 'stale 7d data (7) must not replace 24h data');
    });

    testWidgets('health and probe failures show unknown/unreachable, never OK', (tester) async {
      final api = FakeAdminApi()
        ..overview = overview
        ..healthError = Exception('Health check failed (502)')
        ..probeError = Exception('Public API returned 530');
      await _pump(tester, panel(api));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('health-unknown')), findsOneWidget);
      expect(find.byKey(const Key('probe-unreachable')), findsOneWidget);
      expect(find.text('OK'), findsNothing);
    });

    testWidgets('failed scheduling pass and missing migration are not OK', (tester) async {
      final h = okHealth();
      (h['checks'] as Map)['job_runner'] = {'status': 'failing', 'detail': 'last scheduling pass failed'};
      (h['checks'] as Map)['migrations'] = {'status': 'missing', 'detail': 'not applied: 017'};
      h['status'] = 'degraded';
      final api = FakeAdminApi()
        ..overview = overview
        ..health = h
        ..probeMs = 90;
      await _pump(tester, panel(api));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('health-degraded')), findsOneWidget);
      expect(find.textContaining('Search runner: failing'), findsOneWidget);
      expect(find.textContaining('Schema migrations: missing'), findsOneWidget);
      expect(find.text('OK'), findsNothing);
    });

    testWidgets('unavailable metrics and promo counts say Unavailable, not 0', (tester) async {
      final api = FakeAdminApi()
        ..overview = (r) {
          final o = overview(r);
          (o['metrics'] as Map)
            ..['active_users'] = null
            ..['sandbox_test_credits'] = null;
          return o;
        }
        ..health = okHealth()
        ..probeMs = 50;
      await _pump(tester, panel(api, promos: null, uses: null));
      await tester.pumpAndSettle();
      // active users, sandbox test credits, active promos, promo uses
      expect(find.text('Unavailable'), findsNWidgets(4));
    });

    testWidgets('overview failure shows an error with retry', (tester) async {
      final api = FakeAdminApi()
        ..overviewError = Exception('Failed to load overview (500)')
        ..health = okHealth()
        ..probeMs = 50;
      await _pump(tester, panel(api));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overview-error')), findsOneWidget);
      api
        ..overviewError = null
        ..overview = overview;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overview-error')), findsNothing);
    });

    testWidgets('phone width lays out without overflow', (tester) async {
      final api = FakeAdminApi()
        ..overview = overview
        ..health = okHealth()
        ..probeMs = 75;
      await _pump(tester, panel(api), size: const Size(390, 844));
      await tester.pumpAndSettle();
      expect(find.text('Net search usage'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------------------
  // public reachability probe
  // ------------------------------------------------------------------------
  group('public API probe', () {
    const healthJson = '{"status": "healthy", "timestamp": "2026-01-10T12:00:00.123456"}';
    const proxyHtml = '<!doctype html><html><body>Welcome to our portal</body></html>';

    MockClient serving(int status, String body, {String type = 'application/json'}) =>
        MockClient((_) async => http.Response(body, status, headers: {'content-type': type}));

    test('only the API health JSON counts as reachable', () async {
      final api = ApiService();
      expect(await api.probePublicApi(client: serving(200, healthJson)), isA<int>());
      await expectLater(api.probePublicApi(client: serving(200, proxyHtml, type: 'text/html')),
          throwsA(isA<Exception>()));
      await expectLater(api.probePublicApi(client: serving(200, '{"status": "ok"}')), throwsA(isA<Exception>()));
      await expectLater(api.probePublicApi(client: serving(200, '[]')), throwsA(isA<Exception>()));
      await expectLater(api.probePublicApi(client: serving(530, 'origin unreachable')), throwsA(isA<Exception>()));
      expect(ApiService.isApiHealthBody(healthJson), isTrue);
      expect(ApiService.isApiHealthBody(proxyHtml), isFalse);
      expect(ApiService.isApiHealthBody('{"status": "healthy"}'), isFalse);
    });

    testWidgets('a proxy answering HTML with HTTP 200 is shown as unreachable', (tester) async {
      final api = FakeAdminApi()
        ..overview = overview
        ..health = okHealth()
        ..probeClient = serving(200, proxyHtml, type: 'text/html');
      await _pump(tester, panel(api));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('probe-unreachable')), findsOneWidget);
      expect(find.byKey(const Key('probe-ok')), findsNothing);
      expect(find.textContaining('not with the API health response'), findsOneWidget);

      api.probeClient = serving(200, healthJson);
      await tester.tap(find.byTooltip('Re-check'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('probe-ok')), findsOneWidget);
    });
  });
}
