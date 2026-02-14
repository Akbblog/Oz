import 'package:flutter/material.dart';
import 'app_colors.dart';

/// App Typography System - Consistent text styles
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Inter';

  // Display styles (Atlassian H1-H3 scale)
  static const TextStyle displayLarge = TextStyle(
    fontSize: 33,  // H1: Atlassian 2.07em (was 57)
    fontWeight: FontWeight.w600,  // Atlassian uses 600 for H1 (was 700)
    letterSpacing: 0,  // Remove negative letter spacing
    height: 1.43,  // Atlassian generous line height (was 1.12)
    color: AppColors.textPrimaryLight,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 27,  // H2: Atlassian 1.71em (was 45)
    fontWeight: FontWeight.w500,  // Atlassian uses 500 for H2 (was 600)
    letterSpacing: 0,
    height: 1.48,  // Generous line height (was 1.16)
    color: AppColors.textPrimaryLight,
  );

  static const TextStyle displaySmall = TextStyle(
    fontSize: 23,  // H3: Atlassian 1.43em (was 36)
    fontWeight: FontWeight.w500,  // Atlassian uses 500 for H3 (was 600)
    letterSpacing: 0,
    height: 1.52,  // Generous line height (was 1.22)
    color: AppColors.textPrimaryLight,
  );

  // Headline styles (Generous Atlassian line heights)
  static const TextStyle headlineLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.50,  // Increased for readability (was 1.25)
    color: AppColors.textPrimaryLight,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.50,  // Increased for readability (was 1.29)
    color: AppColors.textPrimaryLight,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.50,  // Increased for readability (was 1.33)
    color: AppColors.textPrimaryLight,
  );

  // Title styles
  static const TextStyle titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.45,  // Increased for readability (was 1.27)
    color: AppColors.textPrimaryLight,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,  // Reduced (was 0.15)
    height: 1.50,
    color: AppColors.textPrimaryLight,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,  // Reduced (was 0.1)
    height: 1.43,
    color: AppColors.textPrimaryLight,
  );

  // Label styles (Reduced letter-spacing for cleaner look)
  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,  // Reduced (was 0.1)
    height: 1.43,
    color: AppColors.textPrimaryLight,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,  // Reduced significantly (was 0.5)
    height: 1.50,  // Increased (was 1.33)
    color: AppColors.textPrimaryLight,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,  // Reduced significantly (was 0.5)
    height: 1.45,
    color: AppColors.textPrimaryLight,
  );

  // Body styles (Atlassian 14px body standard)
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,  // Reduced (was 0.5)
    height: 1.50,
    color: AppColors.textPrimaryLight,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,  // Atlassian standard body size
    fontWeight: FontWeight.w400,
    letterSpacing: 0,  // Reduced (was 0.25)
    height: 1.57,  // Atlassian generous line height for body text
    color: AppColors.textPrimaryLight,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,  // Reduced (was 0.4)
    height: 1.50,  // Increased (was 1.33)
    color: AppColors.textSecondaryLight,
  );

  // Dark theme text variants (for use on dark backgrounds)
  static TextStyle get displayLargeDark => displayLarge.copyWith(color: AppColors.textPrimaryDark);
  static TextStyle get displayMediumDark => displayMedium.copyWith(color: AppColors.textPrimaryDark);
  static TextStyle get displaySmallDark => displaySmall.copyWith(color: AppColors.textPrimaryDark);
  static TextStyle get headlineLargeDark => headlineLarge.copyWith(color: AppColors.textPrimaryDark);
  static TextStyle get headlineMediumDark => headlineMedium.copyWith(color: AppColors.textPrimaryDark);
  static TextStyle get headlineSmallDark => headlineSmall.copyWith(color: AppColors.textPrimaryDark);
  static TextStyle get titleLargeDark => titleLarge.copyWith(color: AppColors.textPrimaryDark);
  static TextStyle get titleMediumDark => titleMedium.copyWith(color: AppColors.textPrimaryDark);
  static TextStyle get bodyLargeDark => bodyLarge.copyWith(color: AppColors.textPrimaryDark);
  static TextStyle get bodyMediumDark => bodyMedium.copyWith(color: AppColors.textPrimaryDark);
  static TextStyle get bodySmallDark => bodySmall.copyWith(color: AppColors.textSecondaryDark);
  static TextStyle get labelLargeDark => labelLarge.copyWith(color: AppColors.textPrimaryDark);
}
