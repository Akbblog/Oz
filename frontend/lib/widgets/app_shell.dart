import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_breakpoints.dart';
import '../providers/active_searches_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/scraper_provider.dart';
import 'app_shell_common.dart';
import 'sidebar_navigation.dart';
import 'top_bar.dart';

export 'app_shell_common.dart';

/// Top-level sections of the signed-in app (plan §3).
enum ShellSection { home, find, searches, credits, account }

/// One navigation destination (labels are exact, plan §3).
class ShellDestination {
  final ShellSection section;
  final String label;
  final String phoneLabel;
  final IconData icon;
  final IconData selectedIcon;
  final String route;

  const ShellDestination({
    required this.section,
    required this.label,
    String? phoneLabel,
    required this.icon,
    required this.selectedIcon,
    required this.route,
  }) : phoneLabel = phoneLabel ?? label;
}

class ShellDestinations {
  ShellDestinations._();

  static const home = ShellDestination(
    section: ShellSection.home,
    label: 'Home',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    route: '/home',
  );
  static const find = ShellDestination(
    section: ShellSection.find,
    label: 'Find leads',
    icon: Icons.add_rounded,
    selectedIcon: Icons.add_rounded,
    route: '/find',
  );
  static const searches = ShellDestination(
    section: ShellSection.searches,
    label: 'My searches',
    phoneLabel: 'Searches',
    icon: Icons.list_alt_outlined,
    selectedIcon: Icons.list_alt_rounded,
    route: '/searches',
  );
  static const credits = ShellDestination(
    section: ShellSection.credits,
    label: 'Credits',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet_rounded,
    route: '/credits',
  );
  static const account = ShellDestination(
    section: ShellSection.account,
    label: 'Account',
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
    route: '/account',
  );

  /// Main items (Account sits apart, at the bottom of sidebar/rail).
  static const main = [home, find, searches, credits];
  static const phone = [home, find, searches, credits, account];

  static ShellDestination of(ShellSection s) {
    switch (s) {
      case ShellSection.home:
        return home;
      case ShellSection.find:
        return find;
      case ShellSection.searches:
        return searches;
      case ShellSection.credits:
        return credits;
      case ShellSection.account:
        return account;
    }
  }
}

/// Navigation helpers shared by the shell and pages.
class AppNav {
  AppNav._();

  /// Path of the route showing [context] ("/searches/abc"), without query.
  static String currentPath(BuildContext context) {
    final name = ModalRoute.of(context)?.settings.name ?? '';
    return Uri.tryParse(name)?.path ?? name;
  }

  /// Top-level navigation: `pushNamed` so browser Back walks visited
  /// sections; going to the page that is already shown does nothing.
  static void go(BuildContext context, String route) {
    final target = Uri.tryParse(route)?.path ?? route;
    final current = currentPath(context);
    if (current == target) return;
    if ((target == '/home' && current == '/') ||
        (target == '/credits' && current == '/wallet')) {
      return;
    }
    Navigator.of(context).pushNamed(route);
  }

  /// Opens sign-in and comes back to [returnRoute] (default: this page).
  static void signIn(BuildContext context, {String? returnRoute}) {
    final back = returnRoute ?? currentPath(context);
    final next = (back.isEmpty || back == '/login') ? null : back;
    Navigator.of(context).pushNamed(
      next == null ? '/login' : '/login?next=${Uri.encodeComponent(next)}',
    );
  }

  /// "Sign out" always confirms (plan §3). On confirm: signs out (which
  /// clears drafts and live state via AuthProvider hooks) and opens Find leads.
  static Future<void> confirmSignOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: UiTokens.card,
        title: const Text('Sign out?', style: TextStyle(color: UiTokens.text)),
        content: const Text(
          'Searches that are running keep going on our servers. '
          'Sign in again to follow them.',
          style: TextStyle(color: UiTokens.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: UiTokens.failedFg,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    await context.read<AuthProvider>().logout();
    navigator.pushNamedAndRemoveUntil('/find', (_) => false);
  }
}

/// A queued/running search as shown by the live chip and banner.
class LiveSearch {
  final String jobId;
  final String category;
  final bool queued;
  final int done;
  final int total;

  const LiveSearch({
    required this.jobId,
    required this.category,
    required this.queued,
    required this.done,
    required this.total,
  });

  /// Active searches from [ActiveSearchesProvider] (10 s), refreshed with the
  /// followed job's fresher counters from [ScraperProvider] (2 s), plus that
  /// job when it started after the last active-list fetch.
  static List<LiveSearch> of(BuildContext context) {
    final active = context.watch<ActiveSearchesProvider>();
    final scraper = context.watch<ScraperProvider>();
    final followed = scraper.currentJob;
    final out = <LiveSearch>[];
    var followedSeen = false;
    for (final j in active.jobs) {
      final id = '${j['job_id']}';
      if (followed != null && followed.jobId == id) {
        followedSeen = true;
        if (!followed.isActive) continue; // finished since the last fetch
        out.add(_fromFollowed(followed));
        continue;
      }
      out.add(LiveSearch(
        jobId: id,
        category: jobCategory(j),
        queued: '${j['status']}' == 'pending',
        done: jobInt(j, 'completed_cities'),
        total: jobInt(j, 'total_cities'),
      ));
    }
    if (!followedSeen && followed != null && followed.isActive) {
      out.insert(0, _fromFollowed(followed));
    }
    return out;
  }

  static LiveSearch _fromFollowed(ScrapingJob job) => LiveSearch(
        jobId: job.jobId,
        category: job.category.trim().isEmpty ? 'Search' : job.category.trim(),
        queued: job.isQueued,
        done: job.completedCities,
        total: job.totalCities,
      );

  /// "Searching · plumbers · 2 of 4 cities", "Queued · plumbers" or
  /// "2 searches running".
  static String label(List<LiveSearch> live) {
    if (live.length > 1) return '${live.length} searches running';
    final s = live.first;
    if (s.queued) return 'Queued · ${s.category}';
    return 'Searching · ${s.category} · ${s.done} of ${s.total} cities';
  }

  static String route(List<LiveSearch> live) =>
      live.length == 1 ? '/searches/${live.first.jobId}' : '/searches';
}

/// The signed-in (and guest) app frame: navigation, top bar with credits and
/// the live search chip/banner. Pages are bodies only.
///
/// * ≥1024 px: 232 px sidebar + top bar.
/// * 768–1023 px: 88 px labelled rail + top bar.
/// * <768 px: top bar (title + credits), live banner, 5-item bottom bar.
class AppShell extends StatelessWidget {
  final ShellSection section;
  final String title;
  final Widget child;

  const AppShell({
    super.key,
    required this.section,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final body = Material(
      color: UiTokens.background,
      child: child,
    );

    if (width >= AppBreakpoints.tablet) {
      return Scaffold(
        backgroundColor: UiTokens.background,
        body: SafeArea(
          child: Row(
            children: [
              AppSidebar(section: section),
              Expanded(
                child: Column(
                  children: [
                    AppTopBar(title: title),
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (width >= AppBreakpoints.mobile) {
      return Scaffold(
        backgroundColor: UiTokens.background,
        body: SafeArea(
          child: Row(
            children: [
              AppNavRail(section: section),
              Expanded(
                child: Column(
                  children: [
                    AppTopBar(title: title),
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: UiTokens.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PhoneTopBar(title: title),
            const LiveSearchBanner(),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: PhoneBottomBar(section: section),
    );
  }
}
