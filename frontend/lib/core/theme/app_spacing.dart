import 'package:flutter/material.dart';

/// App Spacing System - Consistent spacing throughout the app
class AppSpacing {
  AppSpacing._();

  // Base spacing values (Atlassian 4px base scale)
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;   // Changed from 24.0 to match Atlassian
  static const double xl = 24.0;   // Changed from 32.0 to match Atlassian
  static const double xxl = 40.0;  // Changed from 48.0 to match Atlassian
  static const double xxxl = 64.0;

  // Padding presets
  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);

  // Horizontal padding
  static const EdgeInsets paddingHorizontalMd = EdgeInsets.symmetric(horizontal: md);
  static const EdgeInsets paddingHorizontalLg = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets paddingHorizontalXl = EdgeInsets.symmetric(horizontal: xl);

  // Vertical padding
  static const EdgeInsets paddingVerticalMd = EdgeInsets.symmetric(vertical: md);
  static const EdgeInsets paddingVerticalLg = EdgeInsets.symmetric(vertical: lg);

  // Screen padding
  static const EdgeInsets screenPadding = EdgeInsets.all(md);
  static const EdgeInsets screenPaddingLg = EdgeInsets.all(lg);

  // Border radius (Atlassian: 8px primary standard)
  static const double radiusXs = 4.0;   // Small elements (badges, chips)
  static const double radiusSm = 4.0;   // Changed from 8.0
  static const double radiusMd = 8.0;   // Changed from 12.0 - PRIMARY Atlassian standard
  static const double radiusLg = 12.0;  // Changed from 16.0 - Large cards
  static const double radiusXl = 24.0;
  static const double radiusRound = 50.0;

  // Border radius presets
  static final BorderRadius borderRadiusSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(radiusLg);
  static final BorderRadius borderRadiusXl = BorderRadius.circular(radiusXl);
  static final BorderRadius borderRadiusRound = BorderRadius.circular(radiusRound);

  // Icon sizes
  static const double iconXs = 16.0;
  static const double iconSm = 20.0;
  static const double iconMd = 24.0;
  static const double iconLg = 32.0;
  static const double iconXl = 48.0;
  static const double iconXxl = 64.0;

  // Elevation
  static const double elevationNone = 0.0;
  static const double elevationSm = 2.0;
  static const double elevationMd = 4.0;
  static const double elevationLg = 8.0;
  static const double elevationXl = 16.0;

  // Animation durations (Atlassian: 100-250ms for perceived performance)
  static const Duration durationFast = Duration(milliseconds: 100);      // Hover states
  static const Duration durationNormal = Duration(milliseconds: 150);    // Button interactions
  static const Duration durationMedium = Duration(milliseconds: 200);    // Page transitions
  static const Duration durationSlow = Duration(milliseconds: 250);      // Theme switch
  static const Duration durationVerySlow = Duration(milliseconds: 500);  // Complex animations
}

/// App Dimensions - Consistent component sizing throughout the app
class AppDimensions {
  AppDimensions._();

  // Button heights
  static const double buttonHeightSm = 44.0;
  static const double buttonHeightMd = 56.0;
  static const double buttonHeightLg = 64.0;

  // Button widths
  static const double buttonMinWidth = 100.0;
  static const double buttonFullWidth = double.infinity;

  // Avatar sizes
  static const double avatarXs = 24.0;
  static const double avatarSm = 32.0;
  static const double avatarMd = 44.0;
  static const double avatarLg = 56.0;
  static const double avatarXl = 72.0;

  // Input field heights
  static const double inputHeight = 56.0;
  static const double inputHeightSm = 44.0;

  // Card sizes
  static const double cardMinHeight = 100.0;
  static const double cardMaxWidth = 600.0;

  // App bar heights
  static const double appBarHeight = 64.0;
  static const double appBarHeightCompact = 56.0;

  // Bottom navigation
  static const double bottomNavHeight = 72.0;

  // Divider thickness
  static const double dividerThickness = 1.0;
  static const double dividerThicknessBold = 2.0;

  // Border widths
  static const double borderWidthThin = 1.0;
  static const double borderWidthRegular = 2.0;
  static const double borderWidthThick = 3.0;

  // Progress indicator sizes
  static const double progressSizeSm = 16.0;
  static const double progressSizeMd = 24.0;
  static const double progressSizeLg = 48.0;

  // Minimum tap target size (for accessibility)
  static const double minTapTarget = 48.0;
}
