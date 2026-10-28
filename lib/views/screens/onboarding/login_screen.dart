import 'package:buddy/services/Network_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:buddy/services/auth_service.dart';
import 'package:buddy/views/screens/onboarding/signup_screen.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/bottom_navbar_screen.dart';
import 'package:buddy/utils/colors.dart';
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
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      HapticFeedback.lightImpact();
      return;
    }

    HapticFeedback.mediumImpact();

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
        AppSnackbar.showSuccess(
          context,
          'Logged in successfully!',
          duration: const Duration(milliseconds: 800),
        );

        await Future.delayed(const Duration(milliseconds: 900));

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const BottomNavbarScreen()),
            (route) => false,
          );
        }
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, e.toString());
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();

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
        AppSnackbar.showSuccess(
          context,
          'Signed in with Google successfully!',
          duration: const Duration(milliseconds: 800),
        );

        await Future.delayed(const Duration(milliseconds: 900));

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const BottomNavbarScreen()),
            (route) => false,
          );
        }
      } else if (mounted) {
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
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    setState(() => _isLoading = true);

    try {
      final result = await _authService.signInAsGuest();

      if (result != null && mounted) {
        AppSnackbar.showSuccess(
          context,
          'Continuing as guest',
          duration: const Duration(milliseconds: 800),
        );

        await Future.delayed(const Duration(milliseconds: 900));

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const BottomNavbarScreen()),
            (route) => false,
          );
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
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      AppSnackbar.showWarning(
        context,
        'Enter your email address in the box above first',
      );
      return;
    }

    try {
      await _authService.resetPassword(email);
      if (mounted) {
        AppSnackbar.showSuccess(
          context,
          'Password reset link sent! Check your inbox.',
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
    final isDark = AppColors.isDark(context);
    final mq = MediaQuery.of(context);
    final s = (mq.size.width / 390.0).clamp(0.85, 1.2);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: isDark
              ? const Color(0xFF0B1917)
              : const Color(0xFF0F3632),
          body: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? const [
                        Color(0xFF0B1917),
                        Color(0xFF132E2B),
                        Color(0xFF0F2624),
                      ]
                    : const [
                        Color(0xFF0F3632),
                        Color(0xFF1A4F49),
                        Color(0xFF143F3B),
                      ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  // ── Top Brand Showcase ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        24 * s,
                        20 * s,
                        24 * s,
                        28 * s,
                      ),
                      child: Column(
                        children: [
                          // Full-Bleed Edge-to-Edge App Logo
                          Container(
                            width: (78 * s).clamp(68.0, 88.0),
                            height: (78 * s).clamp(68.0, 88.0),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22 * s),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.25,
                                  ),
                                  blurRadius: 32,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22 * s),
                              child: Image.asset(
                                'assets/images/app_logo.png',
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    decoration: const BoxDecoration(
                                      gradient: AppColors.primaryGradient,
                                    ),
                                    child: const Icon(
                                      Icons.account_balance_wallet_rounded,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          SizedBox(height: 18 * s),
                          Text(
                            'Welcome back',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: (28 * s).clamp(24.0, 32.0),
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.7,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sign in to your Buddy account',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: (14.5 * s).clamp(13.0, 16.0),
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Main Curved Sheet Surface ──
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.backgroundOf(context),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(34),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 30,
                            offset: const Offset(0, -6),
                          ),
                        ],
                      ),
                      padding: EdgeInsets.fromLTRB(
                        22 * s,
                        28 * s,
                        22 * s,
                        mq.padding.bottom + 24,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ── Bento Grouped Input Card ──
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.cardOf(context),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: AppColors.borderOf(context),
                                  width: 1.2,
                                ),
                                boxShadow: AppColors.cardShadowOf(context),
                              ),
                              child: Column(
                                children: [
                                  // Email Row
                                  _buildBentoField(
                                    context: context,
                                    label: 'EMAIL ADDRESS',
                                    hint: 'Enter your email ',
                                    controller: _emailController,
                                    icon: Icons.alternate_email_rounded,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    validator: (val) {
                                      if (val == null || val.trim().isEmpty) {
                                        return 'Please enter your email';
                                      }
                                      if (!val.contains('@')) {
                                        return 'Enter a valid email address';
                                      }
                                      return null;
                                    },
                                  ),

                                  // Hairline Divider
                                  Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: AppColors.borderOf(
                                      context,
                                    ).withValues(alpha: 0.7),
                                  ),

                                  // Password Row
                                  _buildBentoField(
                                    context: context,
                                    label: 'PASSWORD',
                                    hint: 'Enter your password',
                                    controller: _passwordController,
                                    icon: Icons.lock_outline_rounded,
                                    isPassword: true,
                                    obscureText: _obscurePassword,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _handleLogin(),
                                    onToggleVisibility: () {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    validator: (val) {
                                      if (val == null || val.isEmpty) {
                                        return 'Please enter your password';
                                      }
                                      if (val.length < 6) {
                                        return 'Password must be at least 6 characters';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Forgot Password Row
                            Align(
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
                                onTap: _isLoading
                                    ? null
                                    : _handleForgotPassword,
                                behavior: HitTestBehavior.opaque,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    'Forgot Password?',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.secondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // ── Custom Primary Gradient CTA ──
                            _buildPrimaryCTA(
                              label: 'Sign In',
                              loadingLabel: 'Signing in...',
                              onTap: _handleLogin,
                            ),

                            const SizedBox(height: 24),

                            // ── Clean Section Divider ──
                            Row(
                              children: [
                                Expanded(
                                  child: Divider(
                                    color: AppColors.borderOf(context),
                                    thickness: 1,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  child: Text(
                                    'OR CONTINUE WITH',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2,
                                      color: AppColors.textLightOf(context),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Divider(
                                    color: AppColors.borderOf(context),
                                    thickness: 1,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // ── Tactile Google & Guest Action Cards ──
                            Row(
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: _buildGoogleButton(
                                    context: context,
                                    label: 'Google',
                                    onTap: _handleGoogleSignIn,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 5,
                                  child: _buildGuestButton(
                                    context: context,
                                    onTap: _handleGuestLogin,
                                  ),
                                ),
                              ],
                            ),

                            const Spacer(),
                            const SizedBox(height: 28),

                            // ── Bottom Switch Link ──
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Don't have an account? ",
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _isLoading
                                      ? null
                                      : () {
                                          HapticFeedback.lightImpact();
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const SignUpScreen(),
                                            ),
                                          );
                                        },
                                  child: const Text(
                                    'Create Account',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBentoField({
    required BuildContext context,
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
    ValueChanged<String>? onSubmitted,
    String? Function(String?)? validator,
  }) {
    final isDark = AppColors.isDark(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.primary.withValues(alpha: 0.14)
                  : const Color(0xFF0F3632).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isDark ? AppColors.primary : const Color(0xFF0F3632),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
                const SizedBox(height: 2),
                TextFormField(
                  controller: controller,
                  keyboardType: keyboardType,
                  textInputAction: textInputAction,
                  obscureText: isPassword ? obscureText : false,
                  onFieldSubmitted: onSubmitted,
                  validator: validator,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                  cursorColor: AppColors.secondary,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textLightOf(
                        context,
                      ).withValues(alpha: 0.7),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    border: InputBorder.none,
                    errorStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isPassword)
            GestureDetector(
              onTap: onToggleVisibility,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  obscureText
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: AppColors.textLightOf(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPrimaryCTA({
    required String label,
    required String loadingLabel,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 58,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F3632), Color(0xFF1E5D57), Color(0xFF2C7A72)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F3632).withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const BuddyLoadingIndicator(size: 22),
                  const SizedBox(width: 12),
                  Text(
                    loadingLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 34),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGoogleButton({
    required BuildContext context,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.cardOf(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderOf(context), width: 1.2),
            boxShadow: AppColors.cardShadowOf(context),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/google_logo.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Text(
                        'G',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF4285F4),
                          height: 1.0,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuestButton({
    required BuildContext context,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.cardOf(context),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderOf(context), width: 1.2),
            boxShadow: AppColors.cardShadowOf(context),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: AppColors.textSecondaryOf(context),
              ),
              const SizedBox(width: 8),
              Text(
                'Guest',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
