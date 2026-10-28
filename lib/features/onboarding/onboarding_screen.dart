import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buddy/views/screens/onboarding/auth_wrapper.dart';

/// Buddy Onboarding v5 — conversion-focused single-canvas flow.
///
/// 1. HOOK    – "Your spending logs itself." (plays once, then HOLDS the result)
/// 2. TRUST   – "We never read your OTPs."   (rows reveal once, then hold)
/// 3. PAYOFF  – "Every pro tool. ₹0 forever." + sign-up CTA + "Sign in" link
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

// ── Design tokens ──────────────────────────────────────────────
const Color _kMint = Color(0xFF1ED794);
const Color _kMintBright = Color(0xFF2AF2AA);
const Color _kMintDeep = Color(0xFF0A7A52);
const Color _kCoral = Color(0xFFE56B6F);
const Color _kAmber = Color(0xFFFFD166);
const Color _kInk = Color(0xFF042419);

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

class _Pal {
  final bool dark;
  const _Pal(this.dark);

  Color get bg => dark ? const Color(0xFF060E0C) : const Color(0xFFF3F8F6);
  Color get text => dark ? Colors.white : const Color(0xFF0B221C);
  Color get muted => dark ? const Color(0xFF9DB5AD) : const Color(0xFF4A645C);
  Color get surface => dark ? const Color(0xFF0F211C) : Colors.white;
  Color get surfaceElevated =>
      dark ? const Color(0xFF142D26) : const Color(0xFFE8F6F0);
  Color get surfaceSubtle =>
      dark ? const Color(0xFF0A1713) : const Color(0xFFEBF3F0);
  Color get border => dark
      ? Colors.white.withValues(alpha: 0.09)
      : const Color(0xFF0F3632).withValues(alpha: 0.10);
  Color get track => dark
      ? Colors.white.withValues(alpha: 0.14)
      : const Color(0xFF0F3632).withValues(alpha: 0.12);
  Color get accent => dark ? _kMint : _kMintDeep;
}

/// Clamped, eased 0..1 progress of [t] between [a] and [b].
double _seg(double t, double a, double b) =>
    Curves.easeOutCubic.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

class _StepMeta {
  final String eyebrow;
  final String headline;
  final String body;
  final String cta;

  const _StepMeta({
    required this.eyebrow,
    required this.headline,
    required this.body,
    required this.cta,
  });
}

