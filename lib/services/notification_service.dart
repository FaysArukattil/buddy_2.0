// lib/services/notification_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transaction.dart';
import 'firestore_service.dart';
import 'notification_helper.dart';

typedef OnTransactionDetected =
    Future<void> Function(Map<String, Object?> transactionMap, String hash);

class NotificationService {
  static const MethodChannel _nativeChannel = MethodChannel(
    'notification_channel',
  );

  static StreamSubscription? _notificationSubscription;
  static bool _isListening = false;
  static OnTransactionDetected? _onTransactionDetected;

  static final Set<String> _recentlyProcessed = {};

  static final RegExp _debitRegex = RegExp(
    r'\b(debited|spent|purchase|paid|withdrawn|debit|payment|sent|transferred|transfer to|paid to)\b',
    caseSensitive: false,
  );

  static final RegExp _creditRegex = RegExp(
    r'\b(credited|received|deposit|income|credit|refund|cashback|received from|got)\b',
    caseSensitive: false,
  );

  static final RegExp _amountRegex = RegExp(
    r'(?:Rs\.?\s?|INR\s?|₹\s?)([0-9,]+\.?[0-9]*)|([0-9,]+\.?[0-9]*)\s?(?:Rs\.?|INR|₹)|(?:amount|amt|sum)[\s:]*(?:Rs\.?\s?|INR\s?|₹\s?)?([0-9,]+\.?[0-9]*)',
    caseSensitive: false,
  );

  static final List<String> _financialApps = [
    'com.google.android.apps.messaging',
    'com.android.messaging',
    'com.samsung.android.messaging',
    'com.android.mms',
    'com.phonepe.app',
    'com.google.android.apps.nbu.paisa.user',
    'in.org.npci.upiapp',
    'net.one97.paytm',
    'com.amazon.mShop.android.shopping',
    'in.amazon.mShop.android.shopping',
    'com.mobikwik_new',
    'com.freecharge.android',
    'com.sbi.SBIFreedomPlus',
    'com.icicibank.mobile.iciciappathon',
    'com.hdfcbank.payzapp',
    'com.axisbank.mobile',
    'com.kotakbank.mobile',
    'com.indusind.mobile',
    'com.whatsapp',
    'com.whatsapp.w4b',
    'com.truecaller',
  ];

  static bool get isSupportedPlatform => !kIsWeb && Platform.isAndroid;

  static Future<bool> requestNotificationAccess() async {
    if (!isSupportedPlatform) {
      debugPrint('⚠️ NOTIFICATION: Platform not supported for notification access');
      return false;
    }
    debugPrint('🔔 NOTIFICATION: Requesting notification access...');
    final isGranted = await NotificationListenerService.isPermissionGranted();
    if (isGranted) {
      debugPrint('✅ NOTIFICATION: Permission already granted');
      await startBackgroundService();
      return true;
    }
    debugPrint('⚠️ NOTIFICATION: Opening settings to grant permission');
    await NotificationListenerService.requestPermission();
    return false;
  }

  static Future<void> startBackgroundService() async {
    if (!isSupportedPlatform) return;
    try {
      debugPrint('🚀 Starting background notification service...');
      await _nativeChannel.invokeMethod('startNotificationService');
      debugPrint('✅ Background service started');
    } catch (e) {
      debugPrint('❌ Error starting background service: $e');
    }
  }

  static Future<void> stopBackgroundService() async {
    if (!isSupportedPlatform) return;
    try {
      debugPrint('🛑 Stopping background notification service...');
      await _nativeChannel.invokeMethod('stopNotificationService');
      debugPrint('✅ Background service stopped');
    } catch (e) {
      debugPrint('❌ Error stopping background service: $e');
    }
  }

  static Future<void> requestQueuedNotifications() async {
    if (!isSupportedPlatform) return;
    try {
      debugPrint('📬 Requesting queued notifications...');
      await _nativeChannel.invokeMethod('getQueuedNotifications');
    } catch (e) {
      debugPrint('❌ Error requesting queued notifications: $e');
    }
  }

