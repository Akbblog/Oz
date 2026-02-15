import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import 'brand_mark.dart';
import 'credit_pill.dart';

class TopBar extends StatelessWidget {
  final String title;
  final bool showMenuToggle;
  final VoidCallback? onMenuToggle;
  final int creditBalance;
  final bool loadingCredits;
  final VoidCallback? onRefreshCredits;
  final String userInitial;
  final bool isAuthenticated;
  final bool isAdmin;
  final VoidCallback? onAdminTap;
  final VoidCallback? onProfileTap;
  final VoidCallback? onLogoutTap;
  final VoidCallback? onAuthTap;

  const TopBar({
    super.key,
    required this.title,
    required this.showMenuToggle,
    this.onMenuToggle,
    required this.creditBalance,
    required this.loadingCredits,
    this.onRefreshCredits,
    required this.userInitial,
    required this.isAuthenticated,
    required this.isAdmin,
    this.onAdminTap,
    this.onProfileTap,
    this.onLogoutTap,
    this.onAuthTap,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.backgroundDark.withValues(alpha: 0.95),
            border: Border(
              bottom: BorderSide(
                color: AppColors.primaryBlue.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              if (showMenuToggle)
                IconButton(
                  onPressed: onMenuToggle,
                  icon: const Icon(Icons.menu_rounded, color: Colors.white),
                )
              else
                Row(
                  children: [
                    const BrandMark(size: 32, hoverGlow: true),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Infinity Leads Pro',
                      style: AppTypography.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isAuthenticated) ...[
                _buildCreditPill(context),
                const SizedBox(width: AppSpacing.sm),
                _iconButton(
                  icon: Icons.notifications_none_rounded,
                  onTap: () {},
                  tooltip: 'Notifications',
                ),
              ],
              if (isAuthenticated && isAdmin) ...[
                const SizedBox(width: AppSpacing.xs),
                _iconButton(
                  icon: Icons.shield_rounded,
                  onTap: onAdminTap,
                  tooltip: 'Admin',
                ),
              ],
              const SizedBox(width: AppSpacing.xs),
              isAuthenticated
                  ? _buildProfileMenu(context)
                  : _buildAuthButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreditPill(BuildContext context) {
    return CreditPill(
      balance: creditBalance,
      loading: loadingCredits,
      onTap: () => Navigator.of(context).pushNamed('/wallet'),
      onRefresh: onRefreshCredits,
    );
  }

  Widget _iconButton({
    required IconData icon,
    required VoidCallback? onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppSpacing.borderRadiusMd,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: AppSpacing.borderRadiusMd,
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.2),
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  Widget _buildProfileMenu(BuildContext context) {
    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusLg),
      color: AppColors.surfaceDark,
      onSelected: (value) {
        if (value == 'profile') {
          onProfileTap?.call();
        } else if (value == 'logout') {
          onLogoutTap?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'profile',
          child: Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  size: 18, color: Colors.white),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Profile',
                style: AppTypography.bodyMedium.copyWith(color: Colors.white),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              const Icon(Icons.logout_rounded,
                  size: 18, color: AppColors.dangerRed),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Logout',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.dangerRed),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: AppSpacing.borderRadiusMd,
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.3),
          ),
        ),
        child: Center(
          child: Text(
            userInitial,
            style: AppTypography.titleSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onAuthTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: AppColors.primaryBlue.withValues(alpha: 0.45)),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppSpacing.borderRadiusMd),
      ),
      icon: const Icon(Icons.login_rounded, size: 18),
      label: Text(
        'Sign in',
        style: AppTypography.labelLarge.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
