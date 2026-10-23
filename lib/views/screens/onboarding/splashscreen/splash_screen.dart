import 'package:flutter/material.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/views/screens/onboarding/auth_wrapper.dart';
import 'package:buddy/views/screens/onboarding/onborading_screen.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  final Future<void>? initFuture;
  const SplashScreen({super.key, this.initFuture});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        navigateToNext();
      }
    });

    // Start animating immediately on frame 1 without waiting for background tasks
    _controller.forward();
  }

  Future<void> navigateToNext() async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    // Ensure core services (Firebase etc.) are fully initialized before moving past splash
    if (widget.initFuture != null) {
      try {
        await widget.initFuture;
      } catch (e) {
        debugPrint('⚠️ SPLASH: initFuture error: $e');
      }
    }

    if (!mounted) return;

    // Check if user has seen onboarding
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

    // Determine next screen
    final Widget nextScreen = hasSeenOnboarding 
        ? const AuthWrapper() 
        : const OnboardingScreen();

    debugPrint('🚀 SPLASH: hasSeenOnboarding=$hasSeenOnboarding, navigating to ${hasSeenOnboarding ? "AuthWrapper" : "OnboardingScreen"}');

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => nextScreen,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
 void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.primaryGradient),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Lottie.asset(
                'assets/lottie/jsonlottie/Coinlottie.json',
                controller: _controller,
                width: 250,
                height: 250,
                fit: BoxFit.contain,
                renderCache: RenderCache.drawingCommands,
                onLoaded: (composition) {
                  final cappedDuration = composition.duration > const Duration(milliseconds: 1100)
                      ? const Duration(milliseconds: 1100)
                      : composition.duration;
                  _controller.duration = cappedDuration;
                  if (!_controller.isAnimating && !_controller.isCompleted) {
                    _controller.forward();
                  }
                },
              ),
              const SizedBox(height: 20),
              const Text(
                "Buddy",
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 50,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}