  // NEW: Request sync of unsynced transactions from native code
  static Future<void> syncUnsyncedTransactions() async {
    if (!isSupportedPlatform) return;
    try {
      debugPrint(
        '🔄 NOTIFICATION: Requesting sync of unsynced transactions...',
      );
      await _nativeChannel.invokeMethod('syncUnsyncedTransactions');
      debugPrint('✅ NOTIFICATION: Sync request sent');
    } catch (e) {
      debugPrint('❌ NOTIFICATION: Error requesting sync: $e');
    }
  }

  static Future<bool> isAutoDetectionEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('auto_detect_transactions') ?? true;
  }

  static Future<void> setAutoDetectionEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_detect_transactions', enabled);
    if (enabled && !_isListening) {
      await startListening();
      await startBackgroundService();
    } else if (!enabled && _isListening) {
      await stopListening();
      await stopBackgroundService();
    }
  }

  static Future<void> startListening([
    OnTransactionDetected? onTransactionDetected,
  ]) async {
    if (!isSupportedPlatform) {
      debugPrint('⚠️ NOTIFICATION: Platform not supported for listener');
      return;
    }
    if (_isListening) {
      debugPrint('⚠️ NOTIFICATION: Already listening');
      return;
    }

    _onTransactionDetected = onTransactionDetected;

    final isEnabled = await isAutoDetectionEnabled();
    if (!isEnabled) {
      debugPrint('⚠️ NOTIFICATION: Auto-detection disabled');
      return;
    }

    final isGranted = await NotificationListenerService.isPermissionGranted();
    debugPrint('🔍 NOTIFICATION: Permission status: $isGranted');
    if (!isGranted) {
      debugPrint(
        '❌ NOTIFICATION: Permission not granted - enable in Settings → Notification Access',
      );
      return;
    }

    debugPrint('🎧 NOTIFICATION: Starting notification listener...');

    await startBackgroundService();
    await requestQueuedNotifications();

    // NEW: Request sync of any unsynced transactions
    await syncUnsyncedTransactions();

    try {
      _notificationSubscription = NotificationListenerService
          .notificationsStream
          .listen(
            (event) async {
              try {
                final result = await _handleNotification(event);
                if (result != null && _onTransactionDetected != null) {
                  final transactionMap =
                      result['transactionMap'] as Map<String, Object?>;
                  final hash = result['hash'] as String;
                  await _onTransactionDetected!(transactionMap, hash);
                }
              } catch (e) {
                debugPrint('❌ NOTIFICATION: Error processing stream event: $e');
              }
            },
            onError: (error) {
              debugPrint('❌ NOTIFICATION: Stream error: $error');
            },
            onDone: () {
              debugPrint('⚠️ NOTIFICATION: Stream closed');
              _isListening = false;
            },
          );
    } catch (e) {
      debugPrint(
        '⚠️ NOTIFICATION: Could not attach to notificationsStream: $e',
      );
    }

    _nativeChannel.setMethodCallHandler((call) async {
      try {
        debugPrint('📨 MethodChannel.call.method=${call.method}');

        if (call.method == 'onTransactionDetected') {
          // CRITICAL: Direct database insert from native code
          final args = call.arguments as Map;

          debugPrint('💾 FLUTTER: Received transaction from native code');
          debugPrint('   Raw data: $args');

          try {
            final hash = args['hash'] as String;

            final exists = await FirestoreService.instance.isDuplicateTransaction(
              hash,
            );
            if (exists) {
              debugPrint(
                '⚠️ Transaction already exists in database (hash: $hash)',
              );
              return;
            }

            DateTime transactionDate;
            if (args['date'] is String) {
              transactionDate = DateTime.parse(args['date'] as String);
            } else if (args['timestamp'] is num) {
              transactionDate = DateTime.fromMillisecondsSinceEpoch(
                (args['timestamp'] as num).toInt(),
              );
            } else {
              transactionDate = DateTime.now();
            }

            final transaction = TransactionModel(
              amount: (args['amount'] as num).toDouble(),
              type: args['type'] as String,
              date: transactionDate,
              note:
                  args['note'] as String? ?? 'Auto-detected from notification',
              category: args['category'] as String,
              icon: (args['icon'] as num).toInt(),
              autoDetected: true,
              notificationSource: args['source'] as String?,
              notificationHash: hash,
            );

            debugPrint('✅ FLUTTER: Created TransactionModel:');
            debugPrint('   Amount: ₹${transaction.amount}');
            debugPrint('   Type: ${transaction.type}');
            debugPrint('   Date: ${transaction.date}');
            debugPrint('   Category: ${transaction.category}');
            debugPrint('   Auto-detected: ${transaction.autoDetected}');

            final transactionMap = transaction.toMap();
            final docId = await FirestoreService.instance.addTransaction(transaction);

            if (docId.isNotEmpty) {
              debugPrint(
                '✅✅✅ FLUTTER: Transaction SUCCESSFULLY saved to database (id=$docId)',
              );

              if (_onTransactionDetected != null) {
                await _onTransactionDetected!(transactionMap, hash);
              }
            } else {
              debugPrint(
                '❌ FLUTTER: Failed to save transaction',
              );
            }
          } catch (e, stackTrace) {
            debugPrint('❌ FLUTTER: Error saving transaction: $e');
            debugPrint('Stack trace: $stackTrace');
          }
        } else if (call.method == 'onNotificationReceived' ||
            call.method == 'notification') {
          final args = call.arguments;
          Map<String, Object?> mapArgs = {};

          if (args is Map) {
            args.forEach((k, v) {
              mapArgs[k.toString()] = v;
            });
          }

          debugPrint('📨 MethodChannel notification received: $mapArgs');

          final event = {
            'package': mapArgs['package'] ?? mapArgs['packageName'] ?? '',
            'title': mapArgs['title'] ?? '',
            'content':
                mapArgs['content'] ?? mapArgs['text'] ?? mapArgs['body'] ?? '',
          };

          final result = await _handleNotification(event);
          if (result != null && _onTransactionDetected != null) {
            final transactionMap =
                result['transactionMap'] as Map<String, Object?>;
            final hash = result['hash'] as String;
            await _onTransactionDetected!(transactionMap, hash);
          }
        } else if (call.method == 'onDuplicateResponse') {
          final args = call.arguments as Map;
          final hash = args['hash'] as String;
          final shouldAdd = args['shouldAdd'] as bool;

          debugPrint('📨 Duplicate response: hash=$hash, shouldAdd=$shouldAdd');

          if (shouldAdd) {
            final prefs = await SharedPreferences.getInstance();
            final jsonStr = prefs.getString('pending_$hash');

            if (jsonStr != null) {
              final pendingData = jsonDecode(jsonStr) as Map<String, dynamic>;
              debugPrint('📦 Found pending transaction data: $pendingData');

              final exists = await FirestoreService.instance
                  .isDuplicateTransaction(hash);
              if (exists) {
                debugPrint('⚠️ Transaction already exists, skipping');
                await prefs.remove('pending_$hash');
                return;
              }

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

              final transaction = TransactionModel(
                amount: (pendingData['amount'] as num).toDouble(),
                type: pendingData['type'] as String,
                date: transactionDate,
                note:
                    pendingData['note'] as String? ??
                    'Auto-detected from notification',
                category: pendingData['category'] as String,
                icon: (pendingData['icon'] as num).toInt(),
                autoDetected: true,
                notificationSource: pendingData['source'] as String?,
                notificationHash: hash,
              );

              debugPrint('✅ Created TransactionModel from pending:');
              debugPrint('   Amount: ₹${transaction.amount}');
              debugPrint('   Type: ${transaction.type}');
              debugPrint('   Date: ${transaction.date}');

              final transactionMap = transaction.toMap();
              final docId = await FirestoreService.instance.addTransaction(transaction);

              if (docId.isNotEmpty) {
                debugPrint(
                  '✅✅✅ DUPLICATE CONFIRMED: Transaction saved (id=$docId)',
                );

                await NotificationHelper.showTransactionAdded(
                  amount: transaction.amount,
                  type: transaction.type,
                  category: transaction.category,
                );

                if (_onTransactionDetected != null) {
                  await _onTransactionDetected!(transactionMap, hash);
                }
              } else {
                debugPrint('❌ Failed to save confirmed duplicate transaction');
              }

              await prefs.remove('pending_$hash');
            } else {
              debugPrint('⚠️ No pending transaction found for hash: $hash');
            }
          } else {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('pending_$hash');
            debugPrint(
              '❌ User declined duplicate - removed pending transaction',
            );
          }
        }
      } catch (e, stackTrace) {
        debugPrint('❌ NOTIFICATION: Error handling MethodChannel call: $e');
        debugPrint('Stack trace: $stackTrace');
      }
    });

    _isListening = true;
    debugPrint(
      '✅ NOTIFICATION: Listener started with proper TransactionModel formatting',
    );
  }

  static Future<void> stopListening() async {
    if (!isSupportedPlatform) return;
    if (!_isListening) return;
    try {
      await _notificationSubscription?.cancel();
      _notificationSubscription = null;
      _nativeChannel.setMethodCallHandler(null);
      await stopBackgroundService();
      _isListening = false;
      _onTransactionDetected = null;
      debugPrint('🛑 NOTIFICATION: Listener stopped');
    } catch (e) {
      debugPrint('❌ NOTIFICATION: Error stopping listener: $e');
    }
  }

  static Future<Map<String, Object?>?> _handleNotification(
    dynamic event,
  ) async {
    try {
      String packageName = '';
      String title = '';
      String content = '';

      if (event is Map) {
        packageName =
            (event['package'] ?? event['packageName'] ?? event['pkg'])
                ?.toString() ??
            '';
        title = (event['title'] ?? event['t'] ?? '')?.toString() ?? '';
        content =
            (event['content'] ?? event['text'] ?? event['body'] ?? '')
                ?.toString() ??
            '';
      } else {
        try {
          final pn = event.packageName;
          final tt = event.title;
          final cc = event.content ?? event.text ?? event.bigText;
          packageName = pn?.toString() ?? '';
          title = tt?.toString() ?? '';
          content = cc?.toString() ?? '';
        } catch (_) {
          final s = event?.toString() ?? '';
          content = s;
        }
      }

      debugPrint('📬 NOTIFICATION: $packageName | $title | $content');

      final notificationKey = '$packageName|$title|$content';
      if (_recentlyProcessed.contains(notificationKey)) {
        debugPrint(
          '   🚫 Skipping - same notification already processed recently',
        );
        return null;
      }

      if (packageName == 'com.example.buddy' ||
          packageName.contains('example.buddy')) {
        debugPrint('   🚫 Skipping own app notification');
        return null;
      }

      final lowerTitle = title.toLowerCase();
      final lowerContent = content.toLowerCase();

      if (lowerTitle.contains('duplicate') ||
          lowerContent.contains('duplicate') ||
          lowerTitle.contains('transaction added') ||
          lowerContent.contains('transaction added') ||
          lowerTitle.contains('possible duplicate') ||
          lowerContent.contains('similar transaction') ||
          lowerTitle.contains('monitoring financial') ||
          lowerContent.contains('expense tracker')) {
        debugPrint('   🚫 Skipping duplicate/confirmation notification');
        return null;
      }

      _recentlyProcessed.add(notificationKey);
      Future.delayed(const Duration(seconds: 5), () {
        _recentlyProcessed.remove(notificationKey);
      });

      final isFinancial = _isFromFinancialApp(packageName);
      debugPrint('   💰 Is financial: $isFinancial');
      if (!isFinancial) return null;

      final fullText = '$title $content'.trim();
      final txnData = _parseTransaction(fullText, packageName);
      if (txnData == null) {
        debugPrint('   ⏭️ No transaction parsed');
        return null;
      }

      final hash = _generateHash(fullText, DateTime.now());

      final isDuplicateHash = await FirestoreService.instance
          .isDuplicateTransaction(hash);
      if (isDuplicateHash) {
        debugPrint(
          '   ⚠️ Exact duplicate notification - already processed, skipping',
        );
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final pendingExists = prefs.getString('pending_$hash');
      if (pendingExists != null) {
        debugPrint('   ⚠️ Pending transaction already exists - skipping');
        return null;
      }

      final transactionDate = DateTime.now();

      final transaction = TransactionModel(
        amount: txnData['amount'] as double,
        type: txnData['type'] as String,
        date: transactionDate,
        note: txnData['note'] as String,
        category: txnData['category'] as String,
        icon: txnData['icon'] as int,
        autoDetected: true,
        notificationSource: packageName,
        notificationHash: hash,
      );

      final transactionMap = transaction.toMap();

      final allTxns = await FirestoreService.instance.getAllTransactions();
      final similarTransactions = allTxns.where((t) =>
          t.amount == transaction.amount &&
          t.type.toLowerCase() == transaction.type.toLowerCase() &&
          t.date.isAfter(DateTime.now().subtract(const Duration(hours: 24)))).toList();

      if (similarTransactions.isNotEmpty) {
        debugPrint(
          '   ⚠️ Found ${similarTransactions.length} similar transaction(s) in last 24h',
        );

        await prefs.setString('pending_$hash', jsonEncode(transactionMap));

        await NotificationHelper.showDuplicateConfirmation(
          transactionHash: hash,
          amount: transaction.amount,
          type: transaction.type,
          category: transaction.category,
          similarCount: similarTransactions.length,
        );

        debugPrint('   📬 Waiting for user confirmation...');
        return null;
      }

      final alreadyExists = await FirestoreService.instance
          .isDuplicateTransaction(hash);
      if (alreadyExists) {
        debugPrint('⚠️ Transaction already exists - skipping');
        return null;
      }

      final docId = await FirestoreService.instance.addTransaction(transaction);
      if (docId.isNotEmpty) {
        debugPrint('✅ NOTIFICATION: Auto-transaction inserted (id=$docId)');
        await NotificationHelper.showTransactionAdded(
          amount: transaction.amount,
          type: transaction.type,
          category: transaction.category,
        );
        return {'transactionMap': transactionMap, 'hash': hash};
      } else {
        debugPrint('⚠️ NOTIFICATION: Insert failed');
        return null;
      }
    } catch (e, st) {
      debugPrint('❌ NOTIFICATION: Exception: $e\n$st');
      return null;
    }
  }

  static bool _isFromFinancialApp(String packageName) {
    if (packageName.isEmpty) return true;

    if (packageName == 'com.example.buddy' ||
        packageName.contains('example.buddy')) {
      return false;
    }

    if (_financialApps.contains(packageName)) return true;

    final bankPatterns = [
      'bank',
      'upi',
      'payment',
      'wallet',
      'paisa',
      'money',
      'sms',
      'messaging',
      'message',
    ];
    final lower = packageName.toLowerCase();
    for (final p in bankPatterns) {
      if (lower.contains(p)) return true;
    }
    return false;
  }

  static Map<String, dynamic>? _parseTransaction(String text, String source) {
    debugPrint('🔍 PARSING: "$text"');

    final lowerText = text.toLowerCase();
    bool isDebit = false;
    bool isCredit = false;

    if (lowerText.contains('paid you') ||
        lowerText.contains('sent you') ||
        lowerText.contains('transferred you') ||
        lowerText.contains('received from')) {
      isCredit = true;
      debugPrint('   💰 Pattern: Someone paid YOU → CREDIT');
    } else if (lowerText.contains('you paid') ||
        lowerText.contains('you sent') ||
        lowerText.contains('you transferred') ||
        lowerText.contains('paid to') ||
        lowerText.contains('payment to')) {
      isDebit = true;
      debugPrint('   💸 Pattern: YOU paid someone → DEBIT');
    } else if (lowerText.contains('debited from your') ||
        lowerText.contains('withdrawn from your') ||
        lowerText.contains('deducted from your')) {
      isDebit = true;
      debugPrint('   💸 Pattern: Debited FROM your account → DEBIT');
    } else if (lowerText.contains('credited to your') ||
        lowerText.contains('deposited to your') ||
        lowerText.contains('added to your')) {
      isCredit = true;
      debugPrint('   💰 Pattern: Credited TO your account → CREDIT');
    } else if (lowerText.contains('refund') ||
        lowerText.contains('cashback') ||
        lowerText.contains('reward')) {
      isCredit = true;
      debugPrint('   💰 Pattern: Refund/Cashback → CREDIT');
    } else {
      final hasDebitKeyword = _debitRegex.hasMatch(text);
      final hasCreditKeyword = _creditRegex.hasMatch(text);

      if (hasDebitKeyword && !hasCreditKeyword) {
        isDebit = true;
        debugPrint('   💸 Fallback: Debit keyword found → DEBIT');
      } else if (hasCreditKeyword && !hasDebitKeyword) {
        isCredit = true;
        debugPrint('   💰 Fallback: Credit keyword found → CREDIT');
      } else if (hasDebitKeyword && hasCreditKeyword) {
        isDebit = true;
        debugPrint('   ⚠️ Both keywords found, defaulting to DEBIT');
      }
    }

    debugPrint('   Final decision - Debit: $isDebit, Credit: $isCredit');

    if (!isDebit && !isCredit) {
      debugPrint('   ❌ No transaction type detected');
      return null;
    }

    final amountMatch = _amountRegex.firstMatch(text);
    if (amountMatch == null) {
      debugPrint('   ❌ No amount found');
      return null;
    }

    final amountStr =
        (amountMatch.group(1) ??
                amountMatch.group(2) ??
                amountMatch.group(3) ??
                '')
            .replaceAll(',', '')
            .trim();
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) {
      debugPrint('   ❌ Invalid amount: $amountStr');
      return null;
    }

    final type = isDebit ? 'expense' : 'income';
    final category = _detectCategory(text, type);
    final icon = _getIconForCategory(category);

    debugPrint('   ✅ Parsed: ₹$amount as $type ($category)');

    return {
      'amount': amount,
      'type': type,
      'note':
          'Auto-detected from notification: ${text.length > 100 ? '${text.substring(0, 100)}...' : text}',
      'category': category,
      'icon': icon,
    };
  }
  static String _detectCategory(String text, String type) {
    final lowerText = text.toLowerCase();
    if (type == 'expense') {
      if (lowerText.contains('swiggy')) return 'Swiggy';
      if (lowerText.contains('zomato')) return 'Zomato';
      if (lowerText.contains('zepto')) return 'Zepto';
      if (lowerText.contains('amazon')) return 'Amazon';
      if (lowerText.contains('flipkart')) return 'Flipkart';
      if (lowerText.contains('netflix')) return 'Netflix';
      if (lowerText.contains('jio')) return 'Jio Internet';
      if (lowerText.contains('wifi')) return 'WiFi';
      if (lowerText.contains('grocery') || lowerText.contains('groceries') || lowerText.contains('instamart')) {
        return 'Grocery';
      }
      if (lowerText.contains('food') || lowerText.contains('dining') || lowerText.contains('restaurant') || lowerText.contains('lunch') || lowerText.contains('dinner')) {
        return 'Local Food';
      }
      if (lowerText.contains('uber') ||
          lowerText.contains('ola') ||
          lowerText.contains('rapido') ||
          lowerText.contains('fuel')) {
        return 'Transport';
      }
      if (lowerText.contains('bill') ||
          lowerText.contains('electricity') ||
          lowerText.contains('water') ||
          lowerText.contains('utility')) {
        return 'Bills & Utilities';
      }
      if (lowerText.contains('movie') || lowerText.contains('youtube') || lowerText.contains('spotify') || lowerText.contains('hotstar')) {
        return 'Subscriptions';
      }
      if (lowerText.contains('pharmacy') || lowerText.contains('hospital') || lowerText.contains('medical')) {
        return 'Medical';
      }
      return 'Other';
    } else {
      if (lowerText.contains('salary')) return 'Salary';
      if (lowerText.contains('refund') || lowerText.contains('cashback')) {
        return 'Cashback';
      }
      if (lowerText.contains('interest')) return 'Interest';
      if (lowerText.contains('investment') || lowerText.contains('stock') || lowerText.contains('mutual fund')) {
        return 'Investment';
      }
      return 'Other';
    }
  }

  static int _getIconForCategory(String category) {
    switch (category) {
      case 'Food & Dining':
        return Icons.restaurant_rounded.codePoint;
      case 'Groceries':
        return Icons.shopping_cart_rounded.codePoint;
      case 'Grocery':
        return Icons.shopping_basket_rounded.codePoint;
      case 'Swiggy':
        return Icons.delivery_dining_rounded.codePoint;
      case 'Zomato':
        return Icons.fastfood_rounded.codePoint;
      case 'Zepto':
        return Icons.bolt_rounded.codePoint;
      case 'Instamart':
        return Icons.storefront_rounded.codePoint;
      case 'Amazon':
        return Icons.inventory_2_rounded.codePoint;
      case 'Flipkart':
        return Icons.shopping_bag_rounded.codePoint;
      case 'Myntra':
        return Icons.checkroom_rounded.codePoint;
      case 'Transport':
        return Icons.directions_car_rounded.codePoint;
      case 'Uber':
      case 'Ola':
        return Icons.local_taxi_rounded.codePoint;
      case 'Rapido':
        return Icons.two_wheeler_rounded.codePoint;
      case 'Fuel':
        return Icons.local_gas_station_rounded.codePoint;
      case 'Netflix':
        return Icons.tv_rounded.codePoint;
      case 'YouTube':
        return Icons.ondemand_video_rounded.codePoint;
      case 'Spotify':
        return Icons.music_note_rounded.codePoint;
      case 'Hotstar':
        return Icons.live_tv_rounded.codePoint;
      case 'Gym & Fitness':
        return Icons.fitness_center_rounded.codePoint;
      case 'Medical':
        return Icons.medical_services_rounded.codePoint;
      case 'Education':
        return Icons.school_rounded.codePoint;
      case 'Rent':
        return Icons.home_rounded.codePoint;
      case 'Bills & Utilities':
        return Icons.receipt_long_rounded.codePoint;
      case 'Recharge':
        return Icons.phone_android_rounded.codePoint;
      case 'Coffee':
        return Icons.coffee_rounded.codePoint;
      case 'Travel':
        return Icons.flight_rounded.codePoint;
      case 'Party':
        return Icons.celebration_rounded.codePoint;
      case 'Gifts & Charity':
        return Icons.volunteer_activism_rounded.codePoint;
      case 'Subscriptions':
        return Icons.autorenew_rounded.codePoint;
      case 'Local Food':
        return Icons.local_pizza_rounded.codePoint;
      case 'Jio Internet':
        return Icons.router_rounded.codePoint;
      case 'WiFi':
        return Icons.wifi_rounded.codePoint;
      case 'Salary':
        return Icons.payments_rounded.codePoint;
      case 'Freelance':
        return Icons.work_outline_rounded.codePoint;
      case 'Business':
        return Icons.business_center_rounded.codePoint;
      case 'Investment':
        return Icons.trending_up_rounded.codePoint;
      case 'Interest':
        return Icons.savings_rounded.codePoint;
      case 'Refund':
        return Icons.reply_rounded.codePoint;
      case 'Gift':
        return Icons.card_giftcard_rounded.codePoint;
      case 'Cashback':
        return Icons.currency_exchange_rounded.codePoint;
      case 'Rental Income':
        return Icons.house_rounded.codePoint;
      default:
        return Icons.note_rounded.codePoint;
    }
  }

  static String _generateHash(String text, DateTime timestamp) {
    final bytes = utf8.encode(text);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
