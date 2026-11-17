/// URL-addressable filters of the CRM screens. Each class reads its page's
/// query string (so a refresh or browser Back restores the view), writes it
/// back (defaults left out) and builds the API query.
library;

String? _clean(String? v) {
  final s = v?.trim();
  return s == null || s.isEmpty ? null : s;
}

/// Record outcome filter (`outcome`, default open).
const List<String> crmOutcomeValues = ['open', 'won', 'lost', 'all'];
const List<String> crmArchivedValues = ['false', 'true', 'all'];
const List<String> crmTypeValues = ['', 'lead', 'opportunity'];
const List<String> crmDueValues = ['', 'overdue', 'today', 'none'];
const List<String> crmSortValues = ['updated', 'created', 'name', 'next_activity'];

String crmOutcomeLabel(String v) {
  switch (v) {
    case 'won':
      return 'Won';
    case 'lost':
      return 'Lost';
    case 'all':
      return 'Any outcome';
    default:
      return 'Open';
  }
}

String crmArchivedLabel(String v) {
  switch (v) {
    case 'true':
      return 'Archived only';
    case 'all':
      return 'Archived and active';
    default:
      return 'Not archived';
  }
}

String crmTypeLabel(String v) {
  switch (v) {
    case 'lead':
      return 'Leads';
    case 'opportunity':
      return 'Opportunities';
    default:
      return 'Leads and opportunities';
  }
}

String crmDueLabel(String v) {
  switch (v) {
    case 'overdue':
      return 'Overdue follow-up';
    case 'today':
      return 'Due today';
    case 'none':
      return 'No next activity';
    default:
      return 'Any follow-up';
  }
}

String crmSortLabel(String v) {
  switch (v) {
    case 'created':
      return 'Recently added';
    case 'name':
      return 'Name A–Z';
    case 'next_activity':
      return 'Next activity';
    default:
      return 'Recently updated';
  }
}

String _pick(String? raw, List<String> allowed, String fallback) {
  final v = _clean(raw);
  return v != null && allowed.contains(v) ? v : fallback;
}

/// Filters of All leads (`/crm/leads`).
class CrmRecordFilters {
  final String? q;
  final String? stageId;
  final String outcome;
  final String archived;
  final String type;
  final String? tagId;
  final String? sourceJobId;
  final String due;
  final String sort;

  const CrmRecordFilters({
    this.q,
    this.stageId,
    this.outcome = 'open',
    this.archived = 'false',
    this.type = '',
    this.tagId,
    this.sourceJobId,
    this.due = '',
    this.sort = 'updated',
  });

  /// From the page's query string (unknown values fall back to defaults).
  factory CrmRecordFilters.fromQuery(Map<String, String> p) => CrmRecordFilters(
        q: _clean(p['q']),
        stageId: _clean(p['stage']),
        outcome: _pick(p['outcome'], crmOutcomeValues, 'open'),
        archived: _pick(p['archived'], crmArchivedValues, 'false'),
        type: _pick(p['type'], crmTypeValues, ''),
        tagId: _clean(p['tag']),
        sourceJobId: _clean(p['source']),
        due: _pick(p['due'], crmDueValues, ''),
        sort: _pick(p['sort'], crmSortValues, 'updated'),
      );

  /// Page query string (defaults omitted).
  Map<String, String> toQuery() => {
        if (q != null) 'q': q!,
        if (stageId != null) 'stage': stageId!,
        if (outcome != 'open') 'outcome': outcome,
        if (archived != 'false') 'archived': archived,
        if (type.isNotEmpty) 'type': type,
        if (tagId != null) 'tag': tagId!,
        if (sourceJobId != null) 'source': sourceJobId!,
        if (due.isNotEmpty) 'due': due,
        if (sort != 'updated') 'sort': sort,
      };

