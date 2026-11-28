import '../../config/business_info.dart';

/// One legal page. Paragraphs that start with "• " are shown as bullet points.
class PolicyDoc {
  final String route;
  final String title;
  final String navLabel;
  final String summary;
  final List<PolicySection> sections;

  const PolicyDoc({
    required this.route,
    required this.title,
    required this.navLabel,
    required this.summary,
    required this.sections,
  });
}

class PolicySection {
  final String heading;
  final List<String> paragraphs;
  const PolicySection(this.heading, this.paragraphs);
}

/// Date shown on every policy page. Update it whenever the wording changes.
const String policiesEffectiveDate = 'November 28, 2026';

String _contactLine() {
  final parts = <String>[
    'email ${BusinessInfo.email}',
    if (BusinessInfo.phone.isNotEmpty) 'phone or WhatsApp ${BusinessInfo.phone}',
    'or the contact form on our Contact page',
  ];
  return 'You can reach us by ${parts.join(', ')}.';
}

String _whoWeAre() {
  final address = BusinessInfo.address.isEmpty ? '' : ', ${BusinessInfo.address.join(', ')}';
  return 'Infinity Leads is operated by ${BusinessInfo.operator}$address. In these pages "we", "us" and "our" mean '
      '${BusinessInfo.legalName.isEmpty ? BusinessInfo.tradingName : BusinessInfo.legalName}, and "you" means the '
      'person or business using the service.';
}

class Policies {
  Policies._();

  static final PolicyDoc terms = PolicyDoc(
    route: '/terms',
    title: 'Terms and Conditions',
    navLabel: 'Terms',
    summary: 'The rules for using Infinity Leads and buying credits.',
    sections: [
      PolicySection('1. Who we are', [_whoWeAre(), _contactLine()]),
      PolicySection('2. The service', [
        'Infinity Leads is a web application for finding local businesses. You choose a country, the states or '
            'cities, and a type of business; our servers search public Google Business listings and return a list '
            'with business name, phone, website, email when it is listed, address, category, city and a map link. '
            'You can review the results in the app and download them as Excel or CSV files.',
        'Results come from public listings that businesses and third parties publish. We do not guarantee that '
            'every listing is complete, current or accurate, or that a search returns a particular number of results.',
      ]),
      PolicySection('3. Your account', [
        'You need an account to run searches and buy credits. Give accurate details, keep your password private and '
            'tell us if you think someone else has used your account. One account is for one person or one business.',
        'We may suspend an account that is used to break these terms or the law, or that puts the service or other '
            'users at risk.',
      ]),
      PolicySection('4. Credits and prices', [
        'Searches are paid for with credits. Before you start a search the app shows its estimated cost in credits. '
            'If a search cannot deliver all the results that were charged for, the credits for the results that were '
            'not delivered are returned to your balance automatically when the search ends.',
        'Credits are sold in packs. The current packs and their prices in US dollars are shown on our Pricing page '
            'and at checkout before you pay. We may change prices for future purchases; a change never affects '
            'credits you have already bought.',
        'Purchased credits do not expire. Credits have no cash value, cannot be transferred to another account and '
            'can only be used on Infinity Leads. Promotional or bonus credits may have their own conditions, which '
            'are shown when they are given.',
      ]),
      PolicySection('5. Payments', [
        'Card payments (Visa and Mastercard) are processed by Safepay, our payment provider. You enter your card '
            'details on Safepay\'s secure checkout page; we never see or store your full card number.',
        'You are charged in US dollars, exactly the amount shown at checkout. If your card is in another currency, '
            'your bank converts the amount and may add its own fees.',
        'Credits are added to your account as soon as Safepay confirms the payment. There are no subscriptions and '
            'no recurring charges: you only pay when you choose to buy a pack.',
      ]),
      PolicySection('6. Refunds and cancellations', [
        'Refunds and cancellations are covered by our Refund and Cancellation Policy, which forms part of these terms.',
      ]),
      PolicySection('7. Acceptable use', [
        'You agree to use the service and the data you download lawfully. In particular you will:',
        '• follow the privacy, data-protection, anti-spam and telemarketing rules that apply where you and the '
            'businesses you contact are located;',
        '• not use the service to harass anyone or to send unlawful messages;',
        '• not try to disrupt the service, get around its limits, access other users\' data, or copy the service '
            'itself;',
        '• not share your account or resell access to the service.',
      ]),
      PolicySection('8. Your results', [
        'You may use the lists you download for your own business purposes. You are responsible for how you store '
            'and use them.',
      ]),
      PolicySection('9. Availability and changes', [
        'We work to keep the service available around the clock, but it may be interrupted for maintenance or by '
            'problems outside our control, and a search can take longer than expected. We may improve or change '
            'features over time.',
      ]),
      PolicySection('10. Our property', [
        'The Infinity Leads software, design, name and logo belong to us. These terms do not give you any rights to '
            'them other than using the service.',
      ]),
      PolicySection('11. Liability', [
        'The service is provided "as is". To the extent the law allows, we are not liable for indirect or '
            'consequential losses, such as lost profits or lost business, and our total liability for any claim is '
            'limited to the amount you paid us in the 12 months before the claim. Nothing in these terms limits '
            'liability that cannot be limited by law.',
      ]),
      PolicySection('12. Ending your account', [
        'You can stop using the service at any time and ask us to close your account by contacting us. Unused '
            'credits are refunded only as described in the Refund and Cancellation Policy.',
      ]),
      PolicySection('13. Changes to these terms', [
        'We may update these terms. The date at the top shows when they last changed. If a change is significant we '
            'will tell you in the app or by email before it applies.',
      ]),
      PolicySection('14. Governing law', [
        BusinessInfo.jurisdictionCity.isEmpty
            ? 'These terms are governed by the laws of ${BusinessInfo.country}.'
            : 'These terms are governed by the laws of ${BusinessInfo.country}, and the courts of '
                '${BusinessInfo.jurisdictionCity} have jurisdiction over any dispute.',
      ]),
      PolicySection('15. Contact', [_contactLine()]),
    ],
  );

