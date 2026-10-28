import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buddy/views/screens/onboarding/auth_wrapper.dart';

/// Buddy Onboarding v5 — 100% Overflow-Proof, Mobbin/Dribbble Conversion Model.
///
/// Architectural Guarantees:
/// - Zero Horizontal or Vertical RenderFlex Overflows across all screen ratios
///   (from compact 320x568 iPhone SE up to tall foldables & tablets).
/// - Protected against OS Accessibility Font Scaling via bounded MediaQuery.
/// - Single-Canvas In-Place Morphing (no PageView sliding).
/// - 3 High-Converting Steps:
///   1. HOOK  — Live UPI Alert -> 0.2s Auto-Logged Expense
///   2. TRUST — On-Device Privacy Firewall (OTPs & Chats Ignored)
///   3. PRO   — Interactive Heatmap / Debt / Category Showcase + ₹0 Forever Pass
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

class _Pal {
  final bool dark;
  const _Pal(this.dark);

  Color get bg => dark ? const Color(0xFF060E0C) : const Color(0xFFF3F8F6);
  Color get text => dark ? Colors.white : const Color(0xFF0B221C);
  Color get muted => dark ? const Color(0xFF94ADA5) : const Color(0xFF4A645C);
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

const List<_StepMeta> _steps = [
  _StepMeta(
    eyebrow: 'ZERO MANUAL ENTRY',
    headline: 'Your spending\nlogs itself.',
    body:
        'Pay with any UPI app as usual. Buddy spots the payment alert and logs the expense in 0.2 seconds.',
    cta: 'See how it stays private',
  ),
  _StepMeta(
    eyebrow: '100% ON-DEVICE PRIVACY',
    headline: 'We never read\nyour OTPs.',
    body:
        'Buddy filters alerts locally on your phone. Personal chats and bank OTPs are strictly ignored.',
    cta: 'Explore pro features',
  ),
  _StepMeta(
    eyebrow: 'NO ADS • NO PAYWALLS',
    headline: 'Every pro tool.\n₹0 forever.',
    body:
        'Heatmaps, category analytics, and friend debt tracking—unlocked out of the box with zero subscriptions.',
    cta: 'Start Tracking Free',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  static const int _pageCount = 3;

  int _page = 0;
  int _direction = 1; // 1 = forward, -1 = backward
  bool _finishing = false;

  // Interactive tab index on Screen 3 (0: Heatmap, 1: Debts, 2: Analytics)
  int _hubTab = 0;
  bool _userTouchedHubTab = false;

  late final AnimationController _loop; // 6s stage loop
  late final AnimationController _ambient; // 3s breathing glow

  @override
  void initState() {
    super.initState();
    _loop =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 6000),
          )
          ..addListener(_onLoopTick)
          ..repeat();

    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  void _onLoopTick() {
    if (_page == 2 && !_userTouchedHubTab && mounted) {
      final t = _loop.value;
      final nextTab = t < 0.34 ? 0 : (t < 0.67 ? 1 : 2);
      if (nextTab != _hubTab) {
        setState(() => _hubTab = nextTab);
      }
    }
  }

  @override
  void dispose() {
    _loop.removeListener(_onLoopTick);
    _loop.dispose();
    _ambient.dispose();
    super.dispose();
  }

  // ── Navigation (In-Place Morphing) ───────────────────────────
  void _goTo(int target) {
    if (target < 0 || target >= _pageCount || target == _page) return;
    HapticFeedback.selectionClick();
    setState(() {
      _direction = target > _page ? 1 : -1;
      _page = target;
      if (target == 2) {
        _userTouchedHubTab = false;
        _hubTab = 0;
      }
    });
    _loop
      ..reset()
      ..repeat();
  }

  void _next() {
    HapticFeedback.lightImpact();
    if (_page < _pageCount - 1) {
      _goTo(_page + 1);
    } else {
      _finish();
    }
  }

  void _prev() {
    if (_page > 0) {
      HapticFeedback.lightImpact();
      _goTo(_page - 1);
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    HapticFeedback.mediumImpact();

    if (widget.onNotificationPermissionRequested != null) {
      await widget.onNotificationPermissionRequested!();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);

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

    // Clamp text scale factor so large OS accessibility fonts never overflow cards
    final mediaQuery = MediaQuery.of(context);
    final clampedScaler = mediaQuery.textScaler.clamp(
      minScaleFactor: 0.85,
      maxScaleFactor: 1.08,
    );

    return MediaQuery(
      data: mediaQuery.copyWith(textScaler: clampedScaler),
      child: Scaffold(
        backgroundColor: p.bg,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: Stack(
            children: [
              // Ambient top spotlight that shifts smoothly across steps
              AnimatedAlign(
                duration: const Duration(milliseconds: 750),
                curve: Curves.easeOutCubic,
                alignment: Alignment(-0.75 + _page * 0.75, -1.18),
                child: IgnorePointer(
                  child: Container(
                    width: 360,
                    height: 360,
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

              // Horizontal Swipe Gesture Layer for Single-Canvas Morphing
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v < -240) {
                    _next();
                  } else if (v > 240) {
                    _prev();
                  }
                },
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, viewport) {
                      final isCompact = viewport.maxHeight < 660;
                      final isUltraShort = viewport.maxHeight < 580;
                      final hPad = viewport.maxWidth < 360 ? 16.0 : 22.0;

                      return Column(
                        children: [
                          _buildTopBar(p, hPad),
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(
                                hPad,
                                isUltraShort ? 4 : (isCompact ? 8 : 14),
                                hPad,
                                8,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 1. In-Place Morphing Header
                                  _buildMorphingHeader(
                                    p,
                                    step,
                                    isCompact: isCompact,
                                    isUltraShort: isUltraShort,
                                  ),

                                  SizedBox(
                                    height: isUltraShort
                                        ? 10
                                        : (isCompact ? 14 : 20),
                                  ),

                                  // 2. In-Place Morphing Hero Stage
                                  _buildMorphingStage(p, isCompact: isCompact),
                                ],
                              ),
                            ),
                          ),
                          _buildBottomDock(
                            p,
                            step,
                            hPad: hPad,
                            isCompact: isCompact,
                          ),
                        ],
                      );
                    },
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
  Widget _buildTopBar(_Pal p, double hPad) {
    final isLast = _page == _pageCount - 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad - 6, 4, hPad - 6, 0),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            height: 36,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _page > 0 ? 1 : 0,
              child: IgnorePointer(
                ignoring: _page == 0,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  onPressed: _prev,
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 17,
                    color: p.text,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: List.generate(_pageCount, (i) {
                final active = i <= _page;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _goTo(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        height: 4,
                        margin: EdgeInsets.only(
                          right: i < _pageCount - 1 ? 6 : 0,
                        ),
                        decoration: BoxDecoration(
                          color: active ? _kMint : p.track,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: i == _page
                              ? [
                                  BoxShadow(
                                    color: _kMint.withValues(alpha: 0.45),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          SizedBox(
            width: 52,
            height: 36,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isLast ? 0 : 1,
              child: IgnorePointer(
                ignoring: isLast,
                child: TextButton(
                  onPressed: () => _goTo(_pageCount - 1),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(52, 36),
                  ),
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      fontSize: 13,
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

  // ── Morphing Top Header ──────────────────────────────────────
  Widget _buildMorphingHeader(
    _Pal p,
    _StepMeta step, {
    required bool isCompact,
    required bool isUltraShort,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topLeft,
          children: [
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, anim) {
        final isEntering = child.key == ValueKey('hdr_$_page');
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
      child: Column(
        key: ValueKey('hdr_$_page'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.9,
                color: p.accent,
              ),
            ),
          ),
          SizedBox(height: isUltraShort ? 6 : (isCompact ? 8 : 11)),
          Text(
            step.headline,
            style: TextStyle(
              fontSize: isUltraShort ? 24 : (isCompact ? 27 : 31),
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: -0.8,
              color: p.text,
            ),
          ),
          SizedBox(height: isUltraShort ? 5 : 8),
          Text(
            step.body,
            style: TextStyle(
              fontSize: isCompact ? 13 : 14.5,
              fontWeight: FontWeight.w500,
              height: 1.38,
              color: p.muted,
            ),
          ),
        ],
      ),
    );
  }

  // ── Morphing Center Stage ────────────────────────────────────
  Widget _buildMorphingStage(_Pal p, {required bool isCompact}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutBack,
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
            ? _stageAutoLog(p, isCompact)
            : (_page == 1
                  ? _stagePrivacy(p, isCompact)
                  : _stageProHubAndFree(p, isCompact)),
      ),
    );
  }

  // ── Bottom dock: CTA + trust line ────────────────────────────
  Widget _buildBottomDock(
    _Pal p,
    _StepMeta step, {
    required double hPad,
    required bool isCompact,
  }) {
    final isLast = _page == _pageCount - 1;

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 4, hPad, isCompact ? 10 : 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _ambient,
            builder: (context, _) {
              final glow = 0.24 + 0.14 * math.sin(_ambient.value * 2 * math.pi);
              return Container(
                height: isCompact ? 50 : 55,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [_kMintBright, _kMint],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _kMint.withValues(alpha: glow),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _next,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.22),
                                end: Offset.zero,
                              ).animate(anim),
                              child: child,
                            ),
                          ),
                          child: FittedBox(
                            key: ValueKey('cta_$_page'),
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  step.cta,
                                  style: const TextStyle(
                                    fontSize: 15.5,
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
                                  size: 19,
                                  color: _kInk,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          SizedBox(height: isCompact ? 8 : 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified_user_rounded, size: 13, color: p.accent),
                const SizedBox(width: 5),
                Text(
                  '100% Free  •  Zero Ads  •  On-Device Privacy',
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

  // ─────────────────────────────────────────────────────────────
  // Shared card shell
  // ─────────────────────────────────────────────────────────────
  Widget _card(
    _Pal p, {
    required Widget child,
    Color? borderColor,
    Color? fill,
    EdgeInsets padding = const EdgeInsets.all(13),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: fill ?? p.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? p.border, width: 1.2),
        boxShadow: p.dark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 1 — Live UPI Alert -> Auto-Logged Expense
  // ─────────────────────────────────────────────────────────────
  Widget _stageAutoLog(_Pal p, bool isCompact) {
    return AnimatedBuilder(
      animation: _loop,
      builder: (context, _) {
        final t = _loop.value;
        final master = 1 - _seg(t, 0.91, 1.0);
        final alertIn = _seg(t, 0.02, 0.16);
        final logged = _seg(t, 0.44, 0.62);
        final netBalance = (6870 - 240 * logged).round();

        return Opacity(
          opacity: master,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Incoming Bank Notification Card
              Transform.translate(
                offset: Offset(0, (1 - alertIn) * -14),
                child: Opacity(
                  opacity: alertIn,
                  child: _card(
                    p,
                    borderColor: logged < 0.5
                        ? _kMint.withValues(alpha: 0.75)
                        : p.border,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF004C8F),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.account_balance_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'HDFC BANK  •  Push Alert',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: p.muted,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'now',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: p.muted,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Paid ₹240.00 to Salala Mini Supermarket via UPI',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
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

              // 2. AI Parsing Connector Pill
              Padding(
                padding: EdgeInsets.symmetric(vertical: isCompact ? 7 : 9),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
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
                        logged > 0.5
                            ? Icons.check_circle_rounded
                            : Icons.auto_awesome_rounded,
                        size: 13,
                        color: p.accent,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          logged > 0.5
                              ? 'Categorized & Logged in 0.2s'
                              : 'On-Device AI Extracting Spend',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: p.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Logged Buddy Transaction Card
              Transform.scale(
                scale: 0.97 + 0.03 * logged,
                child: Opacity(
                  opacity: 0.35 + 0.65 * logged,
                  child: _card(
                    p,
                    borderColor: logged > 0.5
                        ? _kMint.withValues(alpha: 0.85)
                        : p.border,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _kMint.withValues(alpha: 0.16),
                              ),
                              child: Icon(
                                Icons.shopping_bag_rounded,
                                size: 19,
                                color: p.accent,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Salala Mini Supermarket',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: p.text,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _kMint.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          '✨ AI  •  Groceries',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            color: p.accent,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        'Just now',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: p.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '-₹240',
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w900,
                                color: _kCoral,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(height: 1, color: p.border),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'Net Available Balance',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: p.muted,
                                ),
                              ),
                            ),
                            Text(
                              '₹$netBalance',
                              style: TextStyle(
                                fontSize: 13.5,
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
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 2 — On-Device Privacy Firewall Proof
  // ─────────────────────────────────────────────────────────────
  Widget _stagePrivacy(_Pal p, bool isCompact) {
    return AnimatedBuilder(
      animation: Listenable.merge([_loop, _ambient]),
      builder: (context, _) {
        final t = _loop.value;
        final master = 1 - _seg(t, 0.92, 1.0);
        final pulse = 0.5 + 0.5 * math.sin(_ambient.value * 2 * math.pi);

        Widget firewallRow({
          required int i,
          required IconData icon,
          required String title,
          required String sub,
          required String badge,
          required bool allowed,
        }) {
          final r = _seg(t, 0.06 + i * 0.18, 0.24 + i * 0.18);
          final color = allowed ? p.accent : _kCoral;
          return Opacity(
            opacity: 0.45 + 0.55 * r,
            child: Padding(
              padding: EdgeInsets.only(bottom: isCompact ? 7 : 9),
              child: _card(
                p,
                borderColor: r > 0.6
                    ? color.withValues(alpha: allowed ? 0.75 : 0.45)
                    : p.border,
                padding: EdgeInsets.all(isCompact ? 10 : 12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.14),
                      ),
                      child: Icon(icon, size: 17, color: color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: allowed ? p.text : p.muted,
                              decoration: allowed
                                  ? null
                                  : (r > 0.6
                                        ? TextDecoration.lineThrough
                                        : null),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sub,
                            style: TextStyle(fontSize: 10.5, color: p.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Opacity(
                      opacity: r,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 9.5,
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

        return Opacity(
          opacity: master,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Compact Shield Header Card
              Padding(
                padding: EdgeInsets.only(bottom: isCompact ? 8 : 10),
                child: _card(
                  p,
                  fill: p.surfaceElevated,
                  borderColor: _kMint.withValues(alpha: 0.4),
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: isCompact ? 9 : 11,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
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
                          size: 20,
                          color: p.accent,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Local On-Device Firewall Active',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w900,
                                color: p.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Zero servers. Nobody can read your messages.',
                              style: TextStyle(
                                fontSize: 11,
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
                sub: 'Personal WhatsApp / SMS chat',
                badge: 'IGNORED',
                allowed: false,
              ),
              firewallRow(
                i: 2,
                icon: Icons.payments_rounded,
                title: 'Paid ₹15 to Qualify via UPI',
                sub: 'Verified bank transaction alert',
                badge: 'LOCAL ONLY',
                allowed: true,
              ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STAGE 3 — Interactive Pro Hub Showcase + ₹0 Forever VIP Pass
  // ─────────────────────────────────────────────────────────────
  Widget _stageProHubAndFree(_Pal p, bool isCompact) {
    const tabs = [
      (Icons.calendar_month_rounded, 'Heatmaps'),
      (Icons.handshake_rounded, 'Borrow & Lend'),
      (Icons.donut_large_rounded, 'Category AI'),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Interactive Segmented Feature Switcher (Overflow-Safe with FittedBox)
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
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _userTouchedHubTab = true;
                      _hubTab = i;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
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
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 13.5,
                            color: selected ? p.accent : p.muted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: selected ? p.text : p.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        SizedBox(height: isCompact ? 8 : 10),

        // 2. Live Interactive Preview Card (Morphs between the 3 Pro Tools)
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
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
                ? _buildHeatmapPreviewCard(p, isCompact)
                : (_hubTab == 1
                      ? _buildDebtPreviewCard(p)
                      : _buildCategoryPreviewCard(p)),
          ),
        ),
        SizedBox(height: isCompact ? 8 : 10),

        // 3. The "Zero-Paywall" VIP Pass
        _buildZeroPaywallVipCard(p),
      ],
    );
  }

  /// Tab 0: Replicates Buddy's October Spend Heatmap & Daily Avg / Peak Spend
  Widget _buildHeatmapPreviewCard(_Pal p, bool isCompact) {
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

    return _card(
      p,
      borderColor: _kMint.withValues(alpha: 0.45),
      padding: EdgeInsets.all(isCompact ? 11 : 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 15, color: p.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'October Spend Heatmap',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: _kMint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '28 Active Days',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: p.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 5x2 Mini Calendar Heatmap Grid (Responsive Row/Expanded instead of GridView)
          Column(
            children: [
              Row(
                children: days
                    .sublist(0, 5)
                    .map((d) => Expanded(child: _buildHeatCell(p, d)))
                    .toList(),
              ),
              const SizedBox(height: 5),
              Row(
                children: days
                    .sublist(5, 10)
                    .map((d) => Expanded(child: _buildHeatCell(p, d)))
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Daily Avg & Peak Spend Footer Pills
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: p.surfaceSubtle,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Daily Avg',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: p.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '₹448',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: p.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: p.surfaceSubtle,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Peak Spend',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: p.muted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '₹4,337',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: _kCoral,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeatCell(_Pal p, (String, String, int) d) {
    final (dayNum, amount, level) = d;
    final Color cellBg = level == 2
        ? const Color(0xFFE55D60)
        : (level == 1
              ? const Color(0xFF7D4849).withValues(alpha: 0.78)
              : p.surfaceSubtle);
    final Color textColor = level > 0 ? Colors.white : p.muted;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.5),
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: cellBg,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            dayNum,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: textColor,
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w700,
              color: textColor.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  /// Tab 1: Replicates Buddy's Borrow & Lend Screen (Overflow-safe)
  Widget _buildDebtPreviewCard(_Pal p) {
    return _card(
      p,
      borderColor: _kMint.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Borrow & Lend Tracker',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: p.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Friend dues stay separate from your expenses',
                      style: TextStyle(fontSize: 10.5, color: p.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _kMint.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _kMint.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: _kMint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Separate: ON',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: p.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: p.surfaceSubtle,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '↗ To Receive (Lent)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: p.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '₹1,450',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: p.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: p.surfaceSubtle,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '↙ To Pay (Borrowed)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: p.muted,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        '₹0.00',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: _kCoral,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: p.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Split dinner bill • 2 friends settled',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '1-Tap Settle',
                  style: TextStyle(
                    fontSize: 10,
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

  /// Tab 2: Replicates Buddy's Donut Chart & Category Breakdown (Overflow-safe)
  Widget _buildCategoryPreviewCard(_Pal p) {
    return _card(
      p,
      borderColor: _kMint.withValues(alpha: 0.45),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            height: 82,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const CustomPaint(
                  size: Size(82, 82),
                  painter: _DonutRingPainter(),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Spent',
                      style: TextStyle(fontSize: 8.5, color: p.muted),
                    ),
                    Text(
                      '₹12,554',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: p.text,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart Category Split',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 8),
                _categoryLegendRow(p, _kMint, 'Food & Dining', '42% • ₹5,270'),
                const SizedBox(height: 6),
                _categoryLegendRow(p, _kCoral, 'Groceries', '31% • ₹3,890'),
                const SizedBox(height: 6),
                _categoryLegendRow(p, _kAmber, 'Fuel & Travel', '27% • ₹3,394'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryLegendRow(_Pal p, Color dotColor, String name, String value) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: p.text,
            ),
          ),
        ),
        const SizedBox(width: 4),
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

  /// High-Impact "Reverse Paywall" VIP Card (Overflow-safe with Wrap)
  Widget _buildZeroPaywallVipCard(_Pal p) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: p.dark
              ? const [Color(0xFF15382E), Color(0xFF0E251E)]
              : const [Color(0xFFDFF7EC), Color(0xFFC7F0DF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _kMint.withValues(alpha: 0.65), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_kMintBright, _kMint]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '₹0 / Forever',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: _kInk,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No Subscriptions. Zero Ads.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: p.text,
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    const Text(
                      'Other apps: ₹999/yr',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _kCoral,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    Text(
                      '• Buddy: 100% Free',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: p.accent,
                      ),
                    ),
                  ],
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
// CUSTOM PAINTER: DONUT CHART FOR SCREEN 3
// ─────────────────────────────────────────────────────────────
class _DonutRingPainter extends CustomPainter {
  const _DonutRingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    const strokeWidth = 7.5;

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

      final effectiveSweep = math.max(0.01, s.sweep - gap);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + gap / 2,
        effectiveSweep,
        false,
        paint,
      );
      startAngle += s.sweep;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
