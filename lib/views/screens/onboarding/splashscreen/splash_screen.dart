// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/views/screens/onboarding/auth_wrapper.dart';
import 'package:buddy/views/screens/onboarding/onborading_screen.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this);
    _controller.addStatusListener((status) async {
      if (status == AnimationStatus.completed) {
        await navigateToNext();
      }
    });
  }

  Future<void> navigateToNext() async {
    // Add a slight fade transition for smoothness
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    // Check if user has seen onboarding
    final prefs = await SharedPreferences.getInstance();
    final hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

    // Determine next screen
    final Widget nextScreen = hasSeenOnboarding 
        ? const AuthWrapper() 
        : const OnboardingScreen();

    debugPrint('🚀 SPLASH: hasSeenOnboarding=$hasSeenOnboarding, navigating to ${hasSeenOnboarding ? "AuthWrapper" : "OnboardingScreen"}');

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 600),
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
                onLoaded: (composition) {
                  _controller
                    ..duration = composition.duration
                    ..forward();
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