  static final PolicyDoc refund = PolicyDoc(
    route: '/refund-policy',
    title: 'Refund and Cancellation Policy',
    navLabel: 'Refunds & cancellation',
    summary: 'When you can get your money back and how to cancel.',
    sections: [
      PolicySection('1. What you buy', [
        'Infinity Leads sells credit packs for an online service. Credits are added to your account and used to run '
            'searches. Nothing physical is sold or shipped.',
      ]),
      PolicySection('2. Refund of an unused pack within 7 days', [
        'You can ask for a full refund of a credit pack within 7 days of buying it, as long as none of that pack\'s '
            'credits have been used, that is, your credit balance still includes all the credits from that pack. '
            'When we refund the pack, its credits are removed from your account.',
      ]),
      PolicySection('3. Charging mistakes are always refunded', [
        'If you were charged twice for the same purchase, or charged but the credits were not added and we cannot '
            'add them, we refund the extra or failed charge in full, whenever you tell us.',
      ]),
      PolicySection('4. Searches that deliver fewer results', [
        'If a search cannot deliver all the results that were charged for, the credits for the missing results are '
            'returned to your balance automatically when the search ends. These are returned as credits, not money.',
      ]),
      PolicySection('5. What is not refundable', [
        '• packs bought more than 7 days ago;',
        '• packs whose credits have been used, fully or partly;',
        '• free, bonus or promotional credits.',
        'This does not affect charging mistakes (section 3) or any right you have under the law.',
      ]),
      PolicySection('6. How to ask for a refund', [
        'Write to us at ${BusinessInfo.email} or through the Contact page, from the email address of your account. '
            'Include the payment reference shown under Credits > Payments and the reason for the request.',
        'We reply ${BusinessInfo.replyTime}. An approved refund is issued through Safepay to the card you paid with, '
            'for the same amount in US dollars. Your bank usually shows it within 5 to 10 business days. If your '
            'card is in another currency, the amount you get back can differ slightly because of your bank\'s '
            'exchange rate.',
      ]),
      PolicySection('7. Cancelling a payment', [
        'You can cancel on Safepay\'s checkout page before paying by choosing "Cancel payment". Nothing is charged. '
            'A checkout that is not completed expires automatically after about an hour, and nothing is charged.',
      ]),
      PolicySection('8. Cancelling a search', [
        'You can cancel a running search from My searches. The credits for results that were not delivered are '
            'returned to your balance.',
      ]),
      PolicySection('9. No subscriptions', [
        'Infinity Leads has no subscriptions or recurring charges, so there is nothing to cancel to stop future '
            'payments. You only pay when you buy a pack.',
      ]),
      PolicySection('10. Closing your account', [
        'You can ask us to close your account at any time. Unused credits are refunded only under sections 2 and 3.',
      ]),
      PolicySection('11. Before disputing a charge', [
        'If something looks wrong with a payment, please contact us first. We can usually fix it faster than a '
            'card dispute. ${_contactLine()}',
      ]),
    ],
  );

