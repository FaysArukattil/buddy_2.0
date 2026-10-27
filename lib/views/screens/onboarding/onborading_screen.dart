import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/images.dart';
import 'package:buddy/views/screens/onboarding/login_screen.dart';
import 'package:buddy/views/screens/onboarding/signup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final isDark = AppColors.isDark(context);

    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: Stack(
        children: [
          // Crisp ambient top lighting (replaces blurry raster background)
          Positioned(
            top: -100,
            left: -60,
            right: -60,
            height: 420,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      isDark
                          ? AppColors.secondary.withValues(alpha: 0.16)
                          : AppColors.primary.withValues(alpha: 0.14),
                      Colors.transparent,
                    ],
                    radius: 0.7,
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableHeight = constraints.maxHeight;

                // Dynamically calculate sizing based on screen constraints
                final imageHeight = (availableHeight * 0.40).clamp(180.0, 360.0);
                final spacingHeight = (availableHeight * 0.025).clamp(8.0, 24.0);
                final bottomPadding = (availableHeight * 0.035).clamp(16.0, 32.0);
                final titleFontSize = (availableHeight * 0.044).clamp(24.0, 36.0);

                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
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

                              // Mini Badge / Tag
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: (isDark ? AppColors.primary : AppColors.secondary)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: (isDark ? AppColors.primary : AppColors.secondary)
                                        .withValues(alpha: 0.25),
                                    width: 1.0,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      size: 14,
                                      color: isDark ? AppColors.primary : AppColors.secondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "Smart Financial Tracking",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? AppColors.primary : AppColors.secondary,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              SizedBox(height: spacingHeight * 0.8),

                              // Animated Illustration with Breathing Pedestal Shadow
                              AnimatedBuilder(
                                animation: _controller,
                                builder: (context, _) {
                                  final wave = math.sin(_controller.value * 2 * math.pi);
                                  final dy = wave * 8.0;
                                  final scale = 1.0 + (wave * 0.02);
                                  final shadowScale = 1.0 - (wave * 0.08);
                                  final shadowOpacity = (0.16 + (wave * 0.04)).clamp(0.08, 0.24);

                                  return Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Soft ground shadow under character
                                      Positioned(
                                        bottom: 12,
                                        child: Transform.scale(
                                          scaleX: shadowScale,
                                          scaleY: shadowScale * 0.8,
                                          child: Container(
                                            width: imageHeight * 0.55,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(100),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: (isDark
                                                          ? Colors.black
                                                          : AppColors.secondary)
                                                      .withValues(alpha: shadowOpacity),
                                                  blurRadius: 18,
                                                  spreadRadius: 2,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                      // Floating character
                                      Transform.translate(
                                        offset: Offset(0, dy),
                                        child: Transform.scale(
                                          scale: scale,
                                          child: Image.asset(
                                            AppImages.onboardingimage,
                                            height: imageHeight,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),

                                      // Money Lottie element
                                      Positioned(
                                        top: 10,
                                        left: 36,
                                        child: Transform.translate(
                                          offset: Offset(0, dy * 0.5),
                                          child: Lottie.asset(
                                            'assets/lottie/jsonlottie/Moneylottie.json',
                                            width: 70,
                                            height: 70,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),

                              SizedBox(height: spacingHeight),

                              // Refined Title Text
                              RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: TextStyle(
                                    fontSize: titleFontSize,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textPrimaryOf(context),
                                    height: 1.2,
                                    letterSpacing: -0.6,
                                  ),
                                  children: [
                                    const TextSpan(text: "Spend Smarter\n"),
                                    TextSpan(
                                      text: "Save More",
                                      style: TextStyle(
                                        color: isDark
                                            ? const Color(0xFF69AEA9)
                                            : AppColors.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 10),

                              // Elegant Subtitle
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  "Track expenses effortlessly, stay on top of dues, and take complete control of your wealth.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.45,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Bottom Action Section
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 24.0,
                              vertical: bottomPadding,
                            ),
                            child: Column(
                              children: [
                                // Refined Get Started Button
                                Container(
                                  height: 54,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF69AEA9), Color(0xFF3F8782)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(27),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF3F8782).withValues(alpha: 0.35),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      HapticFeedback.mediumImpact();
                                      final navigator = Navigator.of(context);
                                      final prefs = await SharedPreferences.getInstance();
                                      await prefs.setBool('has_seen_onboarding', true);
                                      debugPrint('✅ ONBOARDING: Marked as seen, navigating to SignUp');

                                      navigator.pushReplacement(
                                        MaterialPageRoute(
                                          builder: (context) => const SignUpScreen(),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(27),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          "Get Started",
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 16),

                                // Login Link (No Underline)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "Already Have Account? ",
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppColors.textSecondaryOf(context),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () async {
                                        HapticFeedback.selectionClick();
                                        final navigator = Navigator.of(context);
                                        final prefs = await SharedPreferences.getInstance();
                                        await prefs.setBool('has_seen_onboarding', true);
                                        debugPrint('✅ ONBOARDING: Marked as seen, navigating to Login');

                                        navigator.pushReplacement(
                                          MaterialPageRoute(
                                            builder: (context) => const LoginScreen(),
                                          ),
                                        );
                                      },
                                      child: Text(
                                        "Log In",
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isDark ? AppColors.primary : AppColors.secondary,
                                          fontWeight: FontWeight.w700,
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
