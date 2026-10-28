import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/views/screens/bottomnavbarscreen/bottom_navbar_screen.dart';
import 'package:buddy/views/widgets/buddy_loading_indicator.dart';

// Brand tokens matching Onboarding Hero and Home header
const List<Color> kAuthHeroLight = [
  Color(0xFF0F3632),
  Color(0xFF1E5D57),
  Color(0xFF2C7A72),
];

const List<Color> kAuthHeroDark = [
  Color(0xFF0F2624),
  Color(0xFF163E3B),
  Color(0xFF1E5D57),
];

const Color kAuthMint = Color(0xFF69F0AE);
const List<Color> kAuthCtaGradient = [
  Color(0xFF1E5D57),
  Color(0xFF2C7A72),
];

/// Strips raw Exception prefixes for clean user display.
String authErrorMessage(Object e) {
  var msg = e.toString().replaceFirst(RegExp(r'^(Exception|Error):\s*'), '');
  if (msg.contains('firebase_auth/') || msg.contains('FirebaseAuthException')) {
    final match = RegExp(r'\[.*?\]\s*(.*)').firstMatch(msg);
    if (match != null && match.group(1) != null) {
      msg = match.group(1)!;
    }
  }
  return msg;
}

/// Navigation helpers for authentication flows.
class AuthNav {
  static void toHome(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const BottomNavbarScreen()),
      (route) => false,
    );
  }

  static void swap(BuildContext context, Widget page) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }
}

/// Vector-drawn official 4-color Google "G" logo.
/// Guaranteed crisp rendering on all DPIs without asset dependencies.
class GoogleLogoPainter extends CustomPainter {
  const GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / 48.0;

    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.fill;
    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.fill;
    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.scale(s, s);

    // Blue: horizontal bar + upper right curve
    final bluePath = Path()
      ..moveTo(46.98, 24.55)
      ..cubicTo(46.98, 22.98, 46.83, 21.46, 46.6, 20.0)
      ..lineTo(24.0, 20.0)
      ..lineTo(24.0, 29.02)
      ..lineTo(36.94, 29.02)
      ..cubicTo(36.36, 31.98, 34.68, 34.5, 32.16, 36.2)
      ..lineTo(39.89, 42.2)
      ..cubicTo(44.4, 38.02, 46.98, 31.84, 46.98, 24.55)
      ..close();
    canvas.drawPath(bluePath, bluePaint);

    // Green: bottom arc
    final greenPath = Path()
      ..moveTo(24.0, 48.0)
      ..cubicTo(30.48, 48.0, 35.93, 45.87, 39.89, 42.19)
      ..lineTo(32.16, 36.19)
      ..cubicTo(30.01, 37.64, 27.24, 38.49, 24.0, 38.49)
      ..cubicTo(17.74, 38.49, 12.43, 34.27, 10.53, 28.58)
      ..lineTo(2.55, 34.77)
      ..cubicTo(6.51, 42.62, 14.62, 48.0, 24.0, 48.0)
      ..close();
    canvas.drawPath(greenPath, greenPaint);

    // Yellow: bottom-left arc
    final yellowPath = Path()
      ..moveTo(10.53, 28.59)
      ..cubicTo(10.05, 27.14, 9.77, 25.6, 9.77, 24.0)
      ..cubicTo(9.77, 22.4, 10.05, 20.86, 10.53, 19.41)
      ..lineTo(2.55, 13.22)
      ..cubicTo(0.92, 16.46, 0.0, 20.12, 0.0, 24.0)
      ..cubicTo(0.0, 27.88, 0.92, 31.54, 2.55, 34.78)
      ..lineTo(10.53, 28.59)
      ..close();
    canvas.drawPath(yellowPath, yellowPaint);

    // Red: top arc
    final redPath = Path()
      ..moveTo(24.0, 9.5)
      ..cubicTo(27.54, 9.5, 30.71, 10.72, 33.21, 13.1)
      ..lineTo(40.06, 6.25)
      ..cubicTo(35.9, 2.38, 30.47, 0.0, 24.0, 0.0)
      ..cubicTo(14.62, 0.0, 6.51, 5.38, 2.55, 13.22)
      ..lineTo(10.53, 19.41)
      ..cubicTo(12.43, 13.72, 17.74, 9.5, 24.0, 9.5)
      ..close();
    canvas.drawPath(redPath, redPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GoogleLogoWidget extends StatelessWidget {
  final double size;
  const GoogleLogoWidget({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: GoogleLogoPainter()),
    );
  }
}

/// Compact, premium Hero & responsive Shell for Auth screens.
class AuthShell extends StatelessWidget {
  final String headline;
  final String subtitle;
  final List<(IconData, String)> chips;
  final Widget child;
  final Widget? topControl;

