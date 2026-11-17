import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/active_searches_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/credit_provider.dart';
import 'providers/crm_provider.dart';
import 'providers/scraper_provider.dart';
import 'providers/search_setup_provider.dart';
import 'providers/theme_provider.dart';
import 'services/analytics_service.dart';

void main() {
  // Clean URLs on web (e.g. /searches/abc instead of /#/searches/abc).
  usePathUrlStrategy();
  AnalyticsService.instance.init();
  runApp(
    MultiProvider(
      providers: buildAppProviders(),
      child: const MyApp(),
    ),
  );
}

/// App-wide providers (also used by tests).
List<SingleChildWidget> buildAppProviders() => [
      ChangeNotifierProvider(create: (context) => ThemeProvider()),
      ChangeNotifierProvider(create: (context) => AuthProvider()),
      ChangeNotifierProvider(create: (context) => ScraperProvider()),
      ChangeNotifierProvider<CreditProvider>.value(value: CreditProvider.instance),
      ChangeNotifierProvider(create: (context) => SearchSetupProvider()),
      ChangeNotifierProvider(create: (context) => ActiveSearchesProvider()),
      ChangeNotifierProvider(create: (context) => CrmProvider()),
    ];

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

/// Also coordinates the session: on sign-in it loads credits, starts the
/// live-search poll and resumes following a job; on every sign-out it clears
/// the search setup and drafts, live state and the followed job.
class _MyAppState extends State<MyApp> {
  late final AuthProvider _auth;
  VoidCallback? _removeSignOutHook;
  int _handledSession = 0;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthProvider>();
    _removeSignOutHook = _auth.addSignOutHook(_onSignOut);
    _auth.addListener(_onAuthChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onAuthChanged());
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _removeSignOutHook?.call();
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted || _auth.isRestoring || _auth.isLoading) return;
    if (_auth.isAuthenticated) {
      if (_auth.sessionGeneration == _handledSession) return;
      _handledSession = _auth.sessionGeneration;
      _signedIn = true;
      final credits = CreditProvider.instance;
      unawaited(credits.refresh());
      unawaited(credits.loadConfig(force: true));
      context.read<ActiveSearchesProvider>().start();
      unawaited(context.read<ScraperProvider>().resumeAfterSignIn());
      // CRM navigation appears only when the server has CRM enabled.
      unawaited(context.read<CrmProvider>().start());
    } else if (_signedIn) {
      // Session ended without an explicit sign-out (e.g. rejected token).
      _signedIn = false;
      context.read<ActiveSearchesProvider>().stop();
      context.read<ScraperProvider>().detach();
      context.read<CrmProvider>().clear();
      CreditProvider.instance.clear();
    }
  }

  Future<void> _onSignOut() async {
    _signedIn = false;
    if (!mounted) return;
    final setup = context.read<SearchSetupProvider>();
    final scraper = context.read<ScraperProvider>();
    final active = context.read<ActiveSearchesProvider>();
    active.stop();
    context.read<CrmProvider>().clear();
    CreditProvider.instance.clear();
    await scraper.signOut();
    await setup.clear();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Infinity Leads',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      onGenerateRoute: AppRouter.onGenerateRoute,
      onGenerateInitialRoutes: AppRouter.onGenerateInitialRoutes,
    );
  }
}
