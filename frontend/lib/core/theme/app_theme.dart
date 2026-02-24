import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

export 'app_colors.dart';
export 'app_spacing.dart';
export 'app_typography.dart';
export 'atlassian_shadows.dart';

/// Atlassian Design System Theme Configuration
/// Provides light and dark themes with clean, professional styling
class AppTheme {
  AppTheme._();

  // ==========================================================================
  // LIGHT THEME
  // ==========================================================================

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.light(
          primary: AppColors.primaryBlue,
          onPrimary: Colors.white,
          primaryContainer: AppColors.selectedLight,
          onPrimaryContainer: AppColors.primaryBlueDark,
          secondary: AppColors.brandPurple,
          onSecondary: Colors.white,
          error: AppColors.dangerRed,
          onError: Colors.white,
          surface: AppColors.surfaceLight,
          onSurface: AppColors.textPrimaryLight,
          surfaceContainerHighest: AppColors.backgroundLight,
          outline: AppColors.borderLight,
          outlineVariant: AppColors.borderLightAlt,
        ),
        scaffoldBackgroundColor: AppColors.backgroundLight,

        // AppBar Theme - Clean Atlassian style
        appBarTheme: AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          backgroundColor: AppColors.surfaceLight,
          foregroundColor: AppColors.textPrimaryLight,
          titleTextStyle: AppTypography.titleLarge.copyWith(
            color: AppColors.textPrimaryLight,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: AppColors.textPrimaryLight),
          actionsIconTheme: IconThemeData(color: AppColors.textSecondaryLight),
          surfaceTintColor: Colors.transparent,
        ),

        // Card Theme - Atlassian subtle shadow
        cardTheme: CardThemeData(
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderRadiusMd,
            side: BorderSide(color: AppColors.borderLight, width: 1),
          ),
          color: AppColors.surfaceLight,
          margin: const EdgeInsets.all(0),
        ),

        // Elevated Button Theme - Primary action styling (Deep Teal)
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            elevation: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) return 0;
              if (states.contains(WidgetState.hovered)) return 6;
              return 0;
            }),
            shadowColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return AppColors.primaryBlue.withValues(alpha: 0.55);
              }
              return AppColors.primaryBlue.withValues(alpha: 0.0);
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.disabledLight;
              }
              if (states.contains(WidgetState.hovered)) {
                return AppColors.brighten(AppColors.primaryBlue, 0.10);
              }
              return AppColors.primaryBlue;
            }),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
            minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusLg),
            ),
            textStyle: WidgetStatePropertyAll(
              AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ),

        // Outlined Button Theme
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.textDisabledLight;
              }
              if (states.contains(WidgetState.hovered)) {
                return AppColors.brighten(AppColors.primaryBlue, 0.10);
              }
              return AppColors.primaryBlue;
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return AppColors.primaryBlue.withValues(alpha: 0.10);
              }
              return null;
            }),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
            minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusLg),
            ),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return BorderSide(color: AppColors.borderLight, width: 1);
              }
              final color = states.contains(WidgetState.hovered)
                  ? AppColors.brighten(AppColors.primaryBlue, 0.10)
                  : AppColors.primaryBlue;
              return BorderSide(color: color, width: 1);
            }),
            textStyle: WidgetStatePropertyAll(
              AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ),

        // Text Button Theme - Subtle, but teal-consistent
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.textDisabledLight;
              }
              if (states.contains(WidgetState.hovered)) {
                return AppColors.brighten(AppColors.primaryBlue, 0.10);
              }
              return AppColors.primaryBlue;
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return AppColors.primaryBlue.withValues(alpha: 0.10);
              }
              return null;
            }),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
            ),
            minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
            textStyle: WidgetStatePropertyAll(
              AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ),

        // Input Decoration Theme - Atlassian clean inputs
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.inputBackgroundLight,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          border: OutlineInputBorder(
            borderRadius: AppSpacing.borderRadiusMd,
            borderSide: BorderSide(color: AppColors.inputBorderLight, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppSpacing.borderRadiusMd,
            borderSide: BorderSide(color: AppColors.inputBorderLight, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppSpacing.borderRadiusMd,
            borderSide: BorderSide(
              color: AppColors.inputBorderFocusLight,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: AppSpacing.borderRadiusMd,
            borderSide: BorderSide(color: AppColors.dangerRed, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: AppSpacing.borderRadiusMd,
            borderSide: BorderSide(color: AppColors.dangerRed, width: 2),
          ),
          labelStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondaryLight,
          ),
          hintStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textTertiaryLight,
          ),
          errorStyle: AppTypography.bodySmall.copyWith(
            color: AppColors.dangerRed,
          ),
          prefixIconColor: AppColors.textSecondaryLight,
          suffixIconColor: AppColors.textSecondaryLight,
        ),

        // Chip Theme - Clean pills
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.backgroundLight,
          selectedColor: AppColors.selectedLight,
          labelStyle: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimaryLight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            side: BorderSide(color: AppColors.borderLight, width: 1),
          ),
          elevation: 0,
        ),

        // Bottom Navigation Bar Theme
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.surfaceLight,
          selectedItemColor: AppColors.primaryBlue,
          unselectedItemColor: AppColors.textSecondaryLight,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          selectedLabelStyle: AppTypography.labelSmall.copyWith(
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: AppTypography.labelSmall,
        ),

        // Floating Action Button Theme
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderRadiusLg,
          ),
        ),

        // Dialog Theme
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surfaceLight,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderRadiusLg,
          ),
          titleTextStyle: AppTypography.headlineSmall.copyWith(
            color: AppColors.textPrimaryLight,
          ),
          contentTextStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimaryLight,
          ),
        ),

        // Snackbar Theme
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.textPrimaryLight,
          contentTextStyle: AppTypography.bodyMedium.copyWith(
            color: Colors.white,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderRadiusMd,
          ),
          behavior: SnackBarBehavior.floating,
          elevation: 0,
        ),

        // Divider Theme
        dividerTheme: DividerThemeData(
          color: AppColors.dividerLight,
          thickness: 1,
          space: AppSpacing.md,
        ),

        // Icon Theme
        iconTheme: IconThemeData(
          color: AppColors.textSecondaryLight,
          size: AppSpacing.iconMd,
        ),

        // Text Theme - Atlassian typography
        textTheme: TextTheme(
          displayLarge: AppTypography.displayLarge,
          displayMedium: AppTypography.displayMedium,
          displaySmall: AppTypography.displaySmall,
          headlineLarge: AppTypography.headlineLarge,
          headlineMedium: AppTypography.headlineMedium,
          headlineSmall: AppTypography.headlineSmall,
          titleLarge: AppTypography.titleLarge,
          titleMedium: AppTypography.titleMedium,
          titleSmall: AppTypography.titleSmall,
          labelLarge: AppTypography.labelLarge,
          labelMedium: AppTypography.labelMedium,
          labelSmall: AppTypography.labelSmall,
          bodyLarge: AppTypography.bodyLarge,
          bodyMedium: AppTypography.bodyMedium,
          bodySmall: AppTypography.bodySmall,
        ),

        // Progress Indicator Theme
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: AppColors.primaryBlue,
          linearTrackColor: AppColors.backgroundLight,
        ),

        // Tab Bar Theme
        tabBarTheme: TabBarThemeData(
          labelColor: AppColors.primaryBlue,
          unselectedLabelColor: AppColors.textSecondaryLight,
          indicatorColor: AppColors.primaryBlue,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: AppTypography.labelLarge.copyWith(
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: AppTypography.labelMedium,
          dividerColor: AppColors.dividerLight,
        ),

        // Tooltip Theme
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: AppColors.textPrimaryLight,
            borderRadius: AppSpacing.borderRadiusSm,
          ),
          textStyle: AppTypography.bodySmall.copyWith(color: Colors.white),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
        ),
      );

  // ==========================================================================
  // DARK THEME
  // ==========================================================================

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: AppColors.primaryBlueLight,
          onPrimary: AppColors.textPrimaryDark,
          primaryContainer: AppColors.selectedDark,
          onPrimaryContainer: AppColors.primaryBlueLight,
          secondary: AppColors.brandPurple,
          onSecondary: AppColors.textPrimaryDark,
          error: AppColors.dangerRed,
          onError: AppColors.textPrimaryDark,
          surface: AppColors.surfaceDark,
          onSurface: AppColors.textPrimaryDark,
          surfaceContainerHighest: AppColors.backgroundDark,
          outline: AppColors.borderDark,
          outlineVariant: AppColors.borderDarkAlt,
        ),
        scaffoldBackgroundColor: AppColors.backgroundDark,

        // AppBar Theme - Dark mode
        appBarTheme: AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 1,
          centerTitle: false,
          backgroundColor: AppColors.surfaceDark,
          foregroundColor: AppColors.textPrimaryDark,
          titleTextStyle: AppTypography.titleLarge.copyWith(
            color: AppColors.textPrimaryDark,
            fontWeight: FontWeight.w600,
          ),
          iconTheme: IconThemeData(color: AppColors.textPrimaryDark),
          actionsIconTheme: IconThemeData(color: AppColors.textSecondaryDark),
          surfaceTintColor: Colors.transparent,
        ),

        // Card Theme - Dark mode with subtle shadow
        cardTheme: CardThemeData(
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderRadiusMd,
            side: BorderSide(color: AppColors.borderDark, width: 1),
          ),
          color: AppColors.surfaceDark,
          margin: const EdgeInsets.all(0),
        ),

        // Elevated Button Theme - Dark mode (Deep Teal)
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
            elevation: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) return 0;
              if (states.contains(WidgetState.hovered)) return 6;
              return 0;
            }),
            shadowColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return AppColors.primaryBlue.withValues(alpha: 0.55);
              }
              return AppColors.primaryBlue.withValues(alpha: 0.0);
            }),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.disabledDark;
              }
              if (states.contains(WidgetState.hovered)) {
                return AppColors.brighten(AppColors.primaryBlue, 0.10);
              }
              return AppColors.primaryBlue;
            }),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
            minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusLg),
            ),
            textStyle: WidgetStatePropertyAll(
              AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ),

        // Outlined Button Theme - Dark mode
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.textDisabledDark;
              }
              if (states.contains(WidgetState.hovered)) {
                return AppColors.brighten(AppColors.primaryBlue, 0.10);
              }
              return AppColors.primaryBlue;
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return AppColors.primaryBlue.withValues(alpha: 0.14);
              }
              return null;
            }),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
            minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusLg),
            ),
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return BorderSide(color: AppColors.borderDark, width: 1);
              }
              final color = states.contains(WidgetState.hovered)
                  ? AppColors.brighten(AppColors.primaryBlue, 0.10)
                  : AppColors.primaryBlue;
              return BorderSide(color: color, width: 1);
            }),
            textStyle: WidgetStatePropertyAll(
              AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ),

        // Text Button Theme - Dark mode
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return AppColors.textDisabledDark;
              }
              if (states.contains(WidgetState.hovered)) {
                return AppColors.brighten(AppColors.primaryBlue, 0.10);
              }
              return AppColors.primaryBlue;
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.hovered)) {
                return AppColors.primaryBlue.withValues(alpha: 0.14);
              }
              return null;
            }),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
            ),
            minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
            textStyle: WidgetStatePropertyAll(
              AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
        ),

        // Input Decoration Theme - Dark mode
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.inputBackgroundDark,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          border: OutlineInputBorder(
            borderRadius: AppSpacing.borderRadiusMd,
            borderSide: BorderSide(color: AppColors.inputBorderDark, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppSpacing.borderRadiusMd,
            borderSide: BorderSide(color: AppColors.inputBorderDark, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppSpacing.borderRadiusMd,
            borderSide: BorderSide(
              color: AppColors.inputBorderFocusDark,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: AppSpacing.borderRadiusMd,
            borderSide: BorderSide(color: AppColors.dangerRed, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: AppSpacing.borderRadiusMd,
            borderSide: BorderSide(color: AppColors.dangerRed, width: 2),
          ),
          labelStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondaryDark,
          ),
          hintStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textTertiaryDark,
          ),
          errorStyle: AppTypography.bodySmall.copyWith(
            color: AppColors.dangerRed,
          ),
          prefixIconColor: AppColors.textSecondaryDark,
          suffixIconColor: AppColors.textSecondaryDark,
        ),

        // Chip Theme - Dark mode
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.backgroundDark,
          selectedColor: AppColors.selectedDark,
          labelStyle: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimaryDark,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            side: BorderSide(color: AppColors.borderDark, width: 1),
          ),
          elevation: 0,
        ),

        // Bottom Navigation Bar Theme - Dark mode
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.surfaceDark,
          selectedItemColor: AppColors.primaryBlueLight,
          unselectedItemColor: AppColors.textSecondaryDark,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          selectedLabelStyle: AppTypography.labelSmall.copyWith(
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: AppTypography.labelSmall,
        ),

        // Floating Action Button Theme - Dark mode
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppColors.primaryBlueLight,
          foregroundColor: AppColors.textPrimaryDark,
          elevation: 0,
          focusElevation: 0,
          hoverElevation: 0,
          highlightElevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderRadiusLg,
          ),
        ),

        // Dialog Theme - Dark mode
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surfaceDark,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderRadiusLg,
          ),
          titleTextStyle: AppTypography.headlineSmall.copyWith(
            color: AppColors.textPrimaryDark,
          ),
          contentTextStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimaryDark,
          ),
        ),

        // Snackbar Theme - Dark mode
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.elevatedCardDark,
          contentTextStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimaryDark,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: AppSpacing.borderRadiusMd,
          ),
          behavior: SnackBarBehavior.floating,
          elevation: 0,
        ),

        // Divider Theme - Dark mode
        dividerTheme: DividerThemeData(
          color: AppColors.dividerDark,
          thickness: 1,
          space: AppSpacing.md,
        ),

        // Icon Theme - Dark mode
        iconTheme: IconThemeData(
          color: AppColors.textSecondaryDark,
          size: AppSpacing.iconMd,
        ),

        // Text Theme - Dark mode uses same typography with dark colors
        textTheme: TextTheme(
          displayLarge: AppTypography.displayLargeDark,
          displayMedium: AppTypography.displayMediumDark,
          displaySmall: AppTypography.displaySmallDark,
          headlineLarge: AppTypography.headlineLargeDark,
          headlineMedium: AppTypography.headlineMediumDark,
          headlineSmall: AppTypography.headlineSmallDark,
          titleLarge: AppTypography.titleLargeDark,
          titleMedium: AppTypography.titleMediumDark,
          titleSmall: AppTypography.titleSmall.copyWith(
            color: AppColors.textPrimaryDark,
          ),
          labelLarge: AppTypography.labelLargeDark,
          labelMedium: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimaryDark,
          ),
          labelSmall: AppTypography.labelSmall.copyWith(
            color: AppColors.textPrimaryDark,
          ),
          bodyLarge: AppTypography.bodyLargeDark,
          bodyMedium: AppTypography.bodyMediumDark,
          bodySmall: AppTypography.bodySmallDark,
        ),

        // Progress Indicator Theme - Dark mode
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: AppColors.primaryBlueLight,
          linearTrackColor: AppColors.backgroundDark,
        ),

        // Tab Bar Theme - Dark mode
        tabBarTheme: TabBarThemeData(
          labelColor: AppColors.primaryBlueLight,
          unselectedLabelColor: AppColors.textSecondaryDark,
          indicatorColor: AppColors.primaryBlueLight,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: AppTypography.labelLarge.copyWith(
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: AppTypography.labelMedium,
          dividerColor: AppColors.dividerDark,
        ),

        // Tooltip Theme - Dark mode
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: AppColors.elevatedCardDark,
            borderRadius: AppSpacing.borderRadiusSm,
          ),
          textStyle: AppTypography.bodySmall.copyWith(
            color: AppColors.textPrimaryDark,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
        ),
      );
}
