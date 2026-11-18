import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/error_handler.dart';
import 'api_service.dart';

/// Error of a CRM call: the server's own `detail` sentence as [message],
/// plus the machine `code` (`crm_disabled`, `validation_error`, `not_found`,
/// `version_conflict`, `invalid_transition`, `rate_limited`,
/// `result_not_persisted`) and the decoded body (a version conflict carries
/// the current record in `current`).
class CrmException extends ApiException {
  final String? code;
  final Map<String, dynamic>? body;

  CrmException(super.message, {required int statusCode, this.code, this.body})
      : super(statusCode: statusCode, details: body);

  bool get isDisabled => code == 'crm_disabled';
  bool get isNotFound => statusCode == 404 && !isDisabled;
  bool get isVersionConflict => code == 'version_conflict';
  bool get isInvalidTransition => code == 'invalid_transition';

  /// The current record sent with a version conflict, if any.
  Map<String, dynamic>? get current {
    final c = body?['current'];
    return c is Map ? Map<String, dynamic>.from(c) : null;
  }
}

/// What went wrong, for choosing the right message on a CRM screen.
enum CrmErrorKind { offline, signedOut, disabled, notFound, conflict, rateLimited, other }

CrmErrorKind crmErrorKind(Object? error) {
  if (error is CrmException) {
    if (error.isDisabled) return CrmErrorKind.disabled;
    if (error.statusCode == 404) return CrmErrorKind.notFound;
    if (error.statusCode == 401) return CrmErrorKind.signedOut;
    if (error.isVersionConflict) return CrmErrorKind.conflict;
    if (error.statusCode == 429) return CrmErrorKind.rateLimited;
  }
  if (ErrorHandler.isAuthError(error)) return CrmErrorKind.signedOut;
  if (error is NotFoundException) return CrmErrorKind.notFound;
  if (ErrorHandler.isNetworkError(error)) return CrmErrorKind.offline;
  return CrmErrorKind.other;
}

/// The server's sentence for [error] (never raw JSON).
String crmErrorText(Object? error) {
  if (error is ApiException && error.message.trim().isNotEmpty) return error.message.trim();
  return ErrorHandler.getUserFriendlyMessage(error);
}

/// One keyset page: `items`, `next_cursor` and `total`.
class CrmPage {
  final List<Map<String, dynamic>> items;
  final String? nextCursor;
  final int total;

  const CrmPage({required this.items, this.nextCursor, this.total = 0});

  static const empty = CrmPage(items: <Map<String, dynamic>>[]);

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

  factory CrmPage.fromJson(Object? data) {
    if (data is! Map) return empty;
    final raw = data['items'];
    final items = raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    final next = data['next_cursor'];
    final total = data['total'];
    return CrmPage(
      items: items,
      nextCursor: next == null || '$next'.isEmpty ? null : '$next',
      total: total is num ? total.toInt() : items.length,
    );
  }
}

