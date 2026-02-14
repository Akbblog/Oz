import 'package:flutter/material.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/responsive_utils.dart';

class ResponsiveShell extends StatefulWidget {
  final Widget child;
  final Widget Function(BuildContext context, LayoutType layoutType, bool isSidebarCollapsed, VoidCallback onToggleSidebar) topBarBuilder;
  final Widget Function(BuildContext context, LayoutType layoutType, bool isSidebarCollapsed) sidebarBuilder;
  final Widget? bottomNavigation;

  const ResponsiveShell({
    super.key,
    required this.child,
    required this.topBarBuilder,
    required this.sidebarBuilder,
    this.bottomNavigation,
  });

  @override
  State<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends State<ResponsiveShell> {
  bool _sidebarExpanded = false;

  void _toggleSidebar() {
    setState(() => _sidebarExpanded = !_sidebarExpanded);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutType = AppBreakpoints.getLayoutType(constraints.maxWidth);

        if (layoutType == LayoutType.mobile) {
          return Column(
            children: [
              Expanded(child: widget.child),
              if (widget.bottomNavigation != null) widget.bottomNavigation!,
            ],
          );
        }

        final isCollapsed = layoutType == LayoutType.tablet && !_sidebarExpanded;
        final content = widget.child;

        return Row(
          children: [
            widget.sidebarBuilder(context, layoutType, isCollapsed),
            Expanded(
              child: Column(
                children: [
                  widget.topBarBuilder(
                    context,
                    layoutType,
                    isCollapsed,
                    _toggleSidebar,
                  ),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: ResponsiveUtils.getContentMaxWidth(layoutType),
                        ),
                        child: content,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
