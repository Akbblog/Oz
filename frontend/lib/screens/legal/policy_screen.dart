import 'package:flutter/material.dart';

import '../../config/business_info.dart';
import '../landing/landing_kit.dart';
import 'policies.dart';

/// Public legal page (Terms, Privacy, Refund & Cancellation, Delivery).
class PolicyScreen extends StatelessWidget {
  final PolicyDoc doc;
  const PolicyScreen({super.key, required this.doc});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final pad = width >= 700 ? 28.0 : 18.0;
    return Scaffold(
      backgroundColor: LC.bg,
      body: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: LT.font),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        TextButton.icon(
                          key: const ValueKey('policy-back'),
                          onPressed: () {
                            final nav = Navigator.of(context);
                            nav.canPop() ? nav.pop() : nav.pushReplacementNamed('/');
                          },
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('Back'),
                          style: TextButton.styleFrom(foregroundColor: LC.dim),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => Navigator.of(context).pushNamed('/'),
                          style: TextButton.styleFrom(foregroundColor: LC.dim),
                          child: const Text(BusinessInfo.tradingName),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    PolicyLinks(current: doc.route),
                    const SizedBox(height: 26),
                    Text(doc.title,
                        style: LT.h2.copyWith(fontSize: width >= 700 ? 34 : 27)),
                    const SizedBox(height: 8),
                    Text('Effective $policiesEffectiveDate', style: LT.small),
                    const SizedBox(height: 22),
                    for (final s in doc.sections) _section(s),
                    const SizedBox(height: 12),
                    const MerchantCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(PolicySection s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.heading, style: LT.h3.copyWith(fontSize: 18)),
          const SizedBox(height: 8),
          for (final p in s.paragraphs)
            Padding(
              padding: EdgeInsets.only(bottom: 8, left: p.startsWith('• ') ? 10 : 0),
              child: SelectableText(p,
                  style: LT.body.copyWith(color: LC.dim, height: 1.65)),
            ),
        ],
      ),
    );
  }
}

/// Links between the legal pages and the Contact page.
class PolicyLinks extends StatelessWidget {
  final String? current;
  const PolicyLinks({super.key, this.current});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, String route) {
      final active = route == current;
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: OutlinedButton(
          onPressed: active ? null : () => Navigator.of(context).pushNamed(route),
          style: OutlinedButton.styleFrom(
            foregroundColor: LC.text,
            disabledForegroundColor: LC.accent,
            side: BorderSide(color: active ? LC.accent : LC.border),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          child: Text(label, style: const TextStyle(fontFamily: LT.font, fontSize: 13)),
        ),
      );
    }

    return Wrap(children: [
      for (final d in Policies.all) chip(d.navLabel, d.route),
      chip('Contact', '/contact'),
    ]);
  }
}

/// Merchant identity and contact details (footer, Contact page, legal pages).
class MerchantCard extends StatelessWidget {
  final bool compact;
  const MerchantCard({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final lines = <(IconData, String)>[
      if (BusinessInfo.legalName.isNotEmpty) (Icons.business_rounded, BusinessInfo.legalName),
      if (BusinessInfo.address.isNotEmpty) (Icons.place_outlined, BusinessInfo.address.join(', ')),
      (Icons.mail_outline_rounded, BusinessInfo.email),
      if (BusinessInfo.phone.isNotEmpty) (Icons.phone_outlined, '${BusinessInfo.phone} (phone / WhatsApp)'),
      (Icons.schedule_rounded, 'We reply ${BusinessInfo.replyTime}'),
    ];
    return Container(
      key: const ValueKey('merchant-card'),
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 16 : 20),
      decoration: BoxDecoration(
        color: LC.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LC.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${BusinessInfo.tradingName} · customer support',
              style: LT.h3.copyWith(fontSize: 16)),
          const SizedBox(height: 10),
          for (final (icon, text) in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: LC.accent),
                  const SizedBox(width: 10),
                  Expanded(
                      child: SelectableText(text,
                          style: LT.small.copyWith(color: LC.dim, fontSize: 14))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
