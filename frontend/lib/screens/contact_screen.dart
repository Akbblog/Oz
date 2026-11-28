import 'package:flutter/material.dart';

import '../widgets/app_shell_common.dart' show UiTokens;
import '../widgets/contact_form.dart';
import 'legal/policy_screen.dart';

/// `/contact`: the contact form on its own page (linked from the app's
/// sidebar and the Account page).
class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiTokens.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        final nav = Navigator.of(context);
                        nav.canPop()
                            ? nav.pop()
                            : nav.pushReplacementNamed('/');
                      },
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('Back'),
                      style: TextButton.styleFrom(
                          foregroundColor: UiTokens.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('Contact us',
                      style: TextStyle(
                          color: UiTokens.text,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6)),
                  const SizedBox(height: 8),
                  const Text(
                    'Questions, billing, feedback or a country you need: write to us and a person will reply by email.',
                    style: TextStyle(
                        color: UiTokens.textSecondary, fontSize: 15, height: 1.55),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: UiTokens.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: UiTokens.border),
                    ),
                    child: const ContactForm(),
                  ),
                  const SizedBox(height: 20),
                  const MerchantCard(),
                  const SizedBox(height: 18),
                  const PolicyLinks(current: '/contact'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
