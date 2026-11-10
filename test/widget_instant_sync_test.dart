// test/widget_instant_sync_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buddy/models/transaction.dart';
import 'package:buddy/services/widget_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.faysarukattil.buddy/widget');
  final List<MethodCall> methodCalls = [];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      methodCalls.add(call);
      return true;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('WidgetService immediately pushes updated data on transaction change', () async {
    final now = DateTime.now();

    final txns = [
      TransactionModel(
        id: 'txn_1',
        amount: 250.0,
        type: 'expense',
        date: now,
        note: 'Swiggy Dinner',
        category: 'Food',
        icon: 0xe237,
      ),
      TransactionModel(
        id: 'txn_2',
        amount: 1000.0,
        type: 'income',
        date: now,
        note: 'Freelance',
        category: 'Salary',
        icon: 0xe237,
      ),
    ];

    await WidgetService.updateFromTransactions(txns);

    expect(methodCalls.length, 1);
    expect(methodCalls.first.method, 'updateWidget');

    final data = methodCalls.first.arguments as Map<dynamic, dynamic>;
    expect(data['today_spent_raw'], 250.0);
    expect(data['today_income_raw'], 1000.0);
    expect(data['today_balance_raw'], 750.0);
    expect(data['today_is_negative'], false);
    expect(data['today_count'], 2);
    expect(data['txn_0_exists'], true);
  });

  test('WidgetService immediately reflects edited transaction amounts', () async {
    final now = DateTime.now();

    // User edits the expense from 250 to 800
    final txnsEdited = [
      TransactionModel(
        id: 'txn_1',
        amount: 800.0,
        type: 'expense',
        date: now,
        note: 'Swiggy Dinner (Edited)',
        category: 'Food',
        icon: 0xe237,
      ),
      TransactionModel(
        id: 'txn_2',
        amount: 1000.0,
        type: 'income',
        date: now,
        note: 'Freelance',
        category: 'Salary',
        icon: 0xe237,
      ),
    ];

    await WidgetService.updateFromTransactions(txnsEdited);

    expect(methodCalls.length, 1);
    final data = methodCalls.first.arguments as Map<dynamic, dynamic>;
    expect(data['today_spent_raw'], 800.0);
    expect(data['today_balance_raw'], 200.0);
  });

  test('WidgetService immediately reflects deleted transaction amounts', () async {
    final now = DateTime.now();

    // User deletes txn_1, leaving only txn_2
    final txnsRemaining = [
      TransactionModel(
        id: 'txn_2',
        amount: 1000.0,
        type: 'income',
        date: now,
        note: 'Freelance',
        category: 'Salary',
        icon: 0xe237,
      ),
    ];

    await WidgetService.updateFromTransactions(txnsRemaining);

    expect(methodCalls.length, 1);
    final data = methodCalls.first.arguments as Map<dynamic, dynamic>;
    expect(data['today_spent_raw'], 0.0);
    expect(data['today_income_raw'], 1000.0);
    expect(data['today_balance_raw'], 1000.0);
    expect(data['today_count'], 1);
  });
}

