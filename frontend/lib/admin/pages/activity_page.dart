import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/download_helper.dart';
import '../../services/api_service.dart';
import '../admin_kit.dart';
import '../admin_shell.dart';
import 'job_event_panel.dart';

/// Activity log.
///
/// * **Everything**: the audit trail. Every sign-in, registration, admin
///   action, payment and search event with who did it, from which IP and
///   device, and whether it succeeded.
/// * **Search events**: the search lifecycle feed (created / started /
///   completed) with lead previews.
class AdminActivityPage extends StatefulWidget {
  const AdminActivityPage({super.key});

  @override
  State<AdminActivityPage> createState() => _AdminActivityPageState();
}

class _AdminActivityPageState extends State<AdminActivityPage> {
  static const int _pageSize = 50;

  final ApiService _api = ApiService();
  final TextEditingController _userId = TextEditingController();

  String _mode = 'audit';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];
  int _total = 0;
  int _offset = 0;
  int _seq = 0;
  bool _exporting = false;

  // Filters
  String? _action;
  String? _status;
  String? _jobType;
  DateTime? _from;
  DateTime? _to;

  List<String> _auditActions = [];
  List<String> _jobEventTypes = [];
  List<String> _jobTypes = [];
  List<String> _jobStatuses = [];

  @override
  void initState() {
    super.initState();
    _loadFilters();
    _load();
  }

  @override
  void dispose() {
    _userId.dispose();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    try {
      final a = await _api.getActivityActions();
      if (mounted) setState(() => _auditActions = a);
    } catch (_) {}
    try {
      final f = await _api.getAdminJobActivityFilters();
      if (mounted) {
        setState(() {
          _jobEventTypes = List<String>.from(f['event_types'] ?? const []);
          _jobTypes = List<String>.from(f['job_types'] ?? const []);
          _jobStatuses = List<String>.from(f['job_statuses'] ?? const []);
        });
      }
    } catch (_) {}
  }

  String? _iso(DateTime? d, {bool endOfDay = false}) {
    if (d == null) return null;
    final v = endOfDay
        ? DateTime(d.year, d.month, d.day, 23, 59, 59)
        : DateTime(d.year, d.month, d.day);
    return v.toUtc().toIso8601String();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _offset = 0;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final uid = int.tryParse(_userId.text.trim());
    try {
      final data = _mode == 'audit'
          ? await _api.getActivityFeed(
              userId: uid,
              action: _action,
              status: _status,
              dateFrom: _iso(_from),
              dateTo: _iso(_to, endOfDay: true),
              limit: _pageSize,
              offset: _offset,
            )
          : await _api.getAdminJobActivity(
              userId: uid,
              eventType: _action,
              jobStatus: _status,
              jobType: _jobType,
              dateFrom: _iso(_from),
              dateTo: _iso(_to, endOfDay: true),
              limit: _pageSize,
              offset: _offset,
            );
      if (!mounted || seq != _seq) return;
      setState(() {
        _events = List<Map<String, dynamic>>.from(data['events'] ?? const []);
        _total = (data['total'] as num?)?.toInt() ?? _events.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = cleanError(e);
      });
    }
  }

  void _switchMode(String mode) {
    setState(() {
      _mode = mode;
      _action = null;
      _status = null;
      _jobType = null;
      _events = [];
      _total = 0;
    });
    _load(reset: true);
  }

  void _clearFilters() {
    setState(() {
      _userId.clear();
      _action = null;
      _status = null;
      _jobType = null;
      _from = null;
      _to = null;
    });
    _load(reset: true);
  }

  bool get _hasFilters =>
      _userId.text.trim().isNotEmpty ||
      _action != null ||
      _status != null ||
      _jobType != null ||
      _from != null ||
      _to != null;

  Future<void> _pick(bool from) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (from ? _from : _to) ?? now,
      firstDate: DateTime(2024),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
              primary: AC.accent, surface: AC.surface, onSurface: AC.text),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => from ? _from = picked : _to = picked);
    _load(reset: true);
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final csv = await _api.exportActivityCSV(
        userId: int.tryParse(_userId.text.trim()),
        action: _mode == 'audit' ? _action : null,
        dateFrom: _iso(_from),
        dateTo: _iso(_to, endOfDay: true),
      );
      if (!mounted) return;
      final d = DateTime.now();
      await saveCsv(csv,
          'activity-log-${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}',
          context: context);
    } catch (e) {
      if (mounted) aToast(context, cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      section: AdminSection.activity,
      title: 'Activity log',
      subtitle: _mode == 'audit'
          ? 'Every sign-in, account change, payment and admin action, with IP and device'
          : 'Search lifecycle events with lead previews',
      actions: [
        AButton('Export CSV',
            icon: Icons.download,
            busy: _exporting,
            onPressed: _mode == 'audit' ? _export : null),
        AIconButton(Icons.refresh, 'Refresh',
            onPressed: _loading ? null : () => _load()),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ASegmented<String>(
              value: _mode,
              options: const {
                'audit': 'Everything',
                'jobs': 'Search events',
              },
              onChanged: _switchMode,
            ),
          ),
          const SizedBox(height: 12),
          _filterBar(),
          const SizedBox(height: 12),
          if (_error != null)
            AErrorBox(_error!, onRetry: () => _load())
          else
            APanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (_loading && _events.isEmpty)
                    const ALoading(height: 280)
                  else
                    Opacity(
                      opacity: _loading ? 0.5 : 1,
                      child: _mode == 'audit' ? _auditTable() : _jobTable(),
                    ),
                  if (_total > 0)
                    Container(
                      decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: AC.border))),
                      child: APager(
                        offset: _offset,
                        limit: _pageSize,
                        total: _total,
                        onOffset: (o) {
                          _offset = o;
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateChip(String label, DateTime? value, bool from) {
    return AButton(
      value == null ? label : '$label ${value.day}/${value.month}/${value.year}',
      icon: Icons.event,
      onPressed: () => _pick(from),
    );
  }

  Widget _filterBar() {
    final audit = _mode == 'audit';
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 130,
          child: TextField(
            controller: _userId,
            keyboardType: TextInputType.number,
            style: AT.body,
            cursorColor: AC.accent,
            onSubmitted: (_) => _load(reset: true),
            decoration: aInput(hint: 'User ID', icon: Icons.person_outline),
          ),
        ),
        ADropdown<String>(
          value: _action,
          hint: audit ? 'Any action' : 'Any event',
          width: 210,
          items: {
            for (final a in (audit ? _auditActions : _jobEventTypes)) a: a
          },
          onChanged: (v) {
            setState(() => _action = v);
            _load(reset: true);
          },
        ),
        if (!audit)
          ADropdown<String>(
            value: _jobType,
            hint: 'Any search type',
            width: 190,
            items: {for (final t in _jobTypes) t: t},
            onChanged: (v) {
              setState(() => _jobType = v);
              _load(reset: true);
            },
          ),
        ADropdown<String>(
          value: _status,
          hint: 'Any result',
          width: 150,
          items: audit
              ? const {'success': 'Succeeded', 'failure': 'Failed'}
              : {for (final s in _jobStatuses) s: s},
          onChanged: (v) {
            setState(() => _status = v);
            _load(reset: true);
          },
        ),
        _dateChip('From', _from, true),
        _dateChip('To', _to, false),
        if (_hasFilters)
          AButton('Clear filters',
              kind: AButtonKind.ghost, icon: Icons.close, onPressed: _clearFilters),
      ],
    );
  }

  // ------------------------------------------------------------ audit table

  static (IconData, Color) _actionLook(String action) {
    final a = action.toLowerCase();
    if (a.startsWith('auth.login')) return (Icons.login, AC.blue);
    if (a.startsWith('auth.register')) return (Icons.person_add_alt, AC.purple);
    if (a.startsWith('auth')) return (Icons.key, AC.blue);
    if (a.startsWith('job')) return (Icons.travel_explore, AC.accent);
    if (a.contains('credit')) return (Icons.toll, AC.amber);
    if (a.contains('payment') || a.contains('purchase')) {
      return (Icons.payments_outlined, AC.green);
    }
    if (a.contains('promo')) return (Icons.local_offer_outlined, AC.amber);
    if (a.contains('setting')) return (Icons.tune, AC.grey);
    if (a.startsWith('admin') || a.contains('user')) {
      return (Icons.admin_panel_settings_outlined, AC.purple);
    }
    return (Icons.bolt, AC.grey);
  }

  Widget _auditTable() {
    return ATable<Map<String, dynamic>>(
      minWidth: 920,
      rows: _events,
      onRowTap: _openAudit,
      empty: AEmpty(
        icon: Icons.history,
        title: _hasFilters ? 'Nothing matches these filters' : 'No activity yet',
        message: _hasFilters ? 'Widen the dates or clear the filters.' : null,
      ),
      columns: [
        ACol(
            'When',
            (e) => ATwoLine(timeAgo(e['created_at']),
                secondary: fmtDateTime(e['created_at'])),
            width: 168),
        ACol('Who', (e) {
          final name = '${e['actor_username'] ?? ''}'.trim();
          final id = e['actor_user_id'];
          return ATwoLine(name.isEmpty ? (id == null ? 'System' : 'User #$id') : name,
              secondary: id == null ? 'No account' : 'ID $id',
              leading: AAvatar(name.isEmpty ? 'S' : name, size: 26));
        }, flex: 3),
        ACol('Action', (e) {
          final action = '${e['action'] ?? ''}';
          final look = _actionLook(action);
          return Row(
            children: [
              Icon(look.$1, size: 15, color: look.$2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(action,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AT.body.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          );
        }, flex: 4),
        ACol('Target', (e) {
          final t = e['target_type'];
          if (t == null) return const Text('–', style: AT.mute);
          final id = '${e['target_id'] ?? ''}';
          return Text(
              id.isEmpty
                  ? '$t'
                  : '$t ${id.length > 10 ? '${id.substring(0, 8)}…' : '#$id'}',
              style: AT.bodyDim);
        }, flex: 3),
        ACol('IP address', (e) {
          final ip = '${e['ip_address'] ?? ''}';
          return Text(ip.isEmpty ? '–' : ip, style: AT.mono);
        }, width: 150),
        ACol('Result', (e) => statusPill(e['status']), width: 110),
      ],
    );
  }

  void _openAudit(Map<String, dynamic> e) {
    String pretty(Object? v) {
      if (v == null) return '';
      try {
        return const JsonEncoder.withIndent('  ').convert(v);
      } catch (_) {
        return '$v';
      }
    }

    Widget jsonBlock(String title, Object? v) {
      final text = pretty(v);
      if (text.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ASectionLabel(title),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AC.bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AC.border),
            ),
            child: SelectableText(text, style: AT.mono),
          ),
        ],
      );
    }

    final action = '${e['action'] ?? ''}';
    final look = _actionLook(action);
    final actorId = e['actor_user_id'];
    showASheet<void>(
      context,
      builder: (ctx) => ASheetFrame(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: look.$2.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(look.$1, size: 18, color: look.$2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(action,
                      style: AT.h2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(fmtDateTime(e['created_at']), style: AT.mute),
                ],
              ),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ASectionLabel('Event'),
            AField('Result',
                child: Align(
                    alignment: Alignment.centerLeft,
                    child: statusPill(e['status']))),
            if ('${e['failure_reason'] ?? ''}'.isNotEmpty)
              AField('Failure reason', value: '${e['failure_reason']}'),
            AField('Who',
                value: '${e['actor_username'] ?? 'System'}'
                    '${actorId == null ? '' : '  (ID $actorId)'}'),
            AField('Target',
                value: e['target_type'] == null
                    ? ''
                    : '${e['target_type']} ${e['target_id'] ?? ''}'),
            const ASectionLabel('Where it came from'),
            AField('IP address',
                value: '${e['ip_address'] ?? ''}', copyable: true, mono: true),
            AField('Device / browser', value: '${e['user_agent'] ?? ''}'),
            AField('Request ID',
                value: '${e['request_id'] ?? ''}', copyable: true, mono: true),
            AField('Event ID', value: '${e['id'] ?? ''}', mono: true),
            jsonBlock('Details', e['metadata']),
            jsonBlock('Before', e['before_snapshot']),
            jsonBlock('After', e['after_snapshot']),
            if (actorId != null) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AButton('Open user',
                      icon: Icons.person_outline,
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context)
                            .pushNamed('/admin/users?user=$actorId');
                      }),
                  AButton('Show all by this user',
                      icon: Icons.filter_alt_outlined,
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        setState(() => _userId.text = '$actorId');
                        _load(reset: true);
                      }),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- job table

  Widget _jobTable() {
    return ATable<Map<String, dynamic>>(
      minWidth: 860,
      rows: _events,
      onRowTap: (e) => showASheet<void>(
        context,
        width: 760,
        builder: (ctx) => Material(
          color: AC.surface,
          child: JobEventPanel(
            apiService: _api,
            event: e,
            onClose: () => Navigator.of(ctx).pop(),
          ),
        ),
      ),
      empty: AEmpty(
        icon: Icons.travel_explore,
        title: _hasFilters
            ? 'Nothing matches these filters'
            : 'No search events yet',
      ),
      columns: [
        ACol(
            'When',
            (e) => ATwoLine(timeAgo(e['created_at']),
                secondary: fmtDateTime(e['created_at'])),
            width: 168),
        ACol('User', (e) {
          final name = '${e['username'] ?? ''}'.trim();
          return ATwoLine(name.isEmpty ? 'User #${e['user_id'] ?? '?'}' : name,
              leading: AAvatar(name.isEmpty ? '?' : name, size: 26));
        }, flex: 3),
        ACol(
            'Event',
            (e) => Text('${e['event_type'] ?? ''}'.replaceAll('_', ' '),
                style: AT.body.copyWith(fontWeight: FontWeight.w600)),
            flex: 3),
        ACol('Search type',
            (e) => Text('${e['job_type'] ?? ''}', style: AT.bodyDim),
            flex: 3),
        ACol('Leads', (e) => Text(fmtInt(e['result_count'] ?? 0)),
            width: 84, numeric: true),
        ACol('Status', (e) => statusPill(e['job_status']), width: 124),
      ],
    );
  }
}
