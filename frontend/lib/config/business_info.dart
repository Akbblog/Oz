/// The merchant identity shown in the site footer, the Contact page and the
/// legal pages. It must match the business details given to Safepay in the
/// merchant onboarding (MOB) form.
///
/// Empty values are not shown anywhere (no placeholders are ever published);
/// [BusinessInfo.missing] lists what still has to be filled in before release.
class BusinessInfo {
  BusinessInfo._();

  /// Name customers see.
  static const String tradingName = 'Infinity Leads';

  /// Registered business / legal name exactly as on the Safepay MOB form.
  static const String legalName = '';

  /// Registered business address, one line per entry.
  static const List<String> address = [];

  /// Phone / WhatsApp number in international format, e.g. +92 300 1234567.
  static const String phone = '';

  /// Support email shown to customers.
  static const String email = 'support@infinityleads.pro';

  /// City whose courts have jurisdiction (Terms, governing law).
  static const String jurisdictionCity = '';

  static const String country = 'Pakistan';

  /// Usual reply time promised on the Contact page and in the policies.
  static const String replyTime = 'within 2 business days';

  static String get operator =>
      legalName.isEmpty ? tradingName : '$legalName ("$tradingName")';

  static List<String> get missing => [
        if (legalName.isEmpty) 'legalName',
        if (address.isEmpty) 'address',
        if (phone.isEmpty) 'phone',
        if (jurisdictionCity.isEmpty) 'jurisdictionCity',
      ];
}
