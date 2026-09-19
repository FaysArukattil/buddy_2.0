import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:buddy/views/screens/onboarding/splashscreen/splash_screen.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/services/notification_helper.dart';
import 'package:buddy/services/app_init_helper.dart';
import 'package:buddy/services/theme_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('🚀 APP: Starting initialization...');

  // Initialize Theme Service
  try {
    await ThemeService.initialize();
    debugPrint('✅ APP: ThemeService initialized');
  } catch (e) {
    debugPrint('⚠️ APP: ThemeService initialization failed: $e');
  }

  // 0. Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('✅ APP: Firebase initialized');
  } catch (e) {
    debugPrint('❌ APP: Firebase initialization failed: $e');
  }

  // 1. Initialize the app (Firestore persistence, categories, sync transactions)
  try {
    await AppInitHelper.initialize();
    debugPrint('✅ APP: AppInitHelper initialized');
  } catch (e) {
    debugPrint('⚠️ APP: AppInitHelper initialization failed: $e');
  }

  // 2. Initialize Notification Helper (for showing in-app notifications)
  try {
    await NotificationHelper.initialize();
    debugPrint('✅ APP: Notification helper initialized');
  } catch (e) {
    debugPrint('❌ APP: Notification helper initialization failed: $e');
  }

  // 3. Request notification permission (Android 13+ dialog, NOT listener access)
  try {
    await NotificationHelper.requestNotificationPermission();
    debugPrint('✅ APP: Notification permissions requested');
  } catch (e) {
    debugPrint('⚠️ APP: Notification permission request failed: $e');
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
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeModeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Buddy',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          home: const SplashScreen(),
        );
      },
    );
  }
}
