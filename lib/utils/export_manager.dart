import 'dart:convert';
import 'dart:io';
import 'package:buddy/services/firestore_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

class ExportManager {
  static final _firestore = FirestoreService.instance;
  
  static Future<void> exportToCSV() async {
    try {
      final transactions = await _firestore.getAllTransactions();
      
      if (transactions.isEmpty) {
        throw Exception('No transactions to export');
      }
      
      final StringBuffer csv = StringBuffer();
      csv.writeln('Date,Time,Type,Category,Amount,Note');
      
      for (final tx in transactions) {
        final date = tx.date;
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final timeStr = DateFormat('HH:mm').format(date);
        final type = tx.type;
        final category = tx.category;
        final amount = tx.amount;
        final note = (tx.note ?? '').replaceAll(',', ';');
        
        csv.writeln('$dateStr,$timeStr,$type,$category,$amount,$note');
      }
      
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'buddy_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(csv.toString());
      
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Buddy Expense Tracker Export',
        text: 'Exported ${transactions.length} transactions',
      );
    } catch (e) {
      throw Exception('Failed to export data: $e');
    }
  }
  
  static Future<void> exportToJSON() async {
    try {
      final transactions = await _firestore.getAllTransactions();
      
      if (transactions.isEmpty) {
        throw Exception('No transactions to export');
      }
      
      final exportData = {
        'app': 'Buddy Expense Tracker',
        'version': '1.0.0',
        'export_date': DateTime.now().toIso8601String(),
        'transaction_count': transactions.length,
        'transactions': transactions.map((tx) => {
          'id': tx.id,
          'date': tx.date.toIso8601String(),
          'type': tx.type,
          'category': tx.category,
          'amount': tx.amount,
          'note': tx.note,
          'icon': tx.icon,
        }).toList(),
      };
      
      final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
      
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'buddy_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(jsonString);
      
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Buddy Expense Tracker Export',
        text: 'Exported ${transactions.length} transactions',
      );
    } catch (e) {
      throw Exception('Failed to export data: $e');
    }
  }
  
  static Future<Map<String, dynamic>> generateMonthlyReport(DateTime month) async {
    final transactions = await _firestore.getAllTransactions();
    
    double totalIncome = 0;
    double totalExpense = 0;
    Map<String, double> categoryExpenses = {};
    Map<String, double> categoryIncomes = {};
    List<Map<String, dynamic>> monthTransactions = [];
    
    for (final tx in transactions) {
      final date = tx.date;
      
      if (date.year == month.year && date.month == month.month) {
        final amount = tx.amount;
        final type = tx.type.toLowerCase();
        final category = tx.category;
        
        final txMap = tx.toDisplayMap();
        monthTransactions.add(txMap);
        
        if (type == 'income') {
          totalIncome += amount;
          categoryIncomes[category] = (categoryIncomes[category] ?? 0) + amount;
        } else if (type == 'expense') {
          totalExpense += amount;
          categoryExpenses[category] = (categoryExpenses[category] ?? 0) + amount;
        }
      }
    }
    
    return {
      'month': DateFormat('MMMM yyyy').format(month),
      'total_income': totalIncome,
      'total_expense': totalExpense,
      'balance': totalIncome - totalExpense,
      'transaction_count': monthTransactions.length,
      'category_expenses': categoryExpenses,
      'category_incomes': categoryIncomes,
      'transactions': monthTransactions,
    };
  }
}