  const AuthShell({
    super.key,
    required this.headline,
    required this.subtitle,
    required this.chips,
    required this.child,
    this.topControl,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final shortScreen = MediaQuery.sizeOf(context).height < 700;

    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.15,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: Scaffold(
          backgroundColor: AppColors.backgroundOf(context),
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                children: [
                  _hero(context, isDark, shortScreen),
                  TweenAnimationBuilder<double>(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                    tween: Tween(begin: 0, end: 1),
                    builder: (context, v, c) => Opacity(
                      opacity: v,
                      child: Transform.translate(
                        offset: Offset(0, (1 - v) * 14),
                        child: c,
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        22,
                        20,
                        22,
                        MediaQuery.paddingOf(context).bottom + 24,
                      ),
                      child: child,
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

  Widget _hero(BuildContext context, bool isDark, bool shortScreen) {
    final canPop = Navigator.of(context).canPop();

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark ? kAuthHeroDark : kAuthHeroLight,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F3632).withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Soft ambient circular glow
          Positioned(
            right: -70,
            top: -60,
            child: IgnorePointer(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.28),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                canPop ? 6 : 14,
                20,
                shortScreen ? 20 : 26,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top bar: Back button + Brand badge
                  Row(
                    children: [
                      if (canPop)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.16),
                                ),
                              ),
                              child: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: kAuthMint,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'BUDDY',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (topControl != null) topControl!,
                    ],
                  ),
                  SizedBox(height: shortScreen ? 16 : 22),
                  Text(
                    headline,
                    style: TextStyle(
                      fontSize: shortScreen ? 26 : 30,
                      fontWeight: FontWeight.w900,
                      height: 1.12,
                      letterSpacing: -0.6,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final (icon, label) in chips)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, size: 12, color: kAuthMint),
                                const SizedBox(width: 5),
                                Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sliding segmented pill switcher (Sign In / Create Account)
class AuthSegmentedControl extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabChanged;

  const AuthSegmentedControl({
    super.key,
    required this.selectedIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    const tabs = ['Sign In', 'Create Account'];
    final isDark = AppColors.isDark(context);

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurface
            : AppColors.surfaceOf(context).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.7),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = (constraints.maxWidth - 6) / tabs.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: 3 + selectedIndex * tabWidth,
                top: 3,
                width: tabWidth,
                height: 38,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.cardOf(context),
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (int i = 0; i < tabs.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onTabChanged(i);
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: selectedIndex == i
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: selectedIndex == i
                                  ? (isDark
                                      ? AppColors.darkTextPrimary
                                      : const Color(0xFF0F3632))
                                  : AppColors.textSecondaryOf(context),
                            ),
                            child: Text(tabs[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Primary gradient CTA button with integrated loading state.
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final String loadingLabel;
  final bool loading;
  final VoidCallback? onPressed;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.loadingLabel,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;

    return Semantics(
      button: true,
      label: loading ? loadingLabel : label,
      child: Container(
        height: 52,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: loading
                ? [
                    kAuthCtaGradient[0].withValues(alpha: 0.8),
                    kAuthCtaGradient[1].withValues(alpha: 0.8),
                  ]
                : kAuthCtaGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          boxShadow: [
            BoxShadow(
              color: kAuthCtaGradient.first.withValues(alpha: 0.32),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    onPressed!();
                  }
                : null,
            child: Center(
              child: loading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BuddyLoadingIndicator(size: 20),
                        const SizedBox(width: 10),
                        Text(
                          loadingLabel,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One-tap Google button with official 4-color vector G logo.
class AuthGoogleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  const AuthGoogleButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;

    return Container(
      height: 52,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderOf(context), width: 1.2),
        boxShadow: AppColors.cardShadowOf(context),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled
              ? () {
                  HapticFeedback.lightImpact();
                  onPressed!();
                }
              : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading) ...[
                const BuddyLoadingIndicator(size: 20),
                const SizedBox(width: 10),
              ] else ...[
                const GoogleLogoWidget(size: 20),
                const SizedBox(width: 12),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
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

/// Low-pressure "Continue as Guest" pill for curious users.
class AuthGuestButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;

  const AuthGuestButton({
    super.key,
    required this.onPressed,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: loading ? null : onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        icon: Icon(
          Icons.explore_outlined,
          size: 16,
          color: AppColors.textSecondaryOf(context),
        ),
        label: Text(
          'Explore as Guest without signing in',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
      ),
    );
  }
}

/// Modern text field with icon, focus glow, label, and clear actions.
class ModernAuthField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool isPassword;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final IconData prefixIcon;
  final bool enabled;

  const ModernAuthField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.prefixIcon,
    this.isPassword = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.validator,
    this.onFieldSubmitted,
    this.enabled = true,
  });

  @override
  State<ModernAuthField> createState() => _ModernAuthFieldState();
}

class _ModernAuthFieldState extends State<ModernAuthField> {
  bool _obscureText = true;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 7),
        Focus(
          onFocusChange: (focused) => setState(() => _isFocused = focused),
          child: TextFormField(
            controller: widget.controller,
            obscureText: widget.isPassword && _obscureText,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            autofillHints: widget.autofillHints,
            enabled: widget.enabled,
            validator: widget.validator,
            onFieldSubmitted: widget.onFieldSubmitted,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimaryOf(context),
            ),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(
                color: AppColors.textLightOf(context).withValues(alpha: 0.8),
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Icon(
                widget.prefixIcon,
                size: 20,
                color: _isFocused
                    ? (isDark ? kAuthMint : AppColors.secondary)
                    : AppColors.textLightOf(context),
              ),
              suffixIcon: widget.isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscureText
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: _isFocused
                            ? AppColors.secondary
                            : AppColors.textLightOf(context),
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _obscureText = !_obscureText);
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.surfaceOf(context),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: AppColors.borderOf(context),
                  width: 1.2,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: AppColors.borderOf(context),
                  width: 1.2,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? kAuthMint : AppColors.secondary,
                  width: 1.8,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppColors.error,
                  width: 1.2,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppColors.error,
                  width: 1.8,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dynamic password strength meter replacing "Confirm Password" friction.
class PasswordStrengthMeter extends StatelessWidget {
  final String password;

  const PasswordStrengthMeter({super.key, required this.password});

  int get _score {
    if (password.isEmpty) return 0;
    int score = 0;
    if (password.length >= 6) score++;
    if (password.length >= 8 && RegExp(r'[0-9]').hasMatch(password)) score++;
    if (password.length >= 10 && RegExp(r'[!@#\$&*~]').hasMatch(password)) {
      score++;
    }
    return score;
  }

  String get _label {
    switch (_score) {
      case 1:
        return 'Weak (use 8+ chars & numbers)';
      case 2:
        return 'Good password';
      case 3:
        return 'Strong password';
      default:
        return 'Minimum 6 characters';
    }
  }

  Color _barColor(int index) {
    if (_score <= index) return Colors.black.withValues(alpha: 0.1);
    switch (_score) {
      case 1:
        return AppColors.warning;
      case 2:
        return const Color(0xFF29B6F6);
      case 3:
        return kAuthMint;
      default:
        return Colors.black.withValues(alpha: 0.1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (int i = 0; i < 3; i++)
                Expanded(
                  child: Container(
                    height: 3.5,
                    margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                    decoration: BoxDecoration(
                      color: _barColor(i),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            _label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal divider with custom text label.
class AuthOrDivider extends StatelessWidget {
  final String text;
  const AuthOrDivider({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(
        height: 1,
        color: AppColors.borderOf(context).withValues(alpha: 0.8),
      ),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.textLightOf(context),
            ),
          ),
        ),
        line,
      ],
    );
  }
}

/// Switcher row: "Don't have an account? Sign Up"
class AuthSwitchRow extends StatelessWidget {
  final String prompt;
  final String action;
  final VoidCallback onTap;

  const AuthSwitchRow({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.isDark(context)
        ? kAuthMint
        : const Color(0xFF1E5D57);

    return Center(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        child: Text.rich(
          TextSpan(
            text: '$prompt  ',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondaryOf(context),
            ),
            children: [
              TextSpan(
                text: action,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// High-converting trust signal footer badge.
class AuthTrustBadge extends StatelessWidget {
  const AuthTrustBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock_rounded,
              size: 13,
              color: Color(0xFF4CAF50),
            ),
            const SizedBox(width: 6),
            Text(
              '256-bit AES encryption  •  Offline-first  •  Private',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textLightOf(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Your financial data never leaves your device without consent.',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textLightOf(context).withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}
