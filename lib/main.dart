import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:buddy/views/screens/onboarding/splashscreen/splash_screen.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/services/notification_service.dart';
import 'package:buddy/services/notification_helper.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/services/transaction_sync_helper.dart';
import 'package:buddy/services/app_init_helper.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('🚀 APP: Starting initialization...');

  // 0. Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ APP: Firebase initialized');
  } catch (e) {
    debugPrint('❌ APP: Firebase initialization failed: $e');
  }

  // 1. Enable Firestore offline persistence
  try {
    await FirestoreService.enableOfflinePersistence();
    debugPrint('✅ APP: Firestore persistence enabled');
  } catch (e) {
    debugPrint('⚠️ APP: Firestore persistence setup failed: $e');
  }

  // 2. Initialize the app sync helper (auto-sync & callbacks)
  try {
    await AppInitHelper.initialize();
    debugPrint('✅ APP: AppInitHelper initialized');
  } catch (e) {
    debugPrint('⚠️ APP: AppInitHelper initialization failed: $e');
  }

  // 3. Sync native transactions to Firestore
  try {
    await TransactionSyncHelper.syncNativeTransactions();
    debugPrint('✅ APP: Transaction sync complete');
  } catch (e) {
    debugPrint('⚠️ APP: Transaction sync failed: $e');
  }

  // 4. Initialize Notification Helper (for showing notifications)
  try {
    await NotificationHelper.initialize();
    debugPrint('✅ APP: Notification helper initialized');
  } catch (e) {
    debugPrint('❌ APP: Notification helper initialization failed: $e');
  }

  // 5. Request notification permissions
  try {
    await NotificationHelper.requestNotificationPermission();
    debugPrint('✅ APP: Notification permissions requested');
  } catch (e) {
    debugPrint('⚠️ APP: Notification permission request failed: $e');
  }

  // 6. Check if auto-detection is enabled
  try {
    final isAutoDetectionEnabled =
        await NotificationService.isAutoDetectionEnabled();
    debugPrint('ℹ️ APP: Auto-detection enabled: $isAutoDetectionEnabled');

    if (isAutoDetectionEnabled) {
      final hasAccess = await NotificationService.requestNotificationAccess();

      if (hasAccess) {
        await NotificationService.startListening();
        debugPrint('✅ APP: Notification listener started');
      } else {
        debugPrint('⚠️ APP: Notification listener access not granted');
      }
    } else {
      debugPrint('ℹ️ APP: Auto-detection disabled, not starting listener');
    }
  } catch (e) {
    debugPrint('⚠️ APP: Failed to start notification listener: $e');
  }

  debugPrint('🎉 APP: Initialization complete\n');

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('📱 APP: Observer attached');

    AppInitHelper.onTransactionsSynced = () {
      debugPrint('🔄 Transactions synced - triggering refresh if needed');
      setState(() {});
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppInitHelper.dispose();
    debugPrint('📱 APP: Observer removed');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    debugPrint('📱 APP: Lifecycle state changed to: $state');

    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 APP: App resumed - syncing transactions...');
      _syncTransactions();
    }
  }

  Future<void> _syncTransactions() async {
    try {
      final syncedCount = await AppInitHelper.syncNow();
      debugPrint('✅ APP: Synced $syncedCount transactions');
    } catch (e) {
      debugPrint('❌ APP: Error during sync: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Buddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
