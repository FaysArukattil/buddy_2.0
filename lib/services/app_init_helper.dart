// lib/services/app_init_helper.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'notification_service.dart';
import 'firestore_service.dart';
import 'preference_service.dart';
import 'currency_service.dart';

/// Handles app initialization and transaction syncing.
///
/// Architecture:
/// - On app startup, syncs transactions from SharedPreferences to Firestore.
/// - The native NotificationListenerService saves transactions to SharedPreferences
///   independently (even when the app is closed).
/// - This helper reads those saved transactions and syncs them on app open/resume.
class AppInitHelper {
  static bool _isInitialized = false;
  static bool _isSyncing = false;
  static String? _lastUid;

  // Callback to notify UI when transactions are synced
  static Function()? onTransactionsSynced;

  /// Initialize app — call this in main.dart or app startup
  static Future<void> initialize() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = currentUser?.uid;

    if (_isInitialized) {
      if (_lastUid == uid) {
        debugPrint('⚠️ App already initialized for user: $uid');
        return;
      } else {
        debugPrint('🔄 Auth UID changed from $_lastUid to $uid. Re-initializing...');
        _isInitialized = false;
      }
    }

    _lastUid = uid;

    debugPrint('🚀 ============ APP INITIALIZATION ============');

    try {
      // 0. Initialize app preferences (including debts on home setting & cloud sync)
      await PreferenceService.init();
      if (currentUser != null || uid != null) {
        await PreferenceService.syncFromFirestore();
        // Sync currency settings from Firestore (after auth)
        await CurrencyService.syncFromFirestore();
      }

      // 1. Enable Firestore offline persistence
      debugPrint('📊 Enabling Firestore persistence...');
      await FirestoreService.enableOfflinePersistence();
      debugPrint('✅ Firestore persistence enabled');

      // 2. Seed default categories & clean duplicate transactions if user is logged in
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        debugPrint('🌱 Checking default categories & duplicate cleanup...');
        try {
          await FirestoreService.instance.seedDefaultCategories();
          // Clean up any historical duplicate transactions for production users
          FirestoreService.instance.cleanupDuplicateTransactions().catchError((e) {
            debugPrint('⚠️ Non-critical duplicate cleanup error: $e');
            return 0;
          });
        } catch (e) {
          debugPrint('⚠️ Failed to seed categories (non-critical): $e');
        }
      }

      // 3. Sync transactions from SharedPreferences to Firestore
      //    These were saved by the native NotificationListenerService
      //    while the app was closed.
      debugPrint('🔄 Syncing saved transactions to Firestore...');
      final syncedCount = await NotificationService.syncSavedTransactions(
        onTransactionDetected: (transactionMap, hash) async {
          debugPrint('🆕 Transaction synced: $hash');
          if (onTransactionsSynced != null) {
            onTransactionsSynced!();
          }
        },
      );

      if (syncedCount > 0) {
        debugPrint('🎉 Synced $syncedCount transaction(s)!');
        if (onTransactionsSynced != null) {
          onTransactionsSynced!();
        }
      } else {
        debugPrint('✅ No transactions to sync');
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

  /// Manually trigger sync (useful for pull-to-refresh or on app resume)
  static Future<int> syncNow() async {
    if (_isSyncing) {
      debugPrint('⏳ SYNC: Sync already in progress, skipping concurrent trigger.');
      return 0;
    }
    _isSyncing = true;
    try {
      debugPrint('🔄 Manual sync triggered...');

      // Sync from SharedPreferences to Firestore
      final count = await NotificationService.syncSavedTransactions(
        onTransactionDetected: (transactionMap, hash) async {
          debugPrint('🆕 Transaction synced: $hash');
        },
      );

      // Clean up already-synced entries
      await NotificationService.cleanupSyncedTransactions();

      if (count > 0 && onTransactionsSynced != null) {
        onTransactionsSynced!();
      }

      return count;
    } finally {
      _isSyncing = false;
    }
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

  /// Dispose resources — lightweight since there's no background service to stop
  static Future<void> dispose() async {
    _isInitialized = false;
  }
}
