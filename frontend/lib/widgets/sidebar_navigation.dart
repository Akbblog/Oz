import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/crm_provider.dart';
import 'app_shell.dart';
import 'brand_mark.dart';

/// "1 live" count for My searches.
int _liveCount(BuildContext context) => LiveSearch.of(context).length;

/// CRM nav state: shown only when the server enabled CRM; the badge is
/// activities overdue + due today. (No [CrmProvider] in the tree = off.)
({bool enabled, int due}) _crm(BuildContext context) {
  final crm = context.watch<CrmProvider?>();
  if (crm == null || !crm.isEnabled) return (enabled: false, due: 0);
  return (enabled: true, due: crm.dueCount);
}

String _dueText(int due) => '$due due';

/// Desktop sidebar (≥1024 px, 232 px): wordmark, Home, Find leads
/// (emphasised), My searches (+ "N live"), Credits, Admin (admins) and
/// Account at the bottom. Guests: Find leads + Sign in.
class AppSidebar extends StatelessWidget {
  final ShellSection section;

  static const double width = 232;

  const AppSidebar({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final signedIn = auth.isAuthenticated;
    final live = signedIn ? _liveCount(context) : 0;
    final crm = signedIn ? _crm(context) : (enabled: false, due: 0);

    Widget item(ShellDestination d) => _SidebarItem(
          destination: d,
          selected: d.section == section,
          emphasised: d.section == ShellSection.find,
          trailing: d.section == ShellSection.searches && live > 0
              ? '$live live'
              : (d.section == ShellSection.crm && crm.due > 0 ? _dueText(crm.due) : null),
          trailingWarning: d.section == ShellSection.crm,
          onTap: () => AppNav.go(context, d.route),
        );

    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: UiTokens.background,
        border: Border(right: BorderSide(color: UiTokens.border)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Wordmark(),
          const SizedBox(height: 20),
          if (signedIn) ...[
            for (final d in ShellDestinations.mainFor(crmEnabled: crm.enabled)) ...[
              item(d),
              const SizedBox(height: 4),
            ],
            if (auth.isAdmin)
              _SidebarItem(
                destination: const ShellDestination(
                  section: ShellSection.home,
                  label: 'Admin',
                  icon: Icons.shield_outlined,
                  selectedIcon: Icons.shield_rounded,
                  route: '/admin',
                ),
                selected: false,
                onTap: () => Navigator.of(context).pushNamed('/admin'),
              ),
            const Spacer(),
            item(ShellDestinations.account),
          ] else ...[
            item(ShellDestinations.find),
            const Spacer(),
            _SidebarItem(
              destination: const ShellDestination(
                section: ShellSection.account,
                label: 'Sign in',
                icon: Icons.login_rounded,
                selectedIcon: Icons.login_rounded,
                route: '/login',
              ),
              selected: false,
              onTap: () => AppNav.signIn(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Infinity Leads',
      excludeSemantics: true,
      child: Row(
        children: [
          const BrandMark(size: 22, tiled: true, tileSize: 34),
          const SizedBox(width: 10),
          const Flexible(
            child: Text(
              'Infinity Leads',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: UiTokens.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final ShellDestination destination;
  final bool selected;
  final bool emphasised;
  final String? trailing;

  /// Amber badge (CRM follow-ups due) instead of the blue "live" one.
  final bool trailingWarning;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    this.emphasised = false,
    this.trailing,
    this.trailingWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg;
    if (emphasised) {
      bg = selected ? UiTokens.primaryHover : UiTokens.primary;
    } else {
      bg = selected ? UiTokens.selectedSurface : Colors.transparent;
    }
    final fg = emphasised || selected ? Colors.white : UiTokens.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: trailing == null ? destination.label : '${destination.label}, $trailing',
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              // Selection is shown by shape too (left bar), not colour alone.
              border: selected ? const Border(left: BorderSide(color: UiTokens.accent, width: 3)) : null,
            ),
            child: Row(
              children: [
                Icon(selected ? destination.selectedIcon : destination.icon, size: 20, color: fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    destination.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight: selected || emphasised ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (trailing != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: trailingWarning ? UiTokens.partialBg : UiTokens.searchingBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: trailingWarning ? UiTokens.partialFg : UiTokens.searchingFg),
                    ),
                    child: Text(
                      trailing!,
                      style: const TextStyle(
                        color: UiTokens.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tablet rail (768–1023 px, 88 px): icon + label for every item.
class AppNavRail extends StatelessWidget {
  final ShellSection section;

  static const double width = 88;

  const AppNavRail({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final signedIn = auth.isAuthenticated;
    final live = signedIn ? _liveCount(context) : 0;
    final crm = signedIn ? _crm(context) : (enabled: false, due: 0);

    Widget item(ShellDestination d) => _RailItem(
          icon: d.section == section ? d.selectedIcon : d.icon,
          label: d.label,
          selected: d.section == section,
          emphasised: d.section == ShellSection.find,
          badge: d.section == ShellSection.searches && live > 0
              ? '$live live'
              : (d.section == ShellSection.crm && crm.due > 0 ? _dueText(crm.due) : null),
          badgeColor: d.section == ShellSection.crm ? UiTokens.partialFg : UiTokens.searchingFg,
          onTap: () => AppNav.go(context, d.route),
        );

    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: UiTokens.background,
        border: Border(right: BorderSide(color: UiTokens.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
      child: Column(
        children: [
          Semantics(
            label: 'Infinity Leads',
            child: const BrandMark(size: 22, tiled: true, tileSize: 40),
          ),
          const SizedBox(height: 16),
          if (signedIn) ...[
            for (final d in ShellDestinations.mainFor(crmEnabled: crm.enabled)) ...[
              item(d),
              const SizedBox(height: 4),
            ],
            if (auth.isAdmin)
              _RailItem(
                icon: Icons.shield_outlined,
                label: 'Admin',
                selected: false,
                onTap: () => Navigator.of(context).pushNamed('/admin'),
              ),
            const Spacer(),
            item(ShellDestinations.account),
          ] else ...[
            item(ShellDestinations.find),
            const Spacer(),
            _RailItem(
              icon: Icons.login_rounded,
              label: 'Sign in',
              selected: false,
              onTap: () => AppNav.signIn(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool emphasised;
  final String? badge;
  final Color badgeColor;
  final VoidCallback onTap;

  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.emphasised = false,
    this.badge,
    this.badgeColor = UiTokens.searchingFg,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = emphasised
        ? (selected ? UiTokens.primaryHover : UiTokens.primary)
        : (selected ? UiTokens.selectedSurface : Colors.transparent);
    final fg = emphasised || selected ? Colors.white : UiTokens.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: badge == null ? label : '$label, $badge',
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: selected ? const Border(left: BorderSide(color: UiTokens.accent, width: 3)) : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    height: 1.15,
                    fontWeight: selected || emphasised ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: badgeColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Phone bottom bar (<768 px): Home · Find leads · Searches · Credits ·
/// Account. Guests: Find leads · Sign in.
class PhoneBottomBar extends StatelessWidget {
  final ShellSection section;

  const PhoneBottomBar({super.key, required this.section});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final signedIn = auth.isAuthenticated;
    final live = signedIn ? _liveCount(context) : 0;
    final crm = signedIn ? _crm(context) : (enabled: false, due: 0);

    final items = <Widget>[];
    if (signedIn) {
      for (final d in ShellDestinations.phoneFor(crmEnabled: crm.enabled)) {
        final isCrm = d.section == ShellSection.crm;
        items.add(_BottomItem(
          iconAsset: 'assets/nav/${d.section.name}.svg',
          label: d.phoneLabel,
          selected: d.section == section,
          emphasised: d.section == ShellSection.find,
          badge:
              d.section == ShellSection.searches && live > 0 ? '$live' : (isCrm && crm.due > 0 ? '${crm.due}' : null),
          badgeColor: isCrm ? UiTokens.partialFg : UiTokens.searchingFg,
          semanticsSuffix: d.section == ShellSection.searches && live > 0
              ? '$live live'
              : (isCrm && crm.due > 0 ? '${crm.due} follow-ups due' : null),
          onTap: () => AppNav.go(context, d.route),
        ));
      }
    } else {
      const d = ShellDestinations.find;
      items.add(_BottomItem(
        iconAsset: 'assets/nav/find.svg',
        label: d.phoneLabel,
        selected: section == ShellSection.find,
        emphasised: true,
        onTap: () => AppNav.go(context, d.route),
      ));
      items.add(_BottomItem(
        iconAsset: 'assets/nav/account.svg',
        label: 'Sign in',
        selected: false,
        onTap: () => AppNav.signIn(context),
      ));
    }

    return Container(
      decoration: const BoxDecoration(
        color: UiTokens.background,
        border: Border(top: BorderSide(color: UiTokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [for (final w in items) Expanded(child: w)],
          ),
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  final String iconAsset;
  final String label;
  final bool selected;
  final bool emphasised;
  final String? badge;
  final Color badgeColor;
  final String? semanticsSuffix;
  final VoidCallback onTap;

  const _BottomItem({
    required this.iconAsset,
    required this.label,
    required this.selected,
    required this.onTap,
    this.emphasised = false,
    this.badge,
    this.badgeColor = UiTokens.searchingFg,
    this.semanticsSuffix,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : UiTokens.textSecondary;
    Widget iconWidget = SvgPicture.asset(
      iconAsset,
      width: 22,
      height: 22,
      colorFilter: ColorFilter.mode(emphasised ? Colors.white : fg, BlendMode.srcIn),
    );
    if (emphasised) {
      iconWidget = Container(
        width: 40,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? UiTokens.primaryHover : UiTokens.primary,
          borderRadius: BorderRadius.circular(14),
        ),
        child: iconWidget,
      );
    }
    if (badge != null) {
      iconWidget = Badge(
        label: Text(badge!),
        backgroundColor: badgeColor,
        textColor: Colors.black,
        child: iconWidget,
      );
    }
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsSuffix == null ? label : '$label, $semanticsSuffix',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Selected item: indicator bar on top (shape, not colour alone).
            Container(
              width: 24,
              height: 3,
              margin: const EdgeInsets.only(bottom: 5),
              decoration: BoxDecoration(
                color: selected ? UiTokens.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            iconWidget,
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
