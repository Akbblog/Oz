import 'package:business_scraper_app/services/crm_api.dart';

/// One recorded call of [FakeCrmApi].
class CrmCall {
  final String method;
  final Map<String, dynamic> args;
  CrmCall(this.method, this.args);
  @override
  String toString() => '$method $args';
}

List<Map<String, dynamic>> crmTestStages() => [
      {'id': 's-new', 'key': 'new', 'name': 'New', 'position': 0, 'outcome_kind': 'open'},
      {'id': 's-con', 'key': 'contacted', 'name': 'Contacted', 'position': 1, 'outcome_kind': 'open'},
      {'id': 's-qual', 'key': 'qualified', 'name': 'Qualified', 'position': 2, 'outcome_kind': 'open'},
      {'id': 's-prop', 'key': 'proposal', 'name': 'Proposal', 'position': 3, 'outcome_kind': 'open'},
      {'id': 's-won', 'key': 'won', 'name': 'Won', 'position': 4, 'outcome_kind': 'won'},
    ];

Map<String, dynamic> crmTestWorkspace() => {
      'id': 'ws-1',
      'name': 'My CRM',
      'role': 'owner',
      'pipeline': {'id': 'p-1', 'name': 'Sales', 'stages': crmTestStages()},
      'lost_reasons': [
        {'id': 'r1', 'name': 'Not interested'},
        {'id': 'r2', 'name': 'No response'},
        {'id': 'r5', 'name': 'Other'},
      ],
      'tags': [
        {'id': 't1', 'name': 'Hot', 'color': null},
      ],
      'currency_default': null,
    };

Map<String, dynamic> crmTestRecord({
  String id = 'rec-1',
  String title = 'Acme Plumbing',
  String stageId = 's-new',
  String stageName = 'New',
  String outcome = 'open',
  String type = 'lead',
  int version = 3,
  Object? value,
  String? currency,
  Map<String, dynamic>? next,
}) =>
    {
      'id': id,
      'title': title,
      'type': type,
      'outcome': outcome,
      'stage': {'id': stageId, 'key': stageName.toLowerCase(), 'name': stageName},
      'company': {
        'id': 'co-$id',
        'name': title,
        'city': 'Montreal',
        'region': 'Quebec',
        'country': 'Canada',
        'phone': '+1 514 555 0100',
        'email': null,
        'website': 'https://acme.example',
      },
      'tags': <Map<String, dynamic>>[],
      'next_activity': next,
      'source_count': 1,
      'value': value,
      'currency': currency,
      'archived': false,
      'updated_at': '2026-11-17T10:00:00Z',
      'created_at': '2026-11-16T10:00:00Z',
      'version': version,
    };

Map<String, dynamic> crmTestDetail({String outcome = 'open', bool archived = false, int version = 3}) => {
      ...crmTestRecord(outcome: outcome, version: version),
      'archived': archived,
      'archived_at': archived ? '2026-11-17T10:00:00Z' : null,
      'company': {
        'id': 'co-rec-1',
        'name': 'Acme Plumbing',
        'city': 'Montreal',
        'region': 'Quebec',
        'country': 'Canada',
        'phone': '+1 514 555 0100',
        'email': 'hello@acme.example',
        'website': 'https://acme.example',
        'address': '1 Rue X',
        'maps_url': 'https://maps.google.com/?cid=1',
        'source_snapshot': {
          'business_name': 'Acme Plumbing Inc',
          'phone': '+1 514 555 0100',
          'website': 'https://acme.example',
          'category': 'plumbers',
          'city': 'Montreal',
        },
      },
      'people': [
        {'id': 'pe-1', 'name': 'Rita Lopez', 'role': 'Owner', 'phone': null, 'email': 'rita@acme.example', 'is_primary': true},
      ],
      'sources': [
        {'job_id': 'job-1', 'category': 'plumbers', 'city': 'Montreal', 'region': 'Quebec', 'country': 'Canada', 'imported_at': '2026-11-16T10:00:00Z', 'available': true},
        {'job_id': 'job-0', 'category': 'plumbers', 'city': 'Laval', 'region': 'Quebec', 'country': 'Canada', 'imported_at': '2026-11-10T10:00:00Z', 'available': false},
      ],
      'activities': [
        {'id': 'a-1', 'type': 'call', 'subject': 'Intro call', 'due_at': '2030-01-02T15:00:00Z', 'status': 'open', 'overdue': false},
      ],
      'notes': [
        {'id': 'n-1', 'body': 'Asked for a quote.', 'created_at': '2026-11-16T12:00:00Z', 'author': {'name': 'rita'}},
      ],
      'events': [
        {'id': 'e-2', 'type': 'stage_changed', 'before': {'stage': 'New'}, 'after': {'stage': 'Contacted'}, 'occurred_at': '2026-11-17T09:00:00Z'},
        {'id': 'e-1', 'type': 'imported', 'after': {'category': 'plumbers'}, 'occurred_at': '2026-11-16T10:00:00Z'},
      ],
      'lost_reason': outcome == 'lost' ? {'id': 'r1', 'name': 'Not interested'} : null,
      'lost_note': null,
      'probability': null,
      'expected_close_date': null,
      'closed_at': outcome == 'open' ? null : '2026-11-17T11:00:00Z',
    };

