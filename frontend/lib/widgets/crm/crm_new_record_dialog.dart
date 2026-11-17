import 'package:flutter/material.dart';

import '../../core/crm/crm_format.dart';
import '../../services/crm_api.dart';
import '../app_shell_common.dart';
import 'crm_widgets.dart';

/// "+ New lead": creates a record by hand. Returns the created record (or
/// null when cancelled).
Future<Map<String, dynamic>?> showCrmNewRecordDialog(
  BuildContext context, {
  required CrmApi api,
  List<Map<String, dynamic>> stages = const [],
}) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _NewRecordDialog(api: api, stages: stages),
    );

class _NewRecordDialog extends StatefulWidget {
  final CrmApi api;
  final List<Map<String, dynamic>> stages;

  const _NewRecordDialog({required this.api, required this.stages});

  @override
  State<_NewRecordDialog> createState() => _NewRecordDialogState();
}

class _NewRecordDialogState extends State<_NewRecordDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _city = TextEditingController();
  final _region = TextEditingController();
  final _country = TextEditingController();
  String _type = 'lead';
  String? _stageId;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> get _openStages =>
      widget.stages.where((s) => crmStr(s['outcome_kind']) != 'won').toList();

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _website, _city, _region, _country]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    String? v(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final name = _name.text.trim();
    try {
      final created = await widget.api.createRecord({
        'title': name,
        'company': {
          'name': name,
          if (v(_phone) != null) 'phone': v(_phone),
          if (v(_email) != null) 'email': v(_email),
          if (v(_website) != null) 'website': v(_website),
          if (v(_city) != null) 'city': v(_city),
          if (v(_region) != null) 'region': v(_region),
          if (v(_country) != null) 'country': v(_country),
        },
        'type': _type,
        if (_stageId != null) 'stage_id': _stageId,
      });
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = crmActionError('Creating the lead', e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label,
            {String? Function(String)? validator, TextInputType? keyboard, bool autofocus = false, String? hint}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            controller: c,
            autofocus: autofocus,
            keyboardType: keyboard,
            style: const TextStyle(color: UiTokens.text),
            decoration: crmInputDecoration(label, hint: hint),
            validator: validator == null ? null : (s) => validator(s ?? ''),
          ),
        );

    return AlertDialog(
      backgroundColor: UiTokens.card,
      title: const Text('New lead', style: TextStyle(color: UiTokens.text)),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('Add a business you found yourself. Only the name is required.',
                      style: TextStyle(color: UiTokens.textSecondary, fontSize: 13.5)),
                ),
                field(_name, 'Business name *',
                    autofocus: true,
                    validator: (s) => s.trim().isEmpty ? 'Enter the business name' : (s.trim().length > 200 ? 'Use at most 200 characters' : null)),
                field(_phone, 'Phone', keyboard: TextInputType.phone),
                field(_email, 'Email', keyboard: TextInputType.emailAddress, validator: crmValidateEmail),
                field(_website, 'Website', keyboard: TextInputType.url, hint: 'https://example.com', validator: crmValidateWebsite),
                field(_city, 'City'),
                field(_region, 'Region / state'),
                field(_country, 'Country'),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  dropdownColor: UiTokens.card,
                  style: const TextStyle(color: UiTokens.text),
                  decoration: crmInputDecoration('Type'),
                  items: const [
                    DropdownMenuItem(value: 'lead', child: Text('Lead')),
                    DropdownMenuItem(value: 'opportunity', child: Text('Opportunity')),
                  ],
                  onChanged: (v) => setState(() => _type = v ?? 'lead'),
                ),
                if (_openStages.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: _stageId,
                    dropdownColor: UiTokens.card,
                    style: const TextStyle(color: UiTokens.text),
                    decoration: crmInputDecoration('Stage'),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text('First stage (${crmStr(_openStages.first['name'])})')),
                      for (final s in _openStages)
                        DropdownMenuItem<String?>(value: crmStr(s['id']), child: Text(crmStr(s['name']))),
                    ],
                    onChanged: (v) => setState(() => _stageId = v),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(_error!, style: const TextStyle(color: UiTokens.failedFg, fontSize: 13.5)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(48, 48)),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: searchPrimaryButtonStyle(),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Creating…' : 'Create lead'),
        ),
      ],
    );
  }
}
