import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/admin_roles.dart';
import '../../providers/auth_provider.dart';
import '../../screens/admin_credit_account_dialog.dart';
import '../../services/api_service.dart';
import '../admin_kit.dart';
import '../admin_shell.dart';
import 'user_actions.dart';

/// Users list ("list view") with a slide-over record panel ("form view").
///
/// Query string: `?status=pending|approved|suspended|denied` preselects the
/// status filter, `?user=<id>` opens that account's record.
class AdminUsersPage extends StatefulWidget {
  final Map<String, String> query;
  const AdminUsersPage({super.key, this.query = const {}});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final ApiService _api = ApiService();
  final TextEditingController _search = TextEditingController();

  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;
  String _status = 'all';
  String? _role;
  String _sort = 'newest';
  final Set<int> _selected = {};
  bool _bulkBusy = false;
  bool _openedFromQuery = false;

  Map<String, dynamic>? get _viewer =>
      Provider.of<AuthProvider>(context, listen: false).currentUser;

  @override
  void initState() {
    super.initState();
    final s = widget.query['status'];
    if (s != null &&
        const ['pending', 'approved', 'suspended', 'denied'].contains(s)) {
      _status = s;
    }
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await _api.getAllUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
        _selected.removeWhere((id) => !users.any(
            (u) => u['id'] == id && userState(u) == 'pending'));
      });
      AdminBadges.instance.refresh(force: true);
      _maybeOpenFromQuery();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = cleanError(e);
      });
    }
  }

  void _maybeOpenFromQuery() {
    if (_openedFromQuery) return;
    _openedFromQuery = true;
    final id = int.tryParse(widget.query['user'] ?? '');
    if (id == null) return;
    final match = _users.where((u) => u['id'] == id);
    if (match.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(match.first);
    });
  }

  Map<String, int> get _counts {
    final c = {'all': _users.length, 'pending': 0, 'approved': 0, 'suspended': 0, 'denied': 0};
    for (final u in _users) {
      final s = userState(u);
      c[s] = (c[s] ?? 0) + 1;
    }
    return c;
  }

  List<Map<String, dynamic>> get _visible {
    final q = _search.text.trim().toLowerCase();
    final list = _users.where((u) {
      if (_status != 'all' && userState(u) != _status) return false;
      if (_role != null && AdminRoles.roleOf(u) != _role) return false;
      if (q.isEmpty) return true;
      return '${u['username']} ${u['email']} ${u['phone'] ?? ''} #${u['id']}'
          .toLowerCase()
          .contains(q);
    }).toList();
    int cmpStr(Object? a, Object? b) => '${a ?? ''}'.compareTo('${b ?? ''}');
    switch (_sort) {
      case 'oldest':
        list.sort((a, b) => cmpStr(a['created_at'], b['created_at']));
      case 'credits':
        list.sort((a, b) => ((b['credit_balance'] ?? 0) as num)
            .compareTo((a['credit_balance'] ?? 0) as num));
      case 'last_login':
        list.sort((a, b) => cmpStr(b['last_login'], a['last_login']));
      case 'name':
        list.sort((a, b) => '${a['username']}'
            .toLowerCase()
            .compareTo('${b['username']}'.toLowerCase()));
      default:
        list.sort((a, b) => cmpStr(b['created_at'], a['created_at']));
    }
    return list;
  }

  Future<void> _bulkApprove() async {
    if (_bulkBusy || _selected.isEmpty) return;
    setState(() => _bulkBusy = true);
    try {
      final ids = _selected.toList()..sort();
      final r = await _api.bulkApproveUsers(ids);
      final approved = r['approved'] ?? 0;
      final skipped = r['skipped'] ?? 0;
      if (mounted) {
        aToast(context,
            'Approved $approved account(s)${skipped is num && skipped > 0 ? ', skipped $skipped' : ''}');
      }
      _selected.clear();
      await _load();
    } catch (e) {
      if (mounted) aToast(context, cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _open(Map<String, dynamic> user) async {
    final changed = await showASheet<bool>(
      context,
      width: 620,
      builder: (_) => _UserRecord(api: _api, user: user, viewer: _viewer),
    );
    if (changed == true && mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final counts = _counts;
    final rows = _visible;
    final totalCredits = _users.fold<num>(
        0, (a, u) => a + ((u['credit_balance'] ?? 0) as num));
    return AdminScaffold(
      section: AdminSection.users,
      title: 'Users',
      subtitle: _loading
          ? 'Loading accounts…'
          : '${fmtInt(_users.length)} accounts · ${fmtInt(totalCredits)} credits held · ${counts['pending']} waiting for approval',
      actions: [
        AIconButton(Icons.refresh, 'Refresh', onPressed: _loading ? null : _load),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _filters(counts),
          const SizedBox(height: 12),
          if (_selected.isNotEmpty) ...[
            _bulkBar(),
            const SizedBox(height: 12),
          ],
          if (_error != null)
            AErrorBox(_error!, onRetry: _load)
          else
            APanel(
              padding: EdgeInsets.zero,
              child: _loading
                  ? const ALoading(height: 280)
                  : ATable<Map<String, dynamic>>(
                      minWidth: 980,
                      rows: rows,
                      onRowTap: _open,
                      isSelected: (u) => _selected.contains(u['id']),
                      selectable: (u) => userState(u) == 'pending',
                      onSelect: (u, v) => setState(() {
                        final id = (u['id'] as num).toInt();
                        v ? _selected.add(id) : _selected.remove(id);
                      }),
                      empty: AEmpty(
                        icon: Icons.person_search_outlined,
                        title: _users.isEmpty
                            ? 'No accounts yet'
                            : 'No accounts match these filters',
                        message: _users.isEmpty
                            ? null
                            : 'Try a different status, role or search term.',
                      ),
                      columns: [
                        ACol('User', (u) {
                          final name = '${u['username'] ?? 'Unknown'}';
                          return ATwoLine(name,
                              secondary: '${u['email'] ?? ''}',
                              leading: AAvatar(name));
                        }, flex: 4),
                        ACol('Role', (u) {
                          final r = AdminRoles.roleOf(u);
                          return APill(cap(r), roleColor(r));
                        }, width: 104),
                        ACol('Status', (u) {
                          final s = userState(u);
                          return APill(userStateLabel(s), userStateColor(s),
                              dot: true);
                        }, width: 122),
                        ACol('Credits',
                            (u) => Text(fmtInt(u['credit_balance'] ?? 0)),
                            width: 96, numeric: true),
                        ACol(
                            'Phone',
                            (u) => Text(
                                '${u['phone'] ?? ''}'.trim().isEmpty
                                    ? '–'
                                    : '${u['phone']}',
                                style: AT.bodyDim),
                            flex: 2),
                        ACol(
                            'Joined',
                            (u) => Text(fmtDate(u['created_at']),
                                style: AT.bodyDim),
                            width: 108),
                        ACol(
                            'Last sign-in',
                            (u) => Text(
                                u['last_login'] == null
                                    ? 'Never'
                                    : timeAgo(u['last_login']),
                                style: AT.bodyDim),
                            width: 116),
                        ACol(
                            '',
                            (u) => const Icon(Icons.chevron_right,
                                size: 18, color: AC.textMute),
                            width: 44),
                      ],
                    ),
            ),
          if (!_loading && _error == null && rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                  'Showing ${rows.length} of ${_users.length}. Click a row to open the account record.',
                  style: AT.mute),
            ),
        ],
      ),
    );
  }

  Widget _filters(Map<String, int> counts) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 300,
          child: ASearchField(
            controller: _search,
            hint: 'Search name, email, phone or #id',
            onChanged: (_) => setState(() {}),
          ),
        ),
        ASegmented<String>(
          value: _status,
          counts: counts,
          options: const {
            'all': 'All',
            'pending': 'Pending',
            'approved': 'Active',
            'suspended': 'Suspended',
            'denied': 'Denied',
          },
          onChanged: (v) => setState(() => _status = v),
        ),
        ADropdown<String>(
          value: _role,
          hint: 'Any role',
          width: 140,
          items: const {
            'user': 'User',
            'support': 'Support',
            'admin': 'Admin',
            'owner': 'Owner',
          },
          onChanged: (v) => setState(() => _role = v),
        ),
        ADropdown<String>(
          value: _sort,
          hint: 'Newest first',
          width: 170,
          items: const {
            'oldest': 'Oldest first',
            'name': 'Name A–Z',
            'credits': 'Most credits',
            'last_login': 'Recently signed in',
          },
          onChanged: (v) => setState(() => _sort = v ?? 'newest'),
        ),
      ],
    );
  }

  Widget _bulkBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AC.selected,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AC.primary),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text('${_selected.length} pending account(s) selected',
                style: AT.body.copyWith(fontWeight: FontWeight.w600)),
          ),
          AButton('Clear',
              kind: AButtonKind.ghost,
              onPressed:
                  _bulkBusy ? null : () => setState(() => _selected.clear())),
          const SizedBox(width: 8),
          AButton('Approve selected',
              icon: Icons.check,
              kind: AButtonKind.success,
              busy: _bulkBusy,
              onPressed: _bulkApprove),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- the record

