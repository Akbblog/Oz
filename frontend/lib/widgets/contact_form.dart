import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/countries.dart';
import '../providers/auth_provider.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import 'app_shell_common.dart' show UiTokens;
import 'country_picker.dart';

/// The contact form, used on the landing page and on /contact.
///
/// Signed-in people get their name and email filled in. The message is stored
/// on the server and shows up in the admin console under Messages.
class ContactForm extends StatefulWidget {
  /// Injected in tests.
  final ApiService? api;
  const ContactForm({super.key, this.api});

  @override
  State<ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<ContactForm> {
  static const Map<String, String> _topics = {
    'general': 'General question',
    'sales': 'Sales',
    'support': 'Help with my account',
    'billing': 'Billing',
    'partnership': 'Partnership',
    'feedback': 'Feedback',
  };

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _message = TextEditingController();
  final _trap = TextEditingController(); // never shown; only bots fill it

  String _topic = 'general';
  Country? _country;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    if (user != null) {
      final full = '${user['full_name'] ?? ''}'.trim();
      _name.text = full.isNotEmpty ? full : '${user['username'] ?? ''}';
      _email.text = '${user['email'] ?? ''}';
      _topic = 'support';
    }
    AnalyticsService.instance.geo().then((where) {
      final c = countryByIso(where['country']);
      if (c != null && mounted && _country == null) setState(() => _country = c);
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _message, _trap]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      final who = await AnalyticsService.instance.identity();
      final where = await AnalyticsService.instance.geo();
      await (widget.api ?? ApiService()).sendContactMessage(
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        phoneCountry: _country?.iso,
        topic: _topic,
        message: _message.text.trim(),
        website: _trap.text,
        visitorId: who.visitorId,
        geoCountry: where['country'],
        geoCity: where['city'],
        page: Uri.base.path,
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sent = true;
      });
      AnalyticsService.instance.feature('contact_sent');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e
            .toString()
            .replaceFirst(RegExp(r'^(Exception|ApiException|NetworkException|ValidationException):\s*'), '');
      });
    }
  }

  InputDecoration _decoration(String hint) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: UiTokens.textMuted, fontSize: 14),
      filled: true,
      fillColor: const Color(0xFF15171A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      border: border(UiTokens.border),
      enabledBorder: border(UiTokens.border),
      focusedBorder: border(UiTokens.accent, 1.5),
      errorBorder: border(UiTokens.failedFg),
      focusedErrorBorder: border(UiTokens.failedFg, 1.5),
      errorStyle: const TextStyle(color: UiTokens.failedFg, fontSize: 12),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
                color: UiTokens.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
      );

  @override
  Widget build(BuildContext context) {
    if (_sent) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
                color: UiTokens.completedBg, shape: BoxShape.circle),
            child: const Icon(Icons.check_rounded,
                color: UiTokens.completedFg, size: 30),
          ),
          const SizedBox(height: 16),
          const Text('Message sent',
              style: TextStyle(
                  color: UiTokens.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'Thanks for writing. We read every message and reply by email.',
            textAlign: TextAlign.center,
            style: TextStyle(color: UiTokens.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 18),
          TextButton(
            onPressed: () => setState(() {
              _sent = false;
              _message.clear();
            }),
            child: const Text('Send another message',
                style: TextStyle(color: UiTokens.accent)),
          ),
        ],
      );
    }

    const fieldText = TextStyle(color: UiTokens.text, fontSize: 14.5);
    return Form(
      key: _formKey,
      child: LayoutBuilder(builder: (context, c) {
        final twoCols = c.maxWidth >= 520;
        final name = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Your name'),
            TextFormField(
              key: const Key('contact-name'),
              controller: _name,
              style: fieldText,
              cursorColor: UiTokens.accent,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: _decoration('Full name'),
              validator: (v) =>
                  (v ?? '').trim().length < 2 ? 'Please tell us your name' : null,
            ),
          ],
        );
        final email = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Email'),
            TextFormField(
              key: const Key('contact-email'),
              controller: _email,
              style: fieldText,
              cursorColor: UiTokens.accent,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: _decoration('you@company.com'),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$')
                      .hasMatch((v ?? '').trim())
                  ? null
                  : 'Enter an email we can reply to',
            ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (twoCols)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: name),
                  const SizedBox(width: 12),
                  Expanded(child: email),
                ],
              )
            else ...[name, const SizedBox(height: 14), email],
            const SizedBox(height: 14),
            _label('Phone or WhatsApp (optional)'),
            Row(
              children: [
                CountryDialButton(
                  country: _country,
                  background: const Color(0xFF15171A),
                  border: UiTokens.border,
                  foreground: UiTokens.text,
                  radius: 12,
                  height: 50,
                  onChanged: (c) => setState(() => _country = c),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: const Key('contact-phone'),
                    controller: _phone,
                    style: fieldText,
                    cursorColor: UiTokens.accent,
                    keyboardType: TextInputType.phone,
                    decoration: _decoration('Number'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _label('What is it about?'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _topics.entries)
                  _TopicChip(
                    label: t.value,
                    selected: _topic == t.key,
                    onTap: () => setState(() => _topic = t.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _label('Message'),
            TextFormField(
              key: const Key('contact-message'),
              controller: _message,
              style: fieldText.copyWith(height: 1.45),
              cursorColor: UiTokens.accent,
              minLines: 4,
              maxLines: 8,
              maxLength: 4000,
              buildCounter: (context,
                      {required currentLength,
                      required isFocused,
                      required maxLength}) =>
                  null,
              decoration: _decoration('How can we help?'),
              validator: (v) => (v ?? '').trim().length < 10
                  ? 'Please write a little more so we can help'
                  : null,
            ),
            // Hidden from people (zero size, skipped by keyboard and readers).
            ExcludeSemantics(
              child: SizedBox(
                height: 0,
                width: 0,
                child: Opacity(
                  opacity: 0,
                  child: IgnorePointer(
                    child: ExcludeFocus(
                      child: TextField(controller: _trap),
                    ),
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: UiTokens.failedBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 18, color: UiTokens.failedFg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          key: const Key('contact-error'),
                          style: const TextStyle(
                              color: UiTokens.text, fontSize: 13.5)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: FilledButton(
                key: const Key('contact-send'),
                onPressed: _sending ? null : _send,
                style: FilledButton.styleFrom(
                  backgroundColor: UiTokens.accent,
                  foregroundColor: const Color(0xFF0B1A1E),
                  disabledBackgroundColor: UiTokens.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white),
                      )
                    : const Text('Send message'),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'We only use your details to reply to this message.',
              textAlign: TextAlign.center,
              style: TextStyle(color: UiTokens.textMuted, fontSize: 12),
            ),
          ],
        );
      }),
    );
  }
}

class _TopicChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TopicChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? UiTokens.selectedSurface : const Color(0xFF15171A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: selected ? UiTokens.accent : UiTokens.border),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Text(label,
              style: TextStyle(
                  color: selected ? UiTokens.accent : UiTokens.textSecondary,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
        ),
      ),
    );
  }
}
