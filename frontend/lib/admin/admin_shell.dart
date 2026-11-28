import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../core/admin_roles.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_shell.dart' show AppNav;
import 'admin_kit.dart';

enum AdminSection {
  overview,
  users,
  credits,
  messages,
  searches,
  activity,
  visitors,
  analytics,
  revenue,
  pricing,
  promos,
  settings,
}

class _NavItem {
  final AdminSection section;
  final String label;
  final IconData icon;
  final String route;
  const _NavItem(this.section, this.label, this.icon, this.route);
}

class _NavGroup {
  final String? title;
  final List<_NavItem> items;
  const _NavGroup(this.title, this.items);
}

const List<_NavGroup> _nav = [
  _NavGroup(null, [
    _NavItem(AdminSection.overview, 'Overview', Icons.space_dashboard_outlined,
        '/admin'),
  ]),
  _NavGroup('People', [
    _NavItem(AdminSection.users, 'Users', Icons.group_outlined, '/admin/users'),
    _NavItem(AdminSection.credits, 'Credit requests',
        Icons.request_quote_outlined, '/admin/credits'),
    _NavItem(AdminSection.messages, 'Messages',
        Icons.mark_email_unread_outlined, '/admin/messages'),
  ]),
  _NavGroup('Activity', [
    _NavItem(AdminSection.searches, 'Searches', Icons.travel_explore,
        '/admin/searches'),
    _NavItem(AdminSection.activity, 'Activity log', Icons.history,
        '/admin/activity'),
    _NavItem(AdminSection.visitors, 'Visitors', Icons.public,
        '/admin/visitors'),
    _NavItem(AdminSection.analytics, 'Analytics', Icons.insights,
        '/admin/analytics'),
  ]),
  _NavGroup('Money', [
    _NavItem(AdminSection.revenue, 'Revenue', Icons.payments_outlined,
        '/admin/revenue'),
    _NavItem(AdminSection.pricing, 'Pricing', Icons.sell_outlined,
        '/admin/pricing'),
    _NavItem(AdminSection.promos, 'Promo codes', Icons.local_offer_outlined,
        '/admin/promos'),
  ]),
  _NavGroup('System', [
    _NavItem(AdminSection.settings, 'Settings', Icons.tune, '/admin/settings'),
  ]),
];

/// Counts shown as badges in the sidebar (work waiting for a decision).
/// Shared by every admin page; refreshed at most once a minute unless forced.
class AdminBadges extends ChangeNotifier {
  AdminBadges._();
  static final AdminBadges instance = AdminBadges._();

  /// Replaced in tests.
  static ApiService Function() apiFactory = ApiService.new;

  int pendingUsers = 0;
  int creditRequests = 0;
  int newMessages = 0;
  DateTime? _loadedAt;
  bool _loading = false;

  Future<void> refresh({bool force = false}) async {
    if (_loading) return;
    if (!force &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < const Duration(seconds: 60)) {
      return;
    }
    _loading = true;
    try {
      final data = await apiFactory().getAdminOverview('24h');
      final snap = data['snapshot'];
      if (snap is Map) {
        pendingUsers = (snap['pending_users'] as num?)?.toInt() ?? 0;
        creditRequests =
            (snap['pending_credit_requests'] as num?)?.toInt() ?? 0;
        _loadedAt = DateTime.now();
        notifyListeners();
      }
      // Unread contact messages (absent on a backend without the inbox).
      try {
        final summary = await apiFactory().getAdminContactSummary();
        final n = (summary['new'] as num?)?.toInt() ?? 0;
        if (n != newMessages) {
          newMessages = n;
          notifyListeners();
        }
      } catch (_) {}
    } catch (_) {
      // Badges are a convenience; pages report their own load errors.
    } finally {
      _loading = false;
    }
  }

  int countFor(AdminSection s) => switch (s) {
        AdminSection.users => pendingUsers,
        AdminSection.credits => creditRequests,
        AdminSection.messages => newMessages,
        _ => 0,
      };
}

/// Page frame for every admin screen: sidebar (rail on medium widths, drawer
/// on phones), a header with the page title and actions, and the body.
class AdminScaffold extends StatefulWidget {
  final AdminSection section;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  /// When false the body manages its own scrolling (embedded legacy screens).
  final bool scroll;

  const AdminScaffold({
    super.key,
    required this.section,
    required this.title,
    this.subtitle,
    this.actions = const [],
    required this.child,
    this.scroll = true,
  });

  @override
  State<AdminScaffold> createState() => _AdminScaffoldState();
}

