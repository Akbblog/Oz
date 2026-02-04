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
import 'core/theme/app_colors.dart';

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
        '/home': (context) => HomeScreen(),
        '/login': (context) => LoginScreen(),
        '/admin': (context) => AdminDashboardScreen(),
        '/admin/revenue': (context) => const AdminRevenueDashboardScreen(),
        '/admin/pricing': (context) => const AdminPricingManagementScreen(),
        '/admin/promos': (context) => const AdminPromoManagementScreen(),
        '/forgot-password': (context) => const ForgotPasswordScreen(),
        '/pricing': (context) => const PricingScreen(),
        '/wallet': (context) => const WalletScreen(),
        '/payment-methods': (context) => const PaymentMethodsScreen(),
        '/subscription': (context) => const SubscriptionManagementScreen(),
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
