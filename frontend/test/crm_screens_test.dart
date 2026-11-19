import 'dart:io';

import 'package:business_scraper_app/app_router.dart';
import 'package:business_scraper_app/core/error_handler.dart';
import 'package:business_scraper_app/providers/active_searches_provider.dart';
import 'package:business_scraper_app/providers/auth_provider.dart';
import 'package:business_scraper_app/providers/credit_provider.dart';
import 'package:business_scraper_app/providers/crm_provider.dart';
import 'package:business_scraper_app/providers/scraper_provider.dart';
import 'package:business_scraper_app/screens/crm/crm_agenda_screen.dart';
import 'package:business_scraper_app/screens/crm/crm_leads_screen.dart';
import 'package:business_scraper_app/screens/crm/crm_pipeline_screen.dart';
import 'package:business_scraper_app/screens/crm/crm_record_screen.dart';
import 'package:business_scraper_app/screens/crm/crm_reports_screen.dart';
import 'package:business_scraper_app/screens/results_screen.dart';
import 'package:business_scraper_app/services/api_service.dart';
import 'package:business_scraper_app/services/crm_api.dart';
import 'package:business_scraper_app/widgets/app_shell.dart';
import 'package:business_scraper_app/widgets/crm/crm_widgets.dart';
import 'package:business_scraper_app/widgets/crm/crm_record_card.dart';
import 'package:business_scraper_app/widgets/sidebar_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crm_fakes.dart';

class _FakeAuth extends AuthProvider {
  @override
  bool get isAuthenticated => true;
  @override
  bool get isRestoring => false;
  @override
  bool get isLoading => false;
  @override
  bool get isAdmin => false;
  @override
  Map<String, dynamic>? get currentUser => {'username': 'rita', 'email': 'r@example.com'};
}

class _FakeApi extends ApiService {
  @override
  Future<bool> healthCheck() async => true;
  @override
  Future<List<Map<String, dynamic>>> getActiveJobs() async => const [];
}

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester, {int steps = 12}) async {
  for (var i = 0; i < steps; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

CrmProvider _crm(FakeCrmApi api, {bool enabled = true, Map<String, int>? counts}) =>
    CrmProvider(api: api)..debugSet(enabled: enabled, workspace: crmTestWorkspace(), counts: counts ?? const {});

/// Shell + providers (like the real app) around [child].
Widget _host(CrmProvider crm, Widget child, {bool shell = true}) {
  final api = _FakeApi();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuth()),
      ChangeNotifierProvider(create: (_) => ScraperProvider(api: api)),
      ChangeNotifierProvider<CreditProvider>.value(value: CreditProvider.instance),
      ChangeNotifierProvider(create: (_) => ActiveSearchesProvider(api: api)),
      ChangeNotifierProvider<CrmProvider>.value(value: crm),
    ],
    child: MaterialApp(
      home: shell ? AppShell(section: ShellSection.crm, title: 'CRM', child: child) : Scaffold(body: child),
      onGenerateRoute: (s) => MaterialPageRoute(settings: s, builder: (_) => Scaffold(body: Text('route ${s.name}'))),
    ),
  );
}

Map<String, dynamic> _pipeline() => {
      'stages': [
        for (final s in crmTestStages())
          {
            'stage': s,
            'count': s['id'] == 's-new' ? 2 : 0,
            'values': s['id'] == 's-new'
                ? [
                    {'currency': 'CAD', 'total': 1500},
                    {'currency': 'USD', 'total': 200},
                  ]
                : [],
            'items': s['id'] == 's-new'
                ? [
                    crmTestRecord(value: 1500, currency: 'CAD'),
                    crmTestRecord(id: 'rec-2', title: 'Beta Heating', value: 200, currency: 'USD'),
                  ]
                : [],
            'next_cursor': null,
          },
      ],
      'summary': {'open': 2, 'due_today': 1, 'overdue': 0, 'no_next_activity': 2},
    };

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
    loader.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
    any = true;
  }
  if (!any) return false;
  await loader.load();
  return true;
}

