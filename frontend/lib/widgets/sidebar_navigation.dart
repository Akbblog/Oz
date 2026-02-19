import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import 'brand_mark.dart';

class SidebarNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final List<SidebarNavItem> navItems;
  final bool collapsed;
  final bool hidden;
  final bool isAuthenticated;
  final bool isAdmin;
  final VoidCallback onAdminTap;
  final VoidCallback onWalletTap;
  final VoidCallback onProfileTap;
  final VoidCallback onAuthTap;
  final String? username;
  final String? email;

  const SidebarNavigation({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.navItems,
    required this.collapsed,
    required this.hidden,
    required this.isAuthenticated,
    required this.isAdmin,
    required this.onAdminTap,
    required this.onWalletTap,
    required this.onProfileTap,
    required this.onAuthTap,
    this.username,
    this.email,
  });

  @override
  Widget build(BuildContext context) {
    if (hidden) {
      return const SizedBox.shrink();
    }

    final width = collapsed
        ? AppBreakpoints.sidebarCollapsed
        : AppBreakpoints.sidebarExpanded;

    return Container(
      width: width,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.backgroundDark, AppColors.backgroundDark],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(
          right: BorderSide(
            color: AppColors.primaryBlue.withValues(alpha: 0.2),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryBlue.withValues(alpha: 0.15),
            blurRadius: 16,
            spreadRadius: -12,
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildLogoSection(collapsed),
            const SizedBox(height: AppSpacing.lg),
            for (final item in navItems)
              _buildNavItem(
                icon: item.icon,
                selectedIcon: item.selectedIcon,
                iconAsset: item.iconAsset,
                selectedIconAsset: item.selectedIconAsset,
                label: item.label,
                pageIndex: item.pageIndex,
                activePageIndexes: item.activePageIndexes,
                emphasized: item.emphasized,
              ),
            const Spacer(),
            if (isAuthenticated && isAdmin)
              _buildActionItem(
                icon: Icons.shield_rounded,
                label: 'Admin',
                onTap: onAdminTap,
              ),
            if (isAuthenticated)
              _buildActionItem(
                icon: Icons.account_balance_wallet_rounded,
                iconAsset: 'assets/icons/wallet.svg',
                label: 'Wallet',
                onTap: onWalletTap,
              ),
            if (isAuthenticated)
              _buildActionItem(
                icon: Icons.person_rounded,
                iconAsset: 'assets/icons/profile.svg',
                label: 'Profile',
                onTap: onProfileTap,
              ),
            if (!isAuthenticated)
              _buildActionItem(
                icon: Icons.login_rounded,
                label: 'Sign in',
                onTap: onAuthTap,
              ),
            _buildUserSection(collapsed),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoSection(bool collapsed) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
        0,
      ),
      child: Row(
        mainAxisAlignment:
            collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: AppSpacing.borderRadiusMd,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.3),
                  blurRadius: 16,
                  spreadRadius: -8,
                ),
              ],
            ),
            child: const Center(
              child: BrandMark(
                tiled: false,
                size: 22,
                hoverGlow: true,
              ),
            ),
          ),
          if (!collapsed) ...[
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Infinity',
                  style: AppTypography.titleSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Leads Pro',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.primaryBlue.withValues(alpha: 0.7),
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData? selectedIcon,
    required String? iconAsset,
    required String? selectedIconAsset,
    required String label,
    required int pageIndex,
    required List<int> activePageIndexes,
    required bool emphasized,
  }) {
    final isActive =
        currentIndex == pageIndex || activePageIndexes.contains(currentIndex);
    final resolvedIcon = isActive ? (selectedIcon ?? icon) : icon;
    final resolvedIconAsset =
        isActive ? (selectedIconAsset ?? iconAsset) : iconAsset;
    return Tooltip(
      message: collapsed ? label : '',
      child: InkWell(
        onTap: () => onTabSelected(pageIndex),
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            gradient: isActive
                ? AppColors.primaryGradient
                : (emphasized
                    ? LinearGradient(
                        colors: [
                          AppColors.surfaceDark.withValues(alpha: 0.9),
                          AppColors.backgroundDark.withValues(alpha: 0.9),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      )
                    : null),
            borderRadius: AppSpacing.borderRadiusMd,
            border: isActive
                ? Border(
                    left: BorderSide(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 3,
                    ),
                  )
                : (emphasized
                    ? Border.all(
                        color: AppColors.primaryBlue.withValues(alpha: 0.25),
                      )
                    : null),
          ),
          child: Row(
            mainAxisAlignment:
                collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              _buildAdaptiveIcon(
                icon: resolvedIcon,
                iconAsset: resolvedIconAsset,
                color: isActive ? Colors.white : Colors.white70,
                size: 20,
              ),
              if (!collapsed) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(
                    color: isActive ? Colors.white : Colors.white70,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    String? iconAsset,
    required String label,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: collapsed ? label : '',
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark.withValues(alpha: 0.6),
            borderRadius: AppSpacing.borderRadiusMd,
            border: Border.all(
              color: AppColors.primaryBlue.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisAlignment:
                collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              _buildAdaptiveIcon(
                icon: icon,
                iconAsset: iconAsset,
                color: Colors.white70,
                size: 18,
              ),
              if (!collapsed) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdaptiveIcon({
    required IconData icon,
    required Color color,
    required double size,
    String? iconAsset,
  }) {
    if (iconAsset == null || iconAsset.isEmpty) {
      return Icon(icon, color: color, size: size);
    }

    return SvgPicture.asset(
      iconAsset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  Widget _buildUserSection(bool collapsed) {
    if (!isAuthenticated) {
      return Container(
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.lg,
        ),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark.withValues(alpha: 0.7),
          borderRadius: AppSpacing.borderRadiusLg,
          border: Border.all(
            color: AppColors.primaryBlue.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment:
              collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.backgroundDark,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primaryBlue.withValues(alpha: 0.3),
                ),
              ),
              child: const Center(
                child: Icon(Icons.visibility_rounded,
                    color: Colors.white70, size: 18),
              ),
            ),
            if (!collapsed) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Guest Mode',
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Explore before sign in',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white54,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    final initial =
        (username?.isNotEmpty ?? false) ? username![0].toUpperCase() : 'U';
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.lg,
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark.withValues(alpha: 0.7),
        borderRadius: AppSpacing.borderRadiusLg,
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment:
            collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.backgroundDark,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primaryBlue.withValues(alpha: 0.3),
              ),
            ),
            child: Center(
              child: Text(
                initial,
                style: AppTypography.titleSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (!collapsed) ...[
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username ?? 'User',
                    style: AppTypography.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    email ?? 'Pro Account',
                    style: AppTypography.labelSmall.copyWith(
                      color: Colors.white54,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SidebarNavItem {
  final IconData icon;
  final IconData? selectedIcon;
  final String? iconAsset;
  final String? selectedIconAsset;
  final String label;
  final int pageIndex;
  final List<int> activePageIndexes;
  final bool emphasized;

  const SidebarNavItem({
    required this.icon,
    this.selectedIcon,
    this.iconAsset,
    this.selectedIconAsset,
    required this.label,
    required this.pageIndex,
    this.activePageIndexes = const [],
    this.emphasized = false,
  });
}
