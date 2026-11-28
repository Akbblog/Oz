import 'package:flutter/material.dart';

import 'legal/policies.dart';
import 'legal/policy_screen.dart';

/// Kept for existing imports; the privacy policy now lives with the other legal pages.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) => PolicyScreen(doc: Policies.privacy);
}
