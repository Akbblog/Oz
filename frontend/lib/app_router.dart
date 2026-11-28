import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'providers/active_searches_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/scraper_provider.dart';
import 'admin/admin_kit.dart' show AC;
import 'admin/admin_shell.dart';
import 'admin/pages/activity_page.dart';
import 'admin/pages/analytics_page.dart';
import 'admin/pages/credits_page.dart';
import 'admin/pages/messages_page.dart';
import 'admin/pages/overview_page.dart';
import 'admin/pages/pricing_page.dart';
import 'admin/pages/revenue_page.dart';
import 'admin/pages/settings_page.dart';
import 'admin/pages/users_page.dart';
import 'admin/pages/visitors_page.dart';
import 'screens/admin_jobs_screen.dart';
import 'screens/admin_promo_management_screen.dart';
import 'screens/crm/crm_agenda_screen.dart';
import 'screens/crm/crm_contacts_screen.dart';
import 'screens/crm/crm_leads_screen.dart';
import 'screens/crm/crm_pipeline_screen.dart';
import 'screens/crm/crm_record_screen.dart';
import 'screens/crm/crm_reports_screen.dart';
import 'screens/find/details_step.dart';
import 'screens/find/location_step.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/contact_screen.dart';
import 'screens/home_screen.dart';
import 'screens/landing/landing_screen.dart';
import 'screens/live_payments_gate_screen.dart';
import 'screens/login_screen.dart';
import 'screens/my_searches_screen.dart';
import 'screens/payment_methods_screen.dart';
import 'screens/payment_return_screen.dart';
import 'screens/pricing_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/register_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/search_detail_screen.dart';
import 'screens/subscription_management_screen.dart';
import 'screens/wallet_coming_soon_screen.dart';
import 'screens/wallet_screen.dart';
import 'services/analytics_service.dart';
import 'widgets/app_shell.dart';

/// Route table (brief "Routes"). Path URL strategy is on, so every route is a
/// real URL; a cold load of any of them (e.g. `/searches/<id>`) works once the
/// saved session has been checked.
///
/// * `/`, `/home` → Home (guests → `/find`)
/// * `/find`, `/find/details` → Find leads steps (open to guests)
/// * `/searches`, `/searches/<id>`, `/credits` (`/wallet`), `/account` →
///   signed-in only; without a session the sign-in form is shown in place
///   and the page appears right after signing in.
/// * `/crm` (pipeline), `/crm/leads`, `/crm/activities`, `/crm/contacts`,
///   `/crm/reports`, `/crm/records/<id>` → signed-in CRM pages; filters
///   live in the query string (`/crm/leads?source=<job>&outcome=all`).
/// * `/login?next=<route>` → sign in, then open `<route>`.
class AppRouter {
  AppRouter._();

  /// Exactly one initial route (the URL the app was opened with), so a deep
  /// link does not build Home and My searches underneath.
  static List<Route<dynamic>> onGenerateInitialRoutes(String initialRoute) {
    final route = onGenerateRoute(RouteSettings(name: initialRoute)) ??
        onGenerateRoute(const RouteSettings(name: '/'))!;
    return [route];
  }

