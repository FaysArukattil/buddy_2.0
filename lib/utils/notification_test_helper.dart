import 'package:flutter/material.dart';
import '../services/db_helper.dart';

/// Test helper widget to simulate notifications and test parsing
/// Add this to your Profile screen temporarily for testing
class NotificationTestHelper extends StatelessWidget {
  const NotificationTestHelper({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bug_report, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'Test Notifications',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Simulate notifications to test auto-detection',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          
          // Test buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TestButton(
                label: 'Debit ₹500',
                onPressed: () => _testDebit(context),
                color: Colors.red,
              ),
              _TestButton(
                label: 'Credit ₹2000',
                onPressed: () => _testCredit(context),
                color: Colors.green,
              ),
              _TestButton(
                label: 'Food ₹450',
                onPressed: () => _testFood(context),
                color: Colors.orange,
              ),
              _TestButton(
                label: 'Shopping ₹1250',
                onPressed: () => _testShopping(context),
                color: Colors.purple,
              ),
              _TestButton(
                label: 'Transport ₹300',
                onPressed: () => _testTransport(context),
                color: Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _testDebit(BuildContext context) async {
    await _simulateTransaction(
      context,
      text: 'Your A/C 1234 debited by Rs.500 for shopping',
      packageName: 'com.google.android.apps.messaging',
    );
  }

  Future<void> _testCredit(BuildContext context) async {
    await _simulateTransaction(
      context,
      text: 'Your A/C 5678 credited with Rs.2000 via UPI from John',
      packageName: 'com.google.android.apps.messaging',
    );
  }

  Future<void> _testFood(BuildContext context) async {
    await _simulateTransaction(
      context,
      text: 'Payment of Rs.450 to Swiggy successful',
      packageName: 'com.phonepe.app',
    );
  }

  Future<void> _testShopping(BuildContext context) async {
    await _simulateTransaction(
      context,
      text: 'Rs.1,250 debited for Amazon purchase',
      packageName: 'com.google.android.apps.messaging',
    );
  }

  Future<void> _testTransport(BuildContext context) async {
    await _simulateTransaction(
      context,
      text: 'Rs.300 paid to Uber for ride',
      packageName: 'com.phonepe.app',
    );
  }

  Future<void> _simulateTransaction(
    BuildContext context, {
    required String text,
    required String packageName,
  }) async {
    try {
      debugPrint('🧪 TEST: Simulating notification');
      debugPrint('   Package: $packageName');
      debugPrint('   Text: $text');

      // Parse the transaction (same logic as NotificationService)
      final transactionData = _parseTransaction(text, packageName);

      if (transactionData == null) {
        _showMessage(context, 'No transaction detected in text', Colors.orange);
        return;
      }

      // Insert into database
      final db = await DatabaseHelper.instance.database;
      final id = await db.insert('transactions', {
        'amount': transactionData['amount'],
        'type': transactionData['type'],
        'date': DateTime.now().toIso8601String(),
        'note': transactionData['note'],
        'category': transactionData['category'],
        'icon': transactionData['icon'],
        'auto_detected': 1,
        'notification_source': packageName,
        'notification_hash': 'test_${DateTime.now().millisecondsSinceEpoch}',
      });

      debugPrint('✅ TEST: Transaction added with ID: $id');
      
      if (context.mounted) {
        _showMessage(
          context,
          'Transaction added! ${transactionData['type']} ₹${transactionData['amount']}',
          Colors.green,
        );
      }
    } catch (e) {
      debugPrint('❌ TEST: Error: $e');
      if (context.mounted) {
        _showMessage(context, 'Error: $e', Colors.red);
      }
    }
  }

  Map<String, dynamic>? _parseTransaction(String text, String packageName) {
    // Regex patterns
    final debitRegex = RegExp(
      r'\b(debited|spent|purchase|paid|withdrawn|debit|payment|sent|transferred)\b',
      caseSensitive: false,
    );
    final creditRegex = RegExp(
      r'\b(credited|received|deposit|income|credit|refund|cashback)\b',
      caseSensitive: false,
    );
    final amountRegex = RegExp(
      r'(?:Rs\.?|INR|₹)\s?([0-9,]+\.?[0-9]*)|([0-9,]+\.?[0-9]*)\s?(?:Rs\.?|INR|₹)',
      caseSensitive: false,
    );

    // Check for transaction type
    final isDebit = debitRegex.hasMatch(text);
    final isCredit = creditRegex.hasMatch(text);

    if (!isDebit && !isCredit) {
      return null;
    }

    // Extract amount
    final amountMatch = amountRegex.firstMatch(text);
    if (amountMatch == null) {
      return null;
    }

    final amountStr = amountMatch.group(1) ?? amountMatch.group(2);
    if (amountStr == null) {
      return null;
    }

    final amount = double.parse(amountStr.replaceAll(',', ''));
    final type = isDebit ? 'expense' : 'income';
    final category = _detectCategory(text, type);
    final icon = _getIconForCategory(category);

    return {
      'amount': amount,
      'type': type,
      'note': 'Test: $text',
      'category': category,
      'icon': icon,
    };
  }

  String _detectCategory(String text, String type) {
    final lowerText = text.toLowerCase();

    if (type == 'expense') {
      if (lowerText.contains('swiggy') ||
          lowerText.contains('zomato') ||
          lowerText.contains('restaurant') ||
          lowerText.contains('food')) {
        return 'Food';
      }
      if (lowerText.contains('amazon') ||
          lowerText.contains('flipkart') ||
          lowerText.contains('myntra') ||
          lowerText.contains('shopping')) {
        return 'Shopping';
      }
      if (lowerText.contains('uber') ||
          lowerText.contains('ola') ||
          lowerText.contains('fuel') ||
          lowerText.contains('petrol')) {
        return 'Transport';
      }
      if (lowerText.contains('electricity') ||
          lowerText.contains('water') ||
          lowerText.contains('gas') ||
          lowerText.contains('bill')) {
        return 'Bills';
      }
      if (lowerText.contains('netflix') ||
          lowerText.contains('spotify') ||
          lowerText.contains('movie')) {
        return 'Entertainment';
      }
      if (lowerText.contains('medical') ||
          lowerText.contains('pharmacy') ||
          lowerText.contains('hospital')) {
        return 'Health';
      }
    } else {
      if (lowerText.contains('salary') || lowerText.contains('wage')) {
        return 'Salary';
      }
      if (lowerText.contains('refund') || lowerText.contains('cashback')) {
        return 'Refund';
      }
    }

    return 'Other';
  }

  int _getIconForCategory(String category) {
    switch (category) {
      case 'Food':
        return 0xe56c; // restaurant
      case 'Shopping':
        return 0xe8cc; // shopping_bag
      case 'Transport':
        return 0xe531; // directions_car
      case 'Bills':
        return 0xe24d; // receipt
      case 'Entertainment':
        return 0xe02c; // movie
      case 'Health':
        return 0xe3f0; // local_hospital
      case 'Salary':
        return 0xe263; // account_balance_wallet
      case 'Refund':
        return 0xe5d5; // refresh
      default:
        return 0xe8f4; // category
    }
  }

  void _showMessage(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _TestButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color color;

  const _TestButton({
    required this.label,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}
