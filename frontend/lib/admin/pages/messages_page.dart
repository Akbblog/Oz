import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/countries.dart';
import '../../services/api_service.dart';
import '../../widgets/country_flag_badge.dart';
import '../admin_kit.dart';
import '../admin_shell.dart';

/// Inbox for the contact form. New messages raise a badge in the sidebar;
/// opening one marks it read, and it is closed by "Replied" or "Archive".
class AdminMessagesPage extends StatefulWidget {
  final ApiService? api;
  const AdminMessagesPage({super.key, this.api});

  @override
  State<AdminMessagesPage> createState() => _AdminMessagesPageState();
}

class _AdminMessagesPageState extends State<AdminMessagesPage> {
  static const int _pageSize = 50;
  static const Map<String, String> _topicLabels = {
    'general': 'General',
    'sales': 'Sales',
    'support': 'Support',
    'billing': 'Billing',
    'partnership': 'Partnership',
    'feedback': 'Feedback',
  };

  late final ApiService _api = widget.api ?? ApiService();
  final TextEditingController _search = TextEditingController();

  String _status = 'open';
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _counts = {};
  int _total = 0;
  int _offset = 0;
  bool _loading = true;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) _offset = 0;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.getAdminContactMessages(
        status: _status == 'all' ? null : _status,
        q: _search.text,
        limit: _pageSize,
        offset: _offset,
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from((d['messages'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)));
        _total = (d['total'] as num?)?.toInt() ?? _rows.length;
        _counts = Map<String, dynamic>.from(d['counts'] ?? const {});
        _loading = false;
      });
      AdminBadges.instance.refresh(force: true);
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = cleanError(e);
      });
    }
  }

  int _n(String key) => (_counts[key] as num?)?.toInt() ?? 0;

  static Color _statusColor(String s) => switch (s) {
        'new' => AC.amber,
        'read' => AC.blue,
        'replied' => AC.green,
        _ => AC.grey,
      };

  static String _statusLabel(String s) => switch (s) {
        'new' => 'New',
        'read' => 'Read',
        'replied' => 'Replied',
        'archived' => 'Archived',
        _ => s,
      };

  Future<void> _open(Map<String, dynamic> m) async {
    var current = m;
    if (m['status'] == 'new') {
      try {
        current = await _api.updateAdminContactMessage((m['id'] as num).toInt(), status: 'read');
      } catch (_) {
        // Still show it; the status simply stays "new".
      }
    }
    if (!mounted) return;
    await showASheet<void>(
      context,
      width: 600,
      builder: (_) => _MessageRecord(api: _api, message: current),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final notLive = _error != null &&
        (_error!.toLowerCase().contains('not found') || _error!.contains('404'));
    return AdminScaffold(
      section: AdminSection.messages,
      title: 'Messages',
      subtitle: _loading && _counts.isEmpty
          ? 'Loading…'
          : '${_n('new')} new · ${_n('read')} read, waiting for a reply · ${_n('total')} in total',
      actions: [
        AIconButton(Icons.refresh, 'Refresh', onPressed: _loading ? null : () => _load()),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 300,
                child: ASearchField(
                  controller: _search,
                  hint: 'Search name, email, phone or text',
                  onSubmitted: (_) => _load(reset: true),
                ),
              ),
              ASegmented<String>(
                value: _status,
                options: const {
                  'open': 'To answer',
                  'new': 'New',
                  'replied': 'Replied',
                  'archived': 'Archived',
                  'all': 'All',
                },
                counts: {
                  'open': _n('new') + _n('read'),
                  'new': _n('new'),
                  'replied': _n('replied'),
                  'archived': _n('archived'),
                  'all': _n('total'),
                },
                onChanged: (v) {
                  setState(() => _status = v);
                  _load(reset: true);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (notLive)
            const APanel(
              child: AEmpty(
                icon: Icons.mark_email_unread_outlined,
                title: 'The inbox is not live yet',
                message:
                    'Messages are stored once the backend update with the contact form is running.',
              ),
            )
          else if (_error != null)
            AErrorBox(_error!, onRetry: () => _load())
          else
            APanel(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (_loading && _rows.isEmpty)
                    const ALoading(height: 260)
                  else
                    Opacity(
                      opacity: _loading ? 0.5 : 1,
                      child: ATable<Map<String, dynamic>>(
                        minWidth: 940,
                        rows: _rows,
                        onRowTap: _open,
                        empty: AEmpty(
                          icon: Icons.inbox_outlined,
                          title: _status == 'open' && _search.text.isEmpty
                              ? 'Nothing waiting for an answer'
                              : 'No messages here',
                          message: _status == 'open' && _search.text.isEmpty
                              ? 'When someone uses the contact form, their message appears here.'
                              : null,
                        ),
                        columns: [
                          ACol(
                              'When',
                              (m) => ATwoLine(timeAgo(m['created_at']),
                                  secondary: fmtDateTime(m['created_at'])),
                              width: 164),
                          ACol('From', (m) {
                            final name = '${m['name'] ?? ''}';
                            return ATwoLine(
                              name,
                              secondary: '${m['email'] ?? ''}',
                              leading: AAvatar(name, size: 28),
                            );
                          }, flex: 3),
                          ACol('Topic', (m) {
                            final t = '${m['topic'] ?? 'general'}';
                            return APill(_topicLabels[t] ?? t, AC.accent);
                          }, width: 116),
                          ACol('Message', (m) {
                            final text = '${m['message'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ');
                            final unread = m['status'] == 'new';
                            return Text(text,
                                style: unread
                                    ? AT.body.copyWith(fontWeight: FontWeight.w600)
                                    : AT.bodyDim);
                          }, flex: 5),
                          ACol('From where', (m) {
                            final iso = '${m['country'] ?? ''}';
                            if (iso.isEmpty) return const Text('–', style: AT.mute);
                            return Row(children: [
                              CountryFlagBadge(countryName: iso, size: 14),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(countryName(iso),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AT.bodyDim),
                              ),
                            ]);
                          }, flex: 2),
                          ACol('Status', (m) {
                            final s = '${m['status'] ?? ''}';
                            return APill(_statusLabel(s), _statusColor(s), dot: true);
                          }, width: 110),
                        ],
                      ),
                    ),
                  if (_total > _pageSize)
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
}

class _MessageRecord extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> message;
  const _MessageRecord({required this.api, required this.message});

  @override
  State<_MessageRecord> createState() => _MessageRecordState();
}

class _MessageRecordState extends State<_MessageRecord> {
  late Map<String, dynamic> m = widget.message;
  late final TextEditingController _note =
      TextEditingController(text: '${widget.message['admin_note'] ?? ''}');
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _update({String? status, bool saveNote = false, String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.api.updateAdminContactMessage(
        (m['id'] as num).toInt(),
        status: status,
        adminNote: saveNote ? _note.text.trim() : null,
      );
      if (!mounted) return;
      setState(() => m = updated);
      if (done != null) aToast(context, done);
      if (status == 'archived' || status == 'replied') Navigator.of(context).pop();
    } catch (e) {
      if (mounted) aToast(context, cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = '${m['name'] ?? ''}';
    final email = '${m['email'] ?? ''}';
    final phone = '${m['phone'] ?? ''}';
    final status = '${m['status'] ?? ''}';
    final iso = '${m['country'] ?? ''}';
    final city = '${m['city'] ?? ''}'.trim();
    final firstName = name.trim().split(RegExp(r'\s+')).first;
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
                Wrap(spacing: 6, runSpacing: 4, children: [
                  APill(_AdminMessagesPageState._statusLabel(status),
                      _AdminMessagesPageState._statusColor(status),
                      dot: true),
                  APill(
                      _AdminMessagesPageState._topicLabels['${m['topic']}'] ??
                          '${m['topic'] ?? 'General'}',
                      AC.accent),
                  if (m['user_id'] != null) const APill('Has an account', AC.purple),
                ]),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AButton('Reply by email',
                  icon: Icons.mail_outline,
                  kind: AButtonKind.primary,
                  onPressed: () => launchUrl(Uri(
                        scheme: 'mailto',
                        path: email,
                        query:
                            'subject=${Uri.encodeComponent('Re: your message to Infinity Leads')}&body=${Uri.encodeComponent('Hi $firstName,\n\n')}',
                      ))),
              if (phone.startsWith('+'))
                AButton('WhatsApp',
                    icon: Icons.chat_outlined,
                    onPressed: () => launchUrl(
                        Uri.parse(
                            'https://wa.me/${phone.replaceAll(RegExp(r'[^0-9]'), '')}'),
                        mode: LaunchMode.externalApplication)),
              if (m['user_id'] != null)
                AButton('Open user',
                    icon: Icons.person_outline,
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context)
                          .pushNamed('/admin/users?user=${m['user_id']}');
                    }),
            ],
          ),
          const ASectionLabel('Message'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AC.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AC.border),
            ),
            child: SelectableText('${m['message'] ?? ''}',
                style: AT.body.copyWith(fontSize: 14, height: 1.55)),
          ),
          const ASectionLabel('Contact'),
          AField('Email', value: email, copyable: true),
          AField('Phone', value: phone, copyable: true),
          AField('Account',
              value: m['user_id'] == null
                  ? 'Not signed in when writing'
                  : '${m['username'] ?? ''}  (ID ${m['user_id']})'),
          const ASectionLabel('Sent from'),
          AField('Received', value: fmtDateTime(m['created_at'])),
          AField('Location',
              child: iso.isEmpty
                  ? const Text('–', style: AT.mute)
                  : Row(children: [
                      CountryFlagBadge(countryName: iso, size: 14),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                            city.isEmpty
                                ? countryName(iso)
                                : '$city, ${countryName(iso)}',
                            style: AT.body),
                      ),
                    ])),
          AField('IP address',
              value: '${m['ip_address'] ?? ''}', copyable: true, mono: true),
          AField('Device', value: '${m['device'] ?? ''}'),
          AField('Page', value: '${m['page'] ?? ''}'),
          if (m['handled_at'] != null)
            AField('Closed',
                value:
                    '${fmtDateTime(m['handled_at'])} by ${m['handled_by_username'] ?? 'an admin'}'),
          const ASectionLabel('Your note (only admins see this)'),
          TextField(
            controller: _note,
            style: AT.body,
            cursorColor: AC.accent,
            minLines: 2,
            maxLines: 5,
            decoration: aInput(hint: 'What was agreed, when to follow up…'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: AButton('Save note',
                onPressed: _busy
                    ? null
                    : () => _update(saveNote: true, done: 'Note saved')),
          ),
        ],
      ),
      footer: Row(
        children: [
          if (status != 'archived')
            AButton('Archive',
                icon: Icons.archive_outlined,
                kind: AButtonKind.ghost,
                onPressed: _busy
                    ? null
                    : () => _update(
                        status: 'archived', saveNote: true, done: 'Archived')),
          const Spacer(),
          if (status == 'replied' || status == 'archived')
            AButton('Reopen',
                icon: Icons.undo,
                onPressed: _busy
                    ? null
                    : () => _update(status: 'read', done: 'Moved back to the inbox'))
          else
            AButton('Mark as replied',
                icon: Icons.check,
                kind: AButtonKind.success,
                busy: _busy,
                onPressed: () => _update(
                    status: 'replied', saveNote: true, done: 'Marked as replied')),
        ],
      ),
    );
  }
}
