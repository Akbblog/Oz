/// Responsive utility functions for Infinity Leads Pro
/// Provides helper methods for responsive sizing, spacing, and layout
library;

import '../theme/app_breakpoints.dart';
import '../theme/app_spacing.dart';

class ResponsiveUtils {
  ResponsiveUtils._(); // Private constructor to prevent instantiation

  // ============================================================
  // PADDING & SPACING
  // ============================================================

  /// Get responsive horizontal padding based on layout type
  ///
  /// Returns appropriate padding value for the screen size:
  /// - Mobile: 16px
  /// - Tablet: 20px
  /// - Desktop Small: 24px
  /// - Desktop Medium: 28px
  /// - Desktop Large: 32px
  static double getHorizontalPadding(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.mobile:
        return AppSpacing.md; // 16px
      case LayoutType.tablet:
        return 20.0;
      case LayoutType.desktopSmall:
        return AppSpacing.lg; // 24px
      case LayoutType.desktopMedium:
        return 28.0;
      case LayoutType.desktopLarge:
        return AppSpacing.xl; // 32px
    }
  }

  /// Get responsive vertical padding based on layout type
  ///
  /// Uses same values as horizontal padding for consistency
  static double getVerticalPadding(LayoutType layoutType) {
    return getHorizontalPadding(layoutType);
  }

  /// Get screen-level padding (for main content areas)
  static double getScreenPadding(LayoutType layoutType) {
    return getHorizontalPadding(layoutType);
  }

  /// Get card padding based on layout type
  static double getCardPadding(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.mobile:
        return AppSpacing.md; // 16px
      case LayoutType.tablet:
        return AppSpacing.md; // 16px
      case LayoutType.desktopSmall:
      case LayoutType.desktopMedium:
      case LayoutType.desktopLarge:
        return AppSpacing.lg; // 24px
    }
  }

  /// Get spacing between grid items
  static double getGridSpacing(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.mobile:
        return AppSpacing.md; // 16px
      case LayoutType.tablet:
        return AppSpacing.md; // 16px
      case LayoutType.desktopSmall:
        return AppSpacing.lg; // 24px
      case LayoutType.desktopMedium:
      case LayoutType.desktopLarge:
        return AppSpacing.lg; // 24px
    }
  }

  // ============================================================
  // CARD DIMENSIONS
  // ============================================================

  /// Get maximum card width based on layout type
  ///
  /// Returns null for desktop (grid handles width),
  /// Returns specific max-width for mobile/tablet
  static double? getCardMaxWidth(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.mobile:
        return double.infinity; // Full width
      case LayoutType.tablet:
        return 500.0; // Centered with max width
      case LayoutType.desktopSmall:
      case LayoutType.desktopMedium:
      case LayoutType.desktopLarge:
        return null; // Grid controls width
    }
  }

  /// Get card width percentage for grid layouts
  ///
  /// Helper for manually calculating card widths in grids
  static double getCardWidthPercentage(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.mobile:
        return 1.0; // 100%
      case LayoutType.tablet:
        return 0.5; // 50% (2 columns)
      case LayoutType.desktopSmall:
        return 0.5; // 50% (2 columns)
      case LayoutType.desktopMedium:
        return 0.33; // 33% (3 columns)
      case LayoutType.desktopLarge:
        return 0.25; // 25% (4 columns)
    }
  }

  // ============================================================
  // BUTTON DIMENSIONS
  // ============================================================

  /// Get responsive button height based on layout type
  ///
  /// [compact] - If true, returns slightly smaller heights for dense UIs
  ///
  /// Regular heights:
  /// - Mobile: 56px (touch-friendly)
  /// - Desktop: 52px (slightly more compact)
  ///
  /// Compact heights:
  /// - Mobile: 48px
  /// - Desktop: 44px
  static double getButtonHeight(LayoutType layoutType, {bool compact = false}) {
    if (compact) {
      return AppBreakpoints.isDesktop(layoutType) ? 44.0 : 48.0;
    }
    return AppBreakpoints.isDesktop(layoutType) ? 52.0 : 56.0;
  }

  /// Get button horizontal padding
  static double getButtonPaddingHorizontal(LayoutType layoutType) {
    return AppBreakpoints.isDesktop(layoutType)
        ? AppSpacing.lg // 24px
        : AppSpacing.md; // 16px
  }

  /// Get button vertical padding
  static double getButtonPaddingVertical(LayoutType layoutType) {
    return AppBreakpoints.isDesktop(layoutType)
        ? AppSpacing.sm // 12px
        : AppSpacing.md; // 16px
  }

  // ============================================================
  // FONT SCALING (Optional - currently unchanged)
  // ============================================================

  /// Get scaled font size based on layout type
  ///
  /// Currently returns base size unchanged (per design requirements)
  /// Can be used in future for fine-tuning typography on large screens
  static double getScaledFontSize(
    double baseFontSize,
    LayoutType layoutType,
  ) {
    // No scaling applied - keeping existing typography
    return baseFontSize;
  }

  // ============================================================
  // FORM LAYOUTS
  // ============================================================

  /// Check if forms should use multi-column layout
  static bool shouldUseMultiColumnForms(LayoutType layoutType) {
    return AppBreakpoints.isDesktop(layoutType);
  }

  /// Get number of form columns
  static int getFormColumns(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.mobile:
      case LayoutType.tablet:
        return 1; // Single column
      case LayoutType.desktopSmall:
        return 2; // Two columns for related fields
      case LayoutType.desktopMedium:
      case LayoutType.desktopLarge:
        return 2; // Can be 3 for complex forms
    }
  }

  /// Get input field width for multi-column forms
  static double? getInputFieldWidth(LayoutType layoutType, {bool fullWidth = false}) {
    if (fullWidth || !AppBreakpoints.isDesktop(layoutType)) {
      return double.infinity;
    }

    // Desktop: return null to let flex/expanded handle it
    return null;
  }

  // ============================================================
  // NAVIGATION
  // ============================================================

  /// Check if bottom navigation should be shown
  static bool shouldShowBottomNav(LayoutType layoutType) {
    return AppBreakpoints.isMobile(layoutType);
  }

  /// Check if top bar should be shown
  static bool shouldShowTopBar(LayoutType layoutType) {
    return AppBreakpoints.isTabletOrLarger(layoutType);
  }

  /// Check if sidebar should be visible
  static bool shouldShowSidebar(LayoutType layoutType) {
    return !AppBreakpoints.isMobile(layoutType);
  }

  // ============================================================
  // LAYOUT HELPERS
  // ============================================================

  /// Check if split view layout should be used
  ///
  /// Split views (2 or 3 panel layouts) are used on desktop
  static bool shouldUseSplitView(LayoutType layoutType) {
    return AppBreakpoints.isDesktop(layoutType);
  }

  /// Check if table view should be available
  ///
  /// Data tables are shown on desktop, cards on mobile
  static bool shouldUseTableView(LayoutType layoutType) {
    return layoutType.index >= LayoutType.desktopSmall.index;
  }

  /// Get content max width with padding
  static double getContentMaxWidth(LayoutType layoutType) {
    return AppBreakpoints.contentMaxWidth;
  }

  /// Check if content should be centered with max-width
  static bool shouldCenterContent(LayoutType layoutType) {
    return layoutType == LayoutType.desktopLarge;
  }

  // ============================================================
  // GRID HELPERS
  // ============================================================

  /// Get grid cross-axis spacing
  static double getGridCrossAxisSpacing(LayoutType layoutType) {
    return getGridSpacing(layoutType);
  }

  /// Get grid main-axis spacing
  static double getGridMainAxisSpacing(LayoutType layoutType) {
    return getGridSpacing(layoutType);
  }

  /// Calculate grid child aspect ratio
  ///
  /// [baseRatio] - Base aspect ratio (e.g., 1.0 for square, 1.5 for 3:2)
  /// Returns adjusted ratio for different screen sizes
  static double getGridChildAspectRatio(
    double baseRatio,
    LayoutType layoutType,
  ) {
    // Can adjust aspect ratios based on screen size
    // Currently returning base ratio unchanged
    return baseRatio;
  }

  // ============================================================
  // ICON SIZING
  // ============================================================

  /// Get responsive icon size
  ///
  /// [baseSize] - Base icon size from AppSpacing (e.g., AppSpacing.iconMd)
  static double getIconSize(double baseSize, LayoutType layoutType) {
    // Icons remain same size across breakpoints for consistency
    return baseSize;
  }

  // ============================================================
  // DIALOG & MODAL
  // ============================================================

  /// Get dialog max width based on layout type
  static double? getDialogMaxWidth(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.mobile:
        return double.infinity; // Full width with padding
      case LayoutType.tablet:
        return 600.0;
      case LayoutType.desktopSmall:
        return 700.0;
      case LayoutType.desktopMedium:
      case LayoutType.desktopLarge:
        return 800.0;
    }
  }

  /// Check if dialog should be full screen (mobile only)
  static bool shouldUseFullScreenDialog(LayoutType layoutType) {
    return AppBreakpoints.isMobile(layoutType);
  }
}
