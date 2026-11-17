import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';

import '../../core/crm/crm_filters.dart';
import '../../core/crm/crm_format.dart';
import '../../core/utils/server_time.dart';
import '../../providers/crm_provider.dart';
import '../../services/crm_api.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/crm/crm_record_dialogs.dart';
import '../../widgets/crm/crm_widgets.dart';

/// Lead / opportunity detail (`/crm/records/<id>`): header and next action
/// first; stage selector, Convert, Mark won / lost (reason required),
/// Reopen, Archive / Restore; business details (found online vs your
/// details), deal fields, people, tags, activities, notes (guarded against
/// losing unsaved text), sources and history. Every change sends the
/// record's `version`; a conflict reloads the record and says so.
class CrmRecordScreen extends StatefulWidget {
  final String recordId;
  final CrmApi? api;

  /// Clock for tests.
  final DateTime Function()? now;

  const CrmRecordScreen({super.key, required this.recordId, this.api, this.now});

  @override
  State<CrmRecordScreen> createState() => _CrmRecordScreenState();
}

class _CrmRecordScreenState extends State<CrmRecordScreen> {
  late final CrmApi _api = crmApiOf(context, widget.api);

  bool _loading = true;
  Object? _error;
  Map<String, dynamic> _r = const {};
  String? _busy;
  bool _conflict = false;

  // Business ("your details") form.
  bool _editBusiness = false;
  final Map<String, TextEditingController> _biz = {
    for (final k in ['title', 'phone', 'email', 'website', 'address', 'city', 'region', 'country']) k: TextEditingController(),
  };
  final Map<String, String?> _bizErrors = {};

  // Deal form.
  bool _editDeal = false;
  final _value = TextEditingController();
  final _currency = TextEditingController();
  final _probability = TextEditingController();
  String? _closeDate;
  final Map<String, String?> _dealErrors = {};

  // Notes.
  final _noteDraft = TextEditingController();
  String? _editingNoteId;
  final _noteEdit = TextEditingController();
  String _noteEditOriginal = '';

  // Older history.
  List<Map<String, dynamic>> _olderEvents = const [];
  String? _eventsCursor;
  bool _eventsExhausted = false;
  bool _loadingEvents = false;

  StreamSubscription<html.Event>? _beforeUnload;

  @override
  void initState() {
    super.initState();
    _load();
    _noteDraft.addListener(_onDirtyChanged);
    _noteEdit.addListener(_onDirtyChanged);
    if (kIsWeb) {
      _beforeUnload = html.window.onBeforeUnload.listen((event) {
        if (_dirty && event is html.BeforeUnloadEvent) event.returnValue = 'You have unsaved changes.';
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CrmProvider?>()?.loadWorkspace().catchError((_) => null);
    });
  }

  @override
  void dispose() {
    _beforeUnload?.cancel();
    for (final c in [..._biz.values, _value, _currency, _probability, _noteDraft, _noteEdit]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onDirtyChanged() {
    if (mounted) setState(() {});
  }

  bool get _dirty =>
      _noteDraft.text.trim().isNotEmpty ||
      (_editingNoteId != null && _noteEdit.text.trim() != _noteEditOriginal.trim()) ||
      _editBusiness ||
      _editDeal;

  String get _id => widget.recordId;
  int? get _version => crmIntOrNull(_r['version']);
  Map<String, dynamic> get _company => crmMap(_r['company']);
  bool get _open => crmStr(_r['outcome']).isEmpty || crmStr(_r['outcome']) == 'open';
  bool get _archived => _r['archived'] == true || crmStr(_r['archived_at']).isNotEmpty;

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final r = await _api.getRecord(_id);
      if (!mounted) return;
      setState(() {
        _r = r;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _r.isEmpty) _error = e;
      });
      if (silent && _r.isNotEmpty) crmSnack(context, crmActionError('Reloading the record', e), error: true);
    }
  }

