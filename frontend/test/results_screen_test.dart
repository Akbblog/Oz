import 'package:business_scraper_app/screens/results_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _tracking = 'https://www.example-dental.com/?utm_source=gmb&utm_medium=organic&gclid=abc123';
const _mixedAddress = 'مبنى 12، شارع الكورنيش، الدفنة، الدوحة، قطر — Building 12, Corniche Street, Al Dafna, Doha, '
    'Qatar, next to the Sheraton Grand Doha Resort & Convention Hotel, Gate 3, Tower B, Floor 14, Office 1402';

Map<String, dynamic> _lead(int i, {Map<String, dynamic> extra = const {}}) => {
      'lead_id': 100 + i,
      'lead_key': 'place:$i',
      'business_name': 'Biz $i',
      'category': 'Dentist',
      'city': 'Doha',
      'state': 'Qatar',
      'phone': '+974 4400 00$i',
      'address': '$i Corniche St',
      'google_maps_url': 'https://maps.google.com/?cid=$i',
      ...extra,
    };

List<Map<String, dynamic>> _hardLeads() => [
      _lead(0, extra: {
        'business_name': 'Al Corniche Advanced Dental & Orthodontic Specialist Center — مركز الكورنيش المتقدم لطب الأسنان',
        'email': 'appointments.and.general.enquiries.department@alcornicheadvanceddentalcenter-doha.com.qa',
        'website': _tracking,
        'address': _mixedAddress,
      }),
      _lead(1, extra: {
        'business_name': 'مطعم الدوحة',
        'category': 'مطعم',
        'website': 'https://www.google.com/url?q=https://${'verylongsubdomain' * 6}.example.com/${'p' * 400}',
      }),
      {'lead_id': 102, 'business_name': 'No Contact Co', 'city': 'Doha'},
      _lead(3),
    ];