// Short CTAs on steps 1-2 keep momentum; the last CTA is the conversion moment.
const List<_StepMeta> _steps = [
  _StepMeta(
    eyebrow: 'ZERO MANUAL ENTRY',
    headline: 'Your spending\nlogs itself.',
    body:
        'Pay with any UPI app as usual. Buddy spots the payment alert and logs it for you.',
    cta: 'Continue',
  ),
  _StepMeta(
    eyebrow: 'PRIVATE BY DESIGN',
    headline: 'We never read\nyour OTPs.',
    body:
        'Alerts are filtered on your phone. Bank OTPs and personal chats are ignored.',
    cta: 'Continue',
  ),
  _StepMeta(
    eyebrow: 'NO ADS • NO PAYWALLS',
    headline: 'Every pro tool.\n₹0 forever.',
    body:
        'Heatmaps, category insights and friend-debt tracking are unlocked from day one.',
    cta: 'Start Tracking Free',
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

  /// Subtle breathing glow on the CTA.
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

  // ── Navigation (in-place morphing) ───────────────────────────
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

    if (_reduceMotion) {
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

  /// Asks WHY before the system dialog. true = allow, false = not now,
  /// null = dismissed (stay on screen).
  Future<bool?> _showPermissionPrimer(_Pal p) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: _kMint.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kMint.withValues(alpha: 0.16),
                ),
                child: Icon(
                  Icons.notifications_active_rounded,
                  color: p.accent,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'One quick permission',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Buddy needs notification access to spot your UPI payment '
                'alerts and log them automatically. OTPs and personal chats '
                'are ignored.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: p.muted,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kMint,
                    foregroundColor: _kInk,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text(
                    'Allow & continue',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'Not now',
                  style: TextStyle(fontWeight: FontWeight.w700, color: p.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    HapticFeedback.mediumImpact();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Mark first so a permission error can never trap the user in onboarding.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_onboarding', true);
    } catch (_) {}

    if (!mounted) return;

    if (widget.onNotificationPermissionRequested != null) {
      final choice = await _showPermissionPrimer(_Pal(isDark));
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = _Pal(isDark);
    final step = _steps[_page];

    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 1.0,
      maxScaleFactor: 1.15,
      child: Scaffold(
        backgroundColor: p.bg,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 750),
                curve: Curves.easeOutCubic,
                alignment: Alignment(-0.75 + _page * 0.75, -1.18),
                child: IgnorePointer(
                  child: Container(
                    width: 390,
                    height: 390,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          _kMint.withValues(alpha: isDark ? 0.16 : 0.14),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              GestureDetector(
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
                child: SafeArea(
                  child: Column(
                    children: [
                      _buildTopBar(p),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final isShort = box.maxHeight < 540;
                            return SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(
                                24,
                                isShort ? 8 : 14,
                                24,
                                12,
                              ),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: box.maxHeight - 26,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _buildMorphingHeader(p, step, isShort),
                                    SizedBox(height: isShort ? 12 : 18),
                                    _buildMorphingStage(p),
                                    const SizedBox(height: 4),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      _buildBottomDock(p, step),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar: back, progress bars, skip ───────────────────────
  Widget _buildTopBar(_Pal p) {
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
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 18,
                    color: p.text,
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
                          height: 4.5,
                          margin: EdgeInsets.only(
                            right: i < _pageCount - 1 ? 6 : 0,
                          ),
                          decoration: BoxDecoration(
                            color: active ? _kMint : p.track,
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
                      color: p.muted,
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

  // ── Morphing header ──────────────────────────────────────────
  Widget _buildMorphingHeader(_Pal p, _StepMeta step, bool isShort) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.topLeft,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      transitionBuilder: (child, anim) {
        final isEntering = child.key == ValueKey('hdr_$_page');
        final offset = Offset(
          isEntering ? 0.10 * _direction : -0.10 * _direction,
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
      child: Column(
        key: ValueKey('hdr_$_page'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _kMint.withValues(alpha: p.dark ? 0.14 : 0.16),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _kMint.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: Text(
              step.eyebrow,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.9,
                color: p.accent,
              ),
            ),
          ),
          SizedBox(height: isShort ? 8 : 12),
          Semantics(
            header: true,
            child: Text(
              step.headline,
              style: TextStyle(
                fontSize: isShort ? 27 : 32,
                fontWeight: FontWeight.w900,
                height: 1.1,
                letterSpacing: -0.9,
                color: p.text,
              ),
            ),
          ),
          SizedBox(height: isShort ? 6 : 10),
          Text(
            step.body,
            style: TextStyle(
              fontSize: isShort ? 13.5 : 15,
              fontWeight: FontWeight.w500,
              height: 1.42,
              color: p.muted,
            ),
          ),
        ],
      ),
    );
  }

  // ── Morphing stage ───────────────────────────────────────────
  Widget _buildMorphingStage(_Pal p) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 440),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) {
          final isEntering = child.key == ValueKey('stg_$_page');
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween<double>(
                begin: isEntering ? 0.94 : 1.03,
                end: 1.0,
              ).animate(anim),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey('stg_$_page'),
          child: _page == 0
              ? _stageAutoLog(p)
              : (_page == 1 ? _stagePrivacy(p) : _stageProHubAndFree(p)),
        ),
      ),
    );
  }

  // ── Bottom dock ──────────────────────────────────────────────
  Widget _buildBottomDock(_Pal p, _StepMeta step) {
    final isLast = _page == _pageCount - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ambient,
            builder: (context, _) {
              final glow = _reduceMotion
                  ? 0.26
                  : 0.24 + 0.14 * math.sin(_ambient.value * 2 * math.pi);
              return Container(
                height: 56,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    colors: [_kMintBright, _kMint],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _kMint.withValues(alpha: glow),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: _finishing ? null : _next,
                    child: Center(
                      child: _finishing
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                                color: _kInk,
                              ),
                            )
                          : AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Row(
                                key: ValueKey('cta_$_page'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    step.cta,
                                    style: const TextStyle(
                                      fontSize: 16.5,
                                      fontWeight: FontWeight.w900,
                                      color: _kInk,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    isLast
                                        ? Icons.bolt_rounded
                                        : Icons.arrow_forward_rounded,
                                    size: 20,
                                    color: _kInk,
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
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
                          color: p.muted,
                        ),
                        children: [
                          TextSpan(
                            text: 'Sign in',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: p.accent,
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
                        size: 13,
                        color: p.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Free  •  No ads  •  Private by design',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: p.muted,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ── Shared card shell ────────────────────────────────────────
  Widget _card(
    _Pal p, {
    required Widget child,
    Color? borderColor,
    Color? fill,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: fill ?? p.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor ?? p.border, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.dark ? 0.28 : 0.05),
            blurRadius: p.dark ? 16 : 14,
            offset: Offset(0, p.dark ? 6 : 4),
          ),
        ],
      ),
      child: child,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 1 — UPI alert -> auto-logged expense (plays once, holds)
  // ─────────────────────────────────────────────────────────────
  Widget _stageAutoLog(_Pal p) {
    return AnimatedBuilder(
      animation: _stage,
      builder: (context, _) {
        final t = _stage.value;
        final alertIn = _seg(t, 0.0, 0.2);
        final logged = _seg(t, 0.5, 0.8);
        final done = logged > 0.5;
        final netBalance = (6870 - 240 * logged).round();

        return Column(
          children: [
            Transform.translate(
              offset: Offset(0, (1 - alertIn) * -16),
              child: Opacity(
                opacity: alertIn,
                child: _card(
                  p,
                  borderColor: !done
                      ? _kMint.withValues(alpha: 0.75)
                      : p.border,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFF004C8F),
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
                                  'HDFC BANK  •  Push Alert',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: p.muted,
                                  ),
                                ),
                                Text(
                                  'now',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: p.muted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Paid ₹240.00 to Salala Mini Supermarket via UPI',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                height: 1.32,
                                color: p.text,
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
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Container(
                  key: ValueKey(done),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: p.surfaceElevated,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kMint.withValues(alpha: 0.55)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        done
                            ? Icons.check_circle_rounded
                            : Icons.auto_awesome_rounded,
                        size: 14,
                        color: p.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        done ? 'Categorized & logged' : 'Reading the alert...',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: p.accent,
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
                opacity: 0.35 + 0.65 * logged,
                child: _card(
                  p,
                  borderColor: done ? _kMint.withValues(alpha: 0.85) : p.border,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _kMint.withValues(alpha: 0.16),
                            ),
                            child: Icon(
                              Icons.shopping_bag_rounded,
                              size: 20,
                              color: p.accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Salala Mini Supermarket',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: p.text,
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
                                        color: _kMint.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '✨ Groceries',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: p.accent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Just now',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: p.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            '-₹240',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: _kCoral,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(height: 1, color: p.border),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Balance',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: p.muted,
                            ),
                          ),
                          Text(
                            '₹$netBalance',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: p.text,
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
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 2 — On-device privacy proof (rows reveal once, then hold)
  // ─────────────────────────────────────────────────────────────
  Widget _stagePrivacy(_Pal p) {
    return AnimatedBuilder(
      animation: Listenable.merge([_stage, _ambient]),
      builder: (context, _) {
        final t = _stage.value;
        final pulse = _reduceMotion
            ? 0.5
            : 0.5 + 0.5 * math.sin(_ambient.value * 2 * math.pi);

        Widget firewallRow({
          required int i,
          required IconData icon,
          required String title,
          required String sub,
          required String badge,
          required bool allowed,
        }) {
          final r = _seg(t, 0.15 + i * 0.22, 0.40 + i * 0.22);
          final color = allowed ? p.accent : _kCoral;
          return Opacity(
            opacity: 0.45 + 0.55 * r,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _card(
                p,
                borderColor: r > 0.6
                    ? color.withValues(alpha: allowed ? 0.75 : 0.45)
                    : p.border,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.14),
                      ),
                      child: Icon(icon, size: 18, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: allowed ? p.text : p.muted,
                              decoration: (!allowed && r > 0.6)
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sub,
                            style: TextStyle(fontSize: 11, color: p.muted),
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
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _card(
                p,
                fill: p.surfaceElevated,
                borderColor: _kMint.withValues(alpha: 0.4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kMint.withValues(alpha: 0.16 + 0.08 * pulse),
                        border: Border.all(
                          color: _kMint.withValues(alpha: 0.7),
                          width: 1.4,
                        ),
                      ),
                      child: Icon(
                        Icons.shield_rounded,
                        size: 22,
                        color: p.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'On-device filter active',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: p.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Only payment alerts are used. Nothing else.',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: p.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            firewallRow(
              i: 0,
              icon: Icons.password_rounded,
              title: 'Your bank login OTP is 482910',
              sub: 'OTP & password SMS',
              badge: 'IGNORED',
              allowed: false,
            ),
            firewallRow(
              i: 1,
              icon: Icons.chat_bubble_rounded,
              title: 'Hey, are we meeting for lunch?',
              sub: 'Personal chat',
              badge: 'IGNORED',
              allowed: false,
            ),
            firewallRow(
              i: 2,
              icon: Icons.payments_rounded,
              title: 'Paid ₹15 to Qualify via UPI',
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
  // STAGE 3 — Pro hub + ₹0 pass
  // ─────────────────────────────────────────────────────────────
  Widget _stageProHubAndFree(_Pal p) {
    const tabs = [
      (Icons.calendar_month_rounded, 'Heatmaps'),
      (Icons.handshake_rounded, 'Borrow & Lend'),
      (Icons.donut_large_rounded, 'Categories'),
    ];

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: p.surfaceSubtle,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.border),
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
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: selected ? p.surfaceElevated : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: selected
                          ? Border.all(
                              color: _kMint.withValues(alpha: 0.55),
                              width: 1.0,
                            )
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 14,
                          color: selected ? p.accent : p.muted,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: selected ? p.text : p.muted,
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
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, if (current != null) current],
          ),
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
                ? _buildHeatmapPreviewCard(p)
                : (_hubTab == 1
                      ? _buildDebtPreviewCard(p)
                      : _buildCategoryPreviewCard(p)),
          ),
        ),
        const SizedBox(height: 12),
        _buildZeroPaywallVipCard(p),
      ],
    );
  }

  Widget _miniStat(_Pal p, String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: p.surfaceSubtle,
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
                  color: p.muted,
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

  Widget _buildHeatmapPreviewCard(_Pal p) {
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

    return _card(
      p,
      borderColor: _kMint.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 16, color: p.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$month spend heatmap',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1.35,
            children: days.map((d) {
              final (dayNum, amount, level) = d;
              final Color cellBg = level == 2
                  ? const Color(0xFFE55D60)
                  : (level == 1
                        ? const Color(0xFF7D4849).withValues(alpha: 0.78)
                        : p.surfaceSubtle);
              final Color textColor = level > 0 ? Colors.white : p.muted;
              return Container(
                decoration: BoxDecoration(
                  color: cellBg,
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
                        color: textColor,
                      ),
                    ),
                    Text(
                      amount,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: textColor.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _miniStat(p, 'Daily avg', '₹448', p.accent),
              const SizedBox(width: 8),
              _miniStat(p, 'Peak ($short 5)', '₹4,337', _kCoral),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDebtPreviewCard(_Pal p) {
    Widget tile(String label, String value, Color c) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: p.surfaceSubtle,
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
                color: p.muted,
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

    return _card(
      p,
      borderColor: _kMint.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Borrow & Lend tracker',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: p.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Friend dues stay separate from your expenses',
            style: TextStyle(fontSize: 11, color: p.muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              tile('↗ To receive', '₹1,450', p.accent),
              const SizedBox(width: 8),
              tile('↙ To pay', '₹0', _kCoral),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: p.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'Split dinner bill • 2 friends',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                ),
                Text(
                  'Settle in 1 tap',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: p.accent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryPreviewCard(_Pal p) {
    return _card(
      p,
      borderColor: _kMint.withValues(alpha: 0.45),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const CustomPaint(
                  size: Size(88, 88),
                  painter: _DonutRingPainter(),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Total spent',
                      style: TextStyle(fontSize: 9, color: p.muted),
                    ),
                    Text(
                      '₹12,554',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: p.text,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart category split',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 8),
                _legendRow(p, _kMint, 'Food & Dining', '42% • ₹5,270'),
                const SizedBox(height: 6),
                _legendRow(p, _kCoral, 'Groceries', '31% • ₹3,890'),
                const SizedBox(height: 6),
                _legendRow(p, _kAmber, 'Fuel & Travel', '27% • ₹3,394'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendRow(_Pal p, Color dot, String name, String value) {
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
                    color: p.text,
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
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: p.muted,
          ),
        ),
      ],
    );
  }

  /// "₹0 forever" pass (no competitor price claims: legal-safe).
  Widget _buildZeroPaywallVipCard(_Pal p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: p.dark
              ? const [Color(0xFF15382E), Color(0xFF0E251E)]
              : const [Color(0xFFDFF7EC), Color(0xFFC7F0DF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kMint.withValues(alpha: 0.65), width: 1.3),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_kMintBright, _kMint]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '₹0 / forever',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: _kInk,
                letterSpacing: -0.4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No subscriptions. No ads.',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Every feature unlocked from day one.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: p.accent,
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
// Donut chart painter
// ─────────────────────────────────────────────────────────────
class _DonutRingPainter extends CustomPainter {
  const _DonutRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    const strokeWidth = 8.0;

    final slices = [
      (sweep: 0.42 * 2 * math.pi, color: _kMint),
      (sweep: 0.31 * 2 * math.pi, color: _kCoral),
      (sweep: 0.27 * 2 * math.pi, color: _kAmber),
    ];

    double startAngle = -math.pi / 2;
    const gap = 0.12;

    for (final s in slices) {
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + gap / 2,
        math.max(0.01, s.sweep - gap),
        false,
        paint,
      );
      startAngle += s.sweep;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
