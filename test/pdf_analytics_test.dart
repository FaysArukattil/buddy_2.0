import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buddy/services/pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return Directory.systemTemp.path;
    });
  });

  group('PDF Analytics Report Tests', () {
    test('generateMultipleTransactionsPdf generates PDF with analytics metrics',
        () async {
      final sampleTransactions = [
        {
          'id': 'txn_1',
          'amount': 25000.0,
          'type': 'income',
          'category': 'Salary',
          'date': '2026-10-01T10:00:00.000',
          'note': 'Monthly salary credited',
        },
        {
          'id': 'txn_2',
          'amount': 3500.0,
          'type': 'expense',
          'category': 'Food & Dining',
          'date': '2026-10-03T19:30:00.000',
          'note': 'Dinner at restaurant',
        },
        {
          'id': 'txn_3',
          'amount': 1200.0,
          'type': 'expense',
          'category': 'Transport',
          'date': '2026-10-05T08:15:00.000',
          'note': 'Fuel refill',
        },
        {
          'id': 'txn_4',
          'amount': 2000.0,
          'type': 'expense',
          'category': 'Food & Dining',
          'date': '2026-10-08T13:00:00.000',
          'note': 'Lunch with friends',
        },
      ];

      final file = await PdfService.generateMultipleTransactionsPdf(
        transactions: sampleTransactions,
        title: 'Monthly Financial Report',
        subtitle: 'October 2026',
      );

      expect(file, isNotNull);
      expect(await file.exists(), isTrue);
      final fileSize = await file.length();
      expect(fileSize, greaterThan(1000)); // PDF has substantial data

      // Clean up
      try {
        await file.delete();
      } catch (_) {}
    });
  });
}
