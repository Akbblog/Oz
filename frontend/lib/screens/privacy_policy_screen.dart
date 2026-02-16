import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String effectiveDate = 'February 16, 2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Privacy Policy'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceDark.withValues(alpha: 0.92),
                borderRadius: AppSpacing.borderRadiusLg,
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Infinity Leads Privacy Policy',
                    style: AppTypography.headlineSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Effective date: $effectiveDate',
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _section(
                    title: '1. Scope',
                    body:
                        'This Privacy Policy explains how Infinity Leads ("we", "our", "us") collects, uses, stores, and shares information when you use our web application and related services.',
                  ),
                  _section(
                    title: '2. Information We Collect',
                    body:
                        'We may collect account details (such as username, email, phone), authentication data, billing/payment metadata from payment providers, service usage data, job history, and technical data like IP address, browser, and device details.',
                  ),
                  _section(
                    title: '3. Business Listing Data',
                    body:
                        'Our platform helps users discover publicly available business listing information from third-party sources. Search result data may include business names, websites, phone numbers, addresses, map links, and publicly available contact emails when available.',
                  ),
                  _section(
                    title: '4. How We Use Information',
                    body:
                        'We use information to provide and improve the service, authenticate users, process payments, prevent abuse, monitor system performance, comply with legal obligations, and communicate important service updates.',
                  ),
                  _section(
                    title: '5. Legal Basis and Compliance',
                    body:
                        'Where applicable, we process personal data based on contract performance, legitimate interests, legal obligations, and/or consent. You are responsible for using exported lead data in compliance with applicable privacy, anti-spam, and marketing laws.',
                  ),
                  _section(
                    title: '6. Sharing and Disclosure',
                    body:
                        'We do not sell personal data. We may share data with infrastructure and payment service providers, analytics/security vendors, and authorities where required by law or to protect rights and safety.',
                  ),
                  _section(
                    title: '7. Data Retention',
                    body:
                        'We retain account and operational records for as long as needed to provide services, resolve disputes, enforce agreements, and meet legal obligations. Retention periods may vary by data type.',
                  ),
                  _section(
                    title: '8. Security',
                    body:
                        'We use reasonable administrative, technical, and organizational safeguards to protect data. No method of transmission or storage is completely secure, so absolute security cannot be guaranteed.',
                  ),
                  _section(
                    title: '9. Your Rights',
                    body:
                        'Depending on your location, you may have rights to access, correct, delete, or restrict processing of your personal data, and to object or request portability. You can submit requests using the contact details below.',
                  ),
                  _section(
                    title: '10. Cookies and Local Storage',
                    body:
                        'We may use cookies or local storage to keep sessions active, remember settings, and improve reliability and performance.',
                  ),
                  _section(
                    title: '11. International Transfers',
                    body:
                        'Your data may be processed in countries other than your own. We take reasonable steps to protect transferred data under applicable legal requirements.',
                  ),
                  _section(
                    title: '12. Children',
                    body:
                        'Our service is not intended for children under 13 (or equivalent minimum age in your jurisdiction), and we do not knowingly collect personal data from children.',
                  ),
                  _section(
                    title: '13. Changes to This Policy',
                    body:
                        'We may update this policy from time to time. Material changes will be reflected by updating the effective date and, where appropriate, through in-app or email notices.',
                  ),
                  _section(
                    title: '14. Contact',
                    body:
                        'For privacy questions or requests, contact: support@infinityleads.pro',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required String body,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.titleMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(
            body,
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white70,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
