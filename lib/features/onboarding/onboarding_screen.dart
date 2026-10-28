import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buddy/utils/colors.dart';
import 'package:buddy/views/screens/onboarding/auth_wrapper.dart';

/// Buddy Onboarding v6 — same visual language as the Home screen.
///
/// Layout (every step): dark emerald "hero" panel (identical gradient/radius
/// to Home's balance header) holding the product preview, then copy + CTA on
/// the themed page background.
///
/// 1. HOOK    – "Your spending logs itself."  (alert -> real transaction tile)
/// 2. TRUST   – "We never read your OTPs."    (filter rows reveal once, hold)
/// 3. PAYOFF  – "Every pro tool. ₹0 forever." (feature tabs + ₹0 pill + CTA)
///
/// Finish -> permission primer sheet (explains WHY) -> system permission -> Auth.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onFinishOnboarding;
  final Future<void> Function()? onNotificationPermissionRequested;

  const OnboardingScreen({
    super.key,
    this.onFinishOnboarding,
    this.onNotificationPermissionRequested,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

// ── Tokens (shared with HomeScreen's hero header) ──────────────
const List<Color> _kHeroLight = [
  Color(0xFF0F3632),
  Color(0xFF1E5D57),
  Color(0xFF2C7A72),
];
const List<Color> _kHeroDark = [
  Color(0xFF0F2624),
  Color(0xFF163E3B),
  Color(0xFF1E5D57),
];
const Color _kIncomeOnHero = Color(0xFF69F0AE); // same as Home income text
const Color _kExpenseOnHero = Color(0xFFFF8A80); // same as Home expense text
const Color _kInk = Color(0xFF0F3632);
const List<Color> _kCtaGradient = [Color(0xFF1E5D57), Color(0xFF2C7A72)];

const List<String> _kMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Clamped, eased 0..1 progress of [t] between [a] and [b].
double _seg(double t, double a, double b) =>
    Curves.easeOutCubic.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

class _StepMeta {
  final String headline;
  final String body;
  final String cta;

  const _StepMeta({
    required this.headline,
    required this.body,
    required this.cta,
  });
}

// Short CTAs on steps 1-2 keep momentum; the last CTA is the conversion moment.
const List<_StepMeta> _steps = [
  _StepMeta(
    headline: 'Your spending\nlogs itself.',
    body:
        'Pay with any UPI app as usual. Buddy spots the payment alert and logs it for you.',
    cta: 'Continue',
  ),
  _StepMeta(
    headline: 'We never read\nyour OTPs.',
    body:
        'Alerts are filtered on your phone. Bank OTPs and personal chats are ignored.',
    cta: 'Continue',
  ),
  _StepMeta(
    headline: 'Every pro tool.\n₹0 forever.',
    body:
        'Heatmaps, category insights and friend-debt tracking are unlocked from day one.',
    cta: 'Start tracking free',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  static const int _pageCount = 3;

  int _page = 0;
  int _direction = 1; // 1 = forward, -1 = backward
  bool _finishing = false;
  bool _reduceMotion = false;

  int _hubTab = 0;
  Timer? _hubTimer;

  /// One-shot timeline for stages 1 & 2 (plays once, then holds final state).
  late final AnimationController _stage;

  /// Slow breathing used by the CTA glow and the shield pulse.
  late final AnimationController _ambient;

  @override
  void initState() {
    super.initState();
    _stage = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..forward();

    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      if (reduce) {
        _stage.value = 1;
        _ambient.stop();
        _hubTimer?.cancel();
      } else if (!_ambient.isAnimating) {
        _ambient.repeat();
      }
    }
  }

  @override
  void dispose() {
    _hubTimer?.cancel();
    _stage.dispose();
    _ambient.dispose();
    super.dispose();
  }

  // ── Page 3 auto-cycle (stops as soon as the user touches a tab) ──
  void _startHubTimer() {
    _hubTimer?.cancel();
    if (_reduceMotion) return;
    _hubTimer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (!mounted || _page != 2) return;
      setState(() => _hubTab = (_hubTab + 1) % 3);
    });
  }

  // ── Navigation ───────────────────────────────────────────────
  void _goTo(int target) {
    if (target < 0 || target >= _pageCount || target == _page) return;
    HapticFeedback.selectionClick();
    setState(() {
      _direction = target > _page ? 1 : -1;
      _page = target;
      if (target == 2) _hubTab = 0;
    });

    _hubTimer?.cancel();
    if (target == 2) _startHubTimer();

    // Stage 3 has no one-shot timeline, so don't replay it.
    if (_reduceMotion || target == 2) {
      _stage.value = 1;
    } else {
      _stage
        ..reset()
        ..forward();
    }
  }

  void _next() {
    if (_finishing) return;
    HapticFeedback.lightImpact();
    if (_page < _pageCount - 1) {
      _goTo(_page + 1);
    } else {
      _finish();
    }
  }

  void _prev() {
    if (_page > 0 && !_finishing) {
      HapticFeedback.lightImpact();
      _goTo(_page - 1);
    }
  }

  // ── Permission primer (styled like Home's auto-tracking sheet) ──
  /// true = allow, false = not now, null = dismissed (stay on screen).
  Future<bool?> _showPermissionPrimer() {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = AppColors.isDark(ctx);
        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardOf(ctx),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                blurRadius: 30,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            MediaQuery.of(ctx).padding.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4.5,
                decoration: BoxDecoration(
                  color: AppColors.borderOf(ctx),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Allow notification access',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: AppColors.textPrimaryOf(ctx),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Buddy reads bank and UPI payment alerts on your phone to log '
                'expenses for you. OTPs and personal chats are ignored, and '
                'you can turn it off anytime in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: AppColors.textSecondaryOf(ctx),
                ),
              ),
              const SizedBox(height: 22),
              _GradientButton(
                label: 'Allow & continue',
                icon: Icons.bolt_rounded,
                onTap: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(
                    'Not now',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondaryOf(ctx),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    HapticFeedback.mediumImpact();

    // Mark first so a permission error can never trap the user in onboarding.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_onboarding', true);
    } catch (_) {}

    if (!mounted) return;

    if (widget.onNotificationPermissionRequested != null) {
      final choice = await _showPermissionPrimer();
      if (!mounted) return;
      if (choice == null) {
        // Dismissed the sheet: let them retry instead of forcing them on.
        setState(() => _finishing = false);
        return;
      }
      if (choice) {
        try {
          await widget.onNotificationPermissionRequested!();
        } catch (_) {
          // Never block signup on a permission failure.
        }
      }
    }

    if (!mounted) return;

    if (widget.onFinishOnboarding != null) {
      widget.onFinishOnboarding!();
    } else {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (_, __, ___) => const AuthWrapper(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final step = _steps[_page];

    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.15,
      child: Scaffold(
        backgroundColor: AppColors.backgroundOf(context),
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          // The hero is dark in both themes, so status icons are always light.
          value: SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              final v = details.primaryVelocity ?? 0;
              if (v < -240) {
                // Swipe never triggers signup; only advances to the last page.
                if (_page < _pageCount - 1) _next();
              } else if (v > 240) {
                _prev();
              }
            },
            child: Column(
              children: [
                Expanded(child: _buildHero(isDark)),
                SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCopy(step, isDark),
                      _buildBottomDock(step, isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Hero panel (same gradient + radius language as Home) ─────
  Widget _buildHero(bool isDark) {
    final colors = isDark ? _kHeroDark : _kHeroLight;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
        boxShadow: [
          BoxShadow(
            color: _kInk.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Soft light that drifts as you move through steps.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 750),
                curve: Curves.easeOutCubic,
                alignment: Alignment(-0.7 + _page * 0.7, 0.9),
                child: Container(
                  width: 340,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.22),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final w = math.min(box.maxWidth - 40, 460.0);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 2, 20, 22),
                        child: Center(
                          // Scales the preview down on short phones instead of
                          // overflowing or scrolling.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: w,
                              child: _buildMorphingStage(),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar: back, progress, skip (sits on the hero) ─────────
  Widget _buildTopBar() {
    final isLast = _page == _pageCount - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _page > 0 ? 1 : 0,
              child: IgnorePointer(
                ignoring: _page == 0,
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: _prev,
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Semantics(
              label: 'Step ${_page + 1} of $_pageCount',
              child: Row(
                children: List.generate(_pageCount, (i) {
                  final active = i <= _page;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _goTo(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          height: 4,
                          margin: EdgeInsets.only(
                            right: i < _pageCount - 1 ? 6 : 0,
                          ),
                          decoration: BoxDecoration(
                            color: active
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.24),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isLast ? 0 : 1,
              child: IgnorePointer(
                ignoring: isLast,
                child: TextButton(
                  onPressed: () => _goTo(_pageCount - 1),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 44),
                  ),
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Copy (headline + body) ───────────────────────────────────
  Widget _buildCopy(_StepMeta step, bool isDark) {
    final sw = MediaQuery.sizeOf(context).width;
    final shortScreen = MediaQuery.sizeOf(context).height < 700;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, shortScreen ? 16 : 24, 24, 0),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.topLeft,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        transitionBuilder: (child, anim) {
          final isEntering = child.key == ValueKey('copy_$_page');
          final offset = Offset(
            isEntering ? 0.08 * _direction : -0.08 * _direction,
            0,
          );
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: offset,
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          );
        },
        child: SizedBox(
          key: ValueKey('copy_$_page'),
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  step.headline,
                  style: TextStyle(
                    fontSize: sw < 360 || shortScreen ? 27 : 32,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    letterSpacing: -1.0,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                step.body,
                style: TextStyle(
                  fontSize: shortScreen ? 13.5 : 15,
                  fontWeight: FontWeight.w500,
                  height: 1.42,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Morphing stage ───────────────────────────────────────────
  Widget _buildMorphingStage() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          final isEntering = child.key == ValueKey('stg_$_page');
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(
                  isEntering ? 0.06 * _direction : -0.06 * _direction,
                  0,
                ),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey('stg_$_page'),
          child: _page == 0
              ? _stageAutoLog()
              : (_page == 1 ? _stagePrivacy() : _stageProHub()),
        ),
      ),
    );
  }

  // ── Bottom dock: CTA + secondary line ────────────────────────
  Widget _buildBottomDock(_StepMeta step, bool isDark) {
    final isLast = _page == _pageCount - 1;
    final muted = AppColors.textSecondaryOf(context);
    final accent = isDark ? AppColors.primary : const Color(0xFF1E5D57);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ambient,
            builder: (context, _) {
              final glow = _reduceMotion
                  ? 0.30
                  : 0.28 + 0.12 * math.sin(_ambient.value * 2 * math.pi);
              return _GradientButton(
                label: step.cta,
                icon: isLast ? Icons.bolt_rounded : Icons.arrow_forward_rounded,
                loading: _finishing,
                glow: glow,
                labelKey: ValueKey('cta_$_page'),
                onTap: _finishing ? null : _next,
              );
            },
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 40,
            child: isLast
                ? TextButton(
                    onPressed: _finishing ? null : _finish,
                    child: Text.rich(
                      TextSpan(
                        text: 'Already have an account?  ',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: muted,
                        ),
                        children: [
                          TextSpan(
                            text: 'Sign in',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_user_rounded,
                        size: 14,
                        color: accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Free forever. No ads. Private by design.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Surfaces used inside the hero ────────────────────────────
  /// Frosted card for INPUT things (alerts, filtered junk, tabs).
  Widget _glass({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(12),
    double radius = 18,
    double fill = 0.10,
    Color? borderColor,
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: fill),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.16),
          width: 1.1,
        ),
      ),
      child: child,
    );
  }

  /// Solid themed card for OUTPUT things (real app UI).
  Widget _solid({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
    Color? borderColor,
    double minHeight = 0,
  }) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight),
      alignment: minHeight > 0 ? Alignment.centerLeft : null,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color:
              borderColor ?? AppColors.borderOf(context).withValues(alpha: 0.5),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  /// Exact look of Home's transaction tile (stripe, icon, chip, AI badge).
  Widget _appTile({
    required String title,
    required Color catColor,
    required IconData icon,
    required String category,
    required String time,
    required String amount,
    bool auto = false,
    Color? borderColor,
  }) {
    final isDark = AppColors.isDark(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              borderColor ?? AppColors.borderOf(context).withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.20),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18.5, 16, 14, 13),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: catColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            letterSpacing: -0.2,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: catColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                category,
                                style: TextStyle(
                                  color: catColor,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              time,
                              style: TextStyle(
                                color: AppColors.textLightOf(context),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    amount,
                    style: const TextStyle(
                      color: AppColors.expense,
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 4.5,
              child: ColoredBox(color: catColor),
            ),
            if (auto)
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0F3632), Color(0xFF1E5D57)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, size: 9.5, color: Colors.white),
                      SizedBox(width: 3),
                      Text(
                        'AI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 1 — UPI alert -> auto-logged transaction (plays once)
  // ─────────────────────────────────────────────────────────────
  Widget _stageAutoLog() {
    return AnimatedBuilder(
      animation: _stage,
      builder: (context, _) {
        final t = _stage.value;
        final alertIn = _seg(t, 0.0, 0.2);
        final logged = _seg(t, 0.5, 0.8);
        final done = logged > 0.5;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: Offset(0, (1 - alertIn) * -16),
              child: Opacity(
                opacity: alertIn * (1 - 0.35 * logged),
                child: _glass(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.account_balance_rounded,
                          size: 19,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Bank alert',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                                Text(
                                  'now',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Paid ₹240.00 to Fresh Basket Supermarket via UPI',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                height: 1.32,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Container(
                  key: ValueKey(done),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        done
                            ? Icons.check_circle_rounded
                            : Icons.auto_awesome_rounded,
                        size: 14,
                        color: done
                            ? _kIncomeOnHero
                            : Colors.white.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        done ? 'Categorized and logged' : 'Reading the alert…',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: done
                              ? _kIncomeOnHero
                              : Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Transform.scale(
              scale: 0.96 + 0.04 * logged,
              child: Opacity(
                opacity: 0.25 + 0.75 * logged,
                child: _appTile(
                  title: 'Fresh Basket Supermarket',
                  catColor: AppColors.getCategoryColor('Groceries'),
                  icon: Icons.shopping_basket_rounded,
                  category: 'Groceries',
                  time: 'Just now',
                  amount: '-₹240',
                  auto: true,
                  borderColor: done
                      ? _kIncomeOnHero.withValues(alpha: 0.8)
                      : null,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 2 — On-device privacy proof (rows reveal once, then hold)
  // ─────────────────────────────────────────────────────────────
  Widget _stagePrivacy() {
    return AnimatedBuilder(
      animation: Listenable.merge([_stage, _ambient]),
      builder: (context, _) {
        final t = _stage.value;
        final pulse = _reduceMotion
            ? 0.5
            : 0.5 + 0.5 * math.sin(_ambient.value * 2 * math.pi);

        Widget filterRow({
          required int i,
          required IconData icon,
          required String title,
          required String sub,
          required String badge,
          required bool allowed,
        }) {
          final r = _seg(t, 0.15 + i * 0.22, 0.40 + i * 0.22);
          final struck = !allowed && r > 0.6;
          final badgeColor = allowed ? AppColors.success : _kExpenseOnHero;

          final content = Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: allowed
                      ? AppColors.success.withValues(alpha: 0.14)
                      : Colors.white.withValues(alpha: 0.12),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: allowed
                      ? AppColors.success
                      : Colors.white.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: allowed
                            ? AppColors.textPrimaryOf(context)
                            : Colors.white.withValues(alpha: 0.62),
                        decoration: struck ? TextDecoration.lineThrough : null,
                        decorationColor: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 11,
                        color: allowed
                            ? AppColors.textSecondaryOf(context)
                            : Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Opacity(
                opacity: r,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: badgeColor,
                    ),
                  ),
                ),
              ),
            ],
          );

          return Opacity(
            opacity: 0.4 + 0.6 * r,
            child: Transform.translate(
              offset: Offset(0, (1 - r) * 8),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: allowed
                    ? _solid(
                        padding: const EdgeInsets.all(12),
                        borderColor: r > 0.6
                            ? _kIncomeOnHero.withValues(alpha: 0.8)
                            : null,
                        child: content,
                      )
                    : _glass(
                        padding: const EdgeInsets.all(12),
                        fill: 0.07,
                        child: content,
                      ),
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _glass(
                fill: 0.14,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                borderColor: _kIncomeOnHero.withValues(alpha: 0.4),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kIncomeOnHero.withValues(
                          alpha: 0.14 + 0.10 * pulse,
                        ),
                        border: Border.all(
                          color: _kIncomeOnHero.withValues(alpha: 0.7),
                          width: 1.4,
                        ),
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        size: 22,
                        color: _kIncomeOnHero,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'On-device filter active',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Only payment alerts are used. Nothing else.',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            filterRow(
              i: 0,
              icon: Icons.password_rounded,
              title: 'Your bank login OTP is 482910',
              sub: 'OTP and password SMS',
              badge: 'IGNORED',
              allowed: false,
            ),
            filterRow(
              i: 1,
              icon: Icons.chat_bubble_rounded,
              title: 'Hey, are we meeting for lunch?',
              sub: 'Personal chat',
              badge: 'IGNORED',
              allowed: false,
            ),
            filterRow(
              i: 2,
              icon: Icons.payments_rounded,
              title: 'Paid ₹15 to Campus Canteen via UPI',
              sub: 'Verified bank transaction alert',
              badge: 'LOGGED',
              allowed: true,
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 3 — Pro hub tabs + ₹0 pill
  // ─────────────────────────────────────────────────────────────
  Widget _stageProHub() {
    const tabs = [
      (Icons.calendar_month_rounded, 'Heatmaps'),
      (Icons.handshake_rounded, 'Borrow & Lend'),
      (Icons.donut_large_rounded, 'Categories'),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Same segmented-bar language as Home's Balance/Income/Expense toggle.
        Container(
          height: 42,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(21),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final selected = _hubTab == i;
              final (icon, label) = tabs[i];
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _hubTimer?.cancel(); // user took control
                    setState(() => _hubTab = i);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.20)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                      border: selected
                          ? Border.all(
                              color: Colors.white.withValues(alpha: 0.38),
                              width: 1.0,
                            )
                          : Border.all(color: Colors.transparent),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 14,
                          color: selected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                              color: selected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.97, end: 1.0).animate(anim),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey('hub_tab_$_hubTab'),
            child: _hubTab == 0
                ? _buildHeatmapPreviewCard()
                : (_hubTab == 1
                      ? _buildDebtPreviewCard()
                      : _buildCategoryPreviewCard()),
          ),
        ),
        const SizedBox(height: 12),
        _buildZeroPill(),
      ],
    );
  }

  static const double _kPreviewMinH = 176;

  Widget _buildHeatmapPreviewCard() {
    const days = [
      ('5', '4.3K', 2),
      ('6', '319', 1),
      ('7', '-', 0),
      ('9', '200', 1),
      ('11', '660', 1),
      ('12', '3.6K', 2),
      ('15', '200', 1),
      ('18', '999', 1),
      ('21', '512', 1),
      ('25', '325', 1),
    ];
    final month = _kMonths[DateTime.now().month - 1];
    final short = month.substring(0, 3);

    Widget cell((String, String, int) d) {
      final (dayNum, amount, level) = d;
      final Color bg = level == 2
          ? AppColors.expense.withValues(alpha: 0.88)
          : (level == 1
                ? AppColors.expense.withValues(alpha: 0.30)
                : AppColors.surfaceOf(context));
      final Color fg = level == 2
          ? Colors.white
          : (level == 1
                ? AppColors.textPrimaryOf(context)
                : AppColors.textLightOf(context));
      return Expanded(
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                dayNum,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: fg,
                ),
              ),
              Text(
                amount,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: fg.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget gridRow(List<(String, String, int)> items) => Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          cell(items[i]),
        ],
      ],
    );

    return _solid(
      minHeight: _kPreviewMinH,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_month_rounded,
                size: 16,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$month spend heatmap',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          gridRow(days.sublist(0, 5)),
          const SizedBox(height: 6),
          gridRow(days.sublist(5)),
          const SizedBox(height: 10),
          Row(
            children: [
              _miniStat('Daily avg', '₹448', AppColors.secondary),
              const SizedBox(width: 8),
              _miniStat('Peak ($short 5)', '₹4,337', AppColors.expense),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebtPreviewCard() {
    Widget tile(String label, String value, Color c) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );

    return _solid(
      minHeight: _kPreviewMinH,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Borrow & Lend tracker',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Friend dues stay separate from your expenses',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              tile('↗ To receive', '₹1,450', AppColors.income),
              const SizedBox(width: 8),
              tile('↙ To pay', '₹0', AppColors.expense),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Split dinner bill, 2 friends',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ),
                Text(
                  'Settle in 1 tap',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPreviewCard() {
    // Pulled from the real category palette so it matches the app.
    final food = AppColors.getCategoryColor('Food & Dining');
    final groceries = AppColors.getCategoryColor('Groceries');
    final transport = AppColors.getCategoryColor('Transport');

    return _solid(
      minHeight: _kPreviewMinH,
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(92, 92),
                  painter: _DonutRingPainter(
                    fractions: const [0.42, 0.31, 0.27],
                    colors: [food, groceries, transport],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Total spent',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    Text(
                      '₹12,554',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart category split',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 10),
                _legendRow(food, 'Food & Dining', '42%'),
                const SizedBox(height: 8),
                _legendRow(groceries, 'Groceries', '31%'),
                const SizedBox(height: 8),
                _legendRow(transport, 'Transport', '27%'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendRow(Color dot, String name, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
      ],
    );
  }

  /// "₹0 forever" pill (no competitor price claims: legal-safe).
  Widget _buildZeroPill() {
    return _glass(
      fill: 0.12,
      padding: const EdgeInsets.all(12),
      borderColor: _kIncomeOnHero.withValues(alpha: 0.45),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kIncomeOnHero, Color(0xFF69AEA9)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '₹0 / forever',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w900,
                color: _kInk,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No subscriptions. No ads.',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Every feature unlocked from day one.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Primary CTA (used on the page and in the permission sheet)
// ─────────────────────────────────────────────────────────────
class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;
  final double glow;
  final Key? labelKey;

  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.loading = false,
    this.glow = 0.30,
    this.labelKey,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: _kCtaGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: _kCtaGradient.first.withValues(alpha: glow),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onTap!();
                },
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  )
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Row(
                      key: labelKey ?? ValueKey(label),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(icon, size: 20, color: Colors.white),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Donut chart painter
// ─────────────────────────────────────────────────────────────
class _DonutRingPainter extends CustomPainter {
  final List<double> fractions;
  final List<Color> colors;

  const _DonutRingPainter({required this.fractions, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    const strokeWidth = 8.0;
    const gap = 0.12;

    double startAngle = -math.pi / 2;
    for (var i = 0; i < fractions.length; i++) {
      final sweep = fractions[i] * 2 * math.pi;
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + gap / 2,
        math.max(0.01, sweep - gap),
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutRingPainter old) =>
      old.colors != colors || old.fractions != fractions;
}
