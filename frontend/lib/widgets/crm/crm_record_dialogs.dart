import 'package:flutter/material.dart';

import '../../core/crm/crm_format.dart';
import '../../services/crm_api.dart';
import '../app_shell_common.dart';
import 'crm_widgets.dart';

TextButton _cancel(BuildContext context) => TextButton(
      style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
      onPressed: () => Navigator.of(context).pop(),
      child: const Text('Cancel'),
    );

Widget _dialogError(String? error) => error == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Semantics(
          liveRegion: true,
          child: Text(error, style: const TextStyle(color: UiTokens.failedFg, fontSize: 13.5)),
        ),
      );

// -------------------------------------------------------------- lost

/// Choice made in "Mark lost".
class CrmLostChoice {
  final String? reasonId;
  final String? customReason;
  final String? note;

  const CrmLostChoice({this.reasonId, this.customReason, this.note});
}

/// "Mark lost": a reason is required (a workspace reason or a custom one),
/// the note is optional.
Future<CrmLostChoice?> showCrmLostDialog(BuildContext context, {required List<Map<String, dynamic>> reasons}) =>
    showDialog<CrmLostChoice>(context: context, builder: (_) => _LostDialog(reasons: reasons));

class _LostDialog extends StatefulWidget {
  final List<Map<String, dynamic>> reasons;

  const _LostDialog({required this.reasons});

  @override
  State<_LostDialog> createState() => _LostDialogState();
}

class _LostDialogState extends State<_LostDialog> {
  static const _custom = '__custom__';
  String? _choice;
  final _customText = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _customText.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (_choice == null) {
      setState(() => _error = 'Choose a reason. A lost record always has one.');
      return;
    }
    if (_choice == _custom) {
      final t = _customText.text.trim();
      if (t.isEmpty) {
        setState(() => _error = 'Type your reason, or pick one from the list.');
        return;
      }
      if (t.length > 80) {
        setState(() => _error = 'Keep the reason under 80 characters.');
        return;
      }
      Navigator.of(context).pop(CrmLostChoice(customReason: t, note: _note.text.trim()));
      return;
    }
    Navigator.of(context).pop(CrmLostChoice(reasonId: _choice, note: _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: UiTokens.card,
      title: const Text('Mark as lost', style: TextStyle(color: UiTokens.text)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: RadioGroup<String>(
            groupValue: _choice,
            onChanged: (v) => setState(() {
              _choice = v;
              _error = null;
            }),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Why was it lost? You can reopen it later; the history is kept.',
                    style: TextStyle(color: UiTokens.textSecondary, fontSize: 13.5)),
                const SizedBox(height: 8),
                for (final r in widget.reasons)
                  RadioListTile<String>(
                    value: crmStr(r['id']),
                    title: Text(crmStr(r['name']), style: const TextStyle(color: UiTokens.text)),
                    contentPadding: EdgeInsets.zero,
                    dense: false,
                  ),
                const RadioListTile<String>(
                  value: _custom,
                  title: Text('Another reason (type it)', style: TextStyle(color: UiTokens.text)),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_choice == _custom)
                  TextField(
                    controller: _customText,
                    autofocus: true,
                    style: const TextStyle(color: UiTokens.text),
                    decoration: crmInputDecoration('Your reason', helper: 'Saved as a reason you can pick again.'),
                  ),
                const SizedBox(height: 10),
                TextField(
                  controller: _note,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(color: UiTokens.text),
                  decoration: crmInputDecoration('Note (optional)'),
                ),
                _dialogError(_error),
              ],
            ),
          ),
        ),
      ),
      actions: [
        _cancel(context),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: UiTokens.failedFg, foregroundColor: Colors.black, minimumSize: const Size(48, 48)),
          onPressed: _submit,
          child: const Text('Mark lost'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------- activity

/// Values of the activity dialog; [dueAtUtc] is UTC ISO-8601 with `Z`.
class CrmActivityInput {
  final String type;
  final String subject;
  final String dueAtUtc;
  final String notes;

  const CrmActivityInput({required this.type, required this.subject, required this.dueAtUtc, this.notes = ''});
}

/// Schedule (no [existing]) or reschedule an activity. Date and time are
/// picked in local time and returned as UTC.
Future<CrmActivityInput?> showCrmActivityDialog(BuildContext context, {Map<String, dynamic>? existing, DateTime? now}) =>
    showDialog<CrmActivityInput>(context: context, builder: (_) => _ActivityDialog(existing: existing, now: now));

class _ActivityDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final DateTime? now;

  const _ActivityDialog({this.existing, this.now});

  @override
  State<_ActivityDialog> createState() => _ActivityDialogState();
}

