// lib/services/notification_service.dart
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction.dart';
import 'firestore_service.dart';

typedef OnTransactionDetected =
    Future<void> Function(Map<String, Object?> transactionMap, String hash);

/// Simplified notification service.
///
/// Architecture:
/// - The native NotificationListenerService (OS-managed) handles notification
///   filtering, parsing, and saving transactions to SharedPreferences.
/// - This Flutter service only handles:
///   1. Checking/requesting notification listener permission
///   2. Checking if auto-detection is enabled
///   3. Syncing transactions from SharedPreferences to Firestore on app open
///
/// No background services are started or stopped from Flutter.
class NotificationService {
  static bool get isSupportedPlatform => !kIsWeb && Platform.isAndroid;

  // ── Permission Management ──

  /// Check if notification listener permission is granted
  static Future<bool> isNotificationAccessGranted() async {
    if (!isSupportedPlatform) return false;
    try {
      return await NotificationListenerService.isPermissionGranted();
    } catch (e) {
      debugPrint('⚠️ NOTIFICATION: Error checking permission: $e');
      return false;
    }
  }

  /// Open system settings to grant notification listener access
  static Future<bool> requestNotificationAccess() async {
    if (!isSupportedPlatform) {
      debugPrint('⚠️ NOTIFICATION: Platform not supported');
      return false;
    }
    final isGranted = await NotificationListenerService.isPermissionGranted();
    if (isGranted) {
      debugPrint('✅ NOTIFICATION: Permission already granted');
      return true;
    }
    debugPrint('⚠️ NOTIFICATION: Opening settings to grant permission');
    await NotificationListenerService.requestPermission();
    return false;
  }

  // ── Auto-Detection Settings ──

  static Future<bool> isAutoDetectionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('auto_detect_transactions') ?? true;
  }

  static Future<void> setAutoDetectionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_detect_transactions', enabled);
    debugPrint('🔔 NOTIFICATION: Auto-detection ${enabled ? "enabled" : "disabled"}');
  }

  // ── Transaction Sync (SharedPreferences → Firestore) ──

  /// Sync all transactions saved by the native listener to Firestore.
  /// Call this when the app opens or resumes.
  static Future<int> syncSavedTransactions({
    OnTransactionDetected? onTransactionDetected,
  }) async {
    if (!isSupportedPlatform) return 0;

    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys().toList();
    final firestore = FirestoreService.instance;
    int syncedCount = 0;

    for (final key in allKeys) {
      if (!key.startsWith('txn_')) continue;

      final jsonStr = prefs.getString(key);
      if (jsonStr == null) continue;

      try {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        final hash = key.substring(4); // Remove 'txn_' prefix

        // Skip if already in Firestore
        final exists = await firestore.isDuplicateTransaction(hash);
        if (exists) {
          // Already synced — clean up SharedPreferences
          await prefs.remove(key);
          continue;
        }

        // Parse date
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
          note: data['note'] as String? ?? 'Auto-detected from notification',
          category: data['category'] as String? ?? 'Other',
          icon: (data['icon'] as num?)?.toInt() ?? 0xe8f4,
          autoDetected: true,
          notificationSource: data['source'] as String?,
          notificationHash: hash,
        );

        final docId = await firestore.addTransaction(transaction);

        if (docId.isNotEmpty) {
          syncedCount++;
          debugPrint('✅ SYNC: Transaction synced to Firestore (hash=$hash, id=$docId)');

          // Clean up from SharedPreferences after successful sync
          await prefs.remove(key);

          // Notify callback if provided
          if (onTransactionDetected != null) {
            await onTransactionDetected(transaction.toMap(), hash);
          }
        }
      } catch (e) {
        debugPrint('❌ SYNC: Error syncing transaction $key: $e');
      }
    }

    if (syncedCount > 0) {
      debugPrint('✅ SYNC: Synced $syncedCount transaction(s) to Firestore');
    }

    return syncedCount;
  }

  /// Clean up transactions in SharedPreferences that are already in Firestore
  static Future<void> cleanupSyncedTransactions() async {
    if (!isSupportedPlatform) return;

    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys().toList();
    final firestore = FirestoreService.instance;
    int cleaned = 0;

    for (final key in allKeys) {
      if (!key.startsWith('txn_')) continue;

      final hash = key.substring(4);
      final exists = await firestore.isDuplicateTransaction(hash);
      if (exists) {
        await prefs.remove(key);
        cleaned++;
      }
    }

    if (cleaned > 0) {
      debugPrint('🧹 SYNC: Cleaned $cleaned already-synced transactions');
    }
  }
}