Future<void> _pump(WidgetTester tester, Widget child, {double width = 360, double height = 800}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

Finder _checkbox(String label) => find.byWidgetPredicate((w) => w is Checkbox && w.semanticLabel == label);

class _Recorder {
  final calls = <String>[];
  late final actions = LeadActions(
    call: (p) => calls.add('call:$p'),
    email: (e) => calls.add('email:$e'),
    website: (w) => calls.add('website:$w'),
    maps: (l) => calls.add('maps:${l['business_name']}'),
    copy: (t, what) => calls.add('copy:$what:$t'),
  );
}

void main() {
  group('result cards', () {
    for (final width in [360.0, 390.0, 430.0, 820.0, 1440.0]) {
      testWidgets('long, mixed-language and unbroken text does not overflow at ${width.toInt()} px', (tester) async {
        await _pump(tester, ResultsScreen(jobId: 'job-1', overrideResults: _hardLeads(), title: 'Leads'), width: width);
        expect(tester.takeException(), isNull);
        // Scroll through every card so each one is laid out.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('website shows the clean name, opens and copies the original URL', (tester) async {
      final r = _Recorder();
      await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: LeadCard(lead: _hardLeads().first, selected: false, onSelected: (_) {}, actions: r.actions),
          ),
        ),
      );
      expect(find.text('example-dental.com'), findsOneWidget);
      expect(find.textContaining('utm_source'), findsNothing);
      expect(find.bySemanticsLabel('Open website example-dental.com'), findsWidgets);

      await tester.tap(find.text('example-dental.com'));
      await tester.tap(find.text('Website'));
      expect(r.calls, ['website:$_tracking', 'website:$_tracking']);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy website'));
      await tester.pumpAndSettle();
      expect(r.calls.last, 'copy:website:$_tracking');
    });

    testWidgets('contact actions have visible labels, 48 dp targets and screen-reader names', (tester) async {
      final r = _Recorder();
      final lead = _lead(5, extra: {'email': 'hi@biz5.qa', 'website': 'biz5.qa'});
      await _pump(
        tester,
        Scaffold(body: LeadCard(lead: lead, selected: false, onSelected: (_) {}, actions: r.actions)),
      );
      for (final label in ['Call', 'Email', 'Website', 'Map', 'Copy']) {
        expect(find.text(label), findsOneWidget, reason: label);
        final button = find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is TextButton)).first;
        final size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(48), reason: label);
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
      }
      expect(find.bySemanticsLabel('Call Biz 5, +974 4400 005'), findsOneWidget);
      expect(find.bySemanticsLabel('Email Biz 5, hi@biz5.qa'), findsOneWidget);
      expect(find.bySemanticsLabel('Open Biz 5 in Google Maps'), findsOneWidget);
      expect(find.bySemanticsLabel('Copy details of Biz 5'), findsOneWidget);

      await tester.tap(find.text('Call'));
      await tester.tap(find.text('Email'));
      await tester.tap(find.text('Map'));
      expect(r.calls, ['call:+974 4400 005', 'email:hi@biz5.qa', 'maps:Biz 5']);
    });

    testWidgets('absent contacts are not shown as dead buttons', (tester) async {
      final r = _Recorder();
      await _pump(
        tester,
        Scaffold(
          body: LeadCard(
            lead: const {'business_name': 'No Contact Co', 'website': 'N/A', 'phone': ''},
            selected: false,
            onSelected: (_) {},
            actions: r.actions,
          ),
        ),
      );
      expect(find.text('Call'), findsNothing);
      expect(find.text('Email'), findsNothing);
      expect(find.text('Website'), findsNothing);
      expect(find.text('Map'), findsNothing);
      expect(find.text('No phone, email or website listed'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget, reason: 'the name can still be copied');
    });

    testWidgets('long address: 3 lines, RTL paragraph, expandable', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: LeadCard(lead: _hardLeads().first, selected: false, onSelected: (_) {}, actions: _Recorder().actions),
          ),
        ),
      );
      final address = tester.widget<Text>(find.text(_mixedAddress));
      expect(address.maxLines, 3);
      expect(address.textDirection, TextDirection.rtl);
      expect(leadTextDirection('Building 12 — مبنى'), TextDirection.ltr);
      expect(leadTextDirection('123 —'), TextDirection.ltr);

      await tester.tap(find.text('Show full address'));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text(_mixedAddress)).maxLines, isNull);
      expect(find.text('Show less'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('short address has no expand toggle', (tester) async {
      await _pump(
        tester,
        Scaffold(body: LeadCard(lead: _lead(1), selected: false, onSelected: (_) {}, actions: _Recorder().actions)),
      );
      expect(find.text('Show full address'), findsNothing);
    });
  });

  group('selection', () {
    List<Map<String, dynamic>> leads() => [for (var i = 0; i < 5; i++) _lead(i)];

    testWidgets('survives filtering, shows selected vs shown, and selects all shown', (tester) async {
      await _pump(tester, ResultsScreen(jobId: 'job-1', overrideResults: leads(), title: 'Leads'), width: 390, height: 900);
      await tester.tap(_checkbox('Select Biz 1'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected of 5'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Biz 3');
      await tester.pumpAndSettle();
      expect(find.text('1 selected · 1 shown of 5 · 1 not shown'), findsOneWidget);

      await tester.tap(find.text('Select all shown'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected · 1 shown of 5 · 1 not shown'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected of 5'), findsOneWidget);
      expect(tester.widget<Checkbox>(_checkbox('Select Biz 1')).value, isTrue);
      await tester.scrollUntilVisible(_checkbox('Select Biz 3'), 200, scrollable: find.byType(Scrollable).first);
      expect(tester.widget<Checkbox>(_checkbox('Select Biz 3')).value, isTrue);

      await tester.tap(find.text('Clear selection'));
      await tester.pumpAndSettle();
      expect(find.textContaining('selected'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Select N shown leads" checkbox selects only the shown leads', (tester) async {
      await _pump(tester, ResultsScreen(jobId: 'job-1', overrideResults: leads(), title: 'Leads'), width: 1024);
      await tester.enterText(find.byType(TextField), 'Biz 2');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select 1 shown lead'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected · 1 shown of 5'), findsOneWidget);
      expect(find.text('Deselect 1 shown lead'), findsOneWidget);
    });

    testWidgets('survives switching cards <-> table; table rows have labelled checkboxes', (tester) async {
      await _pump(tester, ResultsScreen(jobId: 'job-1', overrideResults: leads(), title: 'Leads'), width: 1440, height: 1000);
      await tester.tap(_checkbox('Select Biz 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Table'));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(_checkbox('Select Biz 2')).value, isTrue);
      expect(tester.widget<Checkbox>(_checkbox('Select Biz 0')).value, isFalse);
      expect(_checkbox('Select 5 shown leads'), findsOneWidget, reason: 'header checkbox');

      await tester.tap(_checkbox('Select Biz 4'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cards'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected of 5'), findsOneWidget);
      expect(tester.widget<Checkbox>(_checkbox('Select Biz 4')).value, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('table shows the clean website and keeps long text in bounds', (tester) async {
      await _pump(tester, ResultsScreen(jobId: 'job-1', overrideResults: _hardLeads(), title: 'Leads'), width: 1440, height: 1000);
      await tester.tap(find.text('Table'));
      await tester.pumpAndSettle();
      expect(find.text('example-dental.com'), findsOneWidget);
      expect(find.textContaining('utm_source'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('kept when the same search reloads (new maps, same lead ids); cleared for another search', (tester) async {
      final key = GlobalKey();
      Widget screen(String job, List<Map<String, dynamic>> data) =>
          ResultsScreen(key: key, jobId: job, overrideResults: data, title: 'Leads');
      await _pump(tester, screen('job-1', leads()), width: 390, height: 900);
      await tester.tap(_checkbox('Select Biz 1'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(MaterialApp(home: screen('job-1', leads())));
      await tester.pumpAndSettle();
      expect(find.text('1 selected of 5'), findsOneWidget);

      await tester.pumpWidget(MaterialApp(home: screen('job-2', leads())));
      await tester.pumpAndSettle();
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('bulk Copy copies the selected leads with their original website', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _pump(tester, ResultsScreen(jobId: 'job-1', overrideResults: _hardLeads(), title: 'Leads'), width: 1024, height: 1000);
      await tester.tap(find.text('Select 4 shown leads'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(OutlinedButton), matching: find.text('Copy')));
      await tester.pumpAndSettle();
      expect(copied, hasLength(1));
      expect(copied.single, contains('Website: $_tracking'));
      expect(copied.single, contains('No Contact Co'));
      expect(find.text('Copied 4 leads'), findsOneWidget);
    });
  });

  test('clipboard text keeps the raw values', () {
    final text = leadsToClipboardText([_hardLeads().first]);
    expect(text, contains(_tracking));
    expect(text, contains(_mixedAddress));
  });

  test('"Has website" ignores values that cannot be opened', () {
    expect(leadHasContact({'website': 'N/A'}, LeadContact.website), isFalse);
    expect(leadHasContact({'website': 'Call us'}, LeadContact.website), isFalse);
    expect(leadHasContact({'website': 'example.com'}, LeadContact.website), isTrue);
  });
}
