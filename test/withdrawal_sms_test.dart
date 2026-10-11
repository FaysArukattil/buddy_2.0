import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ATM / Card Withdrawal SMS Parsing Tests', () {
    final debitRegex = RegExp(
      r'(?:debited|spent|paid|withdrawn|withdrew|transferred|sent|deducted|charged|purchase|utilized|debited\s*by|spent\s*at)',
      caseSensitive: false,
    );

    final amountRegex = RegExp(
      r'(?:rs\.?|inr|₹)\s*([0-9,]+\.?[0-9]*)|([0-9,]+\.?[0-9]*)\s*(?:rs\.?|inr|₹)|\b([0-9,]+\.[0-9]{2})\b',
      caseSensitive: false,
    );

    final balanceRegex = RegExp(
      r'(?:bal|balance|avbl\.?\s*bal|avl\.?\s*bal|avail\.?\s*bal|available\s*bal|total\s*bal|clear\s*bal|net\s*bal|avail\.?\s*lmt)[\s:.-]*(?:is\s*)?(?:rs\.?|inr|₹)?[0-9,]+\.?[0-9]*',
      caseSensitive: false,
    );

    Map<String, dynamic>? parseSms(String text) {
      final isDebit = debitRegex.hasMatch(text);
      if (!isDebit) return null;

      final allAmountMatches = amountRegex.allMatches(text).toList();
      if (allAmountMatches.isEmpty) return null;

      final balanceMatches = balanceRegex.allMatches(text).toList();
      final validAmountMatches = allAmountMatches.where((amountMatch) {
        return !balanceMatches.any((balMatch) {
          final aStart = amountMatch.start;
          final aEnd = amountMatch.end;
          final bStart = balMatch.start;
          final bEnd = balMatch.end;
          return !(aEnd < bStart || aStart > bEnd);
        });
      }).toList();

      final targetMatch = validAmountMatches.isNotEmpty ? validAmountMatches.first : allAmountMatches.first;
      final amountStr = (targetMatch.group(1) ?? targetMatch.group(2) ?? targetMatch.group(3))?.replaceAll(',', '');
      if (amountStr == null) return null;

      final amount = double.tryParse(amountStr);
      if (amount == null || amount <= 0.0) return null;

      String note = 'Transaction';
      final atmMatch = RegExp(r'withdrawn\s*[@at]\s*([A-Za-z0-9\s_-]+?)(?:\s+on|\s+at|\s+bal|\s+ref|\s*\.|\s*$)', caseSensitive: false).firstMatch(text);
      if (atmMatch != null) {
        final loc = atmMatch.group(1)?.trim();
        if (loc != null && loc.isNotEmpty) {
          note = 'Cash Withdrawal ($loc)';
        }
      }

      return {
        'amount': amount,
        'type': 'expense',
        'note': note,
      };
    }

    test('Parses Federal Bank ATM card withdrawal correctly', () {
      const sms = 'Rs 3000 withdrawn@ DAHISAR  on 03OCT26 10:34 Bal Rs 32839.08 Ref 627610749779. Not you? Call 18004251199/ SMS NO 1549 to 9895088888 -Federal Bank.';
      final result = parseSms(sms);

      expect(result, isNotNull);
      expect(result!['amount'], equals(3000.0));
      expect(result['type'], equals('expense'));
      expect(result['note'], equals('Cash Withdrawal (DAHISAR)'));
    });

    test('Parses standard ATM cash withdrawal with balance', () {
      const sms = 'Rs. 5000.00 withdrawn from ATM at ANDHERI on 01-OCT-26. Avl Bal: Rs. 12500.00';
      final result = parseSms(sms);

      expect(result, isNotNull);
      expect(result!['amount'], equals(5000.0));
      expect(result['type'], equals('expense'));
    });
  });
}
