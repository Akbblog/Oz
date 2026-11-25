import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/admin_roles.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../admin_kit.dart';
import '../admin_shell.dart';

/// Registration, email and payment switches. Each change saves immediately
/// and is written to the audit log by the server.
class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({super.key});

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final ApiService _api = ApiService();
  final TextEditingController _startingCredits = TextEditingController();

  Map<String, dynamic> _settings = {};
  bool _loading = true;
  String? _error;
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _startingCredits.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await _api.getAdminSettings();
      if (!mounted) return;
      setState(() {
        _settings = s;
        _loading = false;
        final sc = '${s['starting_credits'] ?? ''}'.trim();
        if (sc.isNotEmpty) _startingCredits.text = sc;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = cleanError(e);
      });
    }
  }

  bool _bool(String key, {bool fallback = false}) {
    final raw = _settings[key];
    if (raw is bool) return raw;
    if (raw is String) return raw.toLowerCase() == 'true';
    return fallback;
  }

  Future<void> _save(String key, String value, String label) async {
    if (_saving.contains(key)) return;
    setState(() => _saving.add(key));
    try {
      await _api.updateAdminSetting(key, value);
      if (!mounted) return;
      setState(() =>
          _settings = Map<String, dynamic>.from(_settings)..[key] = value);
      aToast(context, '$label saved');
    } catch (e) {
      if (mounted) aToast(context, cleanError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving.remove(key));
    }
  }

  Widget _toggle(String key, String title, String help,
      {bool fallback = false, bool enabled = true}) {
    final value = _bool(key, fallback: fallback);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AT.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(help, style: AT.mute),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: enabled && !_saving.contains(key)
                ? (v) => _save(key, v ? 'true' : 'false', title)
                : null,
            activeThumbColor: Colors.white,
            activeTrackColor: AC.primaryHover,
            inactiveThumbColor: AC.textMute,
            inactiveTrackColor: AC.bg,
            trackOutlineColor: const WidgetStatePropertyAll(AC.borderStrong),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewer = context.watch<AuthProvider>().currentUser;
    final canLive = AdminRoles.canToggleLivePayments(viewer);
    final live = _bool('enable_live_payments');
    final tone = live ? AC.green : AC.amber;
    return AdminScaffold(
      section: AdminSection.settings,
      title: 'Settings',
      subtitle: 'Changes save immediately and are recorded in the activity log',
      actions: [
        AIconButton(Icons.refresh, 'Reload',
            onPressed: _loading ? null : _load),
      ],
      child: _error != null
          ? AErrorBox(_error!, onRetry: _load)
          : _loading
              ? const ALoading(height: 300)
              : Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        APanel(
                          title: 'Registration',
                          subtitle: 'What happens when someone signs up',
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _toggle(
                                  'auto_approve_users',
                                  'Approve new users automatically',
                                  'When off, each new account waits in Users → Pending until an admin approves it.'),
                              const Divider(height: 1, color: AC.border),
                              const SizedBox(height: 12),
                              Text('Starting credits',
                                  style: AT.body
                                      .copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              const Text(
                                  'Free credits added to an account when it is approved.',
                                  style: AT.mute),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  SizedBox(
                                    width: 150,
                                    child: TextField(
                                      controller: _startingCredits,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly
                                      ],
                                      style: AT.body,
                                      cursorColor: AC.accent,
                                      decoration: aInput(hint: 'e.g. 30'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AButton(
                                    'Save',
                                    kind: AButtonKind.primary,
                                    busy: _saving.contains('starting_credits'),
                                    onPressed: () {
                                      final n = int.tryParse(
                                          _startingCredits.text.trim());
                                      if (n == null || n < 0) {
                                        aToast(context,
                                            'Starting credits must be a whole number, 0 or more.',
                                            error: true);
                                        return;
                                      }
                                      _save('starting_credits', '$n',
                                          'Starting credits');
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        APanel(
                          title: 'Emails',
                          subtitle: 'Automatic messages to admins and users',
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                          child: Column(
                            children: [
                              _toggle(
                                  'admin_notification_on_signup',
                                  'Tell admins about new signups',
                                  'Emails the admin(s) when a new account is waiting for approval.',
                                  fallback: true),
                              const Divider(height: 1, color: AC.border),
                              _toggle('send_welcome_email', 'Welcome email',
                                  'Sent when an account is approved automatically at registration.',
                                  fallback: true),
                              const Divider(height: 1, color: AC.border),
                              _toggle('send_approval_email', 'Approval email',
                                  'Sent when an admin approves a pending account.',
                                  fallback: true),
                              const Divider(height: 1, color: AC.border),
                              _toggle('send_rejection_email', 'Rejection email',
                                  'Sent when an admin denies a pending account.',
                                  fallback: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        APanel(
                          title: 'Payments',
                          subtitle: canLive
                              ? 'Owner-only setting'
                              : 'Only an owner can change this',
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _toggle(
                                  'enable_live_payments',
                                  'Live payment methods',
                                  'Lets users buy credits themselves from their wallet.',
                                  enabled: canLive),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: tone.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: tone.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                        live
                                            ? Icons.check_circle_outline
                                            : Icons.info_outline,
                                        size: 17,
                                        color: tone),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        live
                                            ? 'On: users see payment methods and invoices in their wallet.'
                                            : 'Off: users see "Payments coming soon" and can request credits, which arrive in Credit requests.',
                                        style: AT.small,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
