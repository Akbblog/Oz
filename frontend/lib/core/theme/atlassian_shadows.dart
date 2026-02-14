import 'package:flutter/material.dart';

/// Atlassian Design System Shadow Definitions
/// Subtle elevation shadows for depth and visual hierarchy
class AtlassianShadows {
  AtlassianShadows._();

  // ============================================================================
  // LIGHT THEME SHADOWS
  // ============================================================================

  /// Subtle shadow for cards and containers (Light theme)
  /// Elevation: Low (4dp equivalent)
  static final List<BoxShadow> cardLight = [
    BoxShadow(
      color: const Color(0x001e1f21).withOpacity(0.15),
      offset: const Offset(0, 8),
      blurRadius: 9,
      spreadRadius: 0,
    ),
  ];

  /// Elevated shadow for popovers, dropdowns (Light theme)
  /// Elevation: Medium (8dp equivalent)
  static final List<BoxShadow> elevatedLight = [
    BoxShadow(
      color: const Color(0x001e1f21).withOpacity(0.20),
      offset: const Offset(0, 12),
      blurRadius: 16,
      spreadRadius: 0,
    ),
  ];

  /// Modal and dialog shadow (Light theme)
  /// Elevation: High (16dp equivalent)
  static final List<BoxShadow> modalLight = [
    BoxShadow(
      color: const Color(0x001e1f21).withOpacity(0.25),
      offset: const Offset(0, 16),
      blurRadius: 24,
      spreadRadius: 0,
    ),
    BoxShadow(
      color: const Color(0x001e1f21).withOpacity(0.10),
      offset: const Offset(0, 2),
      blurRadius: 4,
      spreadRadius: 0,
    ),
  ];

  /// Subtle inner shadow for inputs (Light theme)
  static final List<BoxShadow> inputLight = [
    BoxShadow(
      color: const Color(0x00000000).withOpacity(0.05),
      offset: const Offset(0, 1),
      blurRadius: 2,
      spreadRadius: 0,
    ),
  ];

  // ============================================================================
  // DARK THEME SHADOWS
  // ============================================================================

  /// Subtle shadow for cards and containers (Dark theme)
  /// Elevation: Low (4dp equivalent)
  static final List<BoxShadow> cardDark = [
    BoxShadow(
      color: const Color(0x00000000).withOpacity(0.30),
      offset: const Offset(0, 8),
      blurRadius: 12,
      spreadRadius: 0,
    ),
  ];

  /// Elevated shadow for popovers, dropdowns (Dark theme)
  /// Elevation: Medium (8dp equivalent)
  static final List<BoxShadow> elevatedDark = [
    BoxShadow(
      color: const Color(0x00000000).withOpacity(0.40),
      offset: const Offset(0, 12),
      blurRadius: 20,
      spreadRadius: 0,
    ),
  ];

  /// Modal and dialog shadow (Dark theme)
  /// Elevation: High (16dp equivalent)
  static final List<BoxShadow> modalDark = [
    BoxShadow(
      color: const Color(0x00000000).withOpacity(0.50),
      offset: const Offset(0, 16),
      blurRadius: 32,
      spreadRadius: 0,
    ),
    BoxShadow(
      color: const Color(0x00000000).withOpacity(0.20),
      offset: const Offset(0, 2),
      blurRadius: 4,
      spreadRadius: 0,
    ),
  ];

  /// Subtle inner shadow for inputs (Dark theme)
  static final List<BoxShadow> inputDark = [
    BoxShadow(
      color: const Color(0x00000000).withOpacity(0.20),
      offset: const Offset(0, 1),
      blurRadius: 2,
      spreadRadius: 0,
    ),
  ];

  // ============================================================================
  // BUTTON SHADOWS
  // ============================================================================

  /// Subtle shadow for raised buttons (Light theme)
  static final List<BoxShadow> buttonLight = [
    BoxShadow(
      color: const Color(0x001e1f21).withOpacity(0.10),
      offset: const Offset(0, 2),
      blurRadius: 4,
      spreadRadius: 0,
    ),
  ];

  /// Subtle shadow for raised buttons (Dark theme)
  static final List<BoxShadow> buttonDark = [
    BoxShadow(
      color: const Color(0x00000000).withOpacity(0.20),
      offset: const Offset(0, 2),
      blurRadius: 4,
      spreadRadius: 0,
    ),
  ];

  /// Hover state shadow for buttons (more elevated)
  static final List<BoxShadow> buttonHoverLight = [
    BoxShadow(
      color: const Color(0x001e1f21).withOpacity(0.15),
      offset: const Offset(0, 4),
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  static final List<BoxShadow> buttonHoverDark = [
    BoxShadow(
      color: const Color(0x00000000).withOpacity(0.30),
      offset: const Offset(0, 4),
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  /// Get card shadow based on theme brightness
  static List<BoxShadow> getCard(Brightness brightness) {
    return brightness == Brightness.dark ? cardDark : cardLight;
  }

  /// Get elevated shadow based on theme brightness
  static List<BoxShadow> getElevated(Brightness brightness) {
    return brightness == Brightness.dark ? elevatedDark : elevatedLight;
  }

  /// Get modal shadow based on theme brightness
  static List<BoxShadow> getModal(Brightness brightness) {
    return brightness == Brightness.dark ? modalDark : modalLight;
  }

  /// Get input shadow based on theme brightness
  static List<BoxShadow> getInput(Brightness brightness) {
    return brightness == Brightness.dark ? inputDark : inputLight;
  }

  /// Get button shadow based on theme brightness
  static List<BoxShadow> getButton(Brightness brightness) {
    return brightness == Brightness.dark ? buttonDark : buttonLight;
  }

  /// Get button hover shadow based on theme brightness
  static List<BoxShadow> getButtonHover(Brightness brightness) {
    return brightness == Brightness.dark ? buttonHoverDark : buttonHoverLight;
  }

  // ============================================================================
  // NO SHADOW (for flat designs)
  // ============================================================================

  /// Empty shadow list for flat components
  static const List<BoxShadow> none = [];
}