  /// Only same-app paths are accepted as a return route.
  static String? safeReturnRoute(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (!value.startsWith('/') || value.startsWith('//')) return null;
    final path = Uri.tryParse(value)?.path ?? '';
    if (path.isEmpty || path == '/login') return null;
    return value;
  }

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    // Every navigation is a page view (and keeps the visit record fresh).
    AnalyticsService.instance.routeChanged(settings.name);
    final uri = Uri.tryParse(settings.name ?? '/') ?? Uri(path: '/');
    var path = uri.path.isEmpty ? '/' : uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    switch (path) {
      case '/':
        // Visitors get the landing page; signed-in people go straight to Home.
        return _shell(settings, const _RootPage());
      case '/contact':
        return _page(settings, const ContactScreen());
      case '/home':
        return _shell(settings, const ShellPage(
          section: ShellSection.home,
          title: 'Home',
          requiresAuth: true,
          guestRedirect: '/find',
          child: HomeScreen(),
        ));
      case '/find':
        return _shell(settings, const ShellPage(
          section: ShellSection.find,
          title: 'Find leads',
          child: FindLocationStep(),
        ));
      case '/find/details':
        return _shell(settings, const ShellPage(
          section: ShellSection.find,
          title: 'Find leads',
          child: FindDetailsStep(),
        ));
      case '/searches':
        return _shell(settings, const ShellPage(
          section: ShellSection.searches,
          title: 'My searches',
          requiresAuth: true,
          child: MySearchesScreen(),
        ));
      case '/credits':
      case '/wallet':
        return _shell(settings, const ShellPage(
          section: ShellSection.credits,
          title: 'Credits',
          requiresAuth: true,
          child: LivePaymentsGateScreen(
            enabledChild: WalletScreen(enableLivePayments: true),
            disabledChild: WalletComingSoonScreen(),
          ),
        ));
      case '/account':
        return _shell(settings, const ShellPage(
          section: ShellSection.account,
          title: 'Account',
          requiresAuth: true,
          child: ProfileScreen(),
        ));
      case '/crm':
        return _crm(settings, 'pipeline', CrmPipelineScreen(initialQuery: uri.queryParameters));
      case '/crm/leads':
        return _crm(settings, 'leads', CrmLeadsScreen(initialQuery: uri.queryParameters));
      case '/crm/activities':
        return _crm(settings, 'activities', CrmAgendaScreen(initialQuery: uri.queryParameters));
      case '/crm/contacts':
        return _crm(settings, 'contacts', CrmContactsScreen(initialQuery: uri.queryParameters));
      case '/crm/reports':
        return _crm(settings, 'reports', CrmReportsScreen(initialQuery: uri.queryParameters));
      case '/login':
        final args = settings.arguments;
        final next = safeReturnRoute(uri.queryParameters['next'] ??
            (args is Map ? args['next'] as String? : (args is String ? args : null)));
        return _page(settings, LoginScreen(returnRoute: next));
      case '/register':
        return _page(settings, const RegisterScreen());
      case '/forgot-password':
        return _page(settings, const ForgotPasswordScreen());
      case '/privacy-policy':
      case '/privacy':
        return _page(settings, const PrivacyPolicyScreen());
      case '/pricing':
        // Packages and checkout need the signed-in user; wait for the saved session first.
        return _page(settings, const ProtectedRoute(child: PricingScreen()));
      case '/wallet-coming-soon':
        return _page(settings, const ProtectedRoute(child: WalletComingSoonScreen()));
      case '/wallet-request-credits':
        return _page(
          settings,
          const ProtectedRoute(
            child: WalletScreen(enableLivePayments: false, initialTabIndex: 1),
          ),
        );
      case '/payment-methods':
        return _page(
          settings,
          const ProtectedRoute(
            child: LivePaymentsGateScreen(
              enabledChild: PaymentMethodsScreen(),
              disabledChild: WalletComingSoonScreen(),
            ),
          ),
        );
      case '/subscription':
        return _page(settings, const ProtectedRoute(child: SubscriptionManagementScreen()));
      case '/admin':
        return _admin(settings, const AdminOverviewPage());
      case '/admin/users':
        return _admin(settings, AdminUsersPage(query: uri.queryParameters));
      case '/admin/credits':
        return _admin(settings, const AdminCreditsPage());
      case '/admin/messages':
        return _admin(settings, const AdminMessagesPage());
      case '/admin/searches':
      case '/admin/jobs':
        return _admin(
          settings,
          const AdminScaffold(
            section: AdminSection.searches,
            title: 'Searches',
            subtitle: 'Every search run by every user, with results and downloads',
            scroll: false,
            child: AdminJobsScreen(showHeader: false),
          ),
        );
      case '/admin/activity':
        return _admin(settings, const AdminActivityPage());
      case '/admin/visitors':
        return _admin(settings, const AdminVisitorsPage());
      case '/admin/analytics':
        return _admin(settings, const AdminAnalyticsPage());
      case '/admin/revenue':
        return _admin(settings, const AdminRevenuePage());
      case '/admin/pricing':
        return _admin(settings, const AdminPricingPage());
      case '/admin/promos':
        return _admin(
          settings,
          const AdminScaffold(
            section: AdminSection.promos,
            title: 'Promo codes',
            subtitle: 'Create codes, see who used them and switch them off',
            scroll: false,
            child: AdminPromoManagementScreen(embedded: true),
          ),
        );
      case '/admin/settings':
        return _admin(settings, const AdminSettingsPage());
    }

    // Safepay hosted checkout returns here (redirect_url / cancel_url).
    for (final prefix in const ['/payment/return/', '/payment/cancelled/']) {
      if (path.startsWith(prefix)) {
        final txn = Uri.decodeComponent(path.substring(prefix.length));
        if (txn.isNotEmpty && !txn.contains('/')) {
          return _page(
            settings,
            ProtectedRoute(
              child: PaymentReturnScreen(
                transactionId: txn,
                cancelled: prefix == '/payment/cancelled/',
              ),
            ),
          );
        }
      }
    }

    if (path.startsWith('/searches/')) {
      final jobId = Uri.decodeComponent(path.substring('/searches/'.length));
      if (jobId.isNotEmpty && !jobId.contains('/')) {
        return _shell(settings, ShellPage(
          section: ShellSection.searches,
          title: 'Search',
          searchJobId: jobId,
          requiresAuth: true,
          child: SearchDetailScreen(key: ValueKey('search-$jobId'), jobId: jobId),
        ));
      }
    }
    if (path.startsWith('/crm/records/')) {
      final id = Uri.decodeComponent(path.substring('/crm/records/'.length));
      if (id.isNotEmpty && !id.contains('/')) {
        return _crm(settings, 'record-$id', CrmRecordScreen(recordId: id));
      }
    }
    if (path.startsWith('/reset-password/')) {
      final token = path.substring('/reset-password/'.length);
      return _page(settings, ResetPasswordScreen(token: token));
    }
    if (path == '/reset-password') return null;

