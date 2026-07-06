import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _database;
  bool _isInitialized = false;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    await initdb();
    return _database!;
  }

  Future<void> initdb() async {
    if (_isInitialized && _database != null && _database!.isOpen) {
      return;
    }

    try {
      final dbPath = join(await getDatabasesPath(), 'user.db');

      _database = await openDatabase(
        dbPath,
        version: 2,
        readOnly: false,
        singleInstance: true,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing database: $e');
      _isInitialized = false;
      _database = null;
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute(
      'CREATE TABLE transactions('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'amount REAL NOT NULL,'
      'type TEXT NOT NULL,'
      'date TEXT NOT NULL,'
      'note TEXT,'
      'category TEXT NOT NULL,'
      'icon INTEGER NOT NULL,'
      'auto_detected INTEGER DEFAULT 0,'
      'notification_source TEXT,'
      'notification_hash TEXT'
      ')',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(date)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_transactions_hash ON transactions(notification_hash)',
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN auto_detected INTEGER DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN notification_source TEXT',
      );
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN notification_hash TEXT',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_transactions_hash ON transactions(notification_hash)',
      );
      debugPrint(
        '✅ DATABASE: Upgraded to version 2 - Added auto-detection fields',
      );
    }
  }

  Future<int> insertTransaction(Map<String, Object?> values) async {
    debugPrint(
      '💾 DATABASE: Inserting transaction: ${values['type']} ₹${values['amount']} on ${values['date']}',
    );
    final db = await database;
    final id = await db.insert(
      'transactions',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('✅ DATABASE: Transaction saved with ID: $id');
    return id;
  }

  Future<int> updateTransaction(int id, Map<String, Object?> values) async {
    final db = await database;
    return db.update(
      'transactions',
      values,
      where: 'id = ?',
      whereArgs: [id],
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, Object?>>> getAllTransactions() async {
    final db = await database;
    final results = await db.query('transactions', orderBy: 'date DESC');
    debugPrint('📖 DATABASE: Retrieved ${results.length} transactions');
    for (final row in results) {
      debugPrint(
        '   - ${row['type']} ₹${row['amount']} (${row['category']}) [ID: ${row['id']}]',
      );
    }
    return results;
  }

  Future<Map<String, Object?>?> getTransactionById(int id) async {
    final db = await database;
    final res = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (res.isEmpty) return null;
    return res.first;
  }

  // Check if exact hash exists (same notification processed twice)
  Future<bool> isDuplicateTransaction(String hash) async {
    final db = await database;
    final result = await db.query(
      'transactions',
      where: 'notification_hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  // Find similar transactions (same amount and type) within time window
  Future<List<Map<String, Object?>>> findSimilarTransactions({
    required double amount,
    required String type,
    required int hoursWindow,
  }) async {
    final db = await database;
    final now = DateTime.now();
    final windowStart = now
        .subtract(Duration(hours: hoursWindow))
        .toIso8601String();

    final results = await db.query(
      'transactions',
      where: 'amount = ? AND type = ? AND date >= ?',
      whereArgs: [amount, type, windowStart],
      orderBy: 'date DESC',
    );

    return results;
  }

  // Insert auto-detected transaction (allows duplicates, but with confirmation)
  Future<int> insertAutoTransaction(Map<String, Object?> values) async {
    debugPrint(
      '🤖 DATABASE: Auto-inserting transaction: ${values['type']} ₹${values['amount']} from ${values['notification_source']}',
    );
    final db = await database;
    final id = await db.insert(
      'transactions',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (id > 0) {
      debugPrint('✅ DATABASE: Auto-transaction saved with ID: $id');
    } else {
      debugPrint('⚠️ DATABASE: Failed to save transaction');
    }
    return id;
  }

  Future<List<Map<String, Object?>>> getAutoDetectedTransactions() async {
    final db = await database;
    return db.query(
      'transactions',
      where: 'auto_detected = ?',
      whereArgs: [1],
      orderBy: 'date DESC',
    );
  }

  // Store pending transaction temporarily in SharedPreferences
  Future<void> storePendingTransaction(
    String hash,
    Map<String, Object?> data,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_$hash', jsonEncode(data));
    debugPrint('💾 Stored pending transaction: $hash');
  }

  Future<Map<String, Object?>?> getPendingTransaction(String hash) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('pending_$hash');
    if (jsonStr == null) return null;
    return Map<String, Object?>.from(jsonDecode(jsonStr) as Map);
  }

  Future<void> removePendingTransaction(String hash) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_$hash');
    debugPrint('🗑️ Removed pending transaction: $hash');
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      _isInitialized = false;
    }
  }
}
