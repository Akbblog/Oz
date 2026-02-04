import 'package:flutter/material.dart';
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
import 'providers/scraper_provider.dart';
import 'providers/auth_provider.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
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
    return MaterialApp(
      title: 'Infinity Leads',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const AuthWrapper(),
      routes: {
        '/home': (context) => const _ProtectedRoute(child: HomeScreen()),
        '/login': (context) => LoginScreen(),
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
        '/wallet': (context) => const _ProtectedRoute(child: WalletScreen()),
        '/payment-methods': (context) => const _ProtectedRoute(child: PaymentMethodsScreen()),
        '/subscription': (context) => const _ProtectedRoute(child: SubscriptionManagementScreen()),
      },
      onGenerateRoute: (settings) {
        // Handle reset password route with token parameter
        if (settings.name != null && settings.name!.startsWith('/reset-password/')) {
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
        body: Container(
          decoration: const BoxDecoration(
            gradient: AppColors.darkGradient,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated Logo
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: AppSpacing.borderRadiusXl,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryStart.withValues(alpha: 0.4),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
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
                  style: AppTypography.headlineMediumLight,
                ),
                const SizedBox(height: AppSpacing.md),
                const SizedBox(
                  width: 200,
                  child: LinearProgressIndicator(
                    backgroundColor: AppColors.glassWhite,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryStart),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (authProvider.isAuthenticated) {
      return HomeScreen();
    }

    return LoginScreen();
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.darkGradient,
        ),
        child: const Center(
          child: SizedBox(
            width: 200,
            child: LinearProgressIndicator(
              backgroundColor: AppColors.glassWhite,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryStart),
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.darkGradient,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, color: Colors.white, size: 48),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Admin access required',
                    style: AppTypography.titleLargeLight,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Your account does not have permission to view this page.',
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pushReplacementNamed('/home'),
                      child: const Text('Go to Home'),
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
