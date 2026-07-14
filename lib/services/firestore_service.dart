// lib/services/firestore_service.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:buddy/models/transaction.dart';
import 'package:buddy/models/category.dart' as cat;
import 'package:buddy/utils/colors.dart';

class FirestoreService {
  static final FirestoreService instance = FirestoreService._();
  FirestoreService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Helpers ──

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _txnCol {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');
    return _db.collection('users').doc(uid).collection('transactions');
  }

  CollectionReference<Map<String, dynamic>> get _catCol {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');
    return _db.collection('users').doc(uid).collection('categories');
  }

  // ── Initialization ──

  static Future<void> enableOfflinePersistence() async {
    // Firestore enables persistence by default on mobile.
    // For web, we enable it explicitly:
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      debugPrint('✅ Firestore offline persistence enabled');
    } catch (e) {
      debugPrint('⚠️ Firestore persistence already enabled or error: $e');
    }
  }

  // ── Transactions ──

  /// Add a new transaction
  Future<String> addTransaction(TransactionModel txn) async {
    final doc = await _txnCol.add(txn.toFirestore());
    debugPrint('✅ FIRESTORE: Transaction added with ID: ${doc.id}');
    return doc.id;
  }

  /// Update an existing transaction
  Future<void> updateTransaction(String id, Map<String, dynamic> data) async {
    // Convert date if it's a DateTime
    if (data['date'] is DateTime) {
      data['date'] = Timestamp.fromDate(data['date'] as DateTime);
    }
    await _txnCol.doc(id).update(data);
    debugPrint('✅ FIRESTORE: Transaction $id updated');
  }

  /// Delete a transaction
  Future<void> deleteTransaction(String id) async {
    await _txnCol.doc(id).delete();
    debugPrint('✅ FIRESTORE: Transaction $id deleted');
  }

  /// Get all transactions (one-time fetch), sorted by date DESC
  Future<List<TransactionModel>> getAllTransactions() async {
    final snapshot = await _txnCol.orderBy('date', descending: true).get();
    return snapshot.docs
        .map((doc) => TransactionModel.fromFirestore(doc))
        .toList();
  }

  /// Get transactions as a real-time stream
  Stream<List<TransactionModel>> getTransactionsStream() {
    return _txnCol
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc))
            .toList());
  }

  /// Get transactions for a specific month
  Future<List<TransactionModel>> getTransactionsForMonth(
    int year,
    int month,
  ) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0, 23, 59, 59);

    final snapshot = await _txnCol
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('date', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => TransactionModel.fromFirestore(doc))
        .toList();
  }

  /// Get transactions filtered by type
  Future<List<TransactionModel>> getTransactionsByType(String type) async {
    final snapshot = await _txnCol
        .where('type', isEqualTo: type.toLowerCase())
        .orderBy('date', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => TransactionModel.fromFirestore(doc))
        .toList();
  }

  /// Get a single transaction by ID
  Future<TransactionModel?> getTransactionById(String id) async {
    final doc = await _txnCol.doc(id).get();
    if (!doc.exists) return null;
    return TransactionModel.fromFirestore(doc);
  }

  /// Check for duplicate notification hash
  Future<bool> isDuplicateTransaction(String hash) async {
    final snapshot = await _txnCol
        .where('notificationHash', isEqualTo: hash)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  /// Add auto-detected transaction
  Future<String> addAutoDetectedTransaction(TransactionModel txn) async {
    if (txn.notificationHash != null) {
      final isDupe = await isDuplicateTransaction(txn.notificationHash!);
      if (isDupe) {
        debugPrint('⚠️ FIRESTORE: Duplicate auto-detected transaction skipped');
        return '';
      }
    }
    return addTransaction(txn);
  }

  /// Get monthly totals
  Future<Map<String, double>> getMonthlyTotals(int year, int month) async {
    final txns = await getTransactionsForMonth(year, month);
    double income = 0;
    double expense = 0;

    for (final txn in txns) {
      if (txn.type == 'income') {
        income += txn.amount;
      } else {
        expense += txn.amount;
      }
    }

    return {'income': income, 'expense': expense, 'balance': income - expense};
  }

  /// Delete all transactions (for data clearing)
  Future<void> deleteAllTransactions() async {
    final snapshot = await _txnCol.get();
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    debugPrint('✅ FIRESTORE: All transactions deleted');
  }

  // ── Categories ──

  /// Get all categories for a type (expense/income), deduplicated by name
  Future<List<cat.Category>> getCategories(String type) async {
    final snapshot = await _catCol
        .where('type', isEqualTo: type.toLowerCase())
        .orderBy('order')
        .get();

    // Deduplicate by name — keep the first occurrence
    final seen = <String>{};
    final categories = <cat.Category>[];
    for (final doc in snapshot.docs) {
      final category = cat.Category.fromFirestore(doc);
      if (!seen.contains(category.name)) {
        seen.add(category.name);
        categories.add(category);
      }
    }
    return categories;
  }

  /// Get categories as a stream
  Stream<List<cat.Category>> getCategoriesStream(String type) {
    return _catCol
        .where('type', isEqualTo: type.toLowerCase())
        .orderBy('order')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => cat.Category.fromFirestore(doc))
            .toList());
  }

  /// Add a custom category
  Future<String> addCategory(cat.Category category) async {
    final doc = await _catCol.add(category.toFirestore());
    debugPrint('✅ FIRESTORE: Category "${category.name}" added');
    return doc.id;
  }

  /// Delete a category
  Future<void> deleteCategory(String id) async {
    await _catCol.doc(id).delete();
    debugPrint('✅ FIRESTORE: Category $id deleted');
  }

  /// Check if default categories exist
  Future<bool> hasCategories() async {
    final snapshot = await _catCol.limit(1).get();
    return snapshot.docs.isNotEmpty;
  }

  /// Seed default categories (batch write for efficiency)
  Future<void> seedDefaultCategories() async {
    final snapshot = await _catCol.get();
    final existingNames = snapshot.docs
        .map((doc) => doc.data()['name'] as String)
        .toSet();

    debugPrint('🌱 FIRESTORE: Seeding default categories...');
    final batch = _db.batch();
    int order = existingNames.length;
    bool hasAddedAny = false;

    for (final entry in _defaultExpenseCategories) {
      if (!existingNames.contains(entry['name'])) {
        final ref = _catCol.doc();
        batch.set(ref, {
          'name': entry['name'],
          'icon': entry['icon'],
          'color': AppColors.getCategoryColor(entry['name'] as String).value,
          'type': 'expense',
          'isDefault': true,
          'order': order++,
        });
        hasAddedAny = true;
      }
    }

    for (final entry in _defaultIncomeCategories) {
      if (!existingNames.contains(entry['name'])) {
        final ref = _catCol.doc();
        batch.set(ref, {
          'name': entry['name'],
          'icon': entry['icon'],
          'color': AppColors.getCategoryColor(entry['name'] as String).value,
          'type': 'income',
          'isDefault': true,
          'order': order++,
        });
        hasAddedAny = true;
      }
    }

    if (hasAddedAny) {
      await batch.commit();
      debugPrint('✅ FIRESTORE: Default categories seeded');
    } else {
      debugPrint('ℹ️ FIRESTORE: All default categories already present');
    }
  }

  /// Remove duplicate categories from Firestore (keeps first by order)
  Future<void> removeDuplicateCategories() async {
    try {
      final snapshot = await _catCol.orderBy('order').get();
      final seen = <String>{};
      final batch = _db.batch();
      bool hasDeleted = false;

      for (final doc in snapshot.docs) {
        final name = doc.data()['name'] as String;
        if (seen.contains(name)) {
          batch.delete(doc.reference);
          hasDeleted = true;
          debugPrint('🗑️ FIRESTORE: Removing duplicate category: $name');
        } else {
          seen.add(name);
        }
      }

      if (hasDeleted) {
        await batch.commit();
        debugPrint('✅ FIRESTORE: Duplicate categories cleaned up');
      } else {
        debugPrint('ℹ️ FIRESTORE: No duplicate categories found');
      }
    } catch (e) {
      debugPrint('⚠️ FIRESTORE: Error cleaning duplicates: $e');
    }
  }

  /// Delete all categories
  Future<void> deleteAllCategories() async {
    final snapshot = await _catCol.get();
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    debugPrint('✅ FIRESTORE: All categories deleted');
  }

  /// Delete all user data
  Future<void> clearAllData() async {
    await deleteAllTransactions();
    await deleteAllCategories();
    debugPrint('✅ FIRESTORE: All user data cleared');
  }

  // ── Default Category Definitions ──

  static final List<Map<String, dynamic>> _defaultExpenseCategories = [
    {'name': 'Food & Dining', 'icon': Icons.restaurant_rounded.codePoint},
    {'name': 'Groceries', 'icon': Icons.shopping_cart_rounded.codePoint},
    {'name': 'Swiggy', 'icon': Icons.delivery_dining_rounded.codePoint},
    {'name': 'Zomato', 'icon': Icons.fastfood_rounded.codePoint},
    {'name': 'Zepto', 'icon': Icons.bolt_rounded.codePoint},
    {'name': 'Instamart', 'icon': Icons.storefront_rounded.codePoint},
    {'name': 'Amazon', 'icon': Icons.inventory_2_rounded.codePoint},
    {'name': 'Flipkart', 'icon': Icons.shopping_bag_rounded.codePoint},
    {'name': 'Myntra', 'icon': Icons.checkroom_rounded.codePoint},
    {'name': 'Transport', 'icon': Icons.directions_car_rounded.codePoint},
    {'name': 'Uber', 'icon': Icons.local_taxi_rounded.codePoint},
    {'name': 'Ola', 'icon': Icons.local_taxi_rounded.codePoint},
    {'name': 'Rapido', 'icon': Icons.two_wheeler_rounded.codePoint},
    {'name': 'Fuel', 'icon': Icons.local_gas_station_rounded.codePoint},
    {'name': 'Netflix', 'icon': Icons.tv_rounded.codePoint},
    {'name': 'YouTube', 'icon': Icons.ondemand_video_rounded.codePoint},
    {'name': 'Spotify', 'icon': Icons.music_note_rounded.codePoint},
    {'name': 'Hotstar', 'icon': Icons.live_tv_rounded.codePoint},
    {'name': 'Gym & Fitness', 'icon': Icons.fitness_center_rounded.codePoint},
    {'name': 'Medical', 'icon': Icons.medical_services_rounded.codePoint},
    {'name': 'Education', 'icon': Icons.school_rounded.codePoint},
    {'name': 'Rent', 'icon': Icons.home_rounded.codePoint},
    {'name': 'Bills & Utilities', 'icon': Icons.receipt_long_rounded.codePoint},
    {'name': 'Recharge', 'icon': Icons.phone_android_rounded.codePoint},
    {'name': 'Coffee', 'icon': Icons.coffee_rounded.codePoint},
    {'name': 'Travel', 'icon': Icons.flight_rounded.codePoint},
    {'name': 'Party', 'icon': Icons.celebration_rounded.codePoint},
    {'name': 'Gifts & Charity', 'icon': Icons.volunteer_activism_rounded.codePoint},
    {'name': 'Subscriptions', 'icon': Icons.autorenew_rounded.codePoint},
    {'name': 'Local Food', 'icon': Icons.local_pizza_rounded.codePoint},
    {'name': 'Jio Internet', 'icon': Icons.router_rounded.codePoint},
    {'name': 'WiFi', 'icon': Icons.wifi_rounded.codePoint},
    {'name': 'Other', 'icon': Icons.note_rounded.codePoint},
  ];

  static final List<Map<String, dynamic>> _defaultIncomeCategories = [
    {'name': 'Salary', 'icon': Icons.payments_rounded.codePoint},
    {'name': 'Freelance', 'icon': Icons.work_outline_rounded.codePoint},
    {'name': 'Business', 'icon': Icons.business_center_rounded.codePoint},
    {'name': 'Investment', 'icon': Icons.trending_up_rounded.codePoint},
    {'name': 'Interest', 'icon': Icons.savings_rounded.codePoint},
    {'name': 'Refund', 'icon': Icons.reply_rounded.codePoint},
    {'name': 'Gift', 'icon': Icons.card_giftcard_rounded.codePoint},
    {'name': 'Cashback', 'icon': Icons.currency_exchange_rounded.codePoint},
    {'name': 'Rental Income', 'icon': Icons.house_rounded.codePoint},
    {'name': 'Other', 'icon': Icons.note_rounded.codePoint},
  ];
}
