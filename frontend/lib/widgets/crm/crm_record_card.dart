import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/crm/crm_format.dart';
import '../app_shell_common.dart';
import 'crm_widgets.dart';

/// "Move to stage" menu: every stage of the pipeline except the current
/// one. Keyboard accessible (it is a button) and always available next to
/// drag and drop.
class CrmMoveToStageMenu extends StatelessWidget {
  final Map<String, dynamic> record;
  final List<Map<String, dynamic>> stages;
  final ValueChanged<Map<String, dynamic>> onMove;
  final bool enabled;

  const CrmMoveToStageMenu({
    super.key,
    required this.record,
    required this.stages,
    required this.onMove,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final currentId = crmStr(crmMap(record['stage'])['id']);
    final title = crmRecordTitle(record);
    return PopupMenuButton<String>(
      tooltip: 'Move $title to stage',
      enabled: enabled && stages.isNotEmpty,
      color: UiTokens.card,
      onSelected: (id) {
        final stage = stages.firstWhere((s) => crmStr(s['id']) == id,
            orElse: () => const {});
        if (stage.isNotEmpty) onMove(stage);
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 36,
          child: Text('Move to stage',
              style: TextStyle(color: UiTokens.textSecondary, fontSize: 12)),
        ),
        for (final s in stages)
          CheckedPopupMenuItem<String>(
            value: crmStr(s['id']),
            checked: crmStr(s['id']) == currentId,
            enabled: crmStr(s['id']) != currentId,
            child: Text(crmStr(s['name'])),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        alignment: Alignment.center,
        child: const Icon(Icons.drive_file_move_outlined,
            size: 20, color: UiTokens.accent),
      ),
    );
  }
}

/// One CRM record as a card (pipeline columns, stage lists, phone lists).
class CrmRecordCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final List<Map<String, dynamic>> stages;
  final VoidCallback onOpen;
  final ValueChanged<Map<String, dynamic>>? onMove;
  final VoidCallback? onDelete;
  final bool busy;
  final bool showStage;

  const CrmRecordCard({
    super.key,
    required this.record,
    required this.stages,
    required this.onOpen,
    this.onMove,
    this.onDelete,
    this.busy = false,
    this.showStage = false,
  });

