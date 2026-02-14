import 'package:flutter/material.dart';
import '../core/theme/app_breakpoints.dart';
import '../core/utils/responsive_utils.dart';

enum ResponsiveGridType { stats, states, results, defaultGrid }

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final ResponsiveGridType gridType;
  final double? spacing;
  final double childAspectRatio;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.gridType = ResponsiveGridType.defaultGrid,
    this.spacing,
    this.childAspectRatio = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layoutType = AppBreakpoints.getLayoutType(constraints.maxWidth);
        final crossAxisCount = AppBreakpoints.getGridColumns(
          layoutType,
          gridType: _gridTypeKey(),
        );
        final gridSpacing =
            spacing ?? ResponsiveUtils.getGridSpacing(layoutType);

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: gridSpacing,
          mainAxisSpacing: gridSpacing,
          childAspectRatio: childAspectRatio,
          children: children,
        );
      },
    );
  }

  String _gridTypeKey() {
    switch (gridType) {
      case ResponsiveGridType.stats:
        return 'stats';
      case ResponsiveGridType.states:
        return 'states';
      case ResponsiveGridType.results:
        return 'results';
      case ResponsiveGridType.defaultGrid:
        return 'default';
    }
  }
}
