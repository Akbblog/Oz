import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/utils/server_time.dart';
import '../providers/auth_provider.dart';
import '../providers/credit_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_shell.dart';

/// Account page (`/account`): only real account data — name, email, role,
/// member since, search counts from the API and the credit balance — plus
/// Billing & credits, password reset and sign-out (always confirmed).
/// Body only inside the shell; a plain page with a back button elsewhere.
class ProfileScreen extends StatefulWidget {
  final ApiService? api;

  const ProfileScreen({super.key, this.api});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ApiService _api = widget.api ?? ApiService();
  bool _loading = true;
  Object? _error;
  Map<String, int> _counts = const {};

  @override
  void initState() {
    super.initState();
    _loadStats();
    if (!CreditProvider.instance.hasValue) CreditProvider.instance.refresh();
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.getJobs(limit: 1);
      final counts = Map<String, int>.from(page['counts'] as Map? ?? const <String, int>{});
      if (counts.isEmpty) counts['all'] = (page['total'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      setState(() {
        _counts = counts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final embedded = context.findAncestorWidgetOfExactType<AppShell>() != null;
    final body = _buildBody(context);
    if (embedded) return body;
    return Scaffold(
      backgroundColor: UiTokens.background,
      appBar: AppBar(
        backgroundColor: UiTokens.background,
        foregroundColor: UiTokens.text,
        elevation: 0,
        title: const Text('Account'),
      ),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser ?? const <String, dynamic>{};
    final username = '${user['username'] ?? ''}'.trim();
    final email = '${user['email'] ?? ''}'.trim();
    final role = '${user['role'] ?? ''}'.trim().toLowerCase();
    final memberSince = parseServerTimeLocal(user['created_at']);
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 24.0;

    String? roleLabel;
    if (role == 'owner') {
      roleLabel = 'Owner';
    } else if (role == 'admin' || auth.isAdmin) {
      roleLabel = 'Administrator';
    } else if (role == 'support') {
      roleLabel = 'Support';
    }

    final identity = _Card(
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: UiTokens.primary,
            child: Text(
              username.isNotEmpty ? username[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username.isEmpty ? 'Your account' : username,
                  style: const TextStyle(color: UiTokens.text, fontSize: 19, fontWeight: FontWeight.w700),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(email, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 14)),
                ],
                if (roleLabel != null || memberSince != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (roleLabel != null) roleLabel,
                      if (memberSince != null) 'Member since ${_monthYear(memberSince)}',
                    ].join(' · '),
                    style: const TextStyle(color: UiTokens.textMuted, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    Widget stat(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: const TextStyle(color: UiTokens.text, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
            ],
          ),
        );

    final stats = _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: const Text('Your activity',
                style: TextStyle(color: UiTokens.text, fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (_error != null)
            Row(
              children: [
                const Expanded(
                  child: Text("We couldn't load your search counts.",
                      style: TextStyle(color: UiTokens.textSecondary, fontSize: 14)),
                ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: UiTokens.accent, minimumSize: const Size(44, 44)),
                  onPressed: _loadStats,
                  child: const Text('Try again'),
                ),
              ],
            )
          else
            ListenableBuilder(
              listenable: CreditProvider.instance,
              builder: (context, _) => Row(
                children: [
                  stat('Searches', formatCount(_counts['all'] ?? 0)),
                  if (_counts.containsKey('completed')) stat('Completed', formatCount(_counts['completed']!)),
                  stat('Credits', CreditProvider.instance.hasValue ? formatCount(CreditProvider.instance.balance) : '—'),
                ],
              ),
            ),
        ],
      ),
    );

    final links = _Card(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          _LinkTile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Billing & credits',
            subtitle: 'Balance, credit history and requests',
            onTap: () => AppNav.go(context, '/credits'),
          ),
          const Divider(height: 1, color: UiTokens.border),
          _LinkTile(
            icon: Icons.list_alt_rounded,
            title: 'My searches',
            onTap: () => AppNav.go(context, '/searches'),
          ),
          const Divider(height: 1, color: UiTokens.border),
          _LinkTile(
            icon: Icons.lock_reset_rounded,
            title: 'Reset password',
            subtitle: 'We email you a link to choose a new password',
            onTap: () => Navigator.of(context).pushNamed('/forgot-password'),
          ),
          if (auth.isAdmin) ...[
            const Divider(height: 1, color: UiTokens.border),
            _LinkTile(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Admin',
              onTap: () => Navigator.of(context).pushNamed('/admin'),
            ),
          ],
          const Divider(height: 1, color: UiTokens.border),
          _LinkTile(
            icon: Icons.support_agent_rounded,
            title: 'Contact us',
            subtitle: 'Questions, billing or feedback: send us a message',
            onTap: () => Navigator.of(context).pushNamed('/contact'),
          ),
          const Divider(height: 1, color: UiTokens.border),
          _LinkTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy policy',
            onTap: () => Navigator.of(context).pushNamed('/privacy-policy'),
          ),
        ],
      ),
    );

    final signOut = Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: UiTokens.failedFg,
          side: const BorderSide(color: UiTokens.border),
          minimumSize: const Size(44, 48),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: () => AppNav.confirmSignOut(context),
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: const Text('Sign out'),
      ),
    );

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_loadStats(), CreditProvider.instance.refresh()]);
      },
      child: ListView(
        padding: EdgeInsets.all(pad),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  identity,
                  const SizedBox(height: 16),
                  stats,
                  const SizedBox(height: 16),
                  links,
                  const SizedBox(height: 24),
                  signOut,
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _monthYear(DateTime t) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[t.month - 1]} ${t.year}';
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Card({required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: UiTokens.card,
        borderRadius: BorderRadius.circular(UiTokens.radius),
        border: Border.all(color: UiTokens.border),
      ),
      child: child,
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _LinkTile({required this.icon, required this.title, required this.onTap, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minTileHeight: 52,
      leading: Icon(icon, color: UiTokens.accent),
      title: Text(title, style: const TextStyle(color: UiTokens.text, fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: const TextStyle(color: UiTokens.textSecondary, fontSize: 13)),
      trailing: const Icon(Icons.chevron_right_rounded, color: UiTokens.textMuted),
      onTap: onTap,
    );
  }
}