  /// Runs one change, then reloads the record. A version conflict reloads
  /// and explains; other errors keep the page and show the server's words.
  Future<bool> _run(String what, Future<Object?> Function() call, {String? done}) async {
    if (_busy != null) return false;
    setState(() => _busy = what);
    try {
      await call();
      if (!mounted) return false;
      setState(() {
        _busy = null;
        _conflict = false;
      });
      final crm = context.read<CrmProvider?>();
      await _load(silent: true);
      unawaited(crm?.refreshCounts());
      if (done != null && mounted) crmSnack(context, done);
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _busy = null);
      if (crmErrorKind(e) == CrmErrorKind.conflict) {
        final current = e is CrmException ? e.current : null;
        setState(() {
          _conflict = true;
          if (current != null && crmStr(current['id']) == _id) _r = {..._r, ...current};
        });
        await _load(silent: true);
      } else {
        crmSnack(context, crmActionError(what, e), error: true);
      }
      return false;
    }
  }

  Future<void> _confirmLeave() async {
    final leave = await crmConfirm(
      context,
      title: 'Leave without saving?',
      body: 'You have a note or changes that are not saved yet.',
      confirmLabel: 'Discard and leave',
      cancelLabel: 'Keep editing',
      danger: true,
    );
    if (!leave || !mounted) return;
    _noteDraft.clear();
    _noteEdit.clear();
    setState(() {
      _editingNoteId = null;
      _editBusiness = false;
      _editDeal = false;
    });
    Navigator.of(context).maybePop();
  }

  // ---------------------------------------------------------- transitions

  Future<void> _moveStage(String stageId) async {
    final stage = _stageById(stageId);
    await _run('Changing the stage', () => _api.moveStage(_id, stageId, version: _version),
        done: 'Moved to ${crmStr(stage?['name'])}.');
  }

  Map<String, dynamic>? _stageById(String id) {
    for (final s in _stages) {
      if (crmStr(s['id']) == id) return s;
    }
    return null;
  }

  List<Map<String, dynamic>> get _stages => context.read<CrmProvider?>()?.stages ?? const [];

  Future<void> _convert() =>
      _run('Converting', () => _api.convertToOpportunity(_id, version: _version), done: 'Converted to an opportunity.');

  Future<void> _won() => _run('Marking won', () => _api.markWon(_id, version: _version), done: 'Marked won.');

  Future<void> _lost() async {
    final crm = context.read<CrmProvider?>();
    final choice = await showCrmLostDialog(context, reasons: crm?.lostReasons ?? const []);
    if (choice == null || !mounted) return;
    final ok = await _run(
      'Marking lost',
      () => _api.markLost(_id,
          reasonId: choice.reasonId, customReason: choice.customReason, note: choice.note, version: _version),
      done: 'Marked lost.',
    );
    if (ok && choice.customReason != null) unawaited(crm?.loadWorkspace(force: true).catchError((_) => null));
  }

  Future<void> _reopen() => _run('Reopening', () => _api.reopen(_id, version: _version), done: 'Reopened.');

  Future<void> _archive() async {
    final ok = await crmConfirm(
      context,
      title: 'Archive this record?',
      body: 'It leaves the pipeline and lists but nothing is deleted. You can restore it at any time.',
      confirmLabel: 'Archive',
    );
    if (!ok || !mounted) return;
    await _run('Archiving', () => _api.archive(_id, version: _version), done: 'Archived. Restore it from this page.');
  }

  Future<void> _restore() => _run('Restoring', () => _api.restore(_id, version: _version), done: 'Restored.');

  // ------------------------------------------------------------- editing

  void _startBusinessEdit() {
    final c = _company;
    _biz['title']!.text = crmStr(_r['title']);
    for (final k in ['phone', 'email', 'website', 'address', 'city', 'region', 'country']) {
      _biz[k]!.text = crmStr(c[k]);
    }
    setState(() {
      _bizErrors.clear();
      _editBusiness = true;
    });
  }

  Future<void> _saveBusiness() async {
    final errors = <String, String?>{
      'title': _biz['title']!.text.trim().isEmpty ? 'The record needs a title' : null,
      'email': crmValidateEmail(_biz['email']!.text),
      'website': crmValidateWebsite(_biz['website']!.text),
    };
    setState(() {
      _bizErrors
        ..clear()
        ..addAll(errors);
    });
    if (errors.values.any((e) => e != null)) return;
    String? v(String k) => _biz[k]!.text.trim().isEmpty ? null : _biz[k]!.text.trim();
    final ok = await _run(
      'Saving the details',
      () => _api.updateRecord(
        _id,
        {
          'title': _biz['title']!.text.trim(),
          'company': {for (final k in ['phone', 'email', 'website', 'address', 'city', 'region', 'country']) k: v(k)},
        },
        version: _version,
      ),
      done: 'Details saved.',
    );
    if (ok && mounted) setState(() => _editBusiness = false);
  }

  void _startDealEdit() {
    final v = crmNum(_r['value']);
    _value.text = v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());
    _currency.text = crmStr(_r['currency']);
    _probability.text = crmStr(_r['probability']);
    _closeDate = crmStr(_r['expected_close_date']).isEmpty ? null : crmStr(_r['expected_close_date']).substring(0, 10);
    setState(() {
      _dealErrors.clear();
      _editDeal = true;
    });
  }

  Future<void> _saveDeal() async {
    final valueSet = _value.text.trim().isNotEmpty;
    final errors = <String, String?>{
      'value': crmValidateValue(_value.text),
      'currency': crmValidateCurrency(_currency.text, valueSet: valueSet),
      'probability': crmValidateProbability(_probability.text),
    };
    setState(() {
      _dealErrors
        ..clear()
        ..addAll(errors);
    });
    if (errors.values.any((e) => e != null)) return;
    final value = valueSet ? num.parse(_value.text.trim().replaceAll(',', '')) : null;
    final prob = _probability.text.trim().isEmpty ? null : int.parse(_probability.text.trim().replaceAll('%', ''));
    final ok = await _run(
      'Saving the deal',
      () => _api.updateRecord(
        _id,
        {
          'value': value,
          'currency': _currency.text.trim().isEmpty ? null : _currency.text.trim().toUpperCase(),
          'probability': prob,
          'expected_close_date': _closeDate,
        },
        version: _version,
      ),
      done: 'Deal saved.',
    );
    if (ok && mounted) setState(() => _editDeal = false);
  }

  Future<void> _pickCloseDate() async {
    final n = DateTime.now();
    final initial = DateTime.tryParse(_closeDate ?? '') ?? n;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(n.year - 5),
      lastDate: DateTime(n.year + 10),
      helpText: 'Expected close date',
    );
    if (d != null) setState(() => _closeDate = crmDateParam(d));
  }

  // ----------------------------------------------------- people/tags/etc.

  Future<void> _addPerson() async {
    final p = await showCrmPersonDialog(context);
    if (p == null || !mounted) return;
    await _run('Adding the person', () => _api.addPerson(_id, p), done: 'Contact person added.');
  }

  Future<void> _editPerson(Map<String, dynamic> person) async {
    final p = await showCrmPersonDialog(context, existing: person);
    if (p == null || !mounted) return;
    await _run('Saving the person', () => _api.updatePerson(crmStr(person['id']), p), done: 'Contact person saved.');
  }

  Future<void> _removePerson(Map<String, dynamic> person) async {
    final ok = await crmConfirm(context,
        title: 'Remove ${crmStr(person['name'])}?',
        body: 'The person is removed from this business. The history keeps a note of it.',
        confirmLabel: 'Remove',
        danger: true);
    if (!ok || !mounted) return;
    await _run('Removing the person', () => _api.deletePerson(crmStr(person['id'])), done: 'Contact person removed.');
  }

  Future<void> _editTags() async {
    final crm = context.read<CrmProvider?>();
    final ids = await showCrmTagsDialog(
      context,
      api: _api,
      allTags: crm?.tags ?? crmList(_r['tags']),
      selected: [for (final t in crmList(_r['tags'])) crmStr(t['id'])],
      onCreated: (t) => crm?.rememberTag(t),
    );
    if (ids == null || !mounted) return;
    await _run('Saving tags', () => _api.setRecordTags(_id, ids), done: 'Tags saved.');
  }

  Future<void> _schedule() async {
    final input = await showCrmActivityDialog(context, now: widget.now?.call());
    if (input == null || !mounted) return;
    await _run(
      'Scheduling',
      () => _api.scheduleActivity(_id, type: input.type, subject: input.subject, dueAtUtc: input.dueAtUtc, notes: input.notes),
      done: 'Activity scheduled.',
    );
  }

  Future<void> _reschedule(Map<String, dynamic> a) async {
    final input = await showCrmActivityDialog(context, existing: a, now: widget.now?.call());
    if (input == null || !mounted) return;
    await _run(
      'Rescheduling',
      () => _api.updateActivity(crmStr(a['id']), {'subject': input.subject, 'due_at': input.dueAtUtc, 'notes': input.notes}),
      done: 'Activity rescheduled.',
    );
  }

  Future<void> _done(Map<String, dynamic> a) async {
    final outcome = await showCrmDoneDialog(context, a);
    if (outcome == null || !mounted) return;
    await _run('Marking done', () => _api.completeActivity(crmStr(a['id']), outcome: outcome), done: 'Activity done.');
  }

  Future<void> _reopenActivity(Map<String, dynamic> a) =>
      _run('Reopening the activity', () => _api.reopenActivity(crmStr(a['id'])), done: 'Activity reopened.');

  Future<void> _addNote() async {
    final body = _noteDraft.text.trim();
    if (body.isEmpty) return;
    final ok = await _run('Saving the note', () => _api.addNote(_id, body), done: 'Note saved.');
    if (ok) _noteDraft.clear();
  }

  Future<void> _saveNoteEdit() async {
    final id = _editingNoteId;
    final body = _noteEdit.text.trim();
    if (id == null || body.isEmpty) return;
    final ok = await _run('Saving the note', () => _api.editNote(id, body), done: 'Note saved.');
    if (ok && mounted) {
      setState(() => _editingNoteId = null);
      _noteEdit.clear();
    }
  }

  Future<void> _loadOlderEvents() async {
    if (_loadingEvents) return;
    setState(() => _loadingEvents = true);
    try {
      final cursor = _eventsCursor ?? (crmStr(_r['events_next_cursor']).isEmpty ? null : crmStr(_r['events_next_cursor']));
      final page = await _api.getEvents(_id, cursor: cursor);
      if (!mounted) return;
      final seen = {for (final e in [...crmList(_r['events']), ..._olderEvents]) crmStr(e['id'])};
      final fresh = page.items.where((e) => !seen.contains(crmStr(e['id']))).toList();
      setState(() {
        _olderEvents = [..._olderEvents, ...fresh];
        _eventsCursor = page.nextCursor;
        _eventsExhausted = !page.hasMore || fresh.isEmpty;
        _loadingEvents = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingEvents = false);
      crmSnack(context, crmActionError('Loading older history', e), error: true);
    }
  }

  /// `{name: ...}` or a plain string, else [fallback].
  static String _nameOf(Object? v, [Object? fallback]) {
    final n = v is Map ? crmStr(v['name'] ?? v['username']) : crmStr(v);
    return n.isNotEmpty ? n : crmStr(fallback);
  }

  Future<void> _launch(Uri uri, String what) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) crmSnack(context, "Couldn't open $what", error: true);
    } catch (_) {
      if (mounted) crmSnack(context, "Couldn't open $what", error: true);
    }
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    context.watch<CrmProvider?>();
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: CrmPageBody(
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          final wide = width >= 960;
          final children = <Widget>[_backLink()];
          if (_loading && _r.isEmpty) {
            children.add(const CrmLoading(label: 'Loading the record…'));
          } else if (_error != null) {
            children.add(CrmErrorView(
              error: _error,
              onRetry: _load,
              what: 'this record',
              notFoundTitle: "This record isn't available",
              notFoundBody: "It doesn't exist or isn't in your CRM. Records are private to each account.",
            ));
          } else {
            children.addAll(_content(wide));
          }
          return ListView(
            padding: crmPagePadding(width),
            children: [CrmContent(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))],
          );
        }),
      ),
    );
  }

  Widget _backLink() => Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
          onPressed: () {
            final nav = Navigator.of(context);
            if (nav.canPop()) {
              nav.maybePop();
            } else {
              AppNav.go(context, '/crm');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: const Text('Back'),
        ),
      );

  List<Widget> _content(bool wide) {
    const gap = SizedBox(height: 16);
    final header = _header();
    final next = _nextAction();
    final business = _businessCard();
    final deal = _dealCard();
    final people = _peopleCard();
    final tags = _tagsCard();
    final sources = _sourcesCard();
    final activities = _activitiesCard();
    final notes = _notesCard();
    final history = _historyCard();
    return [
      if (_conflict) ...[
        SearchNotice(
          icon: Icons.sync_problem_rounded,
          title: 'This record changed somewhere else.',
          body: 'We loaded the latest version (another tab or action saved first). '
              'Your unsaved text is still here; check it and save again.',
          action: TextButton(
            style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
            onPressed: () => setState(() => _conflict = false),
            child: const Text('OK'),
          ),
        ),
        gap,
      ],
      header,
      gap,
      next,
      gap,
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [activities, gap, notes, gap, history]),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [business, gap, deal, gap, people, gap, tags, gap, sources],
              ),
            ),
          ],
        )
      else ...[
        business,
        gap,
        deal,
        gap,
        people,
        gap,
        tags,
        gap,
        activities,
        gap,
        notes,
        gap,
        sources,
        gap,
        history,
      ],
      const SizedBox(height: 24),
    ];
  }

  Widget _header() {
    final title = crmRecordTitle(_r);
    final place = crmPlace(_company);
    final stages = _stages;
    final openStages = stages.where((s) => crmStr(s['outcome_kind']) != 'won').toList();
    final stageId = crmStr(crmMap(_r['stage'])['id']);
    final isLead = crmStr(_r['type']) != 'opportunity';
    final busy = _busy != null;

    final stageSelector = _open && !_archived && openStages.isNotEmpty
        ? Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: UiTokens.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: UiTokens.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: openStages.any((s) => crmStr(s['id']) == stageId) ? stageId : null,
                hint: Text(crmStageName(_r).isEmpty ? 'Stage' : crmStageName(_r),
                    style: const TextStyle(color: UiTokens.text)),
                dropdownColor: UiTokens.card,
                style: const TextStyle(color: UiTokens.text, fontSize: 14, fontWeight: FontWeight.w600),
                iconEnabledColor: UiTokens.textSecondary,
                onChanged: busy ? null : (v) => v == null || v == stageId ? null : _moveStage(v),
                items: [
                  for (final s in openStages)
                    DropdownMenuItem(value: crmStr(s['id']), child: Text('Stage: ${crmStr(s['name'])}')),
                ],
              ),
            ),
          )
        : null;

    final actions = <Widget>[
      if (stageSelector != null) stageSelector,
      if (_open && !_archived && isLead)
        OutlinedButton.icon(
          style: searchSecondaryButtonStyle(),
          onPressed: busy ? null : _convert,
          icon: const Icon(Icons.trending_up_rounded, size: 18),
          label: const Text('Convert to opportunity'),
        ),
      if (_open && !_archived)
        FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: UiTokens.completedFg, foregroundColor: Colors.black, minimumSize: const Size(48, 48)),
          onPressed: busy ? null : _won,
          icon: const Icon(Icons.emoji_events_outlined, size: 18),
          label: const Text('Mark won'),
        ),
      if (_open && !_archived)
        OutlinedButton.icon(
          style: searchSecondaryButtonStyle().copyWith(foregroundColor: const WidgetStatePropertyAll(UiTokens.failedFg)),
          onPressed: busy ? null : _lost,
          icon: const Icon(Icons.do_not_disturb_on_outlined, size: 18),
          label: const Text('Mark lost…'),
        ),
      if (!_open && !_archived)
        FilledButton.icon(
          style: searchPrimaryButtonStyle(),
          onPressed: busy ? null : _reopen,
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
          label: const Text('Reopen'),
        ),
      if (_archived)
        FilledButton.icon(
          style: searchPrimaryButtonStyle(),
          onPressed: busy ? null : _restore,
          icon: const Icon(Icons.unarchive_outlined, size: 18),
          label: const Text('Restore'),
        )
      else
        PopupMenuButton<String>(
          tooltip: 'More actions',
          color: UiTokens.card,
          enabled: !busy,
          onSelected: (v) {
            if (v == 'archive') _archive();
            if (v == 'copy') copyWithSnack(context, Uri.base.resolve(crmRecordRoute(_id)).toString(), message: 'Link copied');
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'copy', child: Text('Copy link')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'archive', child: Text('Archive…')),
          ],
          child: const SizedBox(
            width: 48,
            height: 48,
            child: Icon(Icons.more_horiz_rounded, color: UiTokens.textSecondary),
          ),
        ),
    ];

    final lostReason = _nameOf(_r['lost_reason']);
    final closedAt = parseServerTimeLocal(_r['closed_at']);

    return SearchCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            CrmOutcomeBadge(record: _r),
            CrmBadge(label: crmTypeName(_r['type']), icon: isLead ? Icons.person_search_outlined : Icons.trending_up_rounded),
            if (crmStageName(_r).isNotEmpty) CrmBadge(label: crmStageName(_r), icon: Icons.view_column_outlined),
          ]),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text(title, style: const TextStyle(color: UiTokens.text, fontSize: 22, fontWeight: FontWeight.w700)),
          ),
          if (place.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(place, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 14)),
            ),
          if (crmStr(_r['outcome']) == 'lost')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                [
                  'Lost${lostReason.isEmpty ? '' : ': $lostReason'}',
                  if (crmStr(_r['lost_note']).isNotEmpty) crmStr(_r['lost_note']),
                  if (closedAt != null) 'closed ${formatLocalDateTime(closedAt)}',
                ].join(' · '),
                style: const TextStyle(color: UiTokens.failedFg, fontSize: 13.5),
              ),
            ),
          if (crmStr(_r['outcome']) == 'won' && closedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Won · closed ${formatLocalDateTime(closedAt)}',
                  style: const TextStyle(color: UiTokens.completedFg, fontSize: 13.5)),
            ),
          if (_archived)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Archived: hidden from the pipeline and lists. Restore it to work on it again.',
                  style: TextStyle(color: UiTokens.textSecondary, fontSize: 13.5)),
            ),
          if (!_open && !_archived)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Reopen it to change the stage.', style: TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: actions),
          if (_busy != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text('$_busy…', style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _activities {
    final list = crmList(_r['activities']);
    int rank(Map<String, dynamic> a) => crmActivityDone(a) ? 1 : 0;
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final da = parseServerTime(a['due_at'])?.millisecondsSinceEpoch ?? 0;
      final db = parseServerTime(b['due_at'])?.millisecondsSinceEpoch ?? 0;
      return rank(a) == 0 ? da.compareTo(db) : db.compareTo(da);
    });
    return list;
  }

  Widget _nextAction() {
    final open = _activities.where((a) => !crmActivityDone(a)).toList();
    final next = open.isEmpty ? null : open.first;
    return SearchCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CrmSectionTitle('Next action'),
          if (next == null) ...[
            const Text('No next activity is planned.', style: TextStyle(color: UiTokens.textSecondary, fontSize: 14)),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: searchPrimaryButtonStyle(),
              onPressed: _busy == null ? _schedule : null,
              icon: const Icon(Icons.add_alarm_rounded, size: 18),
              label: const Text('Schedule an activity'),
            ),
          ] else
            _activityTile(next, emphasise: true),
        ],
      ),
    );
  }

  Widget _activityTile(Map<String, dynamic> a, {bool emphasise = false}) {
    final done = crmActivityDone(a);
    final busy = _busy != null;
    final subject = crmStr(a['subject']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: ExcludeSemantics(child: Icon(crmActivityIcon(a['type']), size: 18, color: UiTokens.textSecondary)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${crmActivityTypeLabel(a['type'])}: $subject',
                        style: TextStyle(
                          color: UiTokens.text,
                          fontSize: emphasise ? 15 : 14,
                          fontWeight: FontWeight.w600,
                          decoration: done ? TextDecoration.lineThrough : null,
                          decorationColor: UiTokens.textSecondary,
                        )),
                    const SizedBox(height: 4),
                    CrmDueBadge(activity: a),
                    if (crmStr(a['notes']).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(crmStr(a['notes']), style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
                      ),
                    if (done && crmStr(a['outcome']).isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('Outcome: ${crmStr(a['outcome'])}',
                            style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
                      ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Wrap(spacing: 4, children: [
              if (!done)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                  onPressed: busy ? null : () => _done(a),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text('Mark done', semanticsLabel: 'Mark done: $subject'),
                ),
              if (!done)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                  onPressed: busy ? null : () => _reschedule(a),
                  icon: const Icon(Icons.update_rounded, size: 18),
                  label: Text('Reschedule', semanticsLabel: 'Reschedule: $subject'),
                ),
              if (done)
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                  onPressed: busy ? null : () => _reopenActivity(a),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: Text('Reopen', semanticsLabel: 'Reopen activity: $subject'),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _activitiesCard() {
    final list = _activities;
    return SearchCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CrmSectionTitle(
            'Activities',
            trailing: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
              onPressed: _busy == null ? _schedule : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Schedule'),
            ),
          ),
          if (list.isEmpty)
            const Text('No activities yet. Schedule a call, email, meeting, message or task.',
                style: TextStyle(color: UiTokens.textSecondary, fontSize: 13.5))
          else
            for (final a in list) _activityTile(a),
        ],
      ),
    );
  }

  Widget _notesCard() {
    final notes = crmList(_r['notes']);
    return SearchCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CrmSectionTitle('Notes'),
          TextField(
            controller: _noteDraft,
            minLines: 2,
            maxLines: 6,
            style: const TextStyle(color: UiTokens.text),
            decoration: crmInputDecoration('Add a note', hint: 'What did you learn? What was agreed?'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              style: searchPrimaryButtonStyle(),
              onPressed: _busy == null && _noteDraft.text.trim().isNotEmpty ? _addNote : null,
              child: const Text('Save note'),
            ),
          ),
          if (notes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('No notes yet.', style: TextStyle(color: UiTokens.textSecondary, fontSize: 13.5)),
            ),
          for (final n in notes) _noteTile(n),
        ],
      ),
    );
  }

  Widget _noteTile(Map<String, dynamic> n) {
    final id = crmStr(n['id']);
    final editing = _editingNoteId == id;
    final author = _nameOf(n['author'], n['author_name']);
    final edited = crmStr(n['edited_at']).isNotEmpty;
    final created = parseServerTimeLocal(n['created_at']);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: UiTokens.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: UiTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (editing) ...[
            TextField(
              controller: _noteEdit,
              minLines: 2,
              maxLines: 8,
              autofocus: true,
              style: const TextStyle(color: UiTokens.text),
              decoration: crmInputDecoration('Edit note'),
            ),
            const SizedBox(height: 6),
            Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                onPressed: () {
                  _noteEdit.clear();
                  setState(() => _editingNoteId = null);
                },
                child: const Text('Cancel'),
              ),
              FilledButton(style: searchPrimaryButtonStyle(), onPressed: _busy == null ? _saveNoteEdit : null, child: const Text('Save')),
            ]),
          ] else
            SelectableText(crmStr(n['body']), style: const TextStyle(color: UiTokens.text, fontSize: 14, height: 1.4)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: created == null ? '' : crmFullLocal(created),
                  child: Text(
                    [
                      if (author.isNotEmpty) author,
                      if (created != null) formatLocalDateTime(created),
                      if (edited) 'edited',
                    ].join(' · '),
                    style: const TextStyle(color: UiTokens.textMuted, fontSize: 12.5),
                  ),
                ),
              ),
              if (!editing && n['can_edit'] != false)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 40)),
                  onPressed: () {
                    _noteEditOriginal = crmStr(n['body']);
                    _noteEdit.text = _noteEditOriginal;
                    setState(() => _editingNoteId = id);
                  },
                  child: const Text('Edit', semanticsLabel: 'Edit note'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Widget? action}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
            ),
            Expanded(
              child: Text(value.isEmpty ? 'Not set' : value,
                  style: TextStyle(color: value.isEmpty ? UiTokens.textMuted : UiTokens.text, fontSize: 13.5)),
            ),
            if (action != null) action,
          ],
        ),
      );

  Widget _openButton(String label, Uri? uri, String what) => uri == null
      ? const SizedBox.shrink()
      : TextButton(
          style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 36), padding: const EdgeInsets.symmetric(horizontal: 8)),
          onPressed: () => _launch(uri, what),
          child: Text(label, semanticsLabel: '$label $what'),
        );

  Uri? _web(String v) {
    final u = Uri.tryParse(v.trim());
    return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty ? u : null;
  }

  Widget _businessCard() {
    final c = _company;
    final snap = crmMap(c['source_snapshot']);
    final phone = crmStr(c['phone']);
    final email = crmStr(c['email']);
    final site = crmStr(c['website']);
    final maps = crmStr(c['maps_url']);
    final busy = _busy != null;

    Widget field(String key, String label, {TextInputType? keyboard, String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _biz[key],
            keyboardType: keyboard,
            style: const TextStyle(color: UiTokens.text),
            decoration: crmInputDecoration(label, hint: hint, error: _bizErrors[key]),
          ),
        );

    return SearchCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CrmSectionTitle(
            'Business',
            trailing: _editBusiness
                ? null
                : TextButton(
                    style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                    onPressed: busy ? null : _startBusinessEdit,
                    child: const Text('Edit', semanticsLabel: 'Edit business details'),
                  ),
          ),
          if (_editBusiness) ...[
            field('title', 'Record title *'),
            field('phone', 'Phone', keyboard: TextInputType.phone),
            field('email', 'Email', keyboard: TextInputType.emailAddress),
            field('website', 'Website', keyboard: TextInputType.url, hint: 'https://example.com'),
            field('address', 'Address'),
            field('city', 'City'),
            field('region', 'Region / state'),
            field('country', 'Country'),
            Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                onPressed: () => setState(() => _editBusiness = false),
                child: const Text('Cancel'),
              ),
              FilledButton(style: searchPrimaryButtonStyle(), onPressed: busy ? null : _saveBusiness, child: const Text('Save details')),
            ]),
          ] else ...[
            const Text('Your details', style: TextStyle(color: UiTokens.text, fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _row('Name', crmStr(c['name'])),
            _row('Phone', phone, action: phone.isEmpty ? null : _openButton('Call', Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), '')), phone)),
            _row('Email', email, action: email.isEmpty ? null : _openButton('Email', Uri(scheme: 'mailto', path: email), email)),
            _row('Website', site, action: _openButton('Open', _web(site), 'website')),
            _row('Address', crmStr(c['address']), action: _openButton('Map', _web(maps), 'in Google Maps')),
            _row('Place', crmPlace(c)),
          ],
          if (snap.isNotEmpty) ...[
            const Divider(color: UiTokens.border, height: 24),
            Row(children: [
              const Icon(Icons.travel_explore_rounded, size: 16, color: UiTokens.textSecondary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Found online', style: TextStyle(color: UiTokens.text, fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 2, bottom: 6),
              child: Text('As found by the search. Not verified, and never overwritten by your edits.',
                  style: TextStyle(color: UiTokens.textSecondary, fontSize: 12.5)),
            ),
            for (final e in const [
              ('business_name', 'Name'),
              ('category', 'Category'),
              ('phone', 'Phone'),
              ('email', 'Email'),
              ('website', 'Website'),
              ('address', 'Address'),
              ('city', 'City'),
              ('state', 'Region'),
            ])
              if (crmStr(snap[e.$1]).isNotEmpty && crmStr(snap[e.$1]) != 'N/A') _row(e.$2, crmStr(snap[e.$1])),
            if (_web(crmStr(snap['google_maps_url'])) != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _openButton('Open in Google Maps', _web(crmStr(snap['google_maps_url'])), ''),
              ),
          ],
        ],
      ),
    );
  }

  Widget _dealCard() {
    final busy = _busy != null;
    final value = crmMoney(_r['value'], _r['currency']);
    final prob = crmStr(_r['probability']);
    final close = crmStr(_r['expected_close_date']);
    return SearchCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CrmSectionTitle(
            'Deal',
            trailing: _editDeal
                ? null
                : TextButton(
                    style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                    onPressed: busy ? null : _startDealEdit,
                    child: const Text('Edit', semanticsLabel: 'Edit deal value, probability and close date'),
                  ),
          ),
          if (_editDeal) ...[
            TextField(
              controller: _value,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: UiTokens.text),
              decoration: crmInputDecoration('Expected value', hint: 'e.g. 1500', error: _dealErrors['value']),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _currency,
              textCapitalization: TextCapitalization.characters,
              maxLength: 3,
              style: const TextStyle(color: UiTokens.text),
              decoration: crmInputDecoration('Currency', hint: 'CAD, USD, EUR…', error: _dealErrors['currency']),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _probability,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: UiTokens.text),
              decoration: crmInputDecoration('Probability (%)', hint: '0–100', error: _dealErrors['probability']),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                style: searchSecondaryButtonStyle(),
                onPressed: _pickCloseDate,
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(_closeDate == null ? 'Expected close date' : 'Close: ${crmDateLabel(_closeDate)}'),
              ),
              if (_closeDate != null)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                  onPressed: () => setState(() => _closeDate = null),
                  child: const Text('Clear date'),
                ),
            ]),
            const SizedBox(height: 10),
            Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                onPressed: () => setState(() => _editDeal = false),
                child: const Text('Cancel'),
              ),
              FilledButton(style: searchPrimaryButtonStyle(), onPressed: busy ? null : _saveDeal, child: const Text('Save deal')),
            ]),
          ] else ...[
            _row('Value', value),
            _row('Probability', prob.isEmpty ? '' : '$prob%'),
            _row('Close date', close.isEmpty ? '' : crmDateLabel(close)),
            const Text('Blank values stay blank; nothing is estimated.',
                style: TextStyle(color: UiTokens.textMuted, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _peopleCard() {
    final people = crmList(_r['people']);
    final busy = _busy != null;
    return SearchCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CrmSectionTitle(
            'People',
            trailing: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
              onPressed: busy ? null : _addPerson,
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Add', semanticsLabel: 'Add a contact person'),
            ),
          ),
          if (people.isEmpty)
            const Text('No contact people yet. Add the people you talk to.',
                style: TextStyle(color: UiTokens.textSecondary, fontSize: 13.5)),
          for (final p in people)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 12, right: 8),
                    child: Icon(Icons.person_outline_rounded, size: 18, color: UiTokens.textSecondary),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            Text(crmStr(p['name']), style: const TextStyle(color: UiTokens.text, fontWeight: FontWeight.w600)),
                            if (p['is_primary'] == true) const CrmBadge(label: 'Primary', icon: Icons.star_outline_rounded),
                          ]),
                          Text(
                            [crmStr(p['role']), crmStr(p['phone']), crmStr(p['email'])].where((s) => s.isNotEmpty).join(' · '),
                            style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit ${crmStr(p['name'])}',
                    onPressed: busy ? null : () => _editPerson(p),
                    icon: const Icon(Icons.edit_outlined, size: 18, color: UiTokens.accent),
                  ),
                  IconButton(
                    tooltip: 'Remove ${crmStr(p['name'])}',
                    onPressed: busy ? null : () => _removePerson(p),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: UiTokens.failedFg),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _tagsCard() {
    final tags = crmList(_r['tags']);
    return SearchCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CrmSectionTitle(
            'Tags',
            trailing: TextButton(
              style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
              onPressed: _busy == null ? _editTags : null,
              child: const Text('Edit', semanticsLabel: 'Edit tags'),
            ),
          ),
          if (tags.isEmpty)
            const Text('No tags.', style: TextStyle(color: UiTokens.textSecondary, fontSize: 13.5))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in tags) CrmBadge(label: crmStr(t['name']), icon: Icons.sell_outlined, fg: UiTokens.text),
            ]),
        ],
      ),
    );
  }

  Widget _sourcesCard() {
    final sources = crmList(_r['sources']);
    return SearchCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CrmSectionTitle(sources.length > 1 ? 'Found in ${sources.length} searches' : 'Source'),
          if (sources.isEmpty)
            const Text('Created manually.', style: TextStyle(color: UiTokens.textSecondary, fontSize: 13.5)),
          for (final s in sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      crmStr(s['category']).isEmpty ? 'Search' : crmStr(s['category']),
                      crmPlace(s),
                    ].where((x) => x.isNotEmpty).join(' · '),
                    style: const TextStyle(color: UiTokens.text, fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  Text('Added ${crmWhen(s['imported_at'])}', style: const TextStyle(color: UiTokens.textSecondary, fontSize: 12.5)),
                  if (s['available'] == false || crmStr(s['job_id']).isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text('Original search no longer available',
                          style: TextStyle(color: UiTokens.textMuted, fontSize: 12.5, fontStyle: FontStyle.italic)),
                    )
                  else
                    TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: UiTokens.accent, minimumSize: const Size(48, 40), padding: EdgeInsets.zero),
                      onPressed: () => AppNav.go(context, '/searches/${Uri.encodeComponent(crmStr(s['job_id']))}'),
                      child: const Text('Open the search'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _historyCard() {
    final events = [...crmList(_r['events']), ..._olderEvents];
    final mayHaveMore = !_eventsExhausted &&
        (crmStr(_r['events_next_cursor']).isNotEmpty || _eventsCursor != null || crmList(_r['events']).length >= 50);
    return SearchCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CrmSectionTitle('History'),
          if (events.isEmpty) const Text('No history yet.', style: TextStyle(color: UiTokens.textSecondary, fontSize: 13.5)),
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 6, right: 10),
                    decoration: const BoxDecoration(color: UiTokens.accent, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(crmEventText(e), style: const TextStyle(color: UiTokens.text, fontSize: 13.5)),
                        Builder(builder: (context) {
                          final at = parseServerTimeLocal(e['occurred_at'] ?? e['created_at']);
                          final actor = _nameOf(e['actor'], e['actor_name']);
                          return Tooltip(
                            message: at == null ? '' : crmFullLocal(at),
                            child: Text(
                              [if (actor.isNotEmpty) actor, if (at != null) formatLocalDateTime(at)].join(' · '),
                              style: const TextStyle(color: UiTokens.textMuted, fontSize: 12.5),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (mayHaveMore)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _loadingEvents
                  ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
                  : TextButton(
                      style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
                      onPressed: _loadOlderEvents,
                      child: const Text('Show older history'),
                    ),
            ),
        ],
      ),
    );
  }
}