  static final PolicyDoc delivery = PolicyDoc(
    route: '/delivery-policy',
    title: 'Delivery Policy',
    navLabel: 'Delivery',
    summary: 'How and when you receive what you paid for.',
    sections: [
      PolicySection('1. Digital service, nothing shipped', [
        'Infinity Leads is an online service. Nothing is shipped, and there are no delivery charges. The service is '
            'available worldwide through a web browser, 24 hours a day, except during maintenance.',
      ]),
      PolicySection('2. Credits after payment', [
        'Credits are added to your account automatically as soon as Safepay confirms your payment, usually within a '
            'few seconds. The confirmation page shows "Payment confirmed" with the number of credits added, and the '
            'payment and its invoice appear under Credits in the app.',
        'If confirmation takes longer, the page shows "Still confirming". The credits are added automatically as '
            'soon as Safepay confirms; you do not need to pay again. If they have not appeared within one hour, '
            'contact us with the payment reference.',
      ]),
      PolicySection('3. Search results', [
        'Searches run on our servers. A small search usually finishes within minutes; a large search covering many '
            'cities can take longer. You can close the browser while it runs. Results appear in My searches and can '
            'be downloaded as Excel or CSV at any time while your account is open.',
      ]),
      PolicySection('4. Problems with delivery', [
        'If credits or results do not arrive as described, contact us and we will put it right or refund under the '
            'Refund and Cancellation Policy. ${_contactLine()}',
      ]),
    ],
  );

  static final PolicyDoc privacy = PolicyDoc(
    route: '/privacy-policy',
    title: 'Privacy Policy',
    navLabel: 'Privacy',
    summary: 'What information we collect and how we use it.',
    sections: [
      PolicySection('1. Scope', [
        'This policy explains how Infinity Leads collects, uses, stores and shares information when you use our web '
            'application and related services. ${_whoWeAre()}',
      ]),
      PolicySection('2. Information we collect', [
        'Account details (such as name, email, phone and company), sign-in data, payment records from our payment '
            'provider, how you use the service, your search history, and technical data such as IP address, browser '
            'and device.',
      ]),
      PolicySection('3. Payments', [
        'Card payments are processed by Safepay. We receive the payment status, amount, currency and a payment '
            'reference. We never receive or store your full card number or security code.',
      ]),
      PolicySection('4. Business listing data', [
        'The service helps you find publicly available business listing information. Results can include business '
            'names, websites, phone numbers, addresses, map links and publicly listed contact emails.',
      ]),
      PolicySection('5. How we use information', [
        'To provide and improve the service, sign you in, process payments, prevent abuse, monitor the system, meet '
            'legal obligations and send important service messages.',
      ]),
      PolicySection('6. Legal basis and your responsibility', [
        'Where applicable, we process personal data to perform our contract with you, for our legitimate interests, '
            'to meet legal obligations, or with your consent. You are responsible for using exported lead data in line '
            'with the privacy, anti-spam and marketing laws that apply to you.',
      ]),
      PolicySection('7. Sharing', [
        'We do not sell personal data. We share it only with service providers that run the service for us (hosting, '
            'payments, security and analytics) and with authorities where the law requires it.',
      ]),
      PolicySection('8. Keeping data', [
        'We keep account and payment records for as long as needed to provide the service, resolve disputes, enforce '
            'our terms and meet legal obligations.',
      ]),
      PolicySection('9. Security', [
        'We use reasonable technical and organisational safeguards. No method of sending or storing data is '
            'completely secure.',
      ]),
      PolicySection('10. Your rights', [
        'Depending on where you live, you may have the right to access, correct or delete your personal data, to '
            'restrict or object to its use, and to ask for a copy. Contact us to make a request.',
      ]),
      PolicySection('11. Cookies and local storage', [
        'We use browser storage to keep you signed in, remember settings and keep the service reliable.',
      ]),
      PolicySection('12. International transfers', [
        'Your data may be processed in countries other than your own. We take reasonable steps to protect it.',
      ]),
      PolicySection('13. Children', [
        'The service is not meant for children under 13 and we do not knowingly collect their data.',
      ]),
      PolicySection('14. Changes', [
        'We may update this policy. The date at the top shows when it last changed.',
      ]),
      PolicySection('15. Contact', [_contactLine()]),
    ],
  );

  static List<PolicyDoc> get all => [terms, privacy, refund, delivery];
}
