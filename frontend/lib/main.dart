import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/admin_revenue_dashboard_screen.dart';
import 'screens/admin_pricing_management_screen.dart';
import 'screens/admin_promo_management_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/reset_password_screen.dart';
import 'screens/pricing_screen.dart';
import 'screens/wallet_screen.dart';
import 'screens/payment_methods_screen.dart';
import 'screens/subscription_management_screen.dart';
import 'screens/live_payments_gate_screen.dart';
import 'screens/wallet_coming_soon_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'providers/scraper_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'core/theme/app_theme.dart';

void main() {
  // Enable clean URLs on web (e.g., /privacy-policy instead of /#/privacy-policy).
  usePathUrlStrategy();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
        ChangeNotifierProvider(create: (context) => AuthProvider()),
        ChangeNotifierProvider(create: (context) => ScraperProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Infinity Leads',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      debugShowCheckedModeBanner: false,
      routes: {
        '/': (context) => const AuthWrapper(),
        '/home': (context) => const HomeScreen(),
        '/login': (context) => LoginScreen(),
        '/privacy-policy': (context) => const PrivacyPolicyScreen(),
        '/privacy': (context) => const PrivacyPolicyScreen(),
        '/admin': (context) => const _ProtectedRoute(
              requireAdmin: true,
              child: AdminDashboardScreen(),
            ),
        '/admin/revenue': (context) => const _ProtectedRoute(
              requireAdmin: true,
              child: AdminRevenueDashboardScreen(),
            ),
        '/admin/pricing': (context) => const _ProtectedRoute(
              requireAdmin: true,
              child: AdminPricingManagementScreen(),
            ),
        '/admin/promos': (context) => const _ProtectedRoute(
              requireAdmin: true,
              child: AdminPromoManagementScreen(),
            ),
        '/forgot-password': (context) => const ForgotPasswordScreen(),
        '/pricing': (context) => const PricingScreen(),
        '/wallet': (context) => const _ProtectedRoute(
              child: LivePaymentsGateScreen(
                enabledChild: WalletScreen(enableLivePayments: true),
                disabledChild: WalletComingSoonScreen(),
              ),
            ),
        '/wallet-coming-soon': (context) =>
            const _ProtectedRoute(child: WalletComingSoonScreen()),
        '/wallet-request-credits': (context) => const _ProtectedRoute(
              child:
                  WalletScreen(enableLivePayments: false, initialTabIndex: 1),
            ),
        '/payment-methods': (context) => const _ProtectedRoute(
              child: LivePaymentsGateScreen(
                enabledChild: PaymentMethodsScreen(),
                disabledChild: WalletComingSoonScreen(),
              ),
            ),
        '/subscription': (context) =>
            const _ProtectedRoute(child: SubscriptionManagementScreen()),
      },
      onGenerateRoute: (settings) {
        // Handle reset password route with token parameter
        if (settings.name != null &&
            settings.name!.startsWith('/reset-password/')) {
          final token = settings.name!.substring('/reset-password/'.length);
          return MaterialPageRoute(
            builder: (context) => ResetPasswordScreen(token: token),
          );
        }
        return null;
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated Logo
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue,
                  borderRadius: AppSpacing.borderRadiusXl,
                  boxShadow:
                      AtlassianShadows.getCard(Theme.of(context).brightness),
                ),
                child: SvgPicture.asset(
                  'assets/logo_mark.svg',
                  width: 50,
                  height: 50,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Infinity Leads',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  backgroundColor:
                      Theme.of(context).colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const HomeScreen();
  }
}

class _ProtectedRoute extends StatelessWidget {
  final Widget child;
  final bool requireAdmin;

  const _ProtectedRoute({
    required this.child,
    this.requireAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    if (authProvider.isLoading) {
      return const _FullScreenLoading();
    }

    if (!authProvider.isAuthenticated) {
      return LoginScreen();
    }

    if (requireAdmin && !authProvider.isAdmin) {
      return const _AccessDeniedScreen();
    }

    return child;
  }
}

class _FullScreenLoading extends StatelessWidget {
  const _FullScreenLoading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: SizedBox(
          width: 200,
          child: LinearProgressIndicator(
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              Theme.of(context).colorScheme.primary,
            ),
          ),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  color: Theme.of(context).colorScheme.primary,
                  size: 48,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Admin access required',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your account does not have permission to view this page.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.of(context).pushReplacementNamed('/home'),
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
