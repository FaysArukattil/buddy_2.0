import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:buddy/views/screens/onboarding/splashscreen/splash_screen.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/services/app_init_helper.dart';
import 'package:buddy/services/theme_service.dart';
import 'package:buddy/services/Network_services.dart';
import 'package:buddy/services/firestore_service.dart';
import 'package:buddy/services/preference_service.dart';
import 'package:buddy/services/update_service.dart';
import 'package:buddy/services/currency_service.dart';
import 'package:buddy/views/screens/widget_add_modal_host.dart';
import 'firebase_options.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint('🚀 APP: Starting instant frame-1 launch...');

  // Kick off essential services in background without delaying first frame render
  final initFuture = _initCoreServices();

  // Render UI immediately so splash screen shows instantly!
  runApp(MyApp(initFuture: initFuture));

  // Defer network monitoring to post-frame to eliminate DNS socket contention before frame 1
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NetworkHelper.startMonitoring();
  });
}

/// Dedicated lightweight entrypoint for the pre-warmed widget engine.
/// Renders the Add Transaction modal bottom sheet with zero cold-start delay.
@pragma('vm:entry-point')
void widgetAddMain() {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('⚡ WIDGET_ENTRY: Dedicated widget quick-add engine starting...');

  // Initialize core services needed for adding transactions
  final initFuture = _initCoreServices();

  runApp(WidgetAddApp(initFuture: initFuture));
}

class WidgetAddApp extends StatelessWidget {
  final Future<void>? initFuture;
  const WidgetAddApp({super.key, this.initFuture});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeModeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Buddy Quick Add',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          themeAnimationDuration: Duration.zero,
          home: WidgetAddModalHost(initFuture: initFuture),
        );
      },
    );
  }
}

Future<void> _initCoreServices() async {
  try {
    await Future.wait([
      ThemeService.initialize().catchError((e) {
        debugPrint('⚠️ APP: ThemeService init error: $e');
      }),
      PreferenceService.init().catchError((e) {
        debugPrint('⚠️ APP: PreferenceService init error: $e');
      }),
      CurrencyService.initialize().catchError((e) {
        debugPrint('⚠️ APP: CurrencyService init error: $e');
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
    debugPrint('⚠️ APP: Init error: $e');
  }
}

class MyApp extends StatefulWidget {
  final Future<void>? initFuture;
  const MyApp({super.key, this.initFuture});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  /// Global navigator key used for update dialogs on resume.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

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

      // Check for app updates on resume (non-blocking)
      final ctx = navigatorKey.currentContext;
      if (ctx != null) {
        UpdateService.checkOnResume(ctx);
      }
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
          navigatorKey: navigatorKey,
          title: 'Buddy',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentMode,
          themeAnimationDuration: Duration.zero,
          onGenerateInitialRoutes: (initialRoute) {
            if (initialRoute == '/widget-add') {
              return [
                MaterialPageRoute(
                  builder: (_) => WidgetAddModalHost(initFuture: widget.initFuture),
                  settings: const RouteSettings(name: '/widget-add'),
                ),
              ];
            }
            return [
              MaterialPageRoute(
                builder: (_) => SplashScreen(initFuture: widget.initFuture),
                settings: const RouteSettings(name: '/'),
              ),
            ];
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/widget-add') {
              return MaterialPageRoute(
                builder: (_) => WidgetAddModalHost(initFuture: widget.initFuture),
                settings: settings,
              );
            }
            return null;
          },
        );
      },
    );
  }
}