void main() {
  setUpAll(() async {
    await _loadRoboto();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CreditProvider.instance.clear();
  });

  testWidgets('record status badges stay compact on wide screens', (tester) async {
    _size(tester, const Size(1200, 800));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: Wrap(children: [CrmBadge(label: 'Open'), CrmBadge(label: 'Lead')])),
      ),
    ));
    expect(tester.getSize(find.byType(CrmBadge).first).width, lessThan(100));
    expect(tester.getSize(find.byType(CrmBadge).last).width, lessThan(100));
  });

  testWidgets('pipeline contact actions fit one row in a narrow column', (tester) async {
    _size(tester, const Size(390, 700));
    final record = crmTestRecord();
    record['company'] = {
      ...record['company'] as Map,
      'email': 'hello@acme.example',
      'address': '1 Rue X',
    };
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: CrmRecordCard(
            record: record,
            stages: crmTestStages(),
            onOpen: () {},
            onMove: (_) {},
            onDelete: () {},
          ),
        ),
      ),
    ));

    final labels = ['Call', 'Email', 'Website', 'Map'];
    final top = tester.getTopLeft(find.text(labels.first)).dy;
    for (final label in labels) {
      expect(tester.getTopLeft(find.text(label)).dy, closeTo(top, 1));
    }
    expect(find.byTooltip('Copy contact details'), findsOneWidget);
    expect(find.byTooltip('Delete Acme Plumbing from CRM'), findsOneWidget);
    final move = tester.getCenter(find.byIcon(Icons.drive_file_move_outlined));
    final copy = tester.getCenter(find.byIcon(Icons.copy_outlined));
    expect(copy.dx, closeTo(move.dx, 1));
    expect(copy.dy, greaterThan(move.dy));
    expect(tester.takeException(), isNull);
  });

  group('nav gating', () {
    testWidgets('CRM is hidden until the server enables it (sidebar)', (tester) async {
      _size(tester, const Size(1440, 900));
      final api = FakeCrmApi();
      final crm = _crm(api, enabled: false);
      await tester.pumpWidget(_host(crm, const SizedBox()));
      await _settle(tester);
      expect(find.descendant(of: find.byType(AppSidebar), matching: find.text('CRM')), findsNothing);

      crm.debugSet(enabled: true, counts: {'overdue': 2, 'today': 1});
      await _settle(tester);
      expect(find.bySemanticsLabel('CRM, 3 due'), findsOneWidget);
      expect(find.text('3 due'), findsOneWidget);
    });

    testWidgets('phone bottom bar shows CRM after Searches with a due badge', (tester) async {
      _size(tester, const Size(390, 844));
      final crm = _crm(FakeCrmApi(), counts: {'overdue': 1, 'today': 0});
      await tester.pumpWidget(_host(crm, const SizedBox()));
      await _settle(tester);
      expect(find.bySemanticsLabel('CRM, 1 follow-ups due'), findsOneWidget);
      final labels = tester.widgetList<Text>(find.descendant(of: find.byType(PhoneBottomBar), matching: find.byType(Text))).map((t) => t.data).toList();
      expect(labels.indexOf('CRM'), greaterThan(labels.indexOf('Searches')));
      expect(labels.indexOf('CRM'), lessThan(labels.indexOf('Credits')));
    });

    testWidgets('provider start: status false keeps CRM hidden', (tester) async {
      final api = FakeCrmApi()..enabled = false;
      final crm = CrmProvider(api: api);
      await crm.start();
      expect(crm.enabled, isFalse);
      api.enabled = true;
      await crm.start();
      expect(crm.enabled, isTrue);
      crm.clear();
      expect(crm.enabled, isNull);
      crm.dispose();
    });
  });

  group('pipeline', () {
    testWidgets('stage download exports the selected stage with board filters, not loaded cards', (tester) async {
      _size(tester, const Size(1440, 900));
      final data = _pipeline();
      final stages = data['stages'] as List;
      (stages[2] as Map<String, dynamic>)['count'] = 5;
      final api = FakeCrmApi()..pipeline = data;
      await tester.pumpWidget(_host(
        _crm(api),
        CrmPipelineScreen(api: api, initialQuery: const {'q': 'cafe', 'source': 'job-7'}),
      ));
      await _settle(tester);

      await tester.tap(find.byTooltip('Download Qualified leads'));
      await _settle(tester);
      expect(api.callsOf('export').single.args, {
        'format': 'xlsx',
        'stage_id': 's-qual',
        'outcome': 'open',
        'archived': 'false',
        'q': 'cafe',
        'source_job_id': 'job-7',
      });
    });

    testWidgets('renders stages with counts and separate currency totals; move via menu', (tester) async {
      _size(tester, const Size(1440, 900));
      final api = FakeCrmApi()..pipeline = _pipeline();
      await tester.pumpWidget(_host(_crm(api), CrmPipelineScreen(api: api)));
      await _settle(tester);

      for (final name in ['New', 'Contacted', 'Qualified', 'Proposal', 'Won']) {
        expect(find.text(name), findsWidgets);
      }
      expect(find.text('CAD 1,500.00 · USD 200.00'), findsOneWidget);
      expect(find.textContaining('2 open · 1 due today'), findsOneWidget);
      final newCol = find.byKey(const ValueKey('crm-column-s-new'));
      final conCol = find.byKey(const ValueKey('crm-column-s-con'));
      expect(find.descendant(of: newCol, matching: find.text('Acme Plumbing')), findsOneWidget);

      await tester.tap(find.byTooltip('Move Acme Plumbing to stage'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'Contacted'));
      await _settle(tester);

      final move = api.callsOf('stage').single;
      expect(move.args, {'id': 'rec-1', 'stage_id': 's-con', 'version': 3});
      expect(find.descendant(of: conCol, matching: find.text('Acme Plumbing')), findsOneWidget);
      expect(find.descendant(of: newCol, matching: find.text('Acme Plumbing')), findsNothing);
      expect(find.text('Moved Acme Plumbing to Contacted.'), findsOneWidget);
    });

    testWidgets('a failed move rolls back and explains', (tester) async {
      _size(tester, const Size(1440, 900));
      final api = FakeCrmApi()
        ..pipeline = _pipeline()
        ..failNext = CrmException('That stage is not available.', statusCode: 409, code: 'invalid_transition');
      await tester.pumpWidget(_host(_crm(api), CrmPipelineScreen(api: api)));
      await _settle(tester);
      await tester.tap(find.byTooltip('Move Acme Plumbing to stage'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'Qualified'));
      await _settle(tester);

      expect(api.callsOf('stage'), hasLength(1));
      final newCol = find.byKey(const ValueKey('crm-column-s-new'));
      final qualCol = find.byKey(const ValueKey('crm-column-s-qual'));
      expect(find.descendant(of: newCol, matching: find.text('Acme Plumbing')), findsOneWidget);
      expect(find.descendant(of: qualCol, matching: find.text('Acme Plumbing')), findsNothing);
      expect(find.textContaining("couldn't be moved to Qualified: That stage is not available."), findsOneWidget);
      expect(find.textContaining('It is back in New.'), findsOneWidget);
    });

    testWidgets('card delete asks for confirmation and sends record version', (tester) async {
      _size(tester, const Size(1440, 900));
      final api = FakeCrmApi()..pipeline = _pipeline();
      await tester.pumpWidget(_host(_crm(api), CrmPipelineScreen(api: api)));
      await _settle(tester);
      await tester.tap(find.byTooltip('Delete Acme Plumbing from CRM'));
      await _settle(tester);
      expect(api.callsOf('delete'), isEmpty);
      await tester.tap(find.text('Cancel').last);
      await _settle(tester);
      expect(api.callsOf('delete'), isEmpty);
      await tester.tap(find.byTooltip('Delete Acme Plumbing from CRM'));
      await _settle(tester);
      await tester.tap(find.text('Delete record').last);
      await _settle(tester);
      expect(api.callsOf('delete').single.args, {'id': 'rec-1', 'version': 3});
    });

    testWidgets('empty pipeline offers "Add from a search" and "Create manually"', (tester) async {
      _size(tester, const Size(1440, 900));
      final api = FakeCrmApi()
        ..pipeline = {
          'stages': [
            for (final s in crmTestStages()) {'stage': s, 'count': 0, 'values': [], 'items': [], 'next_cursor': null},
          ],
          'summary': {'open': 0, 'due_today': 0, 'overdue': 0, 'no_next_activity': 0},
        };
      await tester.pumpWidget(_host(_crm(api), CrmPipelineScreen(api: api)));
      await _settle(tester);
      expect(find.text('Your pipeline is empty'), findsOneWidget);
      expect(find.text('Add from a search'), findsOneWidget);
      expect(find.text('Create manually'), findsOneWidget);
    });

    testWidgets('phone: stage chips filter the list', (tester) async {
      _size(tester, const Size(390, 844));
      final api = FakeCrmApi()..pipeline = _pipeline();
      await tester.pumpWidget(_host(_crm(api), CrmPipelineScreen(api: api)));
      await _settle(tester);
      expect(find.text('New · 2'), findsOneWidget);
      expect(find.text('Acme Plumbing'), findsOneWidget);
      await tester.tap(find.text('Contacted · 0'));
      await _settle(tester);
      expect(find.text('Acme Plumbing'), findsNothing);
      expect(find.text('Nothing in Contacted yet'), findsOneWidget);
    });

    testWidgets('phone: selected Won stage can be downloaded', (tester) async {
      _size(tester, const Size(390, 844));
      final data = _pipeline();
      final stages = data['stages'] as List;
      (stages[4] as Map<String, dynamic>)['count'] = 3;
      final api = FakeCrmApi()..pipeline = data;
      await tester.pumpWidget(_host(_crm(api), CrmPipelineScreen(api: api)));
      await _settle(tester);
      await tester.tap(find.byType(ChoiceChip).last);
      await _settle(tester);
      await tester.tap(find.byTooltip('Download Won leads'));
      await _settle(tester);
      expect(api.callsOf('export').single.args, {
        'format': 'xlsx',
        'stage_id': 's-won',
        'outcome': 'won',
        'archived': 'false',
      });
    });
  });

  group('leads list', () {
    testWidgets('URL filters go to the API; Load more sends the cursor', (tester) async {
      _size(tester, const Size(1440, 900));
      final api = FakeCrmApi()
        ..recordPages = [
          CrmPage(items: [crmTestRecord()], nextCursor: 'c2', total: 2),
          CrmPage(items: [crmTestRecord(id: 'rec-2', title: 'Beta Heating')], total: 2),
        ];
      await tester.pumpWidget(_host(
        _crm(api),
        CrmLeadsScreen(api: api, pageSize: 1, initialQuery: const {'source': 'job-9', 'outcome': 'all', 'due': 'overdue'}),
      ));
      await _settle(tester);
      final first = api.callsOf('records').first.args;
      expect(first['source_job_id'], 'job-9');
      expect(first['outcome'], 'all');
      expect(first['archived'], 'false');
      expect(first['due'], 'overdue');
      expect(first['limit'], '1');
      expect(first.containsKey('cursor'), isFalse);
      expect(find.text('From one search'), findsOneWidget);
      expect(find.text('Showing 1 of 2 records'), findsOneWidget);

      await tester.tap(find.text('Load more'));
      await _settle(tester);
      expect(api.callsOf('records').last.args['cursor'], 'c2');
      expect(find.text('Beta Heating'), findsOneWidget);

      api.recordPages = [CrmPage(items: [crmTestRecord()], total: 1)];
      await tester.tap(find.text('Any outcome'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'Won'));
      await _settle(tester);
      final last = api.callsOf('records').last.args;
      expect(last['outcome'], 'won');
      expect(last['source_job_id'], 'job-9');
      expect(last.containsKey('cursor'), isFalse);
    });

    testWidgets('an error shows a retry, not an empty list', (tester) async {
      _size(tester, const Size(1440, 900));
      final api = _ThrowingRecordsApi();
      await tester.pumpWidget(_host(_crm(api), CrmLeadsScreen(api: api)));
      await _settle(tester);
      expect(find.text("We couldn't reach the server"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('No records yet'), findsNothing);
    });
  });

  group('record detail', () {
    Future<FakeCrmApi> open(WidgetTester tester, {Map<String, dynamic>? record, Size size = const Size(1440, 2600)}) async {
      _size(tester, size);
      final api = FakeCrmApi();
      if (record != null) api.record = record;
      await tester.pumpWidget(_host(_crm(api), CrmRecordScreen(key: UniqueKey(), recordId: 'rec-1', api: api, now: () => DateTime(2026, 11, 18, 12))));
      await _settle(tester);
      return api;
    }

    testWidgets('shows header, next action, found-online vs your details, sources', (tester) async {
      await open(tester);
      expect(find.text('Acme Plumbing'), findsWidgets);
      expect(find.text('Next action'), findsOneWidget);
      expect(find.text('Call: Intro call'), findsWidgets);
      expect(find.text('Found online'), findsOneWidget);
      expect(find.text('Your details'), findsOneWidget);
      expect(find.text('Acme Plumbing Inc'), findsOneWidget);
      expect(find.text('Original search no longer available'), findsOneWidget);
      expect(find.text('Moved from New to Contacted'), findsOneWidget);
      expect(find.text('Found in 2 searches'), findsOneWidget);
    });

    testWidgets('Mark lost requires a reason, then sends it with the version', (tester) async {
      final api = await open(tester);
      await tester.tap(find.text('Mark lost…'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Mark lost'));
      await _settle(tester);
      expect(find.textContaining('Choose a reason'), findsOneWidget);
      expect(api.callsOf('lost'), isEmpty);

      await tester.tap(find.text('Not interested'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Mark lost'));
      await _settle(tester);
      expect(api.callsOf('lost').single.args, {'id': 'rec-1', 'reason_id': 'r1', 'custom_reason': null, 'note': '', 'version': 3});
      expect(find.text('Marked lost.'), findsOneWidget);
    });

    testWidgets('a custom lost reason is sent as custom_reason', (tester) async {
      final api = await open(tester);
      await tester.tap(find.text('Mark lost…'));
      await _settle(tester);
      await tester.tap(find.text('Another reason (type it)'));
      await _settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Your reason'), 'Chose a competitor');
      await tester.tap(find.widgetWithText(FilledButton, 'Mark lost'));
      await _settle(tester);
      expect(api.callsOf('lost').single.args['custom_reason'], 'Chose a competitor');
      expect(api.callsOf('lost').single.args['reason_id'], isNull);
    });

    testWidgets('Reopen a lost record', (tester) async {
      final api = await open(tester, record: crmTestDetail(outcome: 'lost', version: 7));
      expect(find.textContaining('Lost: Not interested'), findsOneWidget);
      expect(find.text('Mark won'), findsNothing);
      await tester.tap(find.text('Reopen'));
      await _settle(tester);
      expect(api.callsOf('reopen').single.args, {'id': 'rec-1', 'version': 7});
    });

    testWidgets('Archive asks first; an archived record offers Restore', (tester) async {
      final api = await open(tester);
      await tester.tap(find.byTooltip('More actions'));
      await _settle(tester);
      await tester.tap(find.text('Archive…'));
      await _settle(tester);
      expect(find.text('Archive this record?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
      await _settle(tester);
      expect(api.callsOf('archive').single.args['version'], 3);

      final api2 = await open(tester, record: crmTestDetail(archived: true));
      await tester.tap(find.text('Restore'));
      await _settle(tester);
      expect(api2.callsOf('restore'), hasLength(1));
    });

    testWidgets('Delete is visible, requires confirmation, and sends the record version', (tester) async {
      final api = await open(tester, size: const Size(390, 844));
      expect(find.widgetWithText(OutlinedButton, 'Delete'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      expect(find.text('Delete this CRM record?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await _settle(tester);
      expect(api.callsOf('delete'), isEmpty);
      await tester.tap(find.text('Delete'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete record'));
      await _settle(tester);
      expect(api.callsOf('delete').single.args, {'id': 'rec-1', 'version': 3});
    });

    testWidgets('Convert and Mark won send the version', (tester) async {
      final api = await open(tester);
      await tester.tap(find.text('Convert to opportunity'));
      await _settle(tester);
      expect(api.callsOf('convert').single.args['version'], 3);
      await tester.tap(find.text('Mark won'));
      await _settle(tester);
      expect(api.callsOf('won'), hasLength(1));
    });

    testWidgets('scheduling an activity sends the local time as UTC', (tester) async {
      final api = await open(tester, record: {...crmTestDetail(), 'activities': []});
      expect(find.text('No next activity is planned.'), findsOneWidget);
      await tester.tap(find.text('Schedule an activity'));
      await _settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Subject *'), 'Send the quote');
      await tester.tap(find.widgetWithText(FilledButton, 'Schedule'));
      await _settle(tester);
      final call = api.callsOf('schedule').single.args;
      expect(call['subject'], 'Send the quote');
      expect(call['type'], 'call');
      final due = call['due_at'] as String;
      expect(due.endsWith('Z'), isTrue);
      expect(DateTime.parse(due), DateTime(2026, 11, 19, 9).toUtc(), reason: 'tomorrow 09:00 local, sent as UTC');
    });

    testWidgets('deal fields are validated before saving', (tester) async {
      final api = await open(tester);
      await tester.tap(find.bySemanticsLabel('Edit deal value, probability and close date'));
      await _settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Expected value'), '1500');
      await tester.enterText(find.widgetWithText(TextField, 'Probability (%)'), '140');
      await tester.tap(find.text('Save deal'));
      await _settle(tester);
      expect(find.textContaining('3-letter currency'), findsOneWidget);
      expect(find.text('Enter a whole number from 0 to 100'), findsOneWidget);
      expect(api.callsOf('update'), isEmpty);
      await tester.enterText(find.widgetWithText(TextField, 'Currency'), 'cad');
      await tester.enterText(find.widgetWithText(TextField, 'Probability (%)'), '40');
      await tester.tap(find.text('Save deal'));
      await _settle(tester);
      expect(api.callsOf('update').single.args['changes'],
          {'value': 1500, 'currency': 'CAD', 'probability': 40, 'expected_close_date': null});
    });

    testWidgets('a version conflict reloads and explains', (tester) async {
      final api = await open(tester);
      api.failNext = CrmException('Changed elsewhere', statusCode: 409, code: 'version_conflict');
      await tester.tap(find.text('Mark won'));
      await _settle(tester);
      expect(find.textContaining('This record changed somewhere else.'), findsOneWidget);
      expect(api.callsOf('record').length, greaterThanOrEqualTo(2), reason: 'reloaded');
    });

    testWidgets("another user's record shows a friendly not-found", (tester) async {
      _size(tester, const Size(1440, 900));
      final api = FakeCrmApi()..failNext = CrmException('Not found', statusCode: 404);
      await tester.pumpWidget(_host(_crm(api), CrmRecordScreen(recordId: 'other', api: api)));
      await _settle(tester);
      expect(find.text("This record isn't available"), findsOneWidget);
      expect(find.text('Go to the pipeline'), findsOneWidget);
    });

    testWidgets('an unsaved note is guarded when leaving', (tester) async {
      _size(tester, const Size(1440, 1400));
      final api = FakeCrmApi();
      final crm = _crm(api);
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<CrmProvider>.value(value: crm)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(body: CrmRecordScreen(recordId: 'rec-1', api: api)))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Add a note'), 'Call back Friday');
      await tester.pump();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Call back Friday'), findsOneWidget);
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(api.callsOf('note').single.args['body'], 'Call back Friday');
    });
  });

  group('agenda', () {
    testWidgets('buckets with counts; the tz offset is sent', (tester) async {
      _size(tester, const Size(1440, 900));
      final api = FakeCrmApi()
        ..agendaPages = [
          CrmPage(items: [
            {'id': 'a-1', 'type': 'call', 'subject': 'Call Acme', 'due_at': '2026-11-17T10:00:00Z', 'overdue': true, 'record': {'id': 'rec-1', 'title': 'Acme Plumbing'}},
          ]),
        ];
      await tester.pumpWidget(_host(_crm(api), CrmAgendaScreen(api: api, tzOffsetMinutes: 300, initialQuery: const {'bucket': 'overdue'})));
      await _settle(tester);
      expect(api.callsOf('agenda').first.args, {'bucket': 'overdue', 'tz': 300, 'cursor': null});
      expect(api.callsOf('agendaCounts').first.args['tz'], 300);
      expect(find.text('Overdue (2)'), findsOneWidget);
      expect(find.text('Today (1)'), findsOneWidget);
      expect(find.text('Upcoming (4)'), findsOneWidget);
      expect(find.text('Call: Call Acme'), findsOneWidget);
      expect(find.textContaining('Overdue ·'), findsOneWidget);

      api.agendaPages = [CrmPage.empty];
      await tester.tap(find.text('Upcoming (4)'));
      await _settle(tester);
      expect(api.callsOf('agenda').last.args['bucket'], 'upcoming');
      expect(find.textContaining('No upcoming activities'), findsOneWidget);

      for (final b in ['today', 'done']) {
        await tester.tap(find.textContaining(crmAgendaLabel(b)));
        await _settle(tester);
        expect(api.callsOf('agenda').last.args['bucket'], b);
      }
    });
  });

  group('reports', () {
    testWidgets('"No data yet" when the workspace has nothing', (tester) async {
      _size(tester, const Size(1440, 900));
      final api = FakeCrmApi()
        ..reports = {
          'definitions': {},
          'imported_companies': 0,
          'open_leads': 0,
          'opportunities': 0,
          'by_stage': [],
          'by_source': [],
          'won': 0,
          'lost': 0,
          'won_rate': {'value': null, 'numerator': 0, 'denominator': 0},
          'overdue_activities': 0,
          'activities_completed': 0,
          'lost_reasons': [],
          'value_by_currency': [],
          'records_without_value': 0,
        };
      await tester.pumpWidget(_host(_crm(api), CrmReportsScreen(api: api)));
      await _settle(tester);
      expect(find.text('No data yet'), findsOneWidget);
      expect(api.callsOf('reports').single.args['from'], isNotNull);
    });

    testWidgets('metrics show their definitions; currencies stay separate', (tester) async {
      _size(tester, const Size(1440, 1600));
      final api = FakeCrmApi()
        ..reports = {
          'definitions': {'won_rate': 'Won ÷ closed, in the period.'},
          'imported_companies': 12,
          'open_leads': 9,
          'opportunities': 3,
          'won': 1,
          'lost': 1,
          'won_rate': {'value': 0.5, 'numerator': 1, 'denominator': 2},
          'by_stage': [
            {'stage': {'name': 'New'}, 'count': 9},
          ],
          'value_by_currency': [
            {'currency': 'CAD', 'open_total': 1500, 'won_total': 300},
            {'currency': 'USD', 'open_total': 200, 'won_total': null},
          ],
          'records_without_value': 2,
        };
      await tester.pumpWidget(_host(_crm(api), CrmReportsScreen(api: api)));
      await _settle(tester);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('1 won of 2 closed'), findsOneWidget);
      expect(find.text('Won ÷ closed, in the period.'), findsOneWidget);
      expect(find.text('Open CAD 1,500.00 · Won CAD 300.00'), findsOneWidget);
      expect(find.text('Open USD 200.00 · Won —'), findsOneWidget);
      expect(find.text('No data yet'), findsWidgets, reason: 'empty sections say so');
    });
  });

  group('import from results', () {
    List<Map<String, dynamic>> leads() => [
          {'lead_id': 101, 'business_name': 'Acme Plumbing', 'phone': '+1 514 555 0100', 'city': 'Montreal'},
          {'lead_id': 102, 'business_name': 'Beta Heating', 'city': 'Montreal'},
          {'lead_id': 103, 'business_name': 'Gamma Pipes', 'city': 'Laval'},
          {'business_name': 'Unsaved Co', 'city': 'Laval'},
        ];

    Map<String, dynamic> resp({List<int> created = const [], List<int> already = const [], List<Map<String, dynamic>> matches = const [], bool done = true, int remaining = 0}) => {
          'import_id': 'imp-1',
          'job_id': 'job-1',
          'done': done,
          'processed': created.length + already.length,
          'remaining': remaining,
          'created': [for (final id in created) {'result_id': id, 'record_id': 'r$id'}],
          'already_added': [for (final id in already) {'result_id': id, 'record_id': 'r$id'}],
          'possible_matches': matches,
          'rejected': [],
        };

    Future<FakeCrmApi> pump(WidgetTester tester, {List<Object>? responses, Map<String, dynamic>? state}) async {
      _size(tester, const Size(1440, 2000));
      final api = FakeCrmApi()..importResponses = responses ?? [];
      if (state != null) api.jobState = state;
      await tester.pumpWidget(_host(
        _crm(api),
        ResultsScreen(jobId: 'job-1', overrideResults: leads(), embedded: true, crmEnabled: true, crmApi: api),
        shell: false,
      ));
      await _settle(tester);
      return api;
    }

    final addSelectedButton = find.ancestor(of: find.text('Add selected to CRM'), matching: find.byWidgetPredicate((w) => w is FilledButton));

    Future<void> select(WidgetTester tester, String name) async {
      await tester.tap(find.byWidgetPredicate((w) => w is Checkbox && w.semanticLabel == 'Select $name'));
      await _settle(tester, steps: 3);
    }

    testWidgets('state chips per lead; no CRM in the admin (default) use', (tester) async {
      await pump(tester, state: {
        'results': {
          '101': {'state': 'added', 'record_id': 'r101'},
          '102': {'state': 'possible_match', 'candidate_record_ids': ['r9']},
        },
        'counts': {'added': 1, 'possible_match': 1, 'not_added': 1},
      });
      expect(find.text('Already in CRM · View'), findsOneWidget);
      expect(find.text('Possible match · Review'), findsOneWidget);
      expect(find.text('Add to CRM'), findsOneWidget);
      expect(find.text("Can't add yet (not saved)"), findsOneWidget);
      expect(find.text('View this search in CRM'), findsOneWidget);
      expect(find.textContaining('1 in CRM · 1 to review'), findsOneWidget);

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ResultsScreen(jobId: 'job-1', overrideResults: leads(), embedded: true))));
      await _settle(tester);
      expect(find.text('Add to CRM'), findsNothing);
      expect(find.text('View this search in CRM'), findsNothing);
    });

    testWidgets('Add selected sends selectedLeadIds; summary snack; disabled with a reason for unsaved leads', (tester) async {
      final api = await pump(tester, responses: [resp(created: [101], already: [102])]);
      await select(tester, 'Unsaved Co');
      final button = addSelectedButton;
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNull);
      expect(find.textContaining("can't be added to the CRM"), findsOneWidget);

      await select(tester, 'Unsaved Co');
      await select(tester, 'Acme Plumbing');
      await select(tester, 'Beta Heating');
      expect(tester.widget<ButtonStyleButton>(button).onPressed, isNotNull);
      api.jobState = {
        'results': {
          '101': {'state': 'added', 'record_id': 'r101'},
          '102': {'state': 'added', 'record_id': 'r102'},
        },
        'counts': {'added': 2, 'possible_match': 0, 'not_added': 1},
      };
      await tester.tap(button);
      await _settle(tester);
      expect(api.callsOf('import').single.args['result_ids'], [101, 102]);
      expect(find.text('1 added · 1 already in CRM'), findsOneWidget);
      expect(find.text('Already in CRM · View'), findsNWidgets(2));
      expect(find.textContaining('2 in CRM'), findsOneWidget);
      expect(button, findsNothing, reason: 'added leads left the selection, so the bar is gone');
    });

    testWidgets('a retry after a failure reuses the idempotency key', (tester) async {
      final api = await pump(tester, responses: [NetworkException('offline'), resp(created: [101])]);
      await select(tester, 'Acme Plumbing');
      await tester.tap(addSelectedButton);
      await _settle(tester);
      expect(find.textContaining('Trying again is safe'), findsOneWidget);
      await tester.tap(addSelectedButton);
      await _settle(tester);
      final calls = api.callsOf('import');
      expect(calls, hasLength(2));
      expect(calls[0].args['key'], calls[1].args['key']);
      expect(find.text('1 added'), findsOneWidget);
    });

    testWidgets('Add all repeats the resumable import until done', (tester) async {
      final api = await pump(tester, responses: [
        resp(created: [101], done: false, remaining: 2),
        resp(created: [102], done: false, remaining: 1),
        resp(created: [103]),
      ]);
      await tester.tap(find.text('Add all to CRM'));
      await _settle(tester, steps: 20);
      final calls = api.callsOf('import');
      expect(calls, hasLength(3));
      expect(calls.every((c) => c.args['all'] == true), isTrue);
      expect(calls.map((c) => c.args['key']).toSet(), hasLength(1));
      expect(find.text('3 added'), findsOneWidget);
    });

    testWidgets('possible matches open the review dialog and resolve the choices', (tester) async {
      final api = await pump(tester, responses: [
        resp(created: [101], matches: [
          {
            'result_id': 103,
            'business_name': 'Gamma Pipes',
            'candidates': [
              {'record_id': 'rec-9', 'name': 'Gamma Pipes Ltd', 'stage': 'Contacted', 'reasons': ['same_phone']},
            ],
          },
        ]),
      ]);
      api.resolveResponses = [
        {
          'linked': [
            {'result_id': 103, 'record_id': 'rec-9'}
          ],
          'created': [],
          'skipped': [],
          'rejected': [],
        },
      ];
      await select(tester, 'Acme Plumbing');
      await select(tester, 'Gamma Pipes');
      await tester.tap(addSelectedButton);
      await _settle(tester);
      expect(find.text('1 added · 1 needs review'), findsOneWidget);
      expect(find.text('Possible match: review'), findsOneWidget);
      await tester.tap(find.text('Link to "Gamma Pipes Ltd"'));
      await _settle(tester, steps: 3);
      await tester.tap(find.text('Apply choices'));
      await _settle(tester);
      final resolve = api.callsOf('resolve').single.args;
      expect(resolve['job_id'], 'job-1');
      expect(resolve['decisions'], [
        {'result_id': 103, 'action': 'link', 'record_id': 'rec-9'}
      ]);
      expect(find.text('1 linked'), findsOneWidget);
    });
  });

  group('routes', () {
    Widget app(FakeCrmApi api, String initial) {
      final base = _FakeApi();
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: _FakeAuth()),
          ChangeNotifierProvider(create: (_) => ScraperProvider(api: base)),
          ChangeNotifierProvider<CreditProvider>.value(value: CreditProvider.instance),
          ChangeNotifierProvider(create: (_) => ActiveSearchesProvider(api: base)),
          ChangeNotifierProvider<CrmProvider>.value(value: _crm(api)),
        ],
        child: MaterialApp(initialRoute: initial, onGenerateRoute: AppRouter.onGenerateRoute),
      );
    }

    testWidgets('a direct record URL opens the record', (tester) async {
      _size(tester, const Size(1440, 900));
      final api = FakeCrmApi();
      await tester.pumpWidget(app(api, '/crm/records/rec-1'));
      await _settle(tester);
      expect(find.byType(CrmRecordScreen), findsOneWidget);
      expect(api.callsOf('record').first.args['id'], 'rec-1');
    });

    testWidgets('list filters come from the URL', (tester) async {
      _size(tester, const Size(1440, 900));
      final api = FakeCrmApi();
      await tester.pumpWidget(app(api, '/crm/leads?source=job-7&outcome=all&archived=all'));
      await _settle(tester);
      final q = api.callsOf('records').first.args;
      expect([q['source_job_id'], q['outcome'], q['archived']], ['job-7', 'all', 'all']);
    });
  });

  group('layout (no overflow)', () {
    for (final size in const [Size(360, 740), Size(390, 844), Size(430, 932), Size(820, 1180), Size(1024, 768), Size(1440, 900)]) {
      testWidgets('pipeline, list and detail at ${size.width.toInt()} px', (tester) async {
        _size(tester, size);
        final api = FakeCrmApi()
          ..pipeline = _pipeline()
          ..recordPages = [CrmPage(items: [crmTestRecord(), crmTestRecord(id: 'rec-2', title: 'A very long business name that keeps going and going')], total: 2)];
        final crm = _crm(api, counts: {'overdue': 3, 'today': 2});
        for (final screen in <Widget>[
          CrmPipelineScreen(api: api),
          CrmLeadsScreen(api: api),
          CrmRecordScreen(recordId: 'rec-1', api: api),
          CrmAgendaScreen(api: api),
          CrmReportsScreen(api: api),
        ]) {
          await tester.pumpWidget(_host(crm, screen));
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: '${screen.runtimeType} at $size');
        }
      });
    }
  });
}

String crmAgendaLabel(String b) => b == 'today' ? 'Today' : 'Done';

class _ThrowingRecordsApi extends FakeCrmApi {
  @override
  Future<CrmPage> listRecords(Map<String, String> query) async => throw NetworkException('offline');
}