class _ActivityDialogState extends State<_ActivityDialog> {
  late String _type = crmStr(widget.existing?['type']).isEmpty ? 'call' : crmStr(widget.existing?['type']);
  late final _subject = TextEditingController(text: crmStr(widget.existing?['subject']));
  late final _notes = TextEditingController(text: crmStr(widget.existing?['notes']));
  late DateTime _date;
  late TimeOfDay _time;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existingDue = DateTime.tryParse(crmStr(widget.existing?['due_at']))?.toLocal();
    final due = existingDue ?? crmDefaultDue(widget.now);
    _date = DateTime(due.year, due.month, due.day);
    _time = TimeOfDay(hour: due.hour, minute: due.minute);
  }

  @override
  void dispose() {
    _subject.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final n = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(n.year - 1),
      lastDate: DateTime(n.year + 5),
      helpText: 'Due date',
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time, helpText: 'Due time');
    if (t != null) setState(() => _time = t);
  }

  void _submit() {
    final subject = _subject.text.trim();
    if (subject.isEmpty) {
      setState(() => _error = 'Enter what needs to be done, e.g. "Call to introduce our service".');
      return;
    }
    if (subject.length > 200) {
      setState(() => _error = 'Keep the subject under 200 characters.');
      return;
    }
    Navigator.of(context).pop(CrmActivityInput(
      type: _type,
      subject: subject,
      dueAtUtc: crmDueAtUtc(_date, _time),
      notes: _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final local = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    final pickerStyle = searchSecondaryButtonStyle();
    return AlertDialog(
      backgroundColor: UiTokens.card,
      title: Text(_editing ? 'Reschedule activity' : 'Schedule an activity', style: const TextStyle(color: UiTokens.text)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_editing) ...[
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  dropdownColor: UiTokens.card,
                  style: const TextStyle(color: UiTokens.text),
                  decoration: crmInputDecoration('Kind'),
                  items: [
                    for (final t in crmActivityTypes) DropdownMenuItem(value: t, child: Text(crmActivityTypeLabel(t))),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? 'call'),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _subject,
                autofocus: !_editing,
                style: const TextStyle(color: UiTokens.text),
                decoration: crmInputDecoration('Subject *'),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  style: pickerStyle,
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(crmDateLabel(crmDateParam(_date)), semanticsLabel: 'Due date ${crmDateLabel(crmDateParam(_date))}, change'),
                ),
                OutlinedButton.icon(
                  style: pickerStyle,
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule_rounded, size: 18),
                  label: Text(_time.format(context), semanticsLabel: 'Due time ${_time.format(context)}, change'),
                ),
              ]),
              const SizedBox(height: 6),
              Text('Your local time: ${crmFullLocal(local)}',
                  style: const TextStyle(color: UiTokens.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(color: UiTokens.text),
                decoration: crmInputDecoration('Notes (optional)'),
              ),
              if (_type == 'email' && !_editing)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Infinity Leads does not send emails. This is a reminder for you.',
                      style: TextStyle(color: UiTokens.textSecondary, fontSize: 12.5)),
                ),
              _dialogError(_error),
            ],
          ),
        ),
      ),
      actions: [
        _cancel(context),
        FilledButton(
          style: searchPrimaryButtonStyle(),
          onPressed: _submit,
          child: Text(_editing ? 'Save new time' : 'Schedule'),
        ),
      ],
    );
  }
}

/// "Mark done" with an optional outcome. Returns the outcome ('' = none)
/// or null when cancelled.
Future<String?> showCrmDoneDialog(BuildContext context, Map<String, dynamic> activity) =>
    showDialog<String>(context: context, builder: (_) => _DoneDialog(activity: activity));

class _DoneDialog extends StatefulWidget {
  final Map<String, dynamic> activity;

  const _DoneDialog({required this.activity});

  @override
  State<_DoneDialog> createState() => _DoneDialogState();
}

class _DoneDialogState extends State<_DoneDialog> {
  final _outcome = TextEditingController();