  /// `GET /api/crm/records` / export query.
  Map<String, String> toApiQuery({int limit = 50, String? cursor}) => {
        if (q != null) 'q': q!,
        if (stageId != null) 'stage_id': stageId!,
        'outcome': outcome,
        'archived': archived,
        if (type.isNotEmpty) 'type': type,
        if (tagId != null) 'tag_id': tagId!,
        if (sourceJobId != null) 'source_job_id': sourceJobId!,
        if (due.isNotEmpty) 'due': due,
        'sort': sort,
        'limit': '$limit',
        if (cursor != null) 'cursor': cursor,
      };

  /// `/crm/leads?...`
  String toRoute() => crmRoute('/crm/leads', toQuery());

  bool get isDefault => toQuery().isEmpty;

  /// Filters other than search and sort.
  bool get narrowed =>
      stageId != null || outcome != 'open' || archived != 'false' || type.isNotEmpty || tagId != null ||
      sourceJobId != null || due.isNotEmpty;

  CrmRecordFilters copyWith({
    String? Function()? q,
    String? Function()? stageId,
    String? outcome,
    String? archived,
    String? type,
    String? Function()? tagId,
    String? Function()? sourceJobId,
    String? due,
    String? sort,
  }) =>
      CrmRecordFilters(
        q: q == null ? this.q : _clean(q()),
        stageId: stageId == null ? this.stageId : _clean(stageId()),
        outcome: outcome ?? this.outcome,
        archived: archived ?? this.archived,
        type: type ?? this.type,
        tagId: tagId == null ? this.tagId : _clean(tagId()),
        sourceJobId: sourceJobId == null ? this.sourceJobId : _clean(sourceJobId()),
        due: due ?? this.due,
        sort: sort ?? this.sort,
      );

  @override
  bool operator ==(Object other) => other is CrmRecordFilters && other.toRoute() == toRoute();

  @override
  int get hashCode => toRoute().hashCode;
}

/// Filters of the pipeline (`/crm`).
class CrmPipelineFilters {
  final String? q;
  final String? tagId;
  final String? sourceJobId;

  /// Stage shown on tablet/phone (stage id or key).
  final String? stage;

  const CrmPipelineFilters({this.q, this.tagId, this.sourceJobId, this.stage});

  factory CrmPipelineFilters.fromQuery(Map<String, String> p) => CrmPipelineFilters(
        q: _clean(p['q']),
        tagId: _clean(p['tag']),
        sourceJobId: _clean(p['source']),
        stage: _clean(p['stage']),
      );

  Map<String, String> toQuery() => {
        if (q != null) 'q': q!,
        if (tagId != null) 'tag': tagId!,
        if (sourceJobId != null) 'source': sourceJobId!,
        if (stage != null) 'stage': stage!,
      };

  String toRoute() => crmRoute('/crm', toQuery());

  bool get narrowed => q != null || tagId != null || sourceJobId != null;

  CrmPipelineFilters copyWith({
    String? Function()? q,
    String? Function()? tagId,
    String? Function()? sourceJobId,
    String? Function()? stage,
  }) =>
      CrmPipelineFilters(
        q: q == null ? this.q : _clean(q()),
        tagId: tagId == null ? this.tagId : _clean(tagId()),
        sourceJobId: sourceJobId == null ? this.sourceJobId : _clean(sourceJobId()),
        stage: stage == null ? this.stage : _clean(stage()),
      );
}

/// Agenda buckets (`/crm/activities?bucket=`).
const List<String> crmAgendaBuckets = ['overdue', 'today', 'upcoming', 'done'];

String crmAgendaBucketLabel(String b) {
  switch (b) {
    case 'overdue':
      return 'Overdue';
    case 'upcoming':
      return 'Upcoming';
    case 'done':
      return 'Done';
    default:
      return 'Today';
  }
}

/// `path?query` with the query omitted when empty.
String crmRoute(String path, Map<String, String> query) {
  if (query.isEmpty) return path;
  return Uri(path: path, queryParameters: query).toString();
}

/// "View this search in CRM": every record imported from [jobId],
/// whatever its outcome.
String crmSearchRoute(String jobId) =>
    CrmRecordFilters(sourceJobId: jobId, outcome: 'all').toRoute();

/// Detail page of a record.
String crmRecordRoute(String recordId) => '/crm/records/${Uri.encodeComponent(recordId)}';
