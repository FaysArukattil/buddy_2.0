// lib/services/app_init_helper.dart
import 'package:flutter/material.dart';
import 'notification_service.dart';
import 'transaction_sync_helper.dart';
import 'db_helper.dart';

class AppInitHelper {
  static bool _isInitialized = false;

  // Callback to notify UI when transactions are synced
  static Function()? onTransactionsSynced;

  /// Initialize app - call this in main.dart or app startup
  static Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⚠️ App already initialized');
      return;
    }

    debugPrint('🚀 ============ APP INITIALIZATION ============');

    try {
      // 1. Initialize database
      debugPrint('📊 Initializing database...');
      await DatabaseHelper.instance.initdb();
      debugPrint('✅ Database initialized');

      // 2. Sync transactions from native storage (added while app was closed)
      debugPrint('🔄 Syncing transactions from native storage...');
      final syncedCount = await TransactionSyncHelper.syncNativeTransactions();

      if (syncedCount > 0) {
        debugPrint('🎉 Synced $syncedCount transactions!');

        // Notify UI to refresh
        if (onTransactionsSynced != null) {
          onTransactionsSynced!();
        }
      } else {
        debugPrint('✅ No transactions to sync');
      }

      // 3. Start notification listener
      debugPrint('🎧 Starting notification listener...');
      await NotificationService.startListening((transactionMap, hash) async {
        debugPrint('🆕 New transaction detected in app: $hash');

        // Notify UI to refresh
        if (onTransactionsSynced != null) {
          onTransactionsSynced!();
        }
      });

      _isInitialized = true;
      debugPrint('✅ ============ APP INITIALIZED SUCCESSFULLY ============');
    } catch (e, stackTrace) {
      debugPrint('❌ Error during app initialization: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Manually trigger sync (useful for pull-to-refresh)
  static Future<int> syncNow() async {
    debugPrint('🔄 Manual sync triggered...');
    final count = await TransactionSyncHelper.performFullSync();

    if (count > 0 && onTransactionsSynced != null) {
      onTransactionsSynced!();
    }

    return count;
  }

  /// Check if there are unsynced transactions
  static Future<bool> hasUnsyncedTransactions() async {
    return await TransactionSyncHelper.needsSync();
  }

  /// Get unsynced transaction count
  static Future<int> getUnsyncedCount() async {
    return await TransactionSyncHelper.getUnsyncedCount();
  }

  /// Dispose resources
  static Future<void> dispose() async {
    await NotificationService.stopListening();
    _isInitialized = false;
    onTransactionsSynced = null;
  }
}
