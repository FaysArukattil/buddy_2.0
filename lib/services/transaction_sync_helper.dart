// lib/services/transaction_sync_helper.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/transaction.dart';
import 'firestore_service.dart';

class TransactionSyncHelper {
  static const String _lastSyncKey = 'last_sync_timestamp';
  static const String _syncLockKey = 'sync_in_progress';

  /// Sync transactions from native Android SharedPreferences to Firestore
  static Future<int> syncNativeTransactions() async {
    debugPrint('🔄 SYNC: Starting transaction sync from native storage...');

    try {
      final prefs = await SharedPreferences.getInstance();

      // Prevent concurrent syncs
      final syncInProgress = prefs.getBool(_syncLockKey) ?? false;
      if (syncInProgress) {
        debugPrint('⚠️ SYNC: Sync already in progress, skipping');
        return 0;
      }

      await prefs.setBool(_syncLockKey, true);

      final allKeys = prefs.getKeys();
      int syncedCount = 0;
      int skippedCount = 0;
      int errorCount = 0;

      final firestore = FirestoreService.instance;

      for (final key in allKeys) {
        if (key.startsWith('txn_')) {
          final jsonStr = prefs.getString(key);
          if (jsonStr != null) {
            try {
              final data = jsonDecode(jsonStr) as Map<String, dynamic>;
              final hash = key.substring(4);

              // Check if this transaction already exists in Firestore
              final exists = await firestore.isDuplicateTransaction(hash);

              if (!exists) {
                DateTime transactionDate;
                if (data['date'] is String) {
                  try {
                    transactionDate = DateTime.parse(data['date'] as String);
                  } catch (e) {
                    transactionDate = DateTime.now();
                  }
                } else if (data['timestamp'] is num) {
                  transactionDate = DateTime.fromMillisecondsSinceEpoch(
                    (data['timestamp'] as num).toInt(),
                  );
                } else {
                  transactionDate = DateTime.now();
                }

                final transaction = TransactionModel(
                  amount: (data['amount'] as num).toDouble(),
                  type: data['type'] as String? ?? 'expense',
                  date: transactionDate,
                  note: data['note'] as String? ??
                      'Auto-detected from notification',
                  category: data['category'] as String? ?? 'Other',
                  icon: (data['icon'] as num?)?.toInt() ?? 0xe8f4,
                  autoDetected: true,
                  notificationSource: data['source'] as String?,
                  notificationHash: hash,
                );

                final id = await firestore.addTransaction(transaction);

                if (id.isNotEmpty) {
                  syncedCount++;
                  debugPrint('      ✅ SYNC: Synced to Firestore (id=$id)');
                } else {
                  errorCount++;
                }
              } else {
                skippedCount++;
              }
            } catch (e) {
              errorCount++;
              debugPrint('      ❌ SYNC: Error parsing transaction: $e');
            }
          }
        }
      }

      // Update last sync timestamp
      await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setBool(_syncLockKey, false);

      debugPrint('✅ SYNC: Complete! Synced: $syncedCount, Skipped: $skippedCount, Errors: $errorCount');
      return syncedCount;
    } catch (e) {
      debugPrint('❌ SYNC: Error during sync: $e');

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_syncLockKey, false);
      } catch (_) {}

      return 0;
    }
  }

  /// Get count of native transactions not yet synced
  static Future<int> getUnsyncedCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final firestore = FirestoreService.instance;

      int count = 0;
      for (final key in allKeys) {
        if (key.startsWith('txn_')) {
          final hash = key.substring(4);
          final exists = await firestore.isDuplicateTransaction(hash);
          if (!exists) count++;
        }
      }
      return count;
    } catch (e) {
      debugPrint('❌ SYNC: Error counting unsynced: $e');
      return 0;
    }
  }

  /// Get all pending transactions
  static Future<List<Map<String, dynamic>>> getPendingTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final List<Map<String, dynamic>> pending = [];

      for (final key in allKeys) {
        if (key.startsWith('pending_')) {
          final jsonStr = prefs.getString(key);
          if (jsonStr != null) {
            try {
              final data = jsonDecode(jsonStr) as Map<String, dynamic>;
              data['hash'] = key.substring(8);
              pending.add(data);
            } catch (e) {
              debugPrint('❌ SYNC: Error parsing pending transaction: $e');
            }
          }
        }
      }
      return pending;
    } catch (e) {
      return [];
    }
  }

  /// Clean up synced transactions from native storage
  static Future<void> cleanupSyncedTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final firestore = FirestoreService.instance;
      int cleaned = 0;

      for (final key in allKeys) {
        if (key.startsWith('txn_')) {
          final hash = key.substring(4);
          final exists = await firestore.isDuplicateTransaction(hash);
          if (exists) {
            await prefs.remove(key);
            cleaned++;
          }
        }
      }
      debugPrint('🧹 SYNC: Cleaned up $cleaned synced transactions');
    } catch (e) {
      debugPrint('❌ SYNC: Error during cleanup: $e');
    }
  }

  /// Full sync with cleanup
  static Future<int> performFullSync() async {
    final syncedCount = await syncNativeTransactions();
    await cleanupSyncedTransactions();
    return syncedCount;
  }

  /// Check if sync is needed
  static Future<bool> needsSync() async {
    final unsyncedCount = await getUnsyncedCount();
    return unsyncedCount > 0;
  }
}
