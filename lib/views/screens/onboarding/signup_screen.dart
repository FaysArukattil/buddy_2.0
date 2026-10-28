import 'package:buddy/services/Network_services.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/bottom_navbar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:buddy/services/auth_service.dart';
import 'package:buddy/views/screens/onboarding/login_screen.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/utils/app_snackbar.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    if (_confirmPasswordController.text.isNotEmpty) {
      _formKey.currentState?.validate();
    }
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
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
      final result = await _authService.signUpWithEmailPassword(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (result != null && mounted) {
        AppSnackbar.showSuccess(
          context,
          'Account created successfully!',
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
                  // ── Compact Horizontal Brand Header ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        24 * s,
                        16 * s,
                        24 * s,
                        24 * s,
                      ),
                      child: Row(
                        children: [
                          // Full-Bleed App Logo
                          Container(
                            width: (64 * s).clamp(56.0, 72.0),
                            height: (64 * s).clamp(56.0, 72.0),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18 * s),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18 * s),
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
                                      size: 32,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          SizedBox(width: 16 * s),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Create Account',
                                  style: TextStyle(
                                    fontSize: (26 * s).clamp(22.0, 30.0),
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: -0.6,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Start tracking your money effortlessly',
                                  style: TextStyle(
                                    fontSize: (13.5 * s).clamp(12.0, 15.0),
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.75),
                                  ),
                                ),
                              ],
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
                        26 * s,
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
                                  // Full Name
                                  _buildBentoField(
                                    context: context,
                                    label: 'FULL NAME',
                                    hint: 'Enter your full name',
                                    controller: _nameController,
                                    icon: Icons.person_outline_rounded,
                                    keyboardType: TextInputType.name,
                                    validator: (val) {
                                      if (val == null || val.trim().isEmpty) {
                                        return 'Please enter your name';
                                      }
                                      if (val.trim().length < 2) {
                                        return 'Name must be at least 2 characters';
                                      }
                                      return null;
                                    },
                                  ),

                                  Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: AppColors.borderOf(
                                      context,
                                    ).withValues(alpha: 0.7),
                                  ),

                                  // Email
                                  _buildBentoField(
                                    context: context,
                                    label: 'EMAIL ADDRESS',
                                    hint: 'name@example.com',
                                    controller: _emailController,
                                    icon: Icons.alternate_email_rounded,
                                    keyboardType: TextInputType.emailAddress,
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

                                  Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: AppColors.borderOf(
                                      context,
                                    ).withValues(alpha: 0.7),
                                  ),

                                  // Password
                                  _buildBentoField(
                                    context: context,
                                    label: 'PASSWORD',
                                    hint: 'At least 6 characters',
                                    controller: _passwordController,
                                    icon: Icons.lock_outline_rounded,
                                    isPassword: true,
                                    obscureText: _obscurePassword,
                                    onToggleVisibility: () {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    validator: (val) {
                                      if (val == null || val.isEmpty) {
                                        return 'Please enter a password';
                                      }
                                      if (val.length < 6) {
                                        return 'Password must be at least 6 characters';
                                      }
                                      return null;
                                    },
                                  ),

                                  Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: AppColors.borderOf(
                                      context,
                                    ).withValues(alpha: 0.7),
                                  ),

                                  // Confirm Password
                                  _buildBentoField(
                                    context: context,
                                    label: 'CONFIRM PASSWORD',
                                    hint: 'Re-enter your password',
                                    controller: _confirmPasswordController,
                                    icon: Icons.verified_user_outlined,
                                    isPassword: true,
                                    obscureText: _obscureConfirm,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _handleSignUp(),
                                    onToggleVisibility: () {
                                      HapticFeedback.selectionClick();
                                      setState(() {
                                        _obscureConfirm = !_obscureConfirm;
                                      });
                                    },
                                    validator: (val) {
                                      if (val == null || val.isEmpty) {
                                        return 'Please confirm your password';
                                      }
                                      if (val != _passwordController.text) {
                                        return 'Passwords do not match';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 22),

                            // ── Primary Gradient CTA ──
                            _buildPrimaryCTA(
                              label: 'Create Account',
                              loadingLabel: 'Creating Account...',
                              onTap: _handleSignUp,
                            ),

                            const SizedBox(height: 22),

                            // ── Section Divider ──
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
                                    'OR',
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

                            const SizedBox(height: 18),

                            // ── Tactile Google Card Button ──
                            _buildGoogleButton(
                              context: context,
                              label: 'Continue with Google',
                              onTap: _handleGoogleSignIn,
                            ),

                            const Spacer(),
                            const SizedBox(height: 24),

                            // ── Bottom Switch Link ──
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Already have an account? ',
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
                                                  const LoginScreen(),
                                            ),
                                          );
                                        },
                                  child: const Text(
                                    'Sign In',
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.primary.withValues(alpha: 0.14)
                  : const Color(0xFF0F3632).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              size: 19,
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
                    fontSize: 10,
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
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                  cursorColor: AppColors.secondary,
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textLightOf(
                        context,
                      ).withValues(alpha: 0.7),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 3),
                    border: InputBorder.none,
                    errorStyle: const TextStyle(
                      fontSize: 11,
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
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
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
