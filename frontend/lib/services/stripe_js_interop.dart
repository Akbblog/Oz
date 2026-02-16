import 'dart:async';
import 'dart:js_interop';

/// Minimal Dart interop for Stripe.js (loaded via script tag in index.html).
///
/// Usage:
///   final stripe = StripeJs('pk_test_...');
///   final result = await stripe.confirmCardPayment(clientSecret, googlePayToken: 'tok_...');
class StripeJs {
  final _StripeInstance _stripe;

  StripeJs(String publishableKey)
      : _stripe = _createStripe(publishableKey.toJS);

  /// Confirm a PaymentIntent using a Google Pay token (tok_xxx from Stripe
  /// tokenization via Google Pay gateway).
  Future<StripeConfirmResult> confirmCardPayment(
    String clientSecret, {
    required String googlePayToken,
  }) async {
    final params = _buildConfirmParams(googlePayToken);
    final jsResult =
        await _stripe.confirmCardPayment(clientSecret.toJS, params).toDart;

    final error = jsResult.error;
    if (error != null) {
      return StripeConfirmResult(
        success: false,
        errorMessage: error.message,
      );
    }

    final pi = jsResult.paymentIntent;
    return StripeConfirmResult(
      success: pi?.status == 'succeeded' || pi?.status == 'requires_capture',
      paymentIntentId: pi?.id,
      status: pi?.status,
    );
  }
}

class StripeConfirmResult {
  final bool success;
  final String? paymentIntentId;
  final String? status;
  final String? errorMessage;

  StripeConfirmResult({
    required this.success,
    this.paymentIntentId,
    this.status,
    this.errorMessage,
  });
}

// ---------------------------------------------------------------------------
// JS bindings
// ---------------------------------------------------------------------------

@JS('Stripe')
external _StripeInstance _createStripe(JSString publishableKey);

extension type _StripeInstance(JSObject _) implements JSObject {
  external JSPromise<_ConfirmResult> confirmCardPayment(
      JSString clientSecret, JSObject data);
}

extension type _ConfirmResult(JSObject _) implements JSObject {
  external _StripeError? get error;
  external _PaymentIntent? get paymentIntent;
}

extension type _StripeError(JSObject _) implements JSObject {
  external String get message;
}

extension type _PaymentIntent(JSObject _) implements JSObject {
  external String get id;
  external String get status;
}

/// Build: `{ payment_method: { card: { token: "<tok>" } } }`
@JS('JSON.parse')
external JSObject _jsonParse(JSString json);

JSObject _buildConfirmParams(String token) {
  // Escape token for JSON safety (tokens are alphanumeric + underscore, but be safe).
  final escaped = token.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  final json = '{"payment_method":{"card":{"token":"$escaped"}}}';
  return _jsonParse(json.toJS);
}
