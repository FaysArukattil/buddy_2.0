// lib/repositories/transaction_repository.dart
import 'package:buddy/services/db_helper.dart';
import 'package:buddy/models/transaction.dart';

class TransactionRepository {
  final DatabaseHelper dbh = DatabaseHelper.instance;

  Future<int> add({
    required double amount,
    required String type,
    required DateTime date,
    String? note,
    required String category,
    required int iconCodePoint,
  }) async {
    final map = <String, Object?>{
      'amount': amount,
      'type': type,
      'date': date.toIso8601String(),
      'note': note,
      'category': category,
      'icon': iconCodePoint,
    };
    return dbh.insertTransaction(map);
  }

  Future<int> update(int id, Map<String, Object?> values) async {
    return dbh.updateTransaction(id, values);
  }

  Future<int> delete(int id) async {
    return dbh.deleteTransaction(id);
  }

  Future<List<Map<String, Object?>>> getAll() async {
    return dbh.getAllTransactions();
  }

  Future<Map<String, Object?>?> getById(int id) async {
    return dbh.getTransactionById(id);
  }

  // Auto-detection methods
  Future<List<Map<String, Object?>>> getAutoDetectedTransactions() async {
    return dbh.getAutoDetectedTransactions();
  }

  Future<bool> isDuplicateTransaction(String hash) async {
    return dbh.isDuplicateTransaction(hash);
  }

  Future<int> addAutoDetected(
    TransactionModel tx, {
    required String notificationSource,
    required String notificationHash,
  }) async {
    // Prevent duplicates at repo layer too
    if (await dbh.isDuplicateTransaction(notificationHash)) return 0;

    final map = tx.toMap();
    map['notification_source'] = notificationSource;
    map['notification_hash'] = notificationHash;
    map['auto_detected'] = 1;

    return dbh.insertAutoTransaction(map);
  }
}
