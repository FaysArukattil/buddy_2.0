import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'firestore_service.dart';
import '../models/transaction.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: initializationSettingsDarwin,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationTapped,
    );

    _isInitialized = true;
    debugPrint('✅ NOTIFICATION_HELPER: Initialized');
  }

  /// Request notification permission (Android 13+)
  static Future<bool> requestNotificationPermission() async {
    debugPrint('🔔 Requesting notification permission...');

    final status = await Permission.notification.status;

    if (status.isGranted) {
      debugPrint('✅ Notification permission already granted');
      return true;
    }

    if (status.isDenied) {
      final result = await Permission.notification.request();
      if (result.isGranted) {
        debugPrint('✅ Notification permission granted');
        return true;
      } else {
        debugPrint('❌ Notification permission denied');
        return false;
      }
    }

    if (status.isPermanentlyDenied) {
      debugPrint(
        '⚠️ Notification permission permanently denied - opening settings',
      );
      await openAppSettings();
      return false;
    }

    return false;
  }

  // Background notification handler (must be top-level function)
  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTapped(NotificationResponse response) {
    debugPrint('📱 Background notification tapped: ${response.actionId}');
    _handleNotificationAction(response);
  }

  static void _onNotificationTapped(NotificationResponse response) async {
    debugPrint(
      '📱 Notification tapped: payload=${response.payload}, action=${response.actionId}, input=${response.input}',
    );
    await _handleNotificationAction(response);
  }

  static Future<void> _handleNotificationAction(
    NotificationResponse response,
  ) async {
    if (response.payload == null) {
      debugPrint('⚠️ No payload in notification response');
      return;
    }

    final hash = response.payload!;
    debugPrint('🔑 Processing action for hash: $hash');
    debugPrint('🎯 Action ID: ${response.actionId ?? "NULL - Body Tapped"}');

    try {
      // Get pending transaction from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('pending_$hash');

      if (jsonStr == null) {
        debugPrint('⚠️ No pending transaction found for hash: $hash');
        return;
      }

      final pendingData = jsonDecode(jsonStr) as Map<String, dynamic>;

      debugPrint(
        '📦 Found pending data: ${pendingData['amount']} ${pendingData['type']}',
      );

      // FIX: Check both 'yes' and 'action_yes'
      if (response.actionId == 'action_yes' ||
          response.actionId == 'yes' ||
          (response.actionId == null && response.input == 'yes')) {
        // User confirmed
        debugPrint('✅ User clicked YES - Adding transaction');

        DateTime transactionDate;
        if (pendingData['date'] is String) {
          transactionDate = DateTime.parse(pendingData['date'] as String);
        } else if (pendingData['timestamp'] is num) {
          transactionDate = DateTime.fromMillisecondsSinceEpoch(
            (pendingData['timestamp'] as num).toInt(),
          );
        } else {
          transactionDate = DateTime.now();
        }

        final txn = TransactionModel(
          amount: (pendingData['amount'] as num).toDouble(),
          type: pendingData['type'] as String? ?? 'expense',
          date: transactionDate,
          note: pendingData['note'] as String?,
          category: pendingData['category'] as String? ?? 'Other',
          icon: (pendingData['icon'] as num?)?.toInt() ?? 0xe8f4,
          autoDetected: true,
          notificationSource: pendingData['source'] as String?,
          notificationHash: hash,
        );

        final docId = await FirestoreService.instance.addTransaction(txn);

        if (docId.isNotEmpty) {
          debugPrint('✅ Transaction successfully added to Firestore (id=$docId)');

          await showTransactionAdded(
            amount: txn.amount,
            type: txn.type,
            category: txn.category,
          );
        } else {
          debugPrint('❌ Failed to add transaction to Firestore');
        }

        await prefs.remove('pending_$hash');
        await _notifications.cancel(hash.hashCode);
      } else if (response.actionId == 'action_no' ||
          response.actionId == 'no' ||
          (response.actionId == null && response.input == 'no')) {
        // User rejected
        debugPrint('❌ User clicked NO - Ignoring transaction');

        await prefs.remove('pending_$hash');
        await _notifications.cancel(hash.hashCode);

        debugPrint('✅ Transaction ignored and notification dismissed');
      } else {
        // Body tapped
        debugPrint(
          'ℹ️ Notification body tapped - Keeping notification for user choice',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error handling notification action: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Show duplicate confirmation notification with Yes/No buttons
  static Future<void> showDuplicateConfirmation({
    required String transactionHash,
    required double amount,
    required String type,
    required String category,
    int similarCount = 1,
  }) async {
    await initialize();

    const channelId = 'duplicate_confirmations';
    const channelName = 'Transaction Confirmations';
    const channelDesc = 'Notifications to confirm duplicate transactions';

    // FIX: Use proper action IDs with 'action_' prefix
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      ongoing: false,
      autoCancel: false,
      enableVibration: true,
      playSound: true,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
      // Use contextual actions instead of regular actions
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'action_yes', // Changed from 'yes' to 'action_yes'
          '✅ Yes, Add',
          titleColor: const Color(0xFF4CAF50),
          showsUserInterface: true, // Changed to true
          cancelNotification: true, // Auto-dismiss after tap
        ),
        AndroidNotificationAction(
          'action_no', // Changed from 'no' to 'action_no'
          '❌ No, Ignore',
          titleColor: const Color(0xFFf44336),
          showsUserInterface: true, // Changed to true
          cancelNotification: true, // Auto-dismiss after tap
        ),
      ],
      styleInformation: BigTextStyleInformation(
        'Found $similarCount similar transaction(s) in last 24 hours.\n\nTap "Yes" to add this transaction or "No" to ignore it.',
        contentTitle: '⚠️ Possible Duplicate',
        summaryText: '$type: ₹$amount',
      ),
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    final typeIcon = type == 'expense' ? '💸' : '💰';
    final title = '⚠️ Duplicate Transaction?';
    final body = '$typeIcon ₹$amount ($category) - Found $similarCount similar';

    await _notifications.show(
      transactionHash.hashCode,
      title,
      body,
      notificationDetails,
      payload: transactionHash,
    );

    debugPrint(
      '🔔 Shown duplicate confirmation for ₹$amount (hash: ${transactionHash.hashCode})',
    );
  }

  /// Show transaction added notification
  static Future<void> showTransactionAdded({
    required double amount,
    required String type,
    required String category,
  }) async {
    await initialize();

    const channelId = 'transaction_added';
    const channelName = 'Transaction Added';
    const channelDesc = 'Notifications when transactions are auto-detected';

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: true,
      enableVibration: true,
      autoCancel: true,
      styleInformation: BigTextStyleInformation(
        'Your transaction has been automatically added to your expense tracker.',
        contentTitle: '✅ Transaction Added',
        summaryText: '$type: ₹$amount',
      ),
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    final typeIcon = type == 'expense' ? '💸' : '💰';
    final title = '✅ Transaction Added';
    final body = '$typeIcon ₹$amount - $category';

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      notificationDetails,
    );

    debugPrint('🔔 Shown success notification for ₹$amount');
  }

  /// Cancel notification
  static Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }
}