class _UserRecord extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> user;
  final Map<String, dynamic>? viewer;
  const _UserRecord({required this.api, required this.user, this.viewer});

  @override
  State<_UserRecord> createState() => _UserRecordState();
}

class _UserRecordState extends State<_UserRecord> {
  String _tab = 'summary';

  Map<String, dynamic>? _kpis;
  String? _kpiError;
  List<Map<String, dynamic>>? _jobs;
  String? _jobsError;
  List<Map<String, dynamic>>? _timeline;
  String? _timelineError;

  Map<String, dynamic> get u => widget.user;
  int get _id => (u['id'] as num).toInt();

  @override
  void initState() {
    super.initState();
    _loadKpis();
  }

  Future<void> _loadKpis() async {
    try {
      final k = await widget.api.getUserKpis(_id);
      if (mounted) setState(() => _kpis = k);
    } catch (e) {
      if (mounted) setState(() => _kpiError = cleanError(e));
    }
  }

  Future<void> _loadJobs() async {
    if (_jobs != null) return;
    try {
      final j = await widget.api.getUserJobsAdmin(_id);
      if (mounted) setState(() => _jobs = j);
    } catch (e) {
      if (mounted) setState(() => _jobsError = cleanError(e));
    }
  }

  Future<void> _loadTimeline() async {
    if (_timeline != null) return;
    try {
      final t = await widget.api.getUserTimeline(_id);
      if (mounted) {
        setState(() => _timeline =
            List<Map<String, dynamic>>.from(t['events'] ?? const []));
      }
    } catch (e) {
      if (mounted) setState(() => _timelineError = cleanError(e));
    }
  }

