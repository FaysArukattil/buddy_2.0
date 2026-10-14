// lib/services/firestore_service.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:buddy/models/transaction.dart';
import 'package:buddy/models/category.dart' as cat;
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/icon_helper.dart';

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

  /// Get all transactions (one-time fetch), sorted by date DESC with offline cache fallback
  Future<List<TransactionModel>> getAllTransactions() async {
    try {
      final snapshot = await _txnCol
          .orderBy('date', descending: true)
          .get()
          .timeout(const Duration(seconds: 4));
      return TransactionModel.deduplicate(snapshot.docs
          .map((doc) => TransactionModel.fromFirestore(doc))
          .toList());
    } catch (_) {
      try {
        final snapshot = await _txnCol
            .orderBy('date', descending: true)
            .get(const GetOptions(source: Source.cache));
        return TransactionModel.deduplicate(snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc))
            .toList());
      } catch (e) {
        debugPrint('⚠️ FIRESTORE: getAllTransactions cache fallback error: $e');
        return [];
      }
    }
  }

  /// Get transactions as a real-time stream with automatic deduplication
  Stream<List<TransactionModel>> getTransactionsStream() {
    return _txnCol
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => TransactionModel.deduplicate(snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc))
            .toList()));
  }

  /// Get transactions for a specific month with offline cache fallback
  Future<List<TransactionModel>> getTransactionsForMonth(
    int year,
    int month,
  ) async {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 0, 23, 59, 59);

    try {
      final snapshot = await _txnCol
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .orderBy('date', descending: true)
          .get()
          .timeout(const Duration(seconds: 4));

      return TransactionModel.deduplicate(snapshot.docs
          .map((doc) => TransactionModel.fromFirestore(doc))
          .toList());
    } catch (_) {
      try {
        final snapshot = await _txnCol
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
            .orderBy('date', descending: true)
            .get(const GetOptions(source: Source.cache));

        return TransactionModel.deduplicate(snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc))
            .toList());
      } catch (e) {
        debugPrint('⚠️ FIRESTORE: getTransactionsForMonth cache fallback error: $e');
        return [];
      }
    }
  }

  /// Get transactions filtered by type with offline cache fallback
  Future<List<TransactionModel>> getTransactionsByType(String type) async {
    try {
      final snapshot = await _txnCol
          .where('type', isEqualTo: type.toLowerCase())
          .orderBy('date', descending: true)
          .get()
          .timeout(const Duration(seconds: 4));

      return TransactionModel.deduplicate(snapshot.docs
          .map((doc) => TransactionModel.fromFirestore(doc))
          .toList());
    } catch (_) {
      try {
        final snapshot = await _txnCol
            .where('type', isEqualTo: type.toLowerCase())
            .orderBy('date', descending: true)
            .get(const GetOptions(source: Source.cache));

        return TransactionModel.deduplicate(snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc))
            .toList());
      } catch (e) {
        debugPrint('⚠️ FIRESTORE: getTransactionsByType cache error: $e');
        return [];
      }
    }
  }

  /// Get a single transaction by ID with offline cache fallback
  Future<TransactionModel?> getTransactionById(String id) async {
    try {
      final doc = await _txnCol.doc(id).get().timeout(const Duration(seconds: 3));
      if (!doc.exists) return null;
      return TransactionModel.fromFirestore(doc);
    } catch (_) {
      try {
        final doc = await _txnCol.doc(id).get(const GetOptions(source: Source.cache));
        if (!doc.exists) return null;
        return TransactionModel.fromFirestore(doc);
      } catch (_) {
        return null;
      }
    }
  }

  /// Check for duplicate notification hash with offline cache fallback
  Future<bool> isDuplicateTransaction(String hash) async {
    try {
      final snapshot = await _txnCol
          .where('notificationHash', isEqualTo: hash)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 3));
      return snapshot.docs.isNotEmpty;
    } catch (_) {
      try {
        final snapshot = await _txnCol
            .where('notificationHash', isEqualTo: hash)
            .limit(1)
            .get(const GetOptions(source: Source.cache));
        return snapshot.docs.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  /// Find transactions with the same amount and type from the last N hours
  /// Uses a targeted Firestore query instead of loading all transactions
  Future<List<TransactionModel>> findSimilarTransactions({
    required double amount,
    required String type,
    int withinHours = 24,
  }) async {
    final cutoff = DateTime.now().subtract(Duration(hours: withinHours));
    try {
      final snapshot = await _txnCol
          .where('amount', isEqualTo: amount)
          .where('type', isEqualTo: type.toLowerCase())
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
          .get()
          .timeout(const Duration(seconds: 4));
      return snapshot.docs
          .map((doc) => TransactionModel.fromFirestore(doc))
          .toList();
    } catch (_) {
      try {
        final snapshot = await _txnCol
            .where('amount', isEqualTo: amount)
            .where('type', isEqualTo: type.toLowerCase())
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
            .get(const GetOptions(source: Source.cache));
        return snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc))
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

  /// Add auto-detected transaction with deduplication
  Future<String> addAutoDetectedTransaction(TransactionModel txn) async {
    final hash = txn.notificationHash?.trim();
    if (hash != null && hash.isNotEmpty) {
      final isDupe = await isDuplicateTransaction(hash);
      if (isDupe) {
        debugPrint('⚠️ FIRESTORE: Duplicate auto-detected transaction skipped ($hash)');
        return '';
      }
    }
    return addTransaction(txn);
  }

  /// One-time / background cleanup to remove duplicate transaction documents
  /// from Firestore for existing production users whose databases may have accumulated dupes.
  Future<int> cleanupDuplicateTransactions() async {
    try {
      final uid = _uid;
      if (uid == null) return 0;

      final snapshot = await _txnCol.orderBy('date', descending: true).get();
      if (snapshot.docs.length < 2) return 0;

      final seenHashes = <String, String>{}; // hash -> firstDocId
      final seenSignatures = <String, String>{}; // signature -> firstDocId
      final toDeleteDocIds = <String>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final docId = doc.id;
        final hash = (data['notificationHash'] as String?)?.trim();

        // 1. Check duplicate notificationHash
        if (hash != null && hash.isNotEmpty) {
          if (seenHashes.containsKey(hash)) {
            toDeleteDocIds.add(docId);
            continue;
          } else {
            seenHashes[hash] = docId;
          }
        }

        // 2. Check duplicate signature
        final amt = (data['amount'] as num?)?.toDouble() ?? 0.0;
        final type = (data['type'] as String? ?? '').toLowerCase().trim();
        final cat = (data['category'] as String? ?? '').toLowerCase().trim();
        final rawNote = (data['note'] as String?) ?? '';
        final clean = TransactionModel.cleanNoteText(rawNote) ?? '';
        final date = (data['date'] as Timestamp?)?.toDate() ?? DateTime.now();
        final minuteBucket = DateTime(date.year, date.month, date.day, date.hour, date.minute).millisecondsSinceEpoch;

        final signature = '${type}_${cat}_${amt.toStringAsFixed(2)}_${clean.toLowerCase()}_$minuteBucket';
        if (seenSignatures.containsKey(signature)) {
          toDeleteDocIds.add(docId);
        } else {
          seenSignatures[signature] = docId;
        }
      }

      if (toDeleteDocIds.isNotEmpty) {
        debugPrint('🧹 FIRESTORE: Cleaning up ${toDeleteDocIds.length} duplicate transactions from Firestore...');
        final batch = _db.batch();
        for (final id in toDeleteDocIds) {
          batch.delete(_txnCol.doc(id));
        }
        await batch.commit();
        debugPrint('✅ FIRESTORE: Removed ${toDeleteDocIds.length} duplicate transactions!');
        return toDeleteDocIds.length;
      }
      return 0;
    } catch (e) {
      debugPrint('⚠️ FIRESTORE: cleanupDuplicateTransactions error: $e');
      return 0;
    }
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

  /// In-memory category cache for instant UI rendering
  static List<cat.Category>? _cachedExpenseCategories;
  static List<cat.Category>? _cachedIncomeCategories;

  /// Clear the category cache when modified
  static void clearCategoryCache() {
    _cachedExpenseCategories = null;
    _cachedIncomeCategories = null;
  }

  /// Get categories instantly (returns memory cache or default preset, with 0ms latency)
  /// Automatically filters out Lending and Borrowing so they never conflict with regular transactions.
  static List<cat.Category> getInstantCategories(String type) {
    final isExpense = type.toLowerCase() == 'expense';
    final cached = isExpense ? _cachedExpenseCategories : _cachedIncomeCategories;
    if (cached != null && cached.isNotEmpty) {
      return cached
          .where((c) =>
              c.name.toLowerCase() != 'lending' &&
              c.name.toLowerCase() != 'borrowing')
          .toList();
    }
    return getDefaultCategories(type);
  }

  /// Get default categories without Lending or Borrowing
  static List<cat.Category> getDefaultCategories(String type) {
    final isExpense = type.toLowerCase() == 'expense';
    final list = isExpense ? _defaultExpenseCategories : _defaultIncomeCategories;
    return list
        .where((m) {
          final name = (m['name'] as String).toLowerCase();
          return name != 'lending' && name != 'borrowing';
        })
        .map((m) => cat.Category(
              id: m['name'] as String,
              name: m['name'] as String,
              type: type.toLowerCase(),
              icon: IconHelper.getIcon(m['icon']),
              color: AppColors.getCategoryColor(m['name'] as String),
              order: 0,
            ))
        .toList();
  }

  /// Get recent transactions with an optional limit with offline cache fallback
  Future<List<TransactionModel>> getRecentTransactions({int limit = 50}) async {
    try {
      final snapshot = await _txnCol
          .orderBy('date', descending: true)
          .limit(limit)
          .get()
          .timeout(const Duration(seconds: 4));
      return snapshot.docs
          .map((doc) => TransactionModel.fromFirestore(doc))
          .toList();
    } catch (_) {
      try {
        final snapshot = await _txnCol
            .orderBy('date', descending: true)
            .limit(limit)
            .get(const GetOptions(source: Source.cache));
        return snapshot.docs
            .map((doc) => TransactionModel.fromFirestore(doc))
            .toList();
      } catch (e) {
        debugPrint('⚠️ FIRESTORE: getRecentTransactions cache error: $e');
        return [];
      }
    }
  }

  // ── Categories ──

  /// Get all categories for a type (expense/income), deduplicated by name, with offline fallback
  Future<List<cat.Category>> getCategories(String type) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _catCol
          .where('type', isEqualTo: type.toLowerCase())
          .orderBy('order')
          .get()
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      try {
        snapshot = await _catCol
            .where('type', isEqualTo: type.toLowerCase())
            .orderBy('order')
            .get(const GetOptions(source: Source.cache));
      } catch (_) {
        return getDefaultCategories(type);
      }
    }

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
    if (categories.isEmpty) {
      return getDefaultCategories(type);
    }
    if (type.toLowerCase() == 'expense') {
      _cachedExpenseCategories = categories;
    } else {
      _cachedIncomeCategories = categories;
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
    clearCategoryCache();
    debugPrint('✅ FIRESTORE: Category "${category.name}" added');
    return doc.id;
  }

  /// Delete a category
  Future<void> deleteCategory(String id) async {
    await _catCol.doc(id).delete();
    clearCategoryCache();
    debugPrint('✅ FIRESTORE: Category $id deleted');
  }

  /// Check if default categories exist with offline fallback
  Future<bool> hasCategories() async {
    try {
      final snapshot = await _catCol.limit(1).get().timeout(const Duration(seconds: 3));
      return snapshot.docs.isNotEmpty;
    } catch (_) {
      try {
        final snapshot = await _catCol.limit(1).get(const GetOptions(source: Source.cache));
        return snapshot.docs.isNotEmpty;
      } catch (_) {
        return false;
      }
    }
  }

  /// Seed default categories (batch write for efficiency)
  Future<void> seedDefaultCategories() async {
    Set<String> existingNames = {};
    try {
      final snapshot = await _catCol.get().timeout(const Duration(seconds: 3));
      existingNames = snapshot.docs
          .map((doc) => doc.data()['name'] as String)
          .toSet();
    } catch (_) {
      try {
        final snapshot = await _catCol.get(const GetOptions(source: Source.cache));
        existingNames = snapshot.docs
            .map((doc) => doc.data()['name'] as String)
            .toSet();
      } catch (_) {
        // Continue with empty existing set
      }
    }

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
          'color': AppColors.getCategoryColor(entry['name'] as String).toARGB32(),
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
          'color': AppColors.getCategoryColor(entry['name'] as String).toARGB32(),
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
    {'name': 'Lending', 'icon': Icons.arrow_outward_rounded.codePoint},
    {'name': 'Other', 'icon': Icons.category_rounded.codePoint},
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
    {'name': 'Borrowing', 'icon': Icons.arrow_downward_rounded.codePoint},
    {'name': 'Other', 'icon': Icons.category_rounded.codePoint},
  ];
}