/// CRM API double: canned answers, recorded calls, injectable failures.
class FakeCrmApi extends CrmApi {
  final List<CrmCall> calls = [];
  bool enabled = true;
  Map<String, dynamic> workspace = crmTestWorkspace();
  Map<String, dynamic> pipeline = {'stages': [], 'summary': {}};
  Map<String, dynamic> record = crmTestDetail();
  Map<String, dynamic> jobState = {'job_id': 'job-1', 'results': {}, 'counts': {'not_added': 0, 'added': 0, 'possible_match': 0}};
  Map<String, dynamic> reports = {};
  Map<String, int> agendaCounts = {'overdue': 2, 'today': 1, 'upcoming': 4, 'no_next_activity': 0};

  /// Pages returned by listRecords / getAgenda / listPeople in order (last repeats).
  List<CrmPage> recordPages = [CrmPage.empty];
  List<CrmPage> agendaPages = [CrmPage.empty];
  List<CrmPage> peoplePages = [CrmPage.empty];

  /// Responses of importResults in order (last repeats); an Exception entry is thrown.
  List<Object> importResponses = [];
  List<Object> resolveResponses = [];

  /// Thrown by the next transition / move (then cleared).
  Object? failNext;

  Map<String, dynamic> _transition(String method, Map<String, dynamic> args) {
    calls.add(CrmCall(method, args));
    final f = failNext;
    if (f != null) {
      failNext = null;
      throw f;
    }
    return {...record, 'version': (args['version'] as int? ?? 0) + 1};
  }

  T _next<T>(List<Object> list) {
    if (list.isEmpty) throw StateError('no canned response');
    final v = list.length > 1 ? list.removeAt(0) : list.first;
    if (v is Exception) throw v;
    if (v is Error) throw v;
    return v as T;
  }

  CrmPage _page(List<CrmPage> pages) => pages.length > 1 ? pages.removeAt(0) : pages.first;

  List<CrmCall> callsOf(String method) => calls.where((c) => c.method == method).toList();

  @override
  Future<bool> getStatus() async {
    calls.add(CrmCall('status', {}));
    return enabled;
  }

  @override
  Future<Map<String, dynamic>> getWorkspace() async => workspace;

  @override
  Future<Map<String, dynamic>> getJobState(String jobId) async {
    calls.add(CrmCall('jobState', {'job_id': jobId}));
    return jobState;
  }

  @override
  Future<Map<String, dynamic>> importResults({required String jobId, List<int>? resultIds, bool all = false, required String idempotencyKey}) async {
    calls.add(CrmCall('import', {'job_id': jobId, 'result_ids': resultIds, 'all': all, 'key': idempotencyKey}));
    return _next<Map<String, dynamic>>(importResponses);
  }

  @override
  Future<Map<String, dynamic>> resolveImport({required String jobId, required String idempotencyKey, required List<Map<String, dynamic>> decisions}) async {
    calls.add(CrmCall('resolve', {'job_id': jobId, 'key': idempotencyKey, 'decisions': decisions}));
    return _next<Map<String, dynamic>>(resolveResponses);
  }

  @override
  Future<CrmPage> listRecords(Map<String, String> query) async {
    calls.add(CrmCall('records', Map<String, dynamic>.from(query)));
    return _page(recordPages);
  }

