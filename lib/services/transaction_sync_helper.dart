// lib/services/transaction_sync_helper.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/transaction.dart';
import 'db_helper.dart';

class TransactionSyncHelper {
  static const String _lastSyncKey = 'last_sync_timestamp';
  static const String _syncLockKey = 'sync_in_progress';

  /// Sync transactions from native Android SharedPreferences to Flutter database
  /// This runs when app opens to catch transactions added while app was closed
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

      debugPrint(
        '📊 SYNC: Found ${allKeys.length} total keys in SharedPreferences',
      );

      for (final key in allKeys) {
        // Look for transaction keys from native code (format: txn_HASH)
        if (key.startsWith('txn_')) {
          final jsonStr = prefs.getString(key);
          if (jsonStr != null) {
            try {
              final data = jsonDecode(jsonStr) as Map<String, dynamic>;
              final hash = key.substring(4); // Remove 'txn_' prefix

              debugPrint('   🔍 Found native transaction: $hash');
              debugPrint('      Amount: ${data['amount']}');
              debugPrint('      Type: ${data['type']}');

              // Check if this transaction already exists in database
              final exists = await DatabaseHelper.instance
                  .isDuplicateTransaction(hash);

              if (!exists) {
                // Parse date properly
                DateTime transactionDate;
                if (data['date'] is String) {
                  try {
                    transactionDate = DateTime.parse(data['date'] as String);
                  } catch (e) {
                    debugPrint(
                      '      ⚠️ Invalid date format, using current time',
                    );
                    transactionDate = DateTime.now();
                  }
                } else if (data['timestamp'] is num) {
                  transactionDate = DateTime.fromMillisecondsSinceEpoch(
                    (data['timestamp'] as num).toInt(),
                  );
                } else {
                  transactionDate = DateTime.now();
                }

                // Create TransactionModel
                final transaction = TransactionModel(
                  amount: (data['amount'] as num).toDouble(),
                  type: data['type'] as String? ?? 'expense',
                  date: transactionDate,
                  note:
                      data['note'] as String? ??
                      'Auto-detected from notification',
                  category: data['category'] as String? ?? 'Other',
                  icon: (data['icon'] as num?)?.toInt() ?? 0xe8f4,
                  autoDetected: true,
                  notificationSource: data['source'] as String?,
                  notificationHash: hash,
                );

                // Convert to map and insert
                final transactionMap = transaction.toMap();
                final id = await DatabaseHelper.instance.insertTransaction(
                  transactionMap,
                );

                if (id > 0) {
                  syncedCount++;
                  debugPrint('      ✅ SYNC: Synced to database (id=$id)');

                  // Optionally remove from SharedPreferences after successful sync
                  // Uncomment if you want to clean up:
                  // await prefs.remove(key);
                } else {
                  errorCount++;
                  debugPrint('      ⚠️ SYNC: Failed to sync (id=$id)');
                }
              } else {
                skippedCount++;
                debugPrint('      ⏭️ SYNC: Already exists in DB');

                // Clean up already synced transactions
                // await prefs.remove(key);
              }
            } catch (e, stackTrace) {
              errorCount++;
              debugPrint(
                '      ❌ SYNC: Error parsing transaction from key $key: $e',
              );
              debugPrint('      Stack trace: $stackTrace');
            }
          }
        }
      }

      // Update last sync timestamp
      await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setBool(_syncLockKey, false);

      debugPrint('✅ SYNC: Complete!');
      debugPrint('   📊 Synced: $syncedCount');
      debugPrint('   ⏭️ Skipped: $skippedCount');
      debugPrint('   ❌ Errors: $errorCount');

      if (syncedCount > 0) {
        debugPrint(
          '🎉 SYNC: Successfully added $syncedCount new transactions to database!',
        );
      }

      return syncedCount;
    } catch (e, stackTrace) {
      debugPrint('❌ SYNC: Error during sync: $e');
      debugPrint('Stack trace: $stackTrace');

      // Release lock on error
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

      int count = 0;

      for (final key in allKeys) {
        if (key.startsWith('txn_')) {
          final hash = key.substring(4);
          final exists = await DatabaseHelper.instance.isDuplicateTransaction(
            hash,
          );
          if (!exists) {
            count++;
          }
        }
      }

      debugPrint('📊 SYNC: Found $count unsynced transactions');
      return count;
    } catch (e) {
      debugPrint('❌ SYNC: Error counting unsynced: $e');
      return 0;
    }
  }

  /// Get all pending transactions (awaiting user confirmation)
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
              final hash = key.substring(8); // Remove 'pending_' prefix
              data['hash'] = hash;
              pending.add(data);
            } catch (e) {
              debugPrint('❌ SYNC: Error parsing pending transaction: $e');
            }
          }
        }
      }

      debugPrint('📋 SYNC: Found ${pending.length} pending transactions');
      return pending;
    } catch (e) {
      debugPrint('❌ SYNC: Error getting pending transactions: $e');
      return [];
    }
  }

  /// Clean up old synced transactions from native storage
  static Future<void> cleanupSyncedTransactions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      int cleaned = 0;

      for (final key in allKeys) {
        if (key.startsWith('txn_')) {
          final hash = key.substring(4);
          final exists = await DatabaseHelper.instance.isDuplicateTransaction(
            hash,
          );

          // If it exists in database, remove from SharedPreferences
          if (exists) {
            await prefs.remove(key);
            cleaned++;
          }
        }
      }

      debugPrint(
        '🧹 SYNC: Cleaned up $cleaned synced transactions from native storage',
      );
    } catch (e) {
      debugPrint('❌ SYNC: Error during cleanup: $e');
    }
  }

  /// Get last sync timestamp
  static Future<DateTime?> getLastSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_lastSyncKey);
      if (timestamp != null) {
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      return null;
    } catch (e) {
      debugPrint('❌ SYNC: Error getting last sync time: $e');
      return null;
    }
  }

  /// Full sync with cleanup
  static Future<int> performFullSync() async {
    debugPrint('🔄 SYNC: Starting full sync...');

    // Sync all transactions
    final syncedCount = await syncNativeTransactions();

    // Clean up synced transactions
    await cleanupSyncedTransactions();

    debugPrint('✅ SYNC: Full sync complete - $syncedCount new transactions');
    return syncedCount;
  }

  /// Check if sync is needed (useful for showing UI indicators)
  static Future<bool> needsSync() async {
    final unsyncedCount = await getUnsyncedCount();
    return unsyncedCount > 0;
  }
}