    return _shell(settings, const ShellPage(
      section: ShellSection.home,
      title: 'Page not found',
      child: _NotFound(),
    ));
  }

  /// A signed-in CRM page (sign-in shown in place, then the page).
  static Route<dynamic> _crm(RouteSettings settings, String key, Widget child) => _shell(
        settings,
        ShellPage(
          key: ValueKey('crm-$key-${settings.name}'),
          section: ShellSection.crm,
          title: 'CRM',
          requiresAuth: true,
          child: child,
        ),
      );

  /// Admin console pages: admins only, switching without a transition.
  static Route<dynamic> _admin(RouteSettings settings, Widget page) => _shell(
        settings,
        ColoredBox(
          color: AC.bg,
          child: ProtectedRoute(requireAdmin: true, child: page),
        ),
      );

  /// Shell sections switch without a transition animation.
  static Route<dynamic> _shell(RouteSettings settings, Widget page) => PageRouteBuilder<dynamic>(
        settings: settings,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) => page,
      );

  static Route<dynamic> _page(RouteSettings settings, Widget page) =>
      MaterialPageRoute<dynamic>(settings: settings, builder: (_) => page);
}

/// A shell page: waits for the saved session, applies the auth rules and
/// wraps the body in [AppShell].
class ShellPage extends StatelessWidget {
  final ShellSection section;
  final String title;
  final Widget child;
  final bool requiresAuth;

  /// Where guests are sent instead (Home → `/find`).
  final String? guestRedirect;

  /// For `/searches/<id>`: the title becomes "Search · {category}".
  final String? searchJobId;

  const ShellPage({
    super.key,
    required this.section,
    required this.title,
    required this.child,
    this.requiresAuth = false,
    this.guestRedirect,
    this.searchJobId,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isRestoring) return const BootSplash();

    if (!auth.isAuthenticated) {
      if (guestRedirect != null) {
        final route = ModalRoute.of(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (route != null && route.isCurrent && context.mounted) {
            Navigator.of(context).pushReplacementNamed(guestRedirect!);
          }
        });
        return const AppShell(
          section: ShellSection.find,
          title: 'Find leads',
          child: FindLocationStep(),
        );
      }
      if (requiresAuth) {
        // Sign in here; this page replaces the form once signed in.
        return const LoginScreen(inline: true);
      }
    }

    return AppShell(
      section: section,
      title: searchJobId == null ? title : _searchTitle(context, searchJobId!),
      child: child,
    );
  }

  static String _searchTitle(BuildContext context, String jobId) {
    String? category;
    final followed = context.watch<ScraperProvider>().currentJob;
    if (followed != null && followed.jobId == jobId) category = followed.category;
    category ??= context.watch<ActiveSearchesProvider>().jobById(jobId)?['category'] as String?;
    final c = category?.trim() ?? '';
    return c.isEmpty ? 'Search' : 'Search · $c';
  }
}

/// `/`: the landing page for visitors, Home for signed-in people.
class _RootPage extends StatelessWidget {
  const _RootPage();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isRestoring) return const BootSplash();
    if (!auth.isAuthenticated) return const LandingScreen();
    return const AppShell(
      section: ShellSection.home,
      title: 'Home',
      child: HomeScreen(),
    );
  }
}

/// Signed-in pages outside the shell (wallet sub-pages, admin).
class ProtectedRoute extends StatelessWidget {
  final Widget child;
  final bool requireAdmin;

  const ProtectedRoute({super.key, required this.child, this.requireAdmin = false});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isRestoring) return const BootSplash();
    if (!auth.isAuthenticated) return const LoginScreen(inline: true);
    if (requireAdmin && !auth.isAdmin) return const _AccessDeniedScreen();
    return child;
  }
}

/// Shown while the saved session is checked.
class BootSplash extends StatelessWidget {
  const BootSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiTokens.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: AppSpacing.borderRadiusXl,
              ),
              child: SvgPicture.asset(
                'assets/logo_mark.svg',
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text(
              'Infinity Leads',
              style: TextStyle(color: UiTokens.text, fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.md),
            const SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                backgroundColor: UiTokens.border,
                valueColor: AlwaysStoppedAnimation<Color>(UiTokens.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "This page doesn't exist.",
              style: TextStyle(color: UiTokens.text, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: UiTokens.primary),
              onPressed: () => Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false),
              child: const Text('Go to Home'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessDeniedScreen extends StatelessWidget {
  const _AccessDeniedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiTokens.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, color: UiTokens.accent, size: 48),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Admin access required',
                  style: TextStyle(color: UiTokens.text, fontSize: 20, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'Your account does not have permission to view this page.',
                  style: TextStyle(color: UiTokens.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: UiTokens.primary),
                    onPressed: () => Navigator.of(context).pushReplacementNamed('/home'),
                    child: const Text('Go to Home'),
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