  @override
  Future<Map<String, dynamic>> getPipeline({String? q, String? tagId, String? sourceJobId, int perStage = 20}) async {
    calls.add(CrmCall('pipeline', {'q': q, 'tag_id': tagId, 'source_job_id': sourceJobId}));
    return pipeline;
  }

  @override
  Future<Map<String, dynamic>> getRecord(String id) async {
    calls.add(CrmCall('record', {'id': id}));
    final f = failNext;
    if (f != null && f is CrmException && f.statusCode == 404) {
      failNext = null;
      throw f;
    }
    return record;
  }

  @override
  Future<Map<String, dynamic>> createRecord(Map<String, dynamic> body) async {
    calls.add(CrmCall('create', body));
    return crmTestRecord(id: 'rec-new', title: '${body['title']}');
  }

  @override
  Future<Map<String, dynamic>> updateRecord(String id, Map<String, dynamic> changes, {int? version}) async =>
      _transition('update', {'id': id, 'changes': changes, 'version': version});

  @override
  Future<Map<String, dynamic>> moveStage(String id, String stageId, {int? version}) async =>
      _transition('stage', {'id': id, 'stage_id': stageId, 'version': version});

  @override
  Future<Map<String, dynamic>> convertToOpportunity(String id, {int? version}) async =>
      _transition('convert', {'id': id, 'version': version});

  @override
  Future<Map<String, dynamic>> markWon(String id, {int? version}) async => _transition('won', {'id': id, 'version': version});

  @override
  Future<Map<String, dynamic>> markLost(String id, {String? reasonId, String? customReason, String? note, int? version}) async =>
      _transition('lost', {'id': id, 'reason_id': reasonId, 'custom_reason': customReason, 'note': note, 'version': version});

  @override
  Future<Map<String, dynamic>> reopen(String id, {int? version}) async => _transition('reopen', {'id': id, 'version': version});

  @override
  Future<Map<String, dynamic>> archive(String id, {int? version}) async => _transition('archive', {'id': id, 'version': version});

  @override
  Future<Map<String, dynamic>> restore(String id, {int? version}) async => _transition('restore', {'id': id, 'version': version});

  @override
  Future<Map<String, dynamic>> deleteRecord(String id, {int? version}) async {
    calls.add(CrmCall('delete', {'id': id, 'version': version}));
    return {'deleted': true, 'id': id};
  }

  @override
  Future<Map<String, dynamic>> scheduleActivity(String recordId,
          {required String type, required String subject, required String dueAtUtc, String? notes}) async =>
      _transition('schedule', {'id': recordId, 'type': type, 'subject': subject, 'due_at': dueAtUtc, 'notes': notes});

  @override
  Future<Map<String, dynamic>> updateActivity(String activityId, Map<String, dynamic> changes) async =>
      _transition('reschedule', {'id': activityId, ...changes});

  @override
  Future<Map<String, dynamic>> completeActivity(String activityId, {String? outcome}) async =>
      _transition('done', {'id': activityId, 'outcome': outcome});

  @override
  Future<Map<String, dynamic>> reopenActivity(String activityId) async => _transition('reopenActivity', {'id': activityId});

  @override
  Future<Map<String, dynamic>> addNote(String recordId, String body) async => _transition('note', {'id': recordId, 'body': body});

  @override
  Future<CrmPage> getAgenda({required String bucket, int? tzOffsetMinutes, int limit = 50, String? cursor}) async {
    calls.add(CrmCall('agenda', {'bucket': bucket, 'tz': tzOffsetMinutes, 'cursor': cursor}));
    return _page(agendaPages);
  }

  @override
  Future<Map<String, int>> getAgendaCounts({int? tzOffsetMinutes}) async {
    calls.add(CrmCall('agendaCounts', {'tz': tzOffsetMinutes}));
    return agendaCounts;
  }

  @override
  Future<CrmPage> listPeople({String? q, int limit = 50, String? cursor}) async {
    calls.add(CrmCall('people', {'q': q, 'cursor': cursor}));
    return _page(peoplePages);
  }

  @override
  Future<Map<String, dynamic>> getReports({DateTime? from, DateTime? to, int? tzOffsetMinutes}) async {
    calls.add(CrmCall('reports', {'from': from, 'to': to}));
    return reports;
  }
}
