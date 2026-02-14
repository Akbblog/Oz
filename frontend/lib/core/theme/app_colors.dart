import 'package:flutter/material.dart';

/// Atlassian Design System Color Palette
/// Clean, professional colors for both light and dark themes
class AppColors {
  AppColors._();

  // ============================================================================
  // PRIMARY BRAND COLORS
  // ============================================================================

  /// Primary brand color (Deep Teal) - main action color
  /// Spec: Primary #2C5F6D, darker shade #1E434D.
  static const Color primaryBlue = Color(0xFF2C5F6D);
  static const Color primaryBlueDark = Color(0xFF1E434D);
  /// Brightened primary (roughly +10% lightness) for hover/accents.
  static const Color primaryBlueLight = Color(0xFF347381);

  /// Brand accent colors (used sparingly for visual interest)
  static const Color brandPurple = Color(0xFFBF63F3);
  static const Color brandOrange = Color(0xFFFCA700);
  static const Color brandLime = Color(0xFF94C748);
  static const Color brandObsidian = Color(0xFF101214);

  // ============================================================================
  // SEMANTIC COLORS (Light & Dark variants)
  // ============================================================================

  /// Success colors (green)
  static const Color successGreen = Color(0xFF4bce97);
  static const Color successGreenDark = Color(0xFF22A06B);
  static const Color successGreenLight = Color(0xFF7EE2B8);

  /// Warning colors (yellow)
  static const Color warningYellow = Color(0xFFeed12b);
  static const Color warningYellowDark = Color(0xFFE2B203);
  static const Color warningYellowLight = Color(0xFFF5E100);

  /// Danger/Error colors (red)
  static const Color dangerRed = Color(0xFFf87168);
  static const Color dangerRedDark = Color(0xFFE34935);
  static const Color dangerRedLight = Color(0xFFFF9C8F);

  /// Info colors (blue)
  static const Color infoBlue = Color(0xFF669df1);
  static const Color infoBlueDark = Color(0xFF388BFF);
  static const Color infoBlueLight = Color(0xFF85B8FF);

  /// Discovery colors (purple)
  static const Color discoveryPurple = Color(0xFFc97cf4);
  static const Color discoveryPurpleDark = Color(0xFFA85CFF);
  static const Color discoveryPurpleLight = Color(0xFFDDA6FF);

  // ============================================================================
  // LIGHT THEME COLORS
  // ============================================================================

  /// Surface and background colors for light theme
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color backgroundLight = Color(0xFFF7F8F9);
  static const Color backgroundLightAlt = Color(0xFFEFF1F3); // Slightly darker

  /// Text colors for light theme
  static const Color textPrimaryLight = Color(0xFF292A2E);
  static const Color textSecondaryLight = Color(0xFF5E6C84);
  static const Color textTertiaryLight = Color(0xFF8590A2);
  static const Color textDisabledLight = Color(0xFFB6C2CF);

  /// Border and divider colors for light theme
  static const Color borderLight = Color(0xFFDFE1E6);
  static const Color borderLightAlt = Color(0xFFEBECF0); // Slightly lighter
  static const Color dividerLight = Color(0xFFF0F0F0);

  /// Hover and selected states for light theme
  static const Color hoverLight = Color(0xFFF7F8F9);
  // Teal-tinted selection surfaces (replaces prior blue tint).
  static const Color selectedLight = Color(0xFFE3F0F2);
  static const Color selectedLightAlt = Color(0xFFCAE3E8);

  // ============================================================================
  // DARK THEME COLORS (Soft Dark - not pure black)
  // ============================================================================

  /// Surface and background colors for dark theme
  static const Color surfaceDark = Color(0xFF1f1f21);
  static const Color backgroundDark = Color(0xFF171717);
  static const Color backgroundDarkAlt = Color(0xFF1D1D1F); // Slightly lighter

  /// Text colors for dark theme
  static const Color textPrimaryDark = Color(0xFFe3e5e8);
  static const Color textSecondaryDark = Color(0xFF9FADBC);
  static const Color textTertiaryDark = Color(0xFF758195);
  static const Color textDisabledDark = Color(0xFF5A6977);

  /// Border and divider colors for dark theme
  static const Color borderDark = Color(0xFF3D3D3F);
  static const Color borderDarkAlt = Color(0xFF2C2C2E); // Slightly darker
  static const Color dividerDark = Color(0xFF2A2A2C);

  /// Hover and selected states for dark theme
  static const Color hoverDark = Color(0xFF282829);
  // Teal-tinted selection surfaces (replaces prior blue tint).
  static const Color selectedDark = Color(0xFF12313A);
  static const Color selectedDarkAlt = Color(0xFF0C262D);

  // ============================================================================
  // ELEVATION & OVERLAY COLORS
  // ============================================================================

  /// Overlay colors for modals, dialogs
  static const Color overlayLight = Color(0x66000000); // 40% black
  static const Color overlayDark = Color(0x99000000); // 60% black

