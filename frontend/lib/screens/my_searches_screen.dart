import 'package:flutter/material.dart';

import 'job_history_screen.dart';

/// My searches (`/searches`). Placeholder created by FE-CORE that wraps the
/// existing history screen; the FE-SEARCH agent replaces the body. Page body
/// only (AppShell provides the top bar and navigation).
class MySearchesScreen extends StatefulWidget {
  const MySearchesScreen({super.key});

  @override
  State<MySearchesScreen> createState() => _MySearchesScreenState();
}

class _MySearchesScreenState extends State<MySearchesScreen> {
  @override
  Widget build(BuildContext context) {
    return const JobHistoryScreen(showHeader: false);
  }
}