  Future<void> _do(Future<bool> Function(UserActions a) action) async {
    final changed = await action(UserActions(context, widget.api, widget.viewer));
    if (changed && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final name = '${u['username'] ?? 'Unknown'}';
    final state = userState(u);
    final role = AdminRoles.roleOf(u);
    return ASheetFrame(
      title: Row(
        children: [
          AAvatar(name, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: AT.h1.copyWith(fontSize: 17),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    APill(userStateLabel(state), userStateColor(state),
                        dot: true),
                    APill(cap(role), roleColor(role)),
                    APill('${fmtInt(u['credit_balance'] ?? 0)} credits',
                        AC.blue),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _actions(state),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: ASegmented<String>(
              value: _tab,
              options: const {
                'summary': 'Summary',
                'searches': 'Searches',
                'timeline': 'Timeline',
              },
              onChanged: (v) {
                setState(() => _tab = v);
                if (v == 'searches') _loadJobs();
                if (v == 'timeline') _loadTimeline();
              },
            ),
          ),
          const SizedBox(height: 6),
          if (_tab == 'summary') _summary(state),
          if (_tab == 'searches') _searches(),
          if (_tab == 'timeline') _timelineView(),
        ],
      ),
    );
  }

  Widget _actions(String state) {
    final v = widget.viewer;
    final canManage = AdminRoles.canManage(v, u);
    final buttons = <Widget>[
      if (state == 'pending')
        AButton('Approve',
            icon: Icons.check,
            kind: AButtonKind.success,
            onPressed: () => _do((a) => a.approve(u))),
      if (state == 'pending' && canManage)
        AButton('Deny',
            icon: Icons.block,
            kind: AButtonKind.danger,
            onPressed: () => _do((a) => a.deny(u))),
      if (state == 'approved' && AdminRoles.canGrantCredits(v, u))
        AButton('Grant credits',
            icon: Icons.add_card,
            kind: AButtonKind.primary,
            onPressed: () => _do((a) => a.grantCredits(u))),
      AButton('Credit ledger',
          icon: Icons.receipt_long,
          onPressed: () => showDialog(
                context: context,
                builder: (_) => AdminCreditAccountDialog(
                  apiService: widget.api,
                  userId: _id,
                  username: '${u['username'] ?? 'User'}',
                ),
              )),
      if (AdminRoles.canEditProfile(v, u))
        AButton('Edit profile',
            icon: Icons.edit_outlined,
            onPressed: () => _do((a) => a.editProfile(u))),
      if (AdminRoles.canChangeRole(v, u))
        AButton('Change role',
            icon: Icons.admin_panel_settings_outlined,
            onPressed: () => _do((a) => a.changeRole(u))),
      if (state == 'approved' && canManage)
        AButton('Suspend',
            icon: Icons.pause_circle_outline,
            kind: AButtonKind.danger,
            onPressed: () => _do((a) => a.suspend(u))),
      if (state == 'suspended' && canManage)
        AButton('Lift suspension',
            icon: Icons.play_circle_outline,
            kind: AButtonKind.success,
            onPressed: () => _do((a) => a.unsuspend(u))),
      if (state == 'denied' && canManage)
        AButton('Move back to pending',
            icon: Icons.undo,
            onPressed: () => _do((a) => a.restore(u))),
      if ((state == 'denied' || state == 'suspended') &&
          AdminRoles.canDelete(v, u))
        AButton('Delete',
            icon: Icons.delete_outline,
            kind: AButtonKind.danger,
            onPressed: () => _do((a) => a.delete(u))),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: buttons),
        if (!canManage)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 14, color: AC.textMute),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(AdminRoles.protectedNote(v, u), style: AT.mute)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _summary(String state) {
    final k = _kpis;
    String kv(String key) => k == null ? '…' : fmtInt(k[key]);
    final perLead = k?['cost_per_result'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ASectionLabel('Value'),
        if (_kpiError != null)
          AErrorBox(_kpiError!)
        else
          AGrid(
            minTileWidth: 160,
            gap: 8,
            children: [
              AKpi(
                  label: 'Searches run',
                  value: kv('jobs_run'),
                  icon: Icons.travel_explore,
                  color: AC.blue),
              AKpi(
                  label: 'Leads delivered',
                  value: kv('results_generated'),
                  icon: Icons.checklist,
                  color: AC.green),
              AKpi(
                  label: 'Credits used (net)',
                  value: kv('credits_used_net'),
                  icon: Icons.bolt,
                  color: AC.amber,
                  hint: 'Charges minus refunds'),
              AKpi(
                  label: 'Paid credits',
                  value: kv('paid_credits'),
                  icon: Icons.add_card,
                  color: AC.purple,
                  hint: 'Completed live payments'),
              AKpi(
                  label: 'Credits per lead',
                  value: k == null
                      ? '…'
                      : (perLead == null ? '–' : '$perLead'),
                  icon: Icons.trending_down,
                  color: AC.accent,
                  hint: 'Net, searches on file'),
            ],
          ),
        const ASectionLabel('Account'),
        AField('User ID', value: '#${u['id']}', copyable: true),
        AField('Email', value: '${u['email'] ?? ''}', copyable: true),
        AField('Phone', value: '${u['phone'] ?? ''}', copyable: true),
        AField('Joined', value: fmtDateTime(u['created_at'])),
        AField('Last sign-in',
            value: u['last_login'] == null
                ? 'Never'
                : '${fmtDateTime(u['last_login'])} (${timeAgo(u['last_login'])})'),
        AField('Last activity',
            value: k == null
                ? '…'
                : (k['last_activity'] == null
                    ? 'None recorded'
                    : fmtDateTime(k['last_activity']))),
        const ASectionLabel('Approval'),
        AField('Status', child: Align(
          alignment: Alignment.centerLeft,
          child: APill(userStateLabel(state), userStateColor(state), dot: true),
        )),
        if (u['approved_at'] != null)
          AField('Approved', value: fmtDateTime(u['approved_at'])),
        if (u['denied_at'] != null)
          AField('Denied', value: fmtDateTime(u['denied_at'])),
        if ('${u['denied_reason'] ?? ''}'.trim().isNotEmpty)
          AField('Denial note', value: '${u['denied_reason']}'),
        if (u['suspended_at'] != null)
          AField('Suspended', value: fmtDateTime(u['suspended_at'])),
        if ('${u['suspension_reason'] ?? ''}'.trim().isNotEmpty)
          AField('Suspension reason', value: '${u['suspension_reason']}'),
      ],
    );
  }