  Future<void> _openLink(BuildContext context, Uri uri, String label) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (context.mounted) crmSnack(context, "Couldn't open $label", error: true);
  }

  Widget _contactAction(IconData icon, String label, VoidCallback action) =>
      TextButton(
        style: TextButton.styleFrom(
          foregroundColor: UiTokens.accent,
          minimumSize: const Size(0, 52),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        onPressed: action,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 17),
          const SizedBox(height: 3),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final title = crmRecordTitle(record);
    final company = crmMap(record['company']);
    final place = crmPlace(company);
    final tags = crmList(record['tags']);
    final next =
        record['next_activity'] is Map ? crmMap(record['next_activity']) : null;
    final hint = crmContactHint(company);
    final phone = crmStr(company['phone']);
    final email = crmStr(company['email']);
    final website = crmStr(company['website']);
    final address = crmStr(company['address']);
    final mapsUrl = crmStr(company['maps_url']);
    final value = crmMoney(record['value'], record['currency']);
    final outcome = crmStr(record['outcome']);
    final archived = record['archived'] == true;
    final stage = crmStageName(record);
    final sources = crmInt(record['source_count']);

    final summary = [
      title,
      if (showStage && stage.isNotEmpty) 'stage $stage',
      if (outcome == 'won' || outcome == 'lost' || archived)
        crmOutcomeStyle(outcome, archived: archived).label,
      if (place.isNotEmpty) place,
      if (next != null)
        '${crmDueStyle(crmDueKind(next)).label}: ${crmStr(next['subject'])}, ${crmWhen(next['due_at'])}',
      if (next == null) 'No next activity',
      if (value.isNotEmpty) value,
    ].join(', ');

    return Opacity(
      opacity: busy ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: UiTokens.card,
          borderRadius: BorderRadius.circular(UiTokens.radius),
          border: Border.all(color: UiTokens.border),
        ),
        child: Material(
          color: Colors.transparent,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Open $summary',
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(UiTokens.radius),
                    onTap: onOpen,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: UiTokens.text,
                                        fontSize: 15.5,
                                        height: 1.25,
                                        fontWeight: FontWeight.w700))),
                            const Icon(Icons.chevron_right_rounded,
                                size: 18, color: UiTokens.textSecondary),
                          ]),
                          if (place.isNotEmpty ||
                              (showStage && stage.isNotEmpty))
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                [
                                  if (showStage && stage.isNotEmpty) stage,
                                  if (place.isNotEmpty) place
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: UiTokens.textSecondary,
                                    fontSize: 12.5),
                              ),
                            ),
                          if (outcome == 'won' ||
                              outcome == 'lost' ||
                              archived ||
                              tags.isNotEmpty ||
                              sources > 1)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(spacing: 4, runSpacing: 4, children: [
                                if (outcome == 'won' ||
                                    outcome == 'lost' ||
                                    archived)
                                  CrmOutcomeBadge(record: record),
                                for (final t in tags.take(2))
                                  CrmBadge(
                                      label: crmStr(t['name']),
                                      icon: Icons.sell_outlined),
                                if (tags.length > 2)
                                  CrmBadge(label: '+${tags.length - 2}'),
                                if (sources > 1)
                                  CrmBadge(label: 'Found in $sources searches'),
                              ]),
                            ),
                          const Padding(
                            padding: EdgeInsets.only(top: 10, bottom: 8),
                            child: Divider(height: 1, color: UiTokens.border),
                          ),
                          if (next != null)
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                CrmDueBadge(activity: next),
                                Text(crmStr(next['subject']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: UiTokens.text, fontSize: 12.5)),
                              ],
                            )
                          else
                            const Row(children: [
                              Icon(Icons.event_busy_outlined,
                                  size: 14, color: UiTokens.textMuted),
                              SizedBox(width: 4),
                              Flexible(
                                child: Text('No next activity',
                                    style: TextStyle(
                                        color: UiTokens.textSecondary,
                                        fontSize: 12.5)),
                              ),
                            ]),
                          if (hint != null || value.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 7),
                              child: Row(
                                children: [
                                  if (hint != null) ...[
                                    Icon(hint.icon,
                                        size: 14,
                                        color: UiTokens.textSecondary),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(hint.text,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textDirection: TextDirection.ltr,
                                          style: const TextStyle(
                                              color: UiTokens.textSecondary,
                                              fontSize: 12.5)),
                                    ),
                                  ] else
                                    const Spacer(),
                                  if (value.isNotEmpty)
                                    Text(value,
                                        style: const TextStyle(
                                            color: UiTokens.text,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          if (phone.isNotEmpty ||
                              email.isNotEmpty ||
                              website.isNotEmpty ||
                              mapsUrl.isNotEmpty ||
                              address.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(children: [
                              if (phone.isNotEmpty)
                                Expanded(
                                  child: _contactAction(
                                      Icons.call_outlined,
                                      'Call',
                                      () => _openLink(
                                          context,
                                          Uri(
                                              scheme: 'tel',
                                              path: phone.replaceAll(
                                                  RegExp(r'[^0-9+]'), '')),
                                          'phone')),
                                ),
                              if (email.isNotEmpty)
                                Expanded(
                                    child: _contactAction(
                                        Icons.email_outlined,
                                        'Email',
                                        () => _openLink(
                                            context,
                                            Uri(scheme: 'mailto', path: email),
                                            'email'))),
                              if (website.isNotEmpty)
                                Expanded(
                                    child: _contactAction(
                                        Icons.language_rounded, 'Website', () {
                                  final url = website.startsWith(RegExp(
                                          r'https?://',
                                          caseSensitive: false))
                                      ? website
                                      : 'https://$website';
                                  final uri = Uri.tryParse(url);
                                  if (uri != null &&
                                      (uri.scheme == 'https' ||
                                          uri.scheme == 'http')) {
                                    _openLink(context, uri, 'website');
                                  }
                                })),
                              if (mapsUrl.isNotEmpty || address.isNotEmpty)
                                Expanded(
                                    child: _contactAction(
                                        Icons.map_outlined, 'Map', () {
                                  final uri = mapsUrl.isNotEmpty
                                      ? Uri.tryParse(mapsUrl)
                                      : Uri.https(
                                          'www.google.com',
                                          '/maps/search/',
                                          {'api': '1', 'query': address});
                                  if (uri != null &&
                                      (uri.scheme == 'https' ||
                                          uri.scheme == 'http')) {
                                    _openLink(context, uri, 'map');
                                  }
                                })),
                            ]),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (onMove != null || onDelete != null ||
                  phone.isNotEmpty || email.isNotEmpty ||
                  website.isNotEmpty || address.isNotEmpty)
                SizedBox(
                  width: 48,
                  child: Column(children: [
                    if (busy)
                      const SizedBox(width: 48, height: 48,
                        child: Center(child: SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))))
                    else ...[
                      if (onMove != null)
                        CrmMoveToStageMenu(record: record, stages: stages, onMove: onMove!),
                      if (phone.isNotEmpty || email.isNotEmpty ||
                          website.isNotEmpty || address.isNotEmpty)
                        PopupMenuButton<String>(
                          tooltip: 'Copy contact details',
                          icon: const Icon(Icons.copy_outlined, size: 19, color: UiTokens.accent),
                          onSelected: (value) {
                            final label = value == 'phone' ? 'Phone'
                                : value == 'email' ? 'Email'
                                : value == 'website' ? 'Website' : 'Address';
                            final text = value == 'phone' ? phone
                                : value == 'email' ? email
                                : value == 'website' ? website : address;
                            copyWithSnack(context, text, message: '$label copied');
                          },
                          itemBuilder: (_) => [
                            if (phone.isNotEmpty) const PopupMenuItem(value: 'phone', child: Text('Copy phone')),
                            if (email.isNotEmpty) const PopupMenuItem(value: 'email', child: Text('Copy email')),
                            if (website.isNotEmpty) const PopupMenuItem(value: 'website', child: Text('Copy website')),
                            if (address.isNotEmpty) const PopupMenuItem(value: 'address', child: Text('Copy address')),
                          ],
                        ),
                      if (onDelete != null)
                        IconButton(
                          tooltip: 'Delete ${crmRecordTitle(record)} from CRM',
                          onPressed: onDelete,
                          icon: const Icon(Icons.close_rounded, size: 19),
                          color: UiTokens.failedFg,
                        ),
                    ],
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
