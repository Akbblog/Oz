import 'package:business_scraper_app/core/error_handler.dart';
import 'package:business_scraper_app/screens/payment_return_screen.dart';
import 'package:business_scraper_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ApiService {
  final List<Object> replies;
  int calls = 0;
  _Api(this.replies);

  @override
  Future<Map<String, dynamic>> getSafepayPaymentStatus(String transactionId) async {
    final r = replies[calls < replies.length ? calls : replies.length - 1];
    calls++;
    if (r is Exception) throw r;
    return r as Map<String, dynamic>;
  }
}

Map<String, dynamic> _status(String s) => {
      'status': s,
      'amount_cents': 2500,
      'currency': 'USD',
      'credits_purchased': 500,
      'environment': 'sandbox',
    };

void main() {
  testWidgets('a slow status check keeps "Confirming payment" instead of an error', (tester) async {
    final api = _Api([NetworkException('Request timed out'), _status('completed')]);
    await tester.pumpWidget(MaterialApp(home: PaymentReturnScreen(transactionId: 't1', api: api)));
    await tester.pump();
    expect(find.text('Confirming payment'), findsOneWidget);
    expect(find.text('Could not check this payment'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('Payment confirmed'), findsOneWidget);
    expect(api.calls, 2);
  });

  testWidgets('a payment that is not on the account is an error at once', (tester) async {
    final api = _Api([NotFoundException('not found')]);
    await tester.pumpWidget(MaterialApp(home: PaymentReturnScreen(transactionId: 't2', api: api)));
    await tester.pump();
    expect(find.text('Could not check this payment'), findsOneWidget);
    expect(find.textContaining('could not find this payment'), findsOneWidget);
  });
}
