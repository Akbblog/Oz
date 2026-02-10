import 'package:flutter/material.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';

class SidebarNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final List<SidebarNavItem> navItems;
  final bool collapsed;
  final bool hidden;
  final bool isAuthenticated;
  final bool isAdmin;
  final VoidCallback onAdminTap;
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
                label: item.label,
                pageIndex: item.pageIndex,
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
                icon: Icons.person_rounded,
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
              gradient: LinearGradient(colors: [AppColors.primaryBlue, AppColors.primaryBlueLight]),
              borderRadius: AppSpacing.borderRadiusMd,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withValues(alpha: 0.3),
                  blurRadius: 16,
                  spreadRadius: -8,
                ),
              ],
            ),
            child: const Icon(Icons.all_inclusive, color: Colors.white),
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
                    color: AppColors.primaryBlueLight.withValues(alpha: 0.7),
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
    required String label,
    required int pageIndex,
  }) {
    final isActive = currentIndex == pageIndex;
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
            gradient: isActive ? LinearGradient(colors: [AppColors.primaryBlue, AppColors.primaryBlueLight]) : null,
            borderRadius: AppSpacing.borderRadiusMd,
            border: isActive
                ? Border(
                    left: BorderSide(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 3,
                    ),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment:
                collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(
                icon,
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
              Icon(icon, color: Colors.white70, size: 18),
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
                child: Icon(Icons.visibility_rounded, color: Colors.white70, size: 18),
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
  final String label;
  final int pageIndex;

  const SidebarNavItem({
    required this.icon,
    required this.label,
    required this.pageIndex,
  });
}
