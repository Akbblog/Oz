import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../admin_kit.dart';
import '../admin_shell.dart';

/// Pending credit requests: review one by one or in bulk.
class AdminCreditsPage extends StatefulWidget {
  const AdminCreditsPage({super.key});

  @override
  State<AdminCreditsPage> createState() => _AdminCreditsPageState();
}

class _AdminCreditsPageState extends State<AdminCreditsPage> {
  final ApiService _api = ApiService();

  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _error;
  final Set<int> _selected = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _api.getAdminCreditRequests();
      if (!mounted) return;
      setState(() {
        _requests = r;
        _loading = false;
        _selected.removeWhere((id) => !r.any((x) => x['id'] == id));
      });
      AdminBadges.instance.refresh(force: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = cleanError(e);
      });
    }
  }

  int _id(Map<String, dynamic> r) => (r['id'] as num).toInt();

  Future<void> _guard(Future<String> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final msg = await work();
      if (mounted) aToast(context, msg);
      await _load();
    } catch (e) {
      if (mounted) aToast(context, cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> r) => _guard(() async {
        await _api.approveCreditRequest(_id(r));
        return '${fmtInt(r['amount_requested'])} credits approved for ${r['username']}';
      });

  Future<void> _deny(Map<String, dynamic> r) async {
    final c = await aConfirm(
      context,
      title: 'Deny this request?',
      message:
          '${r['username']} asked for ${fmtInt(r['amount_requested'])} credits.',
      confirmLabel: 'Deny request',
      danger: true,
      noteHint: 'Optional note for the user',
    );
    if (c == null) return;
    await _guard(() async {
      await _api.denyCreditRequest(_id(r),
          adminNote: c.note.isEmpty ? null : c.note);
      return 'Request denied';
    });
  }

  Future<void> _bulkApprove() => _guard(() async {
        final ids = _selected.toList()..sort();
        final r = await _api.bulkApproveCreditRequests(ids);
        final skipped = r['skipped'] ?? 0;
        _selected.clear();
        return 'Approved ${r['approved'] ?? 0} request(s)'
            '${skipped is num && skipped > 0 ? ', skipped $skipped' : ''}';
      });

  Future<void> _bulkDeny() async {
    final c = await aConfirm(
      context,
      title: 'Deny ${_selected.length} request(s)?',
      message: 'The same note is attached to each one.',
      confirmLabel: 'Deny selected',
      danger: true,
      noteHint: 'Optional note for the users',
    );
    if (c == null) return;
    await _guard(() async {
      final ids = _selected.toList()..sort();
      final r = await _api.bulkDenyCreditRequests(ids,
          adminNote: c.note.isEmpty ? null : c.note);
      final skipped = r['skipped'] ?? 0;
      _selected.clear();
      return 'Denied ${r['denied'] ?? 0} request(s)'
          '${skipped is num && skipped > 0 ? ', skipped $skipped' : ''}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalAsked = _requests.fold<num>(
        0, (a, r) => a + ((r['amount_requested'] ?? 0) as num));
    final allSelected =
        _requests.isNotEmpty && _selected.length == _requests.length;
    return AdminScaffold(
      section: AdminSection.credits,
      title: 'Credit requests',
      subtitle: _loading
          ? 'Loading…'
          : _requests.isEmpty
              ? 'Nothing waiting for review'
              : '${_requests.length} waiting · ${fmtInt(totalAsked)} credits requested in total',
      actions: [
        AIconButton(Icons.refresh, 'Refresh',
            onPressed: _loading ? null : _load),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_requests.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _selected.isEmpty ? AC.surface : AC.selected,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _selected.isEmpty ? AC.border : AC.primary),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AButton(allSelected ? 'Clear selection' : 'Select all',
                      kind: AButtonKind.ghost,
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                allSelected
                                    ? _selected.clear()
                                    : _selected.addAll(_requests.map(_id));
                              })),
                  Text(
                      _selected.isEmpty
                          ? 'Tick requests to act on several at once'
                          : '${_selected.length} selected',
                      style: AT.small),
                  if (_selected.isNotEmpty) ...[
                    AButton('Approve selected',
                        icon: Icons.check,
                        kind: AButtonKind.success,
                        busy: _busy,
                        onPressed: _bulkApprove),
                    AButton('Deny selected',
                        icon: Icons.close,
                        kind: AButtonKind.danger,
                        onPressed: _busy ? null : _bulkDeny),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_error != null)
            AErrorBox(_error!, onRetry: _load)
          else
            APanel(
              padding: EdgeInsets.zero,
              child: _loading
                  ? const ALoading(height: 240)
                  : ATable<Map<String, dynamic>>(
                      minWidth: 900,
                      rows: _requests,
                      isSelected: (r) => _selected.contains(_id(r)),
                      onSelect: (r, v) => setState(() {
                        v ? _selected.add(_id(r)) : _selected.remove(_id(r));
                      }),
                      onRowTap: (r) => Navigator.of(context)
                          .pushNamed('/admin/users?user=${r['user_id']}'),
                      empty: const AEmpty(
                        icon: Icons.inbox_outlined,
                        title: 'No credit requests waiting',
                        message:
                            'When a user asks for credits from their wallet, it shows up here for approval.',
                      ),
                      columns: [
                        ACol('User', (r) {
                          final name = '${r['username'] ?? 'Unknown'}';
                          return ATwoLine(name,
                              secondary: '${r['email'] ?? ''}',
                              leading: AAvatar(name));
                        }, flex: 4),
                        ACol(
                            'Credits',
                            (r) => Text(fmtInt(r['amount_requested'] ?? 0),
                                style: AT.num
                                    .copyWith(fontWeight: FontWeight.w700)),
                            width: 100,
                            numeric: true),
                        ACol('Reason', (r) {
                          final reason = '${r['reason'] ?? ''}'.trim();
                          return Tooltip(
                            message: reason,
                            child: Text(reason.isEmpty ? 'No reason given' : reason,
                                style: reason.isEmpty ? AT.mute : AT.bodyDim),
                          );
                        }, flex: 5),
                        ACol(
                            'Requested',
                            (r) => Text(timeAgo(r['created_at']),
                                style: AT.bodyDim),
                            width: 116),
                        ACol(
                            '',
                            (r) => Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AButton('Approve',
                                        kind: AButtonKind.success,
                                        onPressed:
                                            _busy ? null : () => _approve(r)),
                                    const SizedBox(width: 6),
                                    AButton('Deny',
                                        kind: AButtonKind.danger,
                                        onPressed:
                                            _busy ? null : () => _deny(r)),
                                  ],
                                ),
                            width: 190),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
