import 'package:buddy/services/Network_services.dart';
import 'package:flutter/material.dart';
import 'package:buddy/services/auth_service.dart';
import 'package:buddy/views/screens/onboarding/signup_screen.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/bottom_navbar_screen.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/views/widgets/custom_button_filled.dart';
import 'package:buddy/views/widgets/custom_button_outlined.dart';
import 'package:buddy/views/widgets/auth_textfield.dart';
import 'package:buddy/utils/app_snackbar.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    // Check network connectivity
    final hasNetwork = await NetworkHelper.hasInternetConnection();
    if (!hasNetwork) {
      if (mounted) {
        AppSnackbar.showWarning(
          context,
          'No internet connection. Please check your network.',
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.signInWithEmailPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (result != null && mounted) {
        debugPrint('🔐 LOGIN: Login successful!');

        // Show success message
        AppSnackbar.showSuccess(
          context,
          'Logged in successfully!',
          duration: const Duration(milliseconds: 800),
        );

        // Wait for auth state to propagate AND SnackBar to show
        await Future.delayed(const Duration(milliseconds: 900));

        if (mounted) {
          // Navigate to home screen directly (matching SignUpScreen pattern)
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const BottomNavbarScreen()),
            (route) => false,
          );
          debugPrint('🔐 LOGIN: Navigated to home screen');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, e.toString());
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    // Check network connectivity
    final hasNetwork = await NetworkHelper.hasInternetConnection();
    if (!hasNetwork) {
      if (mounted) {
        AppSnackbar.showWarning(
          context,
          'No internet connection. Please check your network.',
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.signInWithGoogle();

      if (result != null && mounted) {
        debugPrint('🔐 GOOGLE SIGNIN: Login successful!');

        // Show success message
        AppSnackbar.showSuccess(
          context,
          'Signed in with Google successfully!',
          duration: const Duration(milliseconds: 800),
        );

        // Wait for auth state to propagate AND SnackBar to show
        await Future.delayed(const Duration(milliseconds: 900));

        if (mounted) {
          // Navigate to home screen directly (matching SignUpScreen pattern)
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const BottomNavbarScreen()),
            (route) => false,
          );
          debugPrint('🔐 GOOGLE SIGNIN: Navigated to home screen');
        }
      } else if (mounted) {
        // User cancelled the sign-in
        AppSnackbar.showWarning(context, 'Sign-in cancelled');
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, e.toString());
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleGuestLogin() async {
    setState(() => _isLoading = true);

    try {
      final result = await _authService.signInAsGuest();

      if (result != null && mounted) {
        debugPrint('🔐 GUEST LOGIN: Login successful!');

        // Show success message
        AppSnackbar.showSuccess(
          context,
          'Continuing as guest',
          duration: const Duration(milliseconds: 800),
        );

        // Wait for auth state to propagate AND SnackBar to show
        await Future.delayed(const Duration(milliseconds: 900));

        if (mounted) {
          // Navigate to home screen directly (matching SignUpScreen pattern)
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const BottomNavbarScreen()),
            (route) => false,
          );
          debugPrint('🔐 GUEST LOGIN: Navigated to home screen');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      AppSnackbar.showWarning(context, 'Please enter your email address');
      return;
    }

    try {
      await _authService.resetPassword(email);
      if (mounted) {
        AppSnackbar.showSuccess(
          context,
          'Password reset email sent! Check your inbox.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),

                  // Welcome Text
                  const Text(
                    "Welcome Back!",
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Sign in to continue managing your finances",
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Email Field
                  AuthTextField(
                    label: "Email",
                    hint: "Enter your email",
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 24),

                  // Password Field
                  AuthTextField(
                    label: "Password",
                    hint: "Enter your password",
                    controller: _passwordController,
                    isPassword: true,
                    prefixIcon: const Icon(
                      Icons.lock_outline,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // Forgot Password
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: _handleForgotPassword,
                      child: const Text(
                        "Forgot Password?",
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Login Button
                  _isLoading
                      ? Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(16),
                          ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  BuddyLoadingIndicator(size: 24),
                                  SizedBox(width: 12),
                                  Text(
                                    'Logging in...',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                        )
                      : CustomButtonFilled(
                          text: "Log In",
                          onPressed: _handleLogin,
                          borderRadius: 16,
                        ),

                  const SizedBox(height: 24),

                  // Divider with "Or"
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          color: AppColors.borderOf(context),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          "OR",
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: AppColors.borderOf(context),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Google Sign In Button
                  CustomButtonOutlined(
                    text: "Continue with Google",
                    onPressed: _isLoading ? () {} : _handleGoogleSignIn,
                    borderRadius: 16,
                    icon: Image.asset(
                      'assets/images/google_logo.png',
                      height: 20,
                      width: 20,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.g_mobiledata,
                          size: 24,
                          color: AppColors.secondary,
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Guest Login Button
                  CustomButtonOutlined(
                    text: "Continue as Guest",
                    onPressed: _isLoading ? () {} : _handleGuestLogin,
                    borderRadius: 16,
                    icon: const Icon(
                      Icons.person_outline,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Sign Up Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account? ",
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SignUpScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          "Sign Up",
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
