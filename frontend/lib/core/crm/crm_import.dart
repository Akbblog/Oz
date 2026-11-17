import '../../services/crm_api.dart';
import 'crm_format.dart';

/// CRM state of one search result (`GET /api/crm/jobs/{id}/state`).
enum CrmLeadState { notAdded, added, possibleMatch }

class CrmLeadStatus {
  final CrmLeadState state;
  final String? recordId;
  final List<String> candidateRecordIds;
  final List<String> reasons;

  const CrmLeadStatus(this.state, {this.recordId, this.candidateRecordIds = const [], this.reasons = const []});

  static const notAdded = CrmLeadStatus(CrmLeadState.notAdded);
}

/// Result id → status from a job-state payload.
Map<int, CrmLeadStatus> parseCrmJobState(Map<String, dynamic> data) {
  final out = <int, CrmLeadStatus>{};
  crmMap(data['results']).forEach((key, value) {
    final id = int.tryParse(key);
    final v = crmMap(value);
    if (id == null) return;
    final s = crmStr(v['state']);
    out[id] = CrmLeadStatus(
      s == 'added'
          ? CrmLeadState.added
          : s == 'possible_match'
              ? CrmLeadState.possibleMatch
              : CrmLeadState.notAdded,
      recordId: crmStr(v['record_id']).isEmpty ? null : crmStr(v['record_id']),
      candidateRecordIds: [for (final c in (v['candidate_record_ids'] as List? ?? const [])) '$c'],
      reasons: [for (final r in (v['reasons'] as List? ?? const [])) '$r'],
    );
  });
  return out;
}

/// Merged outcome of one submission (several calls for "Add all", or a
/// resolve). Items are keyed by result id, so a server that repeats items
/// in a later response is never counted twice.
class CrmImportResult {
  final Map<int, String> created = {};
  final Map<int, String> alreadyAdded = {};
  final Map<int, String> linked = {};
  final Set<int> skipped = {};
  final Map<int, Map<String, dynamic>> possibleMatches = {};
  final Map<int, String> rejected = {};
  bool done = false;
  int processed = 0;
  int remaining = 0;

  void merge(Map<String, dynamic> response) {
    void ids(String key, Map<int, String> into) {
      for (final item in crmList(response[key])) {
        final id = crmIntOrNull(item['result_id']);
        if (id == null) continue;
        into[id] = crmStr(item['record_id'] ?? item['crm_record_id']);
      }
    }

    ids('created', created);
    ids('already_added', alreadyAdded);
    ids('linked', linked);
    for (final item in crmList(response['skipped'])) {
      final id = crmIntOrNull(item['result_id']);
      if (id != null) skipped.add(id);
    }
    for (final item in crmList(response['possible_matches'])) {
      final id = crmIntOrNull(item['result_id']);
      if (id != null) possibleMatches[id] = item;
    }
    for (final item in crmList(response['rejected'])) {
      final id = crmIntOrNull(item['result_id']);
      if (id != null) rejected[id] = crmStr(item['reason']);
    }
    // A decided item is no longer a pending match.
    for (final id in [...created.keys, ...alreadyAdded.keys, ...linked.keys, ...skipped, ...rejected.keys]) {
      possibleMatches.remove(id);
    }
    done = response['done'] != false;
    processed = crmInt(response['processed'], processed);
    remaining = crmInt(response['remaining'], 0);
  }

  /// Result ids that are now in the CRM (added, already there, linked).
  Set<int> get inCrm => {...created.keys, ...alreadyAdded.keys, ...linked.keys};

  String get summary => crmImportSummary(
        added: created.length,
        alreadyInCrm: alreadyAdded.length,
        needsReview: possibleMatches.length,
        linked: linked.length,
        skipped: skipped.length,
        rejected: rejected.length,
      );
}

/// "18 added · 2 already in CRM · 1 needs review" (zero parts left out
/// except "0 added" when nothing else happened).
String crmImportSummary({
  int added = 0,
  int alreadyInCrm = 0,
  int needsReview = 0,
  int linked = 0,
  int skipped = 0,
  int rejected = 0,
}) {
  final parts = <String>[
    if (added > 0 || (alreadyInCrm + needsReview + linked + skipped + rejected) == 0) '$added added',
    if (linked > 0) '$linked linked',
    if (alreadyInCrm > 0) '$alreadyInCrm already in CRM',
    if (needsReview > 0) '$needsReview ${needsReview == 1 ? 'needs' : 'need'} review',
    if (skipped > 0) '$skipped skipped',
    if (rejected > 0) "$rejected couldn't be added",
  ];
  return parts.join(' · ');
}

/// Runs CRM imports with retry-safe idempotency keys: a submission (the
/// same job + the same result ids, or "all") keeps its key until it
/// completes, so a retry after a network error or a crash of the request
/// can never import a row twice.
class CrmImporter {
  CrmImporter(this.api, {String Function()? newKey}) : _newKey = newKey ?? newIdempotencyKey;

  final CrmApi api;
  final String Function() _newKey;
  final Map<String, String> _pending = {};

  /// Upper bound of "Add all" round trips (200 rows each).
  static const int maxAllCalls = 500;

  String _keyFor(String signature) => _pending.putIfAbsent(signature, _newKey);

  /// Key a retry of [signature] would use (tests / diagnostics).
  String? pendingKey(String signature) => _pending[signature];

  static String idsSignature(String jobId, List<int> ids) {
    final sorted = [...{...ids}]..sort();
    return 'ids:$jobId:${sorted.join(',')}';
  }

  static String allSignature(String jobId) => 'all:$jobId';

  Future<CrmImportResult> importIds(String jobId, List<int> ids) async {
    final unique = [...{...ids}];
    if (unique.isEmpty) return CrmImportResult()..done = true;
    final result = CrmImportResult();
    // At most 200 ids per call; each chunk is its own retry-safe submission.
    for (var start = 0; start < unique.length; start += 200) {
      final chunk = unique.sublist(start, (start + 200).clamp(0, unique.length));
      final sig = idsSignature(jobId, chunk);
      final key = _keyFor(sig);
      final response = await api.importResults(jobId: jobId, resultIds: chunk, idempotencyKey: key);
      result.merge(response);
      _pending.remove(sig);
    }
    result.done = true;
    return result;
  }

  /// "Add all": repeats the same request until the server says `done`.
  Future<CrmImportResult> importAll(String jobId, {void Function(CrmImportResult progress)? onProgress}) async {
    final sig = allSignature(jobId);
    final key = _keyFor(sig);
    final result = CrmImportResult();
    for (var call = 0; call < maxAllCalls; call++) {
      final response = await api.importResults(jobId: jobId, all: true, idempotencyKey: key);
      result.merge(response);
      onProgress?.call(result);
      if (result.done) {
        _pending.remove(sig);
        return result;
      }
    }
    throw CrmException('Adding all leads is taking longer than expected. Try again to continue where it stopped.',
        statusCode: 0);
  }

  /// Decisions for possible matches (`add_new`, `link` + `record_id`, `skip`).
  Future<CrmImportResult> resolve(String jobId, List<Map<String, dynamic>> decisions) async {
    final parts = [
      for (final d in decisions) '${d['result_id']}=${d['action']}:${d['record_id'] ?? ''}',
    ]..sort();
    final sig = 'resolve:$jobId:${parts.join(',')}';
    final key = _keyFor(sig);
    final response = await api.resolveImport(jobId: jobId, idempotencyKey: key, decisions: decisions);
    final result = CrmImportResult()..merge(response);
    result.done = true;
    _pending.remove(sig);
    return result;
  }
}