  /// Card elevation colors
  static const Color elevatedCardLight = Color(0xFFFFFFFF);
  static const Color elevatedCardDark = Color(0xFF2A2A2C);

  // ============================================================================
  // INPUT & FORM COLORS
  // ============================================================================

  /// Input field colors for light theme
  static const Color inputLight = Color(0xFFFFFFFF);
  static const Color inputBorderLight = Color(0xFFDFE1E6);
  static const Color inputBorderFocusLight = primaryBlue;
  static const Color inputBackgroundLight = Color(0xFFFAFBFC);

  /// Input field colors for dark theme
  static const Color inputDark = Color(0xFF2A2A2C);
  static const Color inputBorderDark = Color(0xFF3D3D3F);
  static const Color inputBorderFocusDark = primaryBlueLight;
  static const Color inputBackgroundDark = Color(0xFF1D1D1F);

  // ============================================================================
  // SPECIAL USE COLORS
  // ============================================================================

  /// Link colors
  static const Color linkLight = primaryBlue;
  static const Color linkDark = primaryBlueLight;
  static const Color linkHoverLight = primaryBlueDark;
  static const Color linkHoverDark = primaryBlueLight;

  /// Focus ring colors
  static const Color focusRingLight = primaryBlueLight;
  static const Color focusRingDark = primaryBlueLight;

  /// Disabled states
  static const Color disabledLight = Color(0xFFF4F5F7);
  static const Color disabledDark = Color(0xFF2C2C2E);

  // ============================================================================
  // OPTIONAL: Minimal gradient for primary CTA (used sparingly)
  // ============================================================================

  /// Optional subtle gradient for primary call-to-action buttons
  /// Use sparingly - most buttons should be solid colors
  static const LinearGradient primaryButtonGradient = LinearGradient(
    colors: [primaryBlue, primaryBlueDark],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  /// Brighten a color by increasing HSL lightness by [amount] (0.0-1.0).
  static Color brighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    final next = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
    return next.toColor();
  }

  /// Get surface color based on theme brightness
  static Color getSurface(Brightness brightness) {
    return brightness == Brightness.dark ? surfaceDark : surfaceLight;
  }

  /// Get background color based on theme brightness
  static Color getBackground(Brightness brightness) {
    return brightness == Brightness.dark ? backgroundDark : backgroundLight;
  }

  /// Get primary text color based on theme brightness
  static Color getTextPrimary(Brightness brightness) {
    return brightness == Brightness.dark ? textPrimaryDark : textPrimaryLight;
  }

  /// Get secondary text color based on theme brightness
  static Color getTextSecondary(Brightness brightness) {
    return brightness == Brightness.dark
        ? textSecondaryDark
        : textSecondaryLight;
  }

  /// Get border color based on theme brightness
  static Color getBorder(Brightness brightness) {
    return brightness == Brightness.dark ? borderDark : borderLight;
  }

  /// Get input background color based on theme brightness
  static Color getInputBackground(Brightness brightness) {
    return brightness == Brightness.dark
        ? inputBackgroundDark
        : inputBackgroundLight;
  }

  // ============================================================================
  // ADDITIONAL LEGACY COLORS (For compatibility with existing screens)
  // ============================================================================

  static const Color primaryStart = primaryBlue;
  static const Color primaryEnd = primaryBlueDark;
  static const Color secondaryStart = Color(0xFF11998e);
  static const Color secondaryEnd = Color(0xFF38ef7d);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryBlue, primaryBlueDark],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [secondaryStart, secondaryEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient tealGradient = LinearGradient(
    colors: [Color(0xFFe6a817), Color(0xFFf5d020)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient pinkGradient = LinearGradient(
    colors: [Color(0xFFd946ef), Color(0xFFf472b6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Dashboard stat card gradients (muted matte palette)
  static const LinearGradient deepTealGradient = LinearGradient(
    colors: [Color(0xFF3A7A8A), Color(0xFF2C5F6D)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient lavenderGradient = LinearGradient(
    colors: [Color(0xFFA49DC0), Color(0xFF928BB0)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient ochreGradient = LinearGradient(
    colors: [Color(0xFFE0A558), Color(0xFFD69446)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient dustyRoseGradient = LinearGradient(
    colors: [Color(0xFFCA8585), Color(0xFFB86E6E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Additional named colors for compatibility
  static const Color primaryViolet = Color(0xFF8b5cf6); // Violet 500
  static const Color rose = Color(0xFFF472B6);
  static const Color amber = Color(0xFFFCA700);
  static const Color purple = Color(0xFFBF63F3);
  static const Color blue = Color(0xFF669df1); // Using infoBlue for consistency
  static const Color success = Color(0xFF22c55e);
  static const Color error = Color(0xFFef4444);
  static const Color warning = Color(0xFFf59e0b);
  static const Color backgroundCard = Color(0xFFFFFFFF);
  static const Color backgroundDeep = Color(0xFF1e293b);
  static const Color backgroundStatCard = Color(0xFFF8FAFC);
}