/// A random UUID v4 (idempotency keys).
String newIdempotencyKey([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final h = [for (var i = 0; i < 16; i++) hex(i)].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// Local UTC offset in minutes (east of UTC positive, e.g. -300 for New
/// York in winter, 300 for Pakistan), sent as `tz_offset_minutes`.
int localTzOffsetMinutes([DateTime? at]) => (at ?? DateTime.now()).timeZoneOffset.inMinutes;

/// `YYYY-MM-DD` of a local date.
String crmDateParam(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Client for `/api/crm/*` (docs/CRM_PHASE1_CONTRACT.md §2). Every method
/// throws [CrmException] with the server's `detail` on an error answer and
/// [NetworkException] when the server cannot be reached.
class CrmApi {
  CrmApi({ApiService? auth, http.Client? client, this.timeout = const Duration(seconds: 30)})
      : _auth = auth ?? ApiService(),
        _client = client;

  final ApiService _auth;
  final http.Client? _client;
  final Duration timeout;

  static String _seg(String id) => Uri.encodeComponent(id);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration? requestTimeout,
  }) async {
    try {
      final token = await _auth.getToken();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      var uri = Uri.parse('${ApiService.baseUrl}$path');
      final q = <String, String>{};
      query?.forEach((k, v) {
        if (v.isNotEmpty) q[k] = v;
      });
      if (q.isNotEmpty) uri = uri.replace(queryParameters: q);
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final client = _client ?? http.Client();
      http.Response response;
      try {
        final streamed = await client.send(request).timeout(requestTimeout ?? timeout);
        response = await http.Response.fromStream(streamed).timeout(requestTimeout ?? timeout);
      } finally {
        if (_client == null) client.close();
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.trim().isEmpty) return const <String, dynamic>{};
        return jsonDecode(utf8.decode(response.bodyBytes));
      }
      throw _error(response);
    } on TimeoutException {
      throw NetworkException("The server didn't answer in time. Check your connection and try again.");
    } catch (e) {
      if (e is ApiException) rethrow;
      if (e is FormatException) {
        throw CrmException('The server sent an answer we could not read. Please try again.', statusCode: 0);
      }
      throw ErrorHandler.handleNetworkError(e);
    }
  }

  static CrmException _error(http.Response response) {
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) body = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    final status = response.statusCode;
    var message = ErrorHandler.extractDetail(body) ?? '';
    if (message.isEmpty) {
      switch (status) {
        case 401:
          message = 'Your session has expired. Please sign in again.';
          break;
        case 403:
          message = "You don't have permission to do this.";
          break;
        case 404:
          message = 'Not found.';
          break;
        case 409:
          message = 'This changed in the meantime. Reload and try again.';
          break;
        case 429:
          message = 'Too many requests. Please wait a minute and try again.';
          break;
        default:
          message = status >= 500
              ? 'Server error. Please try again later.'
              : 'The request failed (error $status). Please try again.';
      }
    } else if (status >= 500) {
      message = 'Server error. Please try again later.';
    }
    final code = body?['code'];
    return CrmException(message, statusCode: status, code: code is String ? code : null, body: body);
  }

  Map<String, dynamic> _map(Object? data) =>
      data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};

  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? query, Duration? requestTimeout}) async =>
      _map(await _send('GET', path, query: query, requestTimeout: requestTimeout));
  Future<Map<String, dynamic>> _post(String path, [Object? body]) async =>
      _map(await _send('POST', path, body: body ?? const <String, dynamic>{}));
  Future<Map<String, dynamic>> _patch(String path, Object body) async => _map(await _send('PATCH', path, body: body));
  Future<Map<String, dynamic>> _put(String path, Object body) async => _map(await _send('PUT', path, body: body));

  Map<String, dynamic> _withVersion(Map<String, dynamic> body, int? version) =>
      version == null ? body : {...body, 'version': version};

  // ------------------------------------------------- status / workspace

  /// `GET /api/crm/status` → whether CRM is on for this account.
  Future<bool> getStatus() async {
    final data = await _get('/api/crm/status');
    return data['enabled'] == true;
  }

  /// `GET /api/crm/workspace`: pipeline with stages, lost reasons, tags.
  Future<Map<String, dynamic>> getWorkspace() => _get('/api/crm/workspace');

  /// `GET /api/crm/jobs/{job_id}/state`: CRM state per result of a search.
  Future<Map<String, dynamic>> getJobState(String jobId) => _get('/api/crm/jobs/${_seg(jobId)}/state');

  // ------------------------------------------------------------- import

  /// `POST /api/crm/import` with either [resultIds] or [all].
  Future<Map<String, dynamic>> importResults({
    required String jobId,
    List<int>? resultIds,
    bool all = false,
    required String idempotencyKey,
  }) =>
      _post('/api/crm/import', {
        'job_id': jobId,
        if (all) 'all': true else 'result_ids': resultIds ?? const <int>[],
        'idempotency_key': idempotencyKey,
      });

  /// `POST /api/crm/import/resolve`: decisions for possible matches
  /// (`{result_id, action: add_new|link|skip, record_id?}`).
  Future<Map<String, dynamic>> resolveImport({
    required String jobId,
    required String idempotencyKey,
    required List<Map<String, dynamic>> decisions,
  }) =>
      _post('/api/crm/import/resolve', {
        'job_id': jobId,
        'idempotency_key': idempotencyKey,
        'decisions': decisions,
      });

  // ------------------------------------------------------------ records

  /// `GET /api/crm/records` with filters already in API form
  /// (see `CrmRecordFilters.toApiQuery`).
  Future<CrmPage> listRecords(Map<String, String> query) async =>
      CrmPage.fromJson(await _send('GET', '/api/crm/records', query: query));

  /// `GET /api/crm/pipeline` (Kanban columns with the first cards).
  Future<Map<String, dynamic>> getPipeline({String? q, String? tagId, String? sourceJobId, int perStage = 20}) =>
      _get('/api/crm/pipeline', query: {
        if (q != null) 'q': q.trim(),
        if (tagId != null) 'tag_id': tagId,
        if (sourceJobId != null) 'source_job_id': sourceJobId,
        'per_stage': '$perStage',
      });

  /// `POST /api/crm/records` (manual create).
  Future<Map<String, dynamic>> createRecord(Map<String, dynamic> body) => _post('/api/crm/records', body);

  Future<Map<String, dynamic>> getRecord(String id) => _get('/api/crm/records/${_seg(id)}');

  /// `PATCH /api/crm/records/{id}` (allowlisted fields + `version`).
  Future<Map<String, dynamic>> updateRecord(String id, Map<String, dynamic> changes, {int? version}) =>
      _patch('/api/crm/records/${_seg(id)}', _withVersion(changes, version));

  Future<Map<String, dynamic>> moveStage(String id, String stageId, {int? version}) =>
      _post('/api/crm/records/${_seg(id)}/stage', _withVersion({'stage_id': stageId}, version));

  Future<Map<String, dynamic>> convertToOpportunity(String id, {int? version}) =>
      _post('/api/crm/records/${_seg(id)}/convert', _withVersion({}, version));

  Future<Map<String, dynamic>> markWon(String id, {int? version}) =>
      _post('/api/crm/records/${_seg(id)}/won', _withVersion({}, version));

  /// Lost with a workspace [reasonId] or a new [customReason], plus [note].
  Future<Map<String, dynamic>> markLost(String id, {String? reasonId, String? customReason, String? note, int? version}) =>
      _post(
        '/api/crm/records/${_seg(id)}/lost',
        _withVersion({
          if (reasonId != null) 'reason_id': reasonId,
          if (customReason != null) 'custom_reason': customReason,
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        }, version),
      );

  Future<Map<String, dynamic>> reopen(String id, {int? version}) =>
      _post('/api/crm/records/${_seg(id)}/reopen', _withVersion({}, version));

  Future<Map<String, dynamic>> archive(String id, {int? version}) =>
      _post('/api/crm/records/${_seg(id)}/archive', _withVersion({}, version));

  Future<Map<String, dynamic>> restore(String id, {int? version}) =>
      _post('/api/crm/records/${_seg(id)}/restore', _withVersion({}, version));

  Future<Map<String, dynamic>> deleteRecord(String id, {int? version}) async =>
      _map(await _send('DELETE', '/api/crm/records/${_seg(id)}',
          query: {if (version != null) 'version': '$version'}));

  /// Older history of a record.
  Future<CrmPage> getEvents(String id, {String? cursor}) async => CrmPage.fromJson(
      await _send('GET', '/api/crm/records/${_seg(id)}/events', query: {if (cursor != null) 'cursor': cursor}));

  // -------------------------------------------------------------- notes

  Future<Map<String, dynamic>> addNote(String recordId, String body) =>
      _post('/api/crm/records/${_seg(recordId)}/notes', {'body': body});

  Future<Map<String, dynamic>> editNote(String noteId, String body) =>
      _patch('/api/crm/notes/${_seg(noteId)}', {'body': body});

  // ------------------------------------------------------------- people

  Future<Map<String, dynamic>> addPerson(String recordId, Map<String, dynamic> person) =>
      _post('/api/crm/records/${_seg(recordId)}/people', person);

  Future<Map<String, dynamic>> updatePerson(String personId, Map<String, dynamic> person) =>
      _patch('/api/crm/people/${_seg(personId)}', person);

  Future<void> deletePerson(String personId) async {
    await _send('DELETE', '/api/crm/people/${_seg(personId)}');
  }

  /// Contacts screen: people with company and record id.
  Future<CrmPage> listPeople({String? q, int limit = 50, String? cursor}) async =>
      CrmPage.fromJson(await _send('GET', '/api/crm/people', query: {
        if (q != null) 'q': q.trim(),
        'limit': '$limit',
        if (cursor != null) 'cursor': cursor,
      }));

  // --------------------------------------------------------------- tags

  Future<List<Map<String, dynamic>>> listTags() async {
    final data = await _send('GET', '/api/crm/tags');
    final raw = data is Map ? (data['items'] ?? data['tags']) : data;
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> createTag(String name, {String? color}) =>
      _post('/api/crm/tags', {'name': name, if (color != null) 'color': color});

  Future<Map<String, dynamic>> setRecordTags(String recordId, List<String> tagIds) =>
      _put('/api/crm/records/${_seg(recordId)}/tags', {'tag_ids': tagIds});

  // --------------------------------------------------------- activities

  /// [dueAtUtc] must be a UTC ISO-8601 string with `Z`.
  Future<Map<String, dynamic>> scheduleActivity(
    String recordId, {
    required String type,
    required String subject,
    required String dueAtUtc,
    String? notes,
  }) =>
      _post('/api/crm/records/${_seg(recordId)}/activities', {
        'type': type,
        'subject': subject,
        'due_at': dueAtUtc,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      });

  /// Reschedule / edit (`subject`, `due_at` (UTC), `notes`).
  Future<Map<String, dynamic>> updateActivity(String activityId, Map<String, dynamic> changes) =>
      _patch('/api/crm/activities/${_seg(activityId)}', changes);

  Future<Map<String, dynamic>> completeActivity(String activityId, {String? outcome}) =>
      _post('/api/crm/activities/${_seg(activityId)}/done',
          {if (outcome != null && outcome.trim().isNotEmpty) 'outcome': outcome.trim()});

  Future<Map<String, dynamic>> reopenActivity(String activityId) =>
      _post('/api/crm/activities/${_seg(activityId)}/reopen');

  /// `GET /api/crm/agenda?bucket=overdue|today|upcoming|done`.
  Future<CrmPage> getAgenda({required String bucket, int? tzOffsetMinutes, int limit = 50, String? cursor}) async =>
      CrmPage.fromJson(await _send('GET', '/api/crm/agenda', query: {
        'bucket': bucket,
        'tz_offset_minutes': '${tzOffsetMinutes ?? localTzOffsetMinutes()}',
        'limit': '$limit',
        if (cursor != null) 'cursor': cursor,
      }));

  /// `{overdue, today, upcoming, no_next_activity}`.
  Future<Map<String, int>> getAgendaCounts({int? tzOffsetMinutes}) async {
    final data = await _get('/api/crm/agenda/counts',
        query: {'tz_offset_minutes': '${tzOffsetMinutes ?? localTzOffsetMinutes()}'});
    final out = <String, int>{};
    data.forEach((k, v) {
      if (v is num) out[k] = v.toInt();
    });
    return out;
  }

  // ------------------------------------------------------ reports/export

  /// [from] / [to] are local dates (inclusive), sent as `YYYY-MM-DD`.
  Future<Map<String, dynamic>> getReports({DateTime? from, DateTime? to, int? tzOffsetMinutes}) =>
      _get('/api/crm/reports', query: {
        if (from != null) 'from': crmDateParam(from),
        if (to != null) 'to': crmDateParam(to),
        'tz_offset_minutes': '${tzOffsetMinutes ?? localTzOffsetMinutes()}',
      });

  /// `GET /api/crm/export?format=csv|xlsx&<record filters>` →
  /// `{filename, content (base64), content_type}`.
  Future<Map<String, dynamic>> exportRecords({required String format, Map<String, String> filters = const {}}) async {
    final query = Map<String, String>.from(filters)
      ..remove('cursor')
      ..remove('limit')
      ..['format'] = format;
    final data = await _get('/api/crm/export', query: query, requestTimeout: const Duration(seconds: 90));
    if (data['content'] is! String || '${data['content']}'.isEmpty) {
      throw CrmException('The export was empty. Please try again.', statusCode: 0);
    }
    return data;
  }
}