  @override
  void dispose() {
    _outcome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: UiTokens.card,
      title: const Text('Mark activity done', style: TextStyle(color: UiTokens.text)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(crmStr(widget.activity['subject']), style: const TextStyle(color: UiTokens.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            TextField(
              controller: _outcome,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(color: UiTokens.text),
              decoration: crmInputDecoration('What happened? (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        _cancel(context),
        FilledButton(
          style: searchPrimaryButtonStyle(),
          onPressed: () => Navigator.of(context).pop(_outcome.text.trim()),
          child: const Text('Mark done'),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ person

/// Add (no [existing]) or edit a contact person. Returns the fields.
Future<Map<String, dynamic>?> showCrmPersonDialog(BuildContext context, {Map<String, dynamic>? existing}) =>
    showDialog<Map<String, dynamic>>(context: context, builder: (_) => _PersonDialog(existing: existing));

class _PersonDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const _PersonDialog({this.existing});

  @override
  State<_PersonDialog> createState() => _PersonDialogState();
}

class _PersonDialogState extends State<_PersonDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: crmStr(widget.existing?['name']));
  late final _role = TextEditingController(text: crmStr(widget.existing?['role']));
  late final _phone = TextEditingController(text: crmStr(widget.existing?['phone']));
  late final _email = TextEditingController(text: crmStr(widget.existing?['email']));
  late bool _primary = widget.existing?['is_primary'] == true;

  @override
  void dispose() {
    for (final c in [_name, _role, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, {String? Function(String)? validator, TextInputType? keyboard}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            controller: c,
            keyboardType: keyboard,
            style: const TextStyle(color: UiTokens.text),
            decoration: crmInputDecoration(label),
            validator: validator == null ? null : (s) => validator(s ?? ''),
          ),
        );
    return AlertDialog(
      backgroundColor: UiTokens.card,
      title: Text(widget.existing == null ? 'Add a contact person' : 'Edit contact person',
          style: const TextStyle(color: UiTokens.text)),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Text('Only add people you know of. Business phone and email stay with the business.',
                      style: TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
                ),
                field(_name, 'Name *', validator: (s) => s.trim().isEmpty ? 'Enter the name' : null),
                field(_role, 'Role or title'),
                field(_phone, 'Phone', keyboard: TextInputType.phone),
                field(_email, 'Email', keyboard: TextInputType.emailAddress, validator: crmValidateEmail),
                CheckboxListTile(
                  value: _primary,
                  onChanged: (v) => setState(() => _primary = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Primary contact', style: TextStyle(color: UiTokens.text)),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        _cancel(context),
        FilledButton(
          style: searchPrimaryButtonStyle(),
          onPressed: () {
            if (!(_form.currentState?.validate() ?? false)) return;
            String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
            Navigator.of(context).pop({
              'name': _name.text.trim(),
              'role': v(_role),
              'phone': v(_phone),
              'email': v(_email),
              'is_primary': _primary,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- tags

/// Pick the record's tags (and create new ones). Returns the tag ids, or
/// null when cancelled. [onCreated] is told about each new tag.
Future<List<String>?> showCrmTagsDialog(
  BuildContext context, {
  required CrmApi api,
  required List<Map<String, dynamic>> allTags,
  required List<String> selected,
  void Function(Map<String, dynamic> tag)? onCreated,
}) =>
    showDialog<List<String>>(
      context: context,
      builder: (_) => _TagsDialog(api: api, allTags: allTags, selected: selected, onCreated: onCreated),
    );

class _TagsDialog extends StatefulWidget {
  final CrmApi api;
  final List<Map<String, dynamic>> allTags;
  final List<String> selected;
  final void Function(Map<String, dynamic> tag)? onCreated;

  const _TagsDialog({required this.api, required this.allTags, required this.selected, this.onCreated});

  @override
  State<_TagsDialog> createState() => _TagsDialogState();
}

class _TagsDialogState extends State<_TagsDialog> {
  late final List<Map<String, dynamic>> _tags = List.of(widget.allTags);
  late final Set<String> _selected = {...widget.selected};
  final _newTag = TextEditingController();
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _newTag.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _newTag.text.trim();
    if (name.isEmpty || _creating) return;
    final existing = _tags.where((t) => crmStr(t['name']).toLowerCase() == name.toLowerCase());
    if (existing.isNotEmpty) {
      setState(() {
        _selected.add(crmStr(existing.first['id']));
        _newTag.clear();
      });
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final tag = await widget.api.createTag(name);
      if (!mounted) return;
      widget.onCreated?.call(tag);
      setState(() {
        _tags.add(tag);
        _selected.add(crmStr(tag['id']));
        _newTag.clear();
        _creating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = crmActionError('Creating the tag', e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: UiTokens.card,
      title: const Text('Tags', style: TextStyle(color: UiTokens.text)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_tags.isEmpty)
                const Text('No tags yet. Create your first one below.',
                    style: TextStyle(color: UiTokens.textSecondary, fontSize: 13.5)),
              for (final t in _tags)
                CheckboxListTile(
                  value: _selected.contains(crmStr(t['id'])),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(crmStr(t['id']));
                    } else {
                      _selected.remove(crmStr(t['id']));
                    }
                  }),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(crmStr(t['name']), style: const TextStyle(color: UiTokens.text)),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _newTag,
                    onSubmitted: (_) => _create(),
                    style: const TextStyle(color: UiTokens.text),
                    decoration: crmInputDecoration('New tag'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: searchSecondaryButtonStyle(),
                  onPressed: _creating ? null : _create,
                  child: Text(_creating ? 'Adding…' : 'Add'),
                ),
              ]),
              _dialogError(_error),
            ],
          ),
        ),
      ),
      actions: [
        _cancel(context),
        FilledButton(
          style: searchPrimaryButtonStyle(),
          onPressed: () => Navigator.of(context).pop([
            for (final t in _tags)
              if (_selected.contains(crmStr(t['id']))) crmStr(t['id']),
          ]),
          child: const Text('Save tags'),
        ),
      ],
    );
  }
}
