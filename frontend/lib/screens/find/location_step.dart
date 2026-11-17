import 'package:flutter/material.dart';

/// Find leads — step 1 (Location). Placeholder created by FE-CORE; the
/// FE-FIND agent replaces the body. The shell (AppShell) provides the top
/// bar and navigation, so this widget is a page body only (no Scaffold bar).
class FindLocationStep extends StatefulWidget {
  const FindLocationStep({super.key});

  @override
  State<FindLocationStep> createState() => _FindLocationStepState();
}

class _FindLocationStepState extends State<FindLocationStep> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Choose a location'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pushNamed('/find/details'),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
