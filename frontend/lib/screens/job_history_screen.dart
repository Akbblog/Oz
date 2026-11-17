import 'package:flutter/material.dart';

import 'my_searches_screen.dart';

/// Former "Job history" screen, replaced by [MySearchesScreen] (`/searches`).
/// Kept as a thin alias so older references keep compiling.
@Deprecated('Use MySearchesScreen')
class JobHistoryScreen extends StatelessWidget {
  final bool showHeader;

  const JobHistoryScreen({super.key, this.showHeader = true});

  @override
  Widget build(BuildContext context) => const MySearchesScreen();
}
