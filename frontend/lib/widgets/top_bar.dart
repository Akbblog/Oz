import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'app_shell.dart';
import 'credit_pill.dart';

/// Top bar for tablet and desktop: page title, live search chip, credit
/// pill and avatar menu (guests: "Sign in").
class AppTopBar extends StatelessWidget {
  final String title;

  const AppTopBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: UiTokens.background,
        border: Border(bottom: BorderSide(color: UiTokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: UiTokens.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (auth.isAuthenticated) ...[
            const Flexible(child: LiveSearchChip()),
            const SizedBox(width: 12),
            const CreditPill(),
            const SizedBox(width: 12),
            const AvatarMenu(),
          ] else
            const _SignInButton(),
        ],
      ),
    );
  }
}

/// Phone top bar: page title + credit pill (admins also get the avatar menu
/// for the Admin entry; everyone else signs out from Account).
class PhoneTopBar extends StatelessWidget {
  final String title;

  const PhoneTopBar({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: UiTokens.background,
        border: Border(bottom: BorderSide(color: UiTokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: UiTokens.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (auth.isAuthenticated) ...[
            const CreditPill(),
            if (auth.isAdmin) ...[
              const SizedBox(width: 8),
              const AvatarMenu(),
            ],
          ] else
            const _SignInButton(),
        ],
      ),
    );
  }
}

class _SignInButton extends StatelessWidget {
  const _SignInButton();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => AppNav.signIn(context),
      icon: const Icon(Icons.login_rounded, size: 18),
      label: const Text('Sign in'),
      style: OutlinedButton.styleFrom(
        foregroundColor: UiTokens.text,
        side: const BorderSide(color: UiTokens.border),
        minimumSize: const Size(0, 40),
      ),
    );
  }
}

/// Avatar menu: Profile, Admin (admins), Sign out (confirmed).
class AvatarMenu extends StatelessWidget {
  const AvatarMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final name = '${auth.currentUser?['username'] ?? ''}'.trim();
    final initial = name.isEmpty ? 'U' : name[0].toUpperCase();
    return PopupMenuButton<String>(
      tooltip: 'Account menu',
      color: UiTokens.card,
      offset: const Offset(0, 48),
      onSelected: (value) {
        switch (value) {
          case 'profile':
            AppNav.go(context, '/account');
            break;
          case 'admin':
            Navigator.of(context).pushNamed('/admin');
            break;
          case 'signout':
            AppNav.confirmSignOut(context);
            break;
        }
      },
      itemBuilder: (context) => [
        if (name.isNotEmpty)
          PopupMenuItem<String>(
            enabled: false,
            child: Text(name, style: const TextStyle(color: UiTokens.textMuted, fontSize: 12)),
          ),
        const PopupMenuItem<String>(
          value: 'profile',
          child: _MenuRow(icon: Icons.person_outline_rounded, label: 'Profile'),
        ),
        if (auth.isAdmin)
          const PopupMenuItem<String>(
            value: 'admin',
            child: _MenuRow(icon: Icons.shield_outlined, label: 'Admin'),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'signout',
          child: _MenuRow(
            icon: Icons.logout_rounded,
            label: 'Sign out',
            color: UiTokens.failedFg,
          ),
        ),
      ],
      child: Semantics(
        label: 'Account menu',
        button: true,
        excludeSemantics: true,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: UiTokens.card,
            shape: BoxShape.circle,
            border: Border.all(color: UiTokens.border),
          ),
          child: Text(
            initial,
            style: const TextStyle(
              color: UiTokens.text,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MenuRow({required this.icon, required this.label, this.color = UiTokens.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

/// "Searching · plumbers · 2 of 4 cities" chip (≥768 px); opens the search.
class LiveSearchChip extends StatelessWidget {
  const LiveSearchChip({super.key});

  @override
  Widget build(BuildContext context) {
    final live = LiveSearch.of(context);
    if (live.isEmpty) return const SizedBox.shrink();
    final label = LiveSearch.label(live);
    return Semantics(
      button: true,
      label: '$label. Open',
      excludeSemantics: true,
      child: Material(
        color: UiTokens.searchingBg,
        shape: const StadiumBorder(side: BorderSide(color: UiTokens.searchingFg)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => AppNav.go(context, LiveSearch.route(live)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _LiveDot(),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: UiTokens.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Slim tappable banner under the phone top bar while a search runs. Hidden
/// on that search's own page.
class LiveSearchBanner extends StatelessWidget {
  const LiveSearchBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isAuthenticated) return const SizedBox.shrink();
    final live = LiveSearch.of(context);
    if (live.isEmpty) return const SizedBox.shrink();
    final route = LiveSearch.route(live);
    if (AppNav.currentPath(context) == route) return const SizedBox.shrink();
    final label = LiveSearch.label(live);
    return Semantics(
      button: true,
      label: '$label. Open',
      excludeSemantics: true,
      child: Material(
        color: UiTokens.searchingBg,
        child: InkWell(
          onTap: () => AppNav.go(context, route),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: UiTokens.border)),
            ),
            child: Row(
              children: [
                const _LiveDot(),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: UiTokens.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Text(
                  'View',
                  style: TextStyle(color: UiTokens.accent, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const Icon(Icons.chevron_right_rounded, color: UiTokens.accent, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(color: UiTokens.searchingFg, shape: BoxShape.circle),
    );
  }
}
