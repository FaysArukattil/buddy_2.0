// lib/services/app_init_helper.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart';
import 'transaction_sync_helper.dart';
import 'firestore_service.dart';

class AppInitHelper {
  static bool _isInitialized = false;
  static String? _lastUid;

  // Callback to notify UI when transactions are synced
  static Function()? onTransactionsSynced;

  /// Initialize app - call this in main.dart or app startup
  static Future<void> initialize() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = currentUser?.uid;

    if (_isInitialized) {
      if (_lastUid == uid) {
        debugPrint('⚠️ App already initialized for user: $uid');
        return;
      } else {
        debugPrint('🔄 Auth UID changed from $_lastUid to $uid. Re-initializing...');
        await dispose();
      }
    }

    _lastUid = uid;

    debugPrint('🚀 ============ APP INITIALIZATION ============');

    try {
      // 1. Enable Firestore offline persistence
      debugPrint('📊 Enabling Firestore persistence...');
      await FirestoreService.enableOfflinePersistence();
      debugPrint('✅ Firestore persistence enabled');

      // 2. Seed default categories if user is logged in
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        debugPrint('🌱 Checking default categories...');
        try {
          await FirestoreService.instance.seedDefaultCategories();
        } catch (e) {
          debugPrint('⚠️ Failed to seed categories (non-critical): $e');
        }
      }

      // 3. Sync transactions from native storage
      debugPrint('🔄 Syncing transactions from native storage...');
      final syncedCount = await TransactionSyncHelper.syncNativeTransactions();

      if (syncedCount > 0) {
        debugPrint('🎉 Synced $syncedCount transactions!');
        if (onTransactionsSynced != null) {
          onTransactionsSynced!();
        }
      } else {
        debugPrint('✅ No transactions to sync');
      }

      // 4. Start notification listener ONLY if auto-detection is enabled
      //    and permission is already granted (don't request permission here
      //    to avoid ANR — user enables it explicitly via Settings)
      final isAutoDetectEnabled = await NotificationService.isAutoDetectionEnabled();
      if (isAutoDetectEnabled) {
        debugPrint('🎧 Starting notification listener...');
        await NotificationService.startListening((transactionMap, hash) async {
          debugPrint('🆕 New transaction detected in app: $hash');
          if (onTransactionsSynced != null) {
            onTransactionsSynced!();
          }
        });
      } else {
        debugPrint('ℹ️ Auto-detection disabled, skipping notification listener');
      }

      _isInitialized = true;
      debugPrint('✅ ============ APP INITIALIZED SUCCESSFULLY ============');
    } catch (e, stackTrace) {
      debugPrint('❌ Error during app initialization: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Re-initialize for a new/returning user (e.g., after login on a reinstalled app)
  /// This ensures the correct UID is used and data is properly loaded.
  static Future<void> reinitializeForUser() async {
    debugPrint('🔄 Re-initializing for current user...');
    _isInitialized = false;
    _lastUid = null;
    await initialize();
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

  /// Seed categories for current user and clean up duplicates
  static Future<void> seedCategoriesIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // First clean up any existing duplicates
        await FirestoreService.instance.removeDuplicateCategories();
        // Then seed any missing defaults
        await FirestoreService.instance.seedDefaultCategories();
      } catch (e) {
        debugPrint('⚠️ Failed to seed/clean categories: $e');
      }
    }
  }

  /// Dispose resources
  static Future<void> dispose() async {
    await NotificationService.stopListening();
    _isInitialized = false;
  }
}
