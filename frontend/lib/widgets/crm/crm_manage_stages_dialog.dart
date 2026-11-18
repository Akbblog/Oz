import 'package:flutter/material.dart';

import '../../core/crm/crm_format.dart';
import '../../services/crm_api.dart';
import '../app_shell_common.dart';

/// Manages the user's pipeline order and names. Won stays last because it is
/// the terminal outcome; deleting a stage transfers its records first.
class CrmManageStagesDialog extends StatefulWidget {
  final CrmApi api;
  const CrmManageStagesDialog({super.key, required this.api});

  @override
  State<CrmManageStagesDialog> createState() => _CrmManageStagesDialogState();
}

class _CrmManageStagesDialogState extends State<CrmManageStagesDialog> {
  List<Map<String, dynamic>> _stages = [];
  bool _busy = true;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.getStages();
      if (!mounted) return;
      setState(() {
        _stages = crmList(data['stages']);
        _busy = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = '$e'; });
    }
  }

  Future<void> _save(Future<Map<String, dynamic>> Function() action) async {
    setState(() { _busy = true; _error = null; });
    try {
      final data = await action();
      if (!mounted) return;
      setState(() {
        _stages = crmList(data['stages']);
        _busy = false;
        _changed = true;
      });
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = '$e'; });
    }
  }

  Future<String?> _nameDialog({String? current}) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(current == null ? 'Add stage' : 'Rename stage'),
        content: TextField(
          controller: controller,
          maxLength: 120,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Stage name'),
          onSubmitted: (v) { if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim()); },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (controller.text.trim().isNotEmpty) Navigator.pop(ctx, controller.text.trim());
          }, child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    return name;
  }

  Future<void> _delete(Map<String, dynamic> stage) async {
    final id = crmStr(stage['id']);
    final alternatives = _stages.where((s) => crmStr(s['id']) != id && crmStr(s['outcome_kind']) == 'open').toList();
    if (alternatives.isEmpty) return;
    final count = crmInt(stage['dependent_count']);
    String replacement = crmStr(alternatives.first['id']);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: Text('Delete ${crmStr(stage['name'])}?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(count == 0 ? 'This stage has no leads.' : '$count leads reference this stage. Leads here will move to another stage; won leads keep their won status. No leads will be deleted.'),
          if (count > 0) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: replacement,
              decoration: const InputDecoration(labelText: 'Move leads to'),
              items: [for (final s in alternatives) DropdownMenuItem(value: crmStr(s['id']), child: Text(crmStr(s['name'])))],
              onChanged: (v) { if (v != null) update(() => replacement = v); },
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete stage')),
        ],
      )),
    );
    if (confirmed == true) await _save(() => widget.api.deleteStage(id, replacementId: count > 0 ? replacement : null));
  }

  void _reorder(int oldIndex, int newIndex) {
    if (_busy || crmStr(_stages[oldIndex]['outcome_kind']) == 'won') return;
    final updated = [..._stages];
    if (newIndex > oldIndex) newIndex--;
    final wonIndex = updated.indexWhere((s) => crmStr(s['outcome_kind']) == 'won');
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex.clamp(0, wonIndex < 0 ? updated.length : wonIndex - 1), item);
    _save(() => widget.api.reorderStages([for (final s in updated) crmStr(s['id'])]));
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Text('Manage stages', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
            IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context, _changed), icon: const Icon(Icons.close_rounded)),
          ]),
          const SizedBox(height: 4),
          const Text('Drag a stage to reorder it. Won stays last.', style: TextStyle(color: UiTokens.textSecondary)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
          if (_busy) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Flexible(child: _stages.isEmpty && !_busy
              ? Center(child: TextButton(onPressed: _load, child: const Text('Could not load stages. Retry')))
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  itemCount: _stages.length,
                  onReorder: _reorder,
                  itemBuilder: (ctx, i) {
                    final stage = _stages[i];
                    final won = crmStr(stage['outcome_kind']) == 'won';
                    return ListTile(
                      key: ValueKey(crmStr(stage['id'])),
                      contentPadding: EdgeInsets.zero,
                      leading: won ? const Icon(Icons.emoji_events_outlined) : ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle_rounded)),
                      title: Text(crmStr(stage['name'])),
                      subtitle: Text('${crmInt(stage['record_count'])} leads${won ? ' · required' : ''}'),
                      trailing: Wrap(children: [
                        IconButton(tooltip: 'Rename ${crmStr(stage['name'])}', onPressed: _busy ? null : () async {
                          final name = await _nameDialog(current: crmStr(stage['name']));
                          if (name != null) await _save(() => widget.api.renameStage(crmStr(stage['id']), name));
                        }, icon: const Icon(Icons.edit_outlined)),
                        if (!won) IconButton(tooltip: 'Delete ${crmStr(stage['name'])}', onPressed: _busy ? null : () => _delete(stage), icon: const Icon(Icons.delete_outline_rounded)),
                      ]),
                    );
                  },
                )),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: _busy || _stages.length >= 20 ? null : () async {
            final name = await _nameDialog();
            if (name != null) await _save(() => widget.api.createStage(name));
          }, icon: const Icon(Icons.add_rounded), label: const Text('Add stage')),
        ]),
      ),
    ),
  );
}
