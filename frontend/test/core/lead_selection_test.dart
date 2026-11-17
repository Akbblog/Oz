import 'package:business_scraper_app/core/lead_selection.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> lead(String name, {Object? leadId, String? leadKey, String? maps, String? phone}) => {
      'business_name': name,
      if (leadId != null) 'lead_id': leadId,
      if (leadKey != null) 'lead_key': leadKey,
      if (maps != null) 'google_maps_url': maps,
      if (phone != null) 'phone': phone,
    };

void main() {
  group('ids', () {
    test('lead_id first, then lead_key, then a content fallback', () {
      expect(leadSelectionId(lead('A', leadId: 42, leadKey: 'k'), jobId: 'j1'), 'lead:42');
      expect(leadSelectionId(lead('A', leadId: '42'), jobId: 'j1'), 'lead:42');
      expect(leadSelectionId({'id': 7, 'business_name': 'Admin row'}), 'lead:7', reason: 'admin reads return id');
      expect(leadSelectionId(lead('A', leadKey: 'place:abc'), jobId: 'j1'), 'key:j1:place:abc');
      expect(leadSelectionId(lead('A', maps: 'https://maps.google.com/?cid=1'), jobId: 'j1'),
          'row:j1:https://maps.google.com/?cid=1');
      expect(leadSelectionId(lead(' Joe ', phone: '555'), jobId: 'j1'), 'row:j1:joe|555|');
      expect(leadSelectionId({...lead('A', leadKey: 'k'), 'job_id': 'j9'}, jobId: 'j1'), 'key:j9:k');
    });

    test('invalid lead ids are ignored', () {
      expect(leadIdOf(lead('A', leadId: 0)), isNull);
      expect(leadIdOf(lead('A', leadId: -3)), isNull);
      expect(leadIdOf(lead('A', leadId: 'abc')), isNull);
      expect(leadIdOf(lead('A', leadId: 3.0)), 3);
      expect(leadKeyOf(lead('A', leadKey: '  ')), isNull);
    });

    test('kinds', () {
      expect(leadIdKind('lead:1'), LeadIdKind.leadId);
      expect(leadIdKind('key:j:k'), LeadIdKind.leadKey);
      expect(leadIdKind('row:j:x'), LeadIdKind.fallback);
    });

    test('duplicate ids in one list are made unique in order', () {
      final ids = leadSelectionIds([lead('Same', phone: '1'), lead('Same', phone: '1'), lead('Other')], jobId: 'j');
      expect(ids, ['row:j:same|1|', 'row:j:same|1|#2', 'row:j:other||']);
    });
  });

  group('LeadSelection', () {
    late List<Map<String, dynamic>> all;
    late LeadSelection s;
    var notified = 0;

    setUp(() {
      all = [for (var i = 1; i <= 5; i++) lead('Biz $i', leadId: i)];
      s = LeadSelection(scope: 'job-1')..attach(all);
      notified = 0;
      s.addListener(() => notified++);
    });

    test('toggle, isSelected, count, clear', () {
      s.toggle(all[1]);
      expect(s.isSelected(all[1]), isTrue);
      expect(s.count, 1);
      s.toggle(all[1], true);
      expect(notified, 1, reason: 'no change, no notification');
      s.toggle(all[1]);
      expect(s.isSelected(all[1]), isFalse);
      s.toggle(all[3], true);
      s.clear();
      expect(s.isEmpty, isTrue);
    });

    test('selectAll / deselectAll act on the given (visible) leads only', () {
      s.toggle(all[0], true);
      final visible = [all[2], all[3]];
      s.selectAll(visible);
      expect(s.selectedIds, {'lead:1', 'lead:3', 'lead:4'});
      s.deselectAll(visible);
      expect(s.selectedIds, {'lead:1'}, reason: 'hidden selection is kept');
      expect(s.countIn(visible), 0);
      expect(s.stateOf(visible), isFalse);
      s.toggle(all[2], true);
      expect(s.stateOf(visible), isNull);
      s.toggle(all[3], true);
      expect(s.stateOf(visible), isTrue);
      expect(s.stateOf(const []), isFalse);
    });

    test('survives sorting/filtering and reload with new map objects; drops leads that are gone', () {
      s.selectAll([all[0], all[4]]);
      // A reload returns equal data as new maps, in another order, without Biz 5.
      final reloaded = [for (var i = 4; i >= 1; i--) lead('Biz $i', leadId: i)];
      s.attach(reloaded);
      expect(s.isSelected(reloaded.last), isTrue, reason: 'Biz 1 by lead_id');
      expect(s.count, 1, reason: 'Biz 5 no longer exists');
    });

    test('selectedLeads keeps list order; selectedLeadIds are numeric and unique', () {
      s.toggle(all[3], true);
      s.toggle(all[0], true);
      expect(s.selectedLeads(all).map((l) => l['business_name']), ['Biz 1', 'Biz 4']);
      expect(s.selectedLeadIds(all), [1, 4]);
      expect(s.selectedWithoutLeadId(all), 0);
    });

    test('fallback leads are selectable but have no lead_id', () {
      final old = [lead('Old A', maps: 'https://maps.google.com/?cid=9'), lead('Old B')];
      s.attach(old);
      s.selectAll(old);
      expect(s.count, 2);
      expect(s.selectedLeadIds(old), isEmpty);
      expect(s.selectedWithoutLeadId(old), 2);
    });

    test('changing the search clears the selection', () {
      s.toggle(all[0], true);
      s.setScope('job-1');
      expect(s.count, 1);
      s.setScope('job-2');
      expect(s.count, 0);
      expect(s.scope, 'job-2');
    });
  });

  test('summary separates selected and shown', () {
    expect(leadSelectionSummary(selected: 3, shown: 12, total: 40), '3 selected · 12 shown of 40');
    expect(leadSelectionSummary(selected: 3, shown: 40, total: 40), '3 selected of 40');
    expect(leadSelectionSummary(selected: 3, shown: 12, total: 40, hiddenSelected: 1), '3 selected · 12 shown of 40 · 1 not shown');
  });
}
