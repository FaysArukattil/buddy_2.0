import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/images.dart';
import 'package:buddy/views/screens/onboarding/login_screen.dart';
import 'package:buddy/views/screens/onboarding/signup_screen.dart';
import 'package:buddy/views/widgets/custom_button_filled.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              AppImages.onboardingbackground,
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableHeight = constraints.maxHeight;

                // Dynamically calculate sizing based on screen constraints
                final imageHeight = (availableHeight * 0.45).clamp(180.0, 400.0);
                final spacingHeight = (availableHeight * 0.04).clamp(12.0, 40.0);
                final bottomPadding = (availableHeight * 0.035).clamp(16.0, 32.0);
                final titleFontSize = (availableHeight * 0.045).clamp(24.0, 36.0);

                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: availableHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            children: [
                              SizedBox(height: spacingHeight),
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  AnimatedBuilder(
                                    animation: _controller,
                                    child: Image.asset(
                                      AppImages.onboardingimage,
                                      height: imageHeight,
                                      fit: BoxFit.contain,
                                    ),
                                    builder: (context, child) {
                                      final wave = math.sin(
                                        _controller.value * 2 * math.pi,
                                      );
                                      final dy = wave * 8.0;
                                      final scale = 1.0 + (wave * 0.02);
                                      return Transform.translate(
                                        offset: Offset(0, dy),
                                        child: Transform.scale(
                                          scale: scale,
                                          child: child,
                                        ),
                                      );
                                    },
                                  ),
                                  Positioned(
                                    top: 16,
                                    left: 40,
                                    child: Lottie.asset(
                                      'assets/lottie/jsonlottie/Moneylottie.json',
                                      width: 70,
                                      height: 70,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: spacingHeight),

                              // Title Text
                              Text(
                                "Spend Smarter\nSave More",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.secondary,
                                ),
                              ),
                            ],
                          ),

                          // Bottom Section
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 24.0,
                              vertical: bottomPadding,
                            ),
                            child: Column(
                              children: [
                                // Get Started Button
                                CustomButtonFilled(
                                  text: "Get Started",
                                  onPressed: () async {
                                    final navigator = Navigator.of(context);
                                    // Mark onboarding as seen
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setBool('has_seen_onboarding', true);
                                    debugPrint('✅ ONBOARDING: Marked as seen, navigating to SignUp');
                                    
                                    navigator.pushReplacement(
                                      MaterialPageRoute(
                                        builder: (context) => SignUpScreen(),
                                      ),
                                    );
                                  },
                                  borderRadius: 40,
                                ),
                                const SizedBox(height: 16),

                                // Login Link
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      "Already Have Account? ",
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () async {
                                        final navigator = Navigator.of(context);
                                        // Mark onboarding as seen
                                        final prefs = await SharedPreferences.getInstance();
                                        await prefs.setBool('has_seen_onboarding', true);
                                        debugPrint('✅ ONBOARDING: Marked as seen, navigating to Login');
                                        
                                        navigator.pushReplacement(
                                          MaterialPageRoute(
                                            builder: (context) => LoginScreen(),
                                          ),
                                        );
                                      },
                                      child: const Text(
                                        "Log In",
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: AppColors.secondary,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
