import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:buddy/views/screens/onboarding/splashscreen/splash_screen.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/services/app_init_helper.dart';
import 'package:buddy/services/theme_service.dart';
import 'package:buddy/services/Network_services.dart';
import 'package:buddy/services/firestore_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('🚀 APP: Starting lightning-fast initialization...');

  // Start network monitoring immediately
  NetworkHelper.startMonitoring();

  // Initialize essential services in parallel
  try {
    await Future.wait([
      ThemeService.initialize().catchError((e) {
        debugPrint('⚠️ APP: ThemeService init error: $e');
      }),
      Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).then((_) {
        // Enable offline persistence as soon as Firebase is initialized
        FirestoreService.enableOfflinePersistence();
      }).catchError((e) {
        debugPrint('❌ APP: Firebase init error: $e');
      }),
    ]);
    debugPrint('✅ APP: Core services initialized in parallel');
  } catch (e) {
    debugPrint('⚠️ APP: Init error (continuing to render): $e');
  }

  // Render UI immediately without waiting for heavy sync/network tasks!
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
