/// Responsive breakpoints and layout constants for Infinity Leads Pro
/// Defines breakpoint values and layout behavior for different screen sizes
library;

// ============================================================
// LAYOUT TYPE ENUM
// ============================================================

/// Layout type based on screen width
enum LayoutType {
  /// Mobile layout (< 768px)
  /// - Bottom tab navigation
  /// - Single column layout
  /// - Full-width cards
  mobile,

  /// Tablet layout (768px - 1024px)
  /// - Sidebar collapsed (72px rail, icons only)
  /// - Top bar with menu toggle
  /// - 2-3 column grids
  tablet,

  /// Desktop small layout (1024px - 1200px)
  /// - Sidebar expanded (260px, icons + labels)
  /// - Top bar with logo, credits, user menu
  /// - Split views (2 panels)
  /// - 2-3 column grids
  desktopSmall,

  /// Desktop medium layout (1200px - 1440px)
  /// - Full desktop features
  /// - Enhanced layouts (3 panels in some screens)
  /// - 3-4 column grids
  desktopMedium,

  /// Desktop large layout (1440px+)
  /// - Maximum grid columns (4-5)
  /// - Advanced multi-panel layouts
  /// - Content max-width enforced (1600px centered)
  desktopLarge,
}

// ============================================================
// BREAKPOINTS CLASS
// ============================================================

class AppBreakpoints {
  AppBreakpoints._(); // Private constructor to prevent instantiation

  // ============================================================
  // BREAKPOINT VALUES
  // ============================================================

  /// Mobile breakpoint threshold (< 768px)
  static const double mobile = 768;

  /// Tablet breakpoint threshold (768px - 1024px)
  static const double tablet = 1024;

  /// Desktop small breakpoint threshold (1024px - 1200px)
  static const double desktopSmall = 1200;

  /// Desktop medium breakpoint threshold (1200px - 1440px)
  static const double desktopMedium = 1440;

  // ============================================================
  // SIDEBAR DIMENSIONS
  // ============================================================

  /// Sidebar width when fully expanded (desktop)
  static const double sidebarExpanded = 260;

  /// Sidebar width when collapsed (tablet - icons only)
  static const double sidebarCollapsed = 72;

  /// Sidebar hidden (mobile)
  static const double sidebarHidden = 0;

  // ============================================================
  // TOP BAR DIMENSIONS
  // ============================================================

  /// Height of the desktop top bar
  static const double topBarHeight = 68;

  // ============================================================
  // CONTENT CONSTRAINTS
  // ============================================================

  /// Maximum content width for large screens (prevents overstretching)
  static const double contentMaxWidth = 1600;

  // ============================================================
  // HELPER METHODS
  // ============================================================

  /// Get layout type from screen width
  ///
  /// Returns the appropriate [LayoutType] based on the provided [width]
  ///
  /// Example:
  /// ```dart
  /// final width = MediaQuery.of(context).size.width;
  /// final layoutType = AppBreakpoints.getLayoutType(width);
  /// ```
  static LayoutType getLayoutType(double width) {
    if (width >= desktopMedium) {
      return LayoutType.desktopLarge;
    } else if (width >= desktopSmall) {
      return LayoutType.desktopMedium;
    } else if (width >= tablet) {
      return LayoutType.desktopSmall;
    } else if (width >= mobile) {
      return LayoutType.tablet;
    } else {
      return LayoutType.mobile;
    }
  }

  /// Get sidebar width based on layout type
  ///
  /// Returns the appropriate sidebar width for the current [layoutType]
  static double getSidebarWidth(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.mobile:
        return sidebarHidden;
      case LayoutType.tablet:
        return sidebarCollapsed;
      case LayoutType.desktopSmall:
      case LayoutType.desktopMedium:
      case LayoutType.desktopLarge:
        return sidebarExpanded;
    }
  }

  /// Check if sidebar should be collapsed (icons only)
  static bool isSidebarCollapsed(LayoutType layoutType) {
    return layoutType == LayoutType.tablet;
  }

  /// Check if sidebar should be hidden (mobile)
  static bool isSidebarHidden(LayoutType layoutType) {
    return layoutType == LayoutType.mobile;
  }

  /// Check if layout is mobile
  static bool isMobile(LayoutType layoutType) {
    return layoutType == LayoutType.mobile;
  }

  /// Check if layout is tablet or larger
  static bool isTabletOrLarger(LayoutType layoutType) {
    return layoutType.index >= LayoutType.tablet.index;
  }

  /// Check if layout is desktop (any size)
  static bool isDesktop(LayoutType layoutType) {
    return layoutType.index >= LayoutType.desktopSmall.index;
  }

  /// Get number of grid columns for different content types
  ///
  /// [gridType] specifies the type of content:
  /// - 'stats': Stat cards
  /// - 'states': State selection grid
  /// - 'results': Result cards
  /// - 'default': General purpose grid
  static int getGridColumns(
    LayoutType layoutType, {
    String gridType = 'default',
  }) {
    switch (gridType) {
      case 'stats':
        return _getStatsGridColumns(layoutType);
      case 'states':
        return _getStatesGridColumns(layoutType);
      case 'results':
        return _getResultsGridColumns(layoutType);
      default:
        return _getDefaultGridColumns(layoutType);
    }
  }

  // Private helper methods for specific grid types

  static int _getStatsGridColumns(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.mobile:
        return 1;
      case LayoutType.tablet:
        return 2;
      case LayoutType.desktopSmall:
        return 3;
      case LayoutType.desktopMedium:
        return 4;
      case LayoutType.desktopLarge:
        return 6;
    }
  }

  static int _getStatesGridColumns(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.mobile:
        return 2;
      case LayoutType.tablet:
        return 3;
      case LayoutType.desktopSmall:
        return 3;
      case LayoutType.desktopMedium:
        return 4;
      case LayoutType.desktopLarge:
        return 5;
    }
  }

  static int _getResultsGridColumns(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.mobile:
        return 1;
      case LayoutType.tablet:
        return 2;
      case LayoutType.desktopSmall:
        return 2;
      case LayoutType.desktopMedium:
        return 3;
      case LayoutType.desktopLarge:
        return 4;
    }
  }

  static int _getDefaultGridColumns(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.mobile:
        return 1;
      case LayoutType.tablet:
        return 2;
      case LayoutType.desktopSmall:
        return 2;
      case LayoutType.desktopMedium:
        return 3;
      case LayoutType.desktopLarge:
        return 4;
    }
  }
}
