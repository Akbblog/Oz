import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/crm/crm_filters.dart';
import '../../core/crm/crm_format.dart';
import '../../services/crm_api.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/crm/crm_widgets.dart';

/// Contacts (`/crm/contacts?q=`): the people added to CRM businesses, with
/// their business and a link to its record. Server search, "Load more".
class CrmContactsScreen extends StatefulWidget {
  final Map<String, String> initialQuery;
  final CrmApi? api;

  const CrmContactsScreen({super.key, this.initialQuery = const {}, this.api});

  @override
  State<CrmContactsScreen> createState() => _CrmContactsScreenState();
}

class _CrmContactsScreenState extends State<CrmContactsScreen> {
  late final CrmApi _api = crmApiOf(context, widget.api);
  late String _q = (widget.initialQuery['q'] ?? '').trim();
  late final TextEditingController _query = TextEditingController(text: _q);
  Timer? _debounce;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  List<Map<String, dynamic>> _items = const [];
  String? _cursor;
  int _total = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.listPeople(q: _q.isEmpty ? null : _q);
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = page.items;
        _cursor = page.nextCursor;
        _total = page.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _cursor == null) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    try {
      final page = await _api.listPeople(q: _q.isEmpty ? null : _q, cursor: _cursor);
      if (!mounted || generation != _generation) return;
      setState(() {
        final seen = {for (final p in _items) crmStr(p['id'])};
        _items = [..._items, ...page.items.where((p) => !seen.contains(crmStr(p['id'])))];
        _cursor = page.nextCursor;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showSearchSnack(context, crmActionError('Loading more contacts', e), error: true);
    }
  }

  void _setQuery(String v) {
    final q = v.trim();
    if (q == _q) return;
    _q = q;
    crmReplaceUrl(crmRoute('/crm/contacts', q.isEmpty ? const {} : {'q': q}));
    _load();
  }

  static String _recordId(Map<String, dynamic> p) {
    final r = p['record'];
    if (r is Map && crmStr(r['id']).isNotEmpty) return crmStr(r['id']);
    return crmStr(p['record_id']);
  }

  @override
  Widget build(BuildContext context) {
    return CrmPageBody(
      tab: CrmTab.contacts,
      child: LayoutBuilder(builder: (context, constraints) {
        return ListView(
          padding: crmPagePadding(constraints.maxWidth),
          children: [
            CrmContent(
              maxWidth: 960,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _query,
                    textInputAction: TextInputAction.search,
                    onChanged: (v) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 350), () => _setQuery(v));
                    },
                    onSubmitted: (v) {
                      _debounce?.cancel();
                      _setQuery(v);
                    },
                    style: const TextStyle(color: UiTokens.text, fontSize: 14),
                    decoration: crmInputDecoration(
                      'Search people',
                      hint: 'Name, role, phone, email or business',
                      prefix: const Icon(Icons.search_rounded, size: 20, color: UiTokens.textMuted),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _body(),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) return const CrmLoading(label: 'Loading contacts…');
    if (_error != null) return CrmErrorView(error: _error, onRetry: _load, what: 'your contacts');
    if (_items.isEmpty) {
      return CrmEmptyView(
        title: _q.isEmpty ? 'No contact people yet' : 'No people match "$_q"',
        icon: Icons.people_outline_rounded,
        body: _q.isEmpty
            ? 'Add the people you talk to from a record page (People → Add). '
                'Business phone numbers and emails found online stay with the business.'
            : null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _items.length >= _total
                ? plural(_items.length, 'person', 'people')
                : '${formatCount(_items.length)} of ${plural(_total, 'person', 'people')}',
            style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13),
          ),
        ),
        for (final p in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SearchCard(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(
                children: [
                  const ExcludeSemantics(child: Icon(Icons.person_outline_rounded, color: UiTokens.textSecondary)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                          Text(crmStr(p['name']), style: const TextStyle(color: UiTokens.text, fontWeight: FontWeight.w700)),
                          if (p['is_primary'] == true) const CrmBadge(label: 'Primary', icon: Icons.star_outline_rounded),
                        ]),
                        Text(
                          [crmStr(p['role']), crmStr(p['phone']), crmStr(p['email'])].where((s) => s.isNotEmpty).join(' · '),
                          style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13),
                        ),
                        if (crmStr(crmMap(p['company'])['name']).isNotEmpty)
                          Text(crmStr(crmMap(p['company'])['name']),
                              style: const TextStyle(color: UiTokens.textMuted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  if (_recordId(p).isNotEmpty)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                      onPressed: () => Navigator.of(context).pushNamed(crmRecordRoute(_recordId(p))),
                      child: Text('Open record', semanticsLabel: 'Open the record of ${crmStr(p['name'])}'),
                    ),
                ],
              ),
            ),
          ),
        if (_cursor != null)
          Center(
            child: _loadingMore
                ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())
                : OutlinedButton(style: searchSecondaryButtonStyle(), onPressed: _loadMore, child: const Text('Load more')),
          ),
      ],
    );
  }
}