  Widget _searches() {
    if (_jobsError != null) return AErrorBox(_jobsError!);
    final jobs = _jobs;
    if (jobs == null) return const ALoading();
    if (jobs.isEmpty) {
      return const AEmpty(
          icon: Icons.travel_explore, title: 'No searches yet');
    }
    return Column(
      children: [
        for (final j in jobs)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AC.border))),
            child: Row(
              children: [
                Expanded(
                  child: ATwoLine('${j['category'] ?? 'Search'}',
                      secondary:
                          '${fmtDateTime(j['created_at'])} · ${fmtInt(j['total_cities'] ?? 0)} cities'),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${fmtInt(j['result_count'] ?? 0)} leads',
                        style: AT.num),
                    Text('${fmtInt(j['credit_charged'] ?? 0)} credits',
                        style: AT.mute),
                  ],
                ),
                const SizedBox(width: 12),
                SizedBox(width: 108, child: Align(
                  alignment: Alignment.centerRight,
                  child: statusPill(j['status']),
                )),
              ],
            ),
          ),
      ],
    );
  }

  Widget _timelineView() {
    if (_timelineError != null) return AErrorBox(_timelineError!);
    final events = _timeline;
    if (events == null) return const ALoading();
    if (events.isEmpty) {
      return const AEmpty(
          icon: Icons.history, title: 'Nothing recorded for this account');
    }
    return Column(
      children: [
        for (final e in events)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AC.border))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: e['status'] == 'success' ? AC.green : AC.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${e['action'] ?? ''}',
                          style:
                              AT.body.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                        [
                          fmtDateTime(e['created_at']),
                          if ('${e['ip_address'] ?? ''}'.isNotEmpty)
                            'IP ${e['ip_address']}',
                          if (e['target_type'] != null)
                            '${e['target_type']}${e['target_id'] != null ? ' #${e['target_id']}' : ''}',
                          if ('${e['failure_reason'] ?? ''}'.isNotEmpty)
                            '${e['failure_reason']}',
                        ].join(' · '),
                        style: AT.mute,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