class _AdminScaffoldState extends State<AdminScaffold> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    AdminBadges.instance.refresh();
  }

  void _go(String route) {
    final current = AppNav.currentPath(context);
    if (current == route) return;
    Navigator.of(context).pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final mobile = width < 820;
    final rail = !mobile && width < 1180;

    final sidebar = _Sidebar(
      section: widget.section,
      collapsed: rail,
      onGo: (route) {
        if (mobile) Navigator.of(context).pop();
        _go(route);
      },
    );

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: AC.bg,
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: AC.raised,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AC.borderStrong),
          ),
          textStyle: const TextStyle(color: AC.text, fontSize: 12),
        ),
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AC.bg,
        drawer: mobile
            ? Drawer(
                backgroundColor: AC.sidebar,
                width: 264,
                child: SafeArea(child: sidebar),
              )
            : null,
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!mobile)
                Container(
                  width: rail ? 64 : 236,
                  decoration: const BoxDecoration(
                    color: AC.sidebar,
                    border: Border(right: BorderSide(color: AC.border)),
                  ),
                  child: sidebar,
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(mobile),
                    Expanded(
                      child: widget.scroll
                          ? SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(
                                  mobile ? 12 : 24, 4, mobile ? 12 : 24, 40),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 1480),
                                  child: widget.child,
                                ),
                              ),
                            )
                          : widget.child,
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

  Widget _header(bool mobile) {
    return Padding(
      padding: EdgeInsets.fromLTRB(mobile ? 4 : 24, 14, mobile ? 8 : 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (mobile)
            AIconButton(Icons.menu, 'Menu',
                onPressed: () => _scaffoldKey.currentState?.openDrawer()),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title,
                    style: AT.h1, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (widget.subtitle != null && !mobile)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(widget.subtitle!,
                        style: AT.mute,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          for (final a in widget.actions) ...[a, const SizedBox(width: 8)],
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final AdminSection section;
  final bool collapsed;
  final ValueChanged<String> onGo;
  const _Sidebar({
    required this.section,
    required this.collapsed,
    required this.onGo,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final name = '${user?['username'] ?? 'Admin'}';
    final role = AdminRoles.roleOf(user);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(collapsed ? 14 : 16, 16, 12, 14),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AC.primary,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: SvgPicture.asset(
                  'assets/logo_mark.svg',
                  colorFilter:
                      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
              ),
              if (!collapsed) ...[
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Infinity Leads',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AC.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w700)),
                      Text('Admin console', style: AT.mute),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: AdminBadges.instance,
            builder: (context, _) => ListView(
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 10 : 10),
              children: [
                for (final g in _nav) ...[
                  if (g.title != null)
                    collapsed
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(height: 1, color: AC.border),
                          )
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
                            child: Text(g.title!.toUpperCase(), style: AT.label),
                          ),
                  for (final it in g.items)
                    _NavTile(
                      item: it,
                      active: it.section == section,
                      collapsed: collapsed,
                      badge: AdminBadges.instance.countFor(it.section),
                      onTap: () => onGo(it.route),
                    ),
                ],
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: AC.border),
        Padding(
          padding: const EdgeInsets.all(10),
          child: collapsed
              ? Column(
                  children: [
                    AIconButton(Icons.arrow_back, 'Back to the app',
                        onPressed: () => Navigator.of(context)
                            .pushNamedAndRemoveUntil('/home', (_) => false)),
                    AIconButton(Icons.logout, 'Sign out',
                        onPressed: () => AppNav.confirmSignOut(context)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        AAvatar(name, size: 30),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AT.body
                                      .copyWith(fontWeight: FontWeight.w600)),
                              Text(
                                  '${role[0].toUpperCase()}${role.substring(1)}',
                                  style: AT.mute),
                            ],
                          ),
                        ),
                        AIconButton(Icons.logout, 'Sign out',
                            onPressed: () => AppNav.confirmSignOut(context)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AButton('Back to the app',
                        icon: Icons.arrow_back,
                        expand: true,
                        onPressed: () => Navigator.of(context)
                            .pushNamedAndRemoveUntil('/home', (_) => false)),
                  ],
                ),
        ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  final _NavItem item;
  final bool active;
  final bool collapsed;
  final int badge;
  final VoidCallback onTap;
  const _NavTile({
    required this.item,
    required this.active,
    required this.collapsed,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? AC.text : AC.textDim;
    final badgeDot = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: AC.amber.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$badge',
          style: const TextStyle(
              color: AC.amber, fontSize: 11, fontWeight: FontWeight.w700)),
    );
    final tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Material(
        color: active ? AC.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: AC.hover,
          child: SizedBox(
            height: 38,
            child: collapsed
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(item.icon,
                          size: 19, color: active ? AC.accent : fg),
                      if (badge > 0)
                        Positioned(
                          right: 8,
                          top: 7,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                                color: AC.amber, shape: BoxShape.circle),
                          ),
                        ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(item.icon,
                            size: 18, color: active ? AC.accent : fg),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Text(item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: fg,
                                  fontSize: 13.5,
                                  fontWeight: active
                                      ? FontWeight.w600
                                      : FontWeight.w500)),
                        ),
                        if (badge > 0) badgeDot,
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
    return collapsed ? Tooltip(message: item.label, child: tile) : tile;
  }
